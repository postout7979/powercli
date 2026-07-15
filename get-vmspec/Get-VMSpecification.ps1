<#
.SYNOPSIS
    vCenter 8 환경의 모든 VM Specification 정보를 수집하는 PowerCLI 스크립트

.DESCRIPTION
    수집 항목:
    - vCPU 수, Cores per Socket, Socket 수, Memory Size
    - CPU Hot Add/Remove, Memory Hot Add 설정
    - vNUMA 상태 (추정치 - VMware 기본 동작 기준. 하단 NOTE 참고)
    - Virtual Network Adapter 목록 (Type, PortGroup, MAC Address, Connected 상태)
    - Virtual Disk 목록 (SCSI Controller Type/Bus, Disk Type: Thin/Thick Lazy/Thick Eager/RDM, Datastore)
    - RDM(Raw Device Mapping) 여부 및 Compatibility Mode
    - ISO Mount 여부 및 경로

.OUTPUTS
    <실행경로>\VM_Spec_Report_<timestamp>\ 폴더 내
    - VM_Summary.csv          (VM 당 1행 - 전체 요약)
    - VM_NetworkAdapters.csv  (vNIC 당 1행)
    - VM_Disks.csv            (Virtual Disk 당 1행, RDM 포함)
    - VM_ISO.csv              (ISO 마운트된 CD/DVD 드라이브만)

.NOTE (vNUMA 관련 중요 사항)
    PowerCLI/vSphere API에는 "실제로 활성화된 vNUMA 노드 구성"을 직접 노출하는
    공식 프로퍼티가 없습니다. 이 스크립트는 VMware 문서화된 기본 동작 규칙
    (vCPU > 8 이고 CPU Hot Add가 비활성화된 경우 vNUMA가 자동 활성화됨,
    numa.vcpu.min 값으로 임계치 변경 가능)을 기준으로 "추정"만 제공합니다.
    운영 중인 VM에 대한 정확한 vNUMA 토폴로지 확인이 필요하다면 vmware.log
    (VM 폴더 내) 또는 esxtop의 NUMA 통계를 통해 재확인하시기 바랍니다.

.NOTES
    Windows PowerShell 5.1 호환
    대상: vCenter 8.x (단일 vCenter 연결)
#>

#region 사전 준비
$ErrorActionPreference = 'Stop'

Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host " vCenter VM Specification 수집 스크립트" -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan

if (-not (Get-Module -ListAvailable -Name VMware.PowerCLI)) {
    Write-Host "[오류] VMware.PowerCLI 모듈이 설치되어 있지 않습니다." -ForegroundColor Red
    Write-Host "설치 명령: Install-Module -Name VMware.PowerCLI -Scope CurrentUser" -ForegroundColor Yellow
    exit 1
}

Import-Module VMware.PowerCLI -ErrorAction SilentlyContinue | Out-Null

# 인증서 경고/CEIP 참여 여부 설정 (세션 한정)
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -ParticipateInCEIP $false -Scope Session -Confirm:$false | Out-Null
#endregion

#region vCenter 접속 정보 입력 및 연결
$vCenterServer = Read-Host "vCenter 서버 주소를 입력하세요 (예: vcenter01.domain.com)"

if ([string]::IsNullOrWhiteSpace($vCenterServer)) {
    Write-Host "[오류] vCenter 서버 주소가 입력되지 않았습니다." -ForegroundColor Red
    exit 1
}

Write-Host "`nvCenter 계정 정보를 입력해주세요 (로그인 창이 표시됩니다)..." -ForegroundColor Yellow
$cred = Get-Credential -Message "vCenter 로그인 정보를 입력하세요 ($vCenterServer)"

if (-not $cred) {
    Write-Host "[오류] 자격 증명이 입력되지 않았습니다." -ForegroundColor Red
    exit 1
}

try {
    Write-Host "`n[$vCenterServer] 에 연결 중..." -ForegroundColor Yellow
    $viConnection = Connect-VIServer -Server $vCenterServer -Credential $cred -ErrorAction Stop
    Write-Host "[성공] $($viConnection.Name) (버전 $($viConnection.Version)) 에 연결되었습니다." -ForegroundColor Green
}
catch {
    Write-Host "[오류] vCenter 연결 실패: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
#endregion

#region 출력 경로 설정
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFolder = Join-Path -Path (Get-Location) -ChildPath "VM_Spec_Report_$timestamp"
New-Item -Path $outputFolder -ItemType Directory -Force | Out-Null

$summaryCsv = Join-Path $outputFolder "VM_Summary.csv"
$networkCsv = Join-Path $outputFolder "VM_NetworkAdapters.csv"
$diskCsv    = Join-Path $outputFolder "VM_Disks.csv"
$isoCsv     = Join-Path $outputFolder "VM_ISO.csv"

Write-Host "`n출력 경로: $outputFolder" -ForegroundColor Cyan
#endregion

#region VM 목록 조회 (Get-View 사용, 대규모 환경 성능 고려)
Write-Host "`nVM 목록을 조회합니다 (전체 VM 대상, 환경 규모에 따라 시간이 소요될 수 있습니다)..." -ForegroundColor Yellow

$allVMs = Get-View -ViewType VirtualMachine -Property Name, Config, Runtime, Guest -ErrorAction Stop
$totalCount = $allVMs.Count
Write-Host "총 $totalCount 개의 VM이 조회되었습니다." -ForegroundColor Green

# Host / Datastore / DVPortgroup 이름 캐시 (반복 API 호출 최소화)
$hostNameCache = @{}
$dsNameCache   = @{}
$dvpgNameCache = @{}
#endregion

#region 데이터 수집
$summaryResults = New-Object System.Collections.Generic.List[Object]
$networkResults = New-Object System.Collections.Generic.List[Object]
$diskResults    = New-Object System.Collections.Generic.List[Object]
$isoResults     = New-Object System.Collections.Generic.List[Object]

$counter = 0

foreach ($vmView in $allVMs) {

    $counter++
    Write-Progress -Activity "VM 정보 수집 중" -Status "$($vmView.Name) ($counter / $totalCount)" `
        -PercentComplete (($counter / $totalCount) * 100)

    try {
        $vmName   = $vmView.Name
        $config   = $vmView.Config
        $hardware = $config.Hardware

        # ---- ESXi Host / Cluster 이름 ----
        $esxiHostName = ""
        $clusterName  = ""
        $hostMoRef = $vmView.Runtime.Host

        if ($hostMoRef) {
            $hostKey = $hostMoRef.ToString()
            if ($hostNameCache.ContainsKey($hostKey)) {
                $esxiHostName = $hostNameCache[$hostKey].HostName
                $clusterName  = $hostNameCache[$hostKey].ClusterName
            }
            else {
                try {
                    $hostView = Get-View -Id $hostMoRef -Property Name, Parent -ErrorAction SilentlyContinue
                    $esxiHostName = $hostView.Name
                    $cName = ""
                    if ($hostView.Parent) {
                        $parentView = Get-View -Id $hostView.Parent -Property Name -ErrorAction SilentlyContinue
                        if ($parentView) { $cName = $parentView.Name }
                    }
                    $clusterName = $cName
                    $hostNameCache[$hostKey] = [PSCustomObject]@{ HostName = $esxiHostName; ClusterName = $clusterName }
                } catch { }
            }
        }

        # ---- CPU / Memory / Topology ----
        $numCPU         = $hardware.NumCPU
        $coresPerSocket = $hardware.NumCoresPerSocket
        if (-not $coresPerSocket -or $coresPerSocket -eq 0) { $coresPerSocket = 1 }
        $numSockets = [Math]::Ceiling($numCPU / $coresPerSocket)
        $memoryGB   = [Math]::Round($hardware.MemoryMB / 1024, 2)

        $cpuHotAdd    = $config.CpuHotAddEnabled
        $cpuHotRemove = $config.CpuHotRemoveEnabled
        $memHotAdd    = $config.MemoryHotAddEnabled

        # ---- vNUMA 상태 추정 ----
        $numaMaxPerNode = $null
        $numaVcpuMin    = $null
        if ($config.ExtraConfig) {
            foreach ($ec in $config.ExtraConfig) {
                if ($ec.Key -eq "numa.vcpu.maxPerVirtualNode") { $numaMaxPerNode = $ec.Value }
                if ($ec.Key -eq "numa.vcpu.min") { $numaVcpuMin = $ec.Value }
            }
        }

        $vnumaThreshold = 8
        if ($numaVcpuMin) {
            try { $vnumaThreshold = [int]$numaVcpuMin } catch { }
        }

        if ($numCPU -gt $vnumaThreshold -and -not $cpuHotAdd) {
            $vnumaStatus = "Likely Enabled (추정)"
        }
        elseif ($numaMaxPerNode) {
            $vnumaStatus = "Manual Override (maxPerVirtualNode=$numaMaxPerNode)"
        }
        else {
            $vnumaStatus = "Likely Disabled (추정)"
        }

        # ---- Device 목록 처리 준비 ----
        $devices = $hardware.Device
        $networkAdapterCount = 0
        $diskCount = 0
        $rdmCount  = 0
        $isoCount  = 0

        # SCSI 컨트롤러 Key -> 정보 매핑
        $scsiControllerMap = @{}
        foreach ($dev in $devices) {
            if ($dev -is [VMware.Vim.VirtualSCSIController]) {
                $controllerType = $dev.GetType().Name -replace "Virtual", "" -replace "Controller", ""
                $scsiControllerMap[$dev.Key] = [PSCustomObject]@{
                    Label     = $dev.DeviceInfo.Label
                    Type      = $controllerType
                    BusNumber = $dev.BusNumber
                }
            }
        }

        foreach ($dev in $devices) {

            # ---- Network Adapter ----
            if ($dev -is [VMware.Vim.VirtualEthernetCard]) {
                $networkAdapterCount++

                $adapterType = $dev.GetType().Name -replace "Virtual", ""
                $portGroup = ""

                if ($dev.Backing -is [VMware.Vim.VirtualEthernetCardNetworkBackingInfo]) {
                    $portGroup = $dev.Backing.DeviceName
                }
                elseif ($dev.Backing -is [VMware.Vim.VirtualEthernetCardDistributedVirtualPortBackingInfo]) {
                    $dvPgKey = $dev.Backing.Port.PortgroupKey
                    if ($dvpgNameCache.ContainsKey($dvPgKey)) {
                        $portGroup = $dvpgNameCache[$dvPgKey]
                    }
                    else {
                        try {
                            $dvpg = Get-View -Id "DistributedVirtualPortgroup-$dvPgKey" -Property Name -ErrorAction SilentlyContinue
                            $portGroup = if ($dvpg) { $dvpg.Name } else { "DVPortgroup ($dvPgKey)" }
                            $dvpgNameCache[$dvPgKey] = $portGroup
                        } catch {
                            $portGroup = "DVPortgroup (조회 실패)"
                        }
                    }
                }

                $networkResults.Add([PSCustomObject]@{
                    VMName         = $vmName
                    AdapterLabel   = $dev.DeviceInfo.Label
                    AdapterType    = $adapterType
                    PortGroup      = $portGroup
                    MacAddress     = $dev.MacAddress
                    MacType        = $dev.AddressType
                    Connected      = $dev.Connectable.Connected
                    StartConnected = $dev.Connectable.StartConnected
                })
            }

            # ---- Virtual Disk ----
            elseif ($dev -is [VMware.Vim.VirtualDisk]) {
                $diskCount++
                $capacityGB = [Math]::Round($dev.CapacityInKB / 1MB, 2)
                $backing = $dev.Backing

                $diskType      = "Unknown"
                $datastoreName = ""
                $rdmDeviceName = ""
                $rdmCompatMode = ""
                $isRDM = $false

                if ($backing -is [VMware.Vim.VirtualDiskFlatVer2BackingInfo]) {
                    if ($backing.ThinProvisioned -eq $true) {
                        $diskType = "Thin"
                    }
                    elseif ($backing.EagerlyScrub -eq $true) {
                        $diskType = "Thick Eager Zeroed"
                    }
                    else {
                        $diskType = "Thick Lazy Zeroed"
                    }
                    if ($backing.Datastore) {
                        $dsKey = $backing.Datastore.ToString()
                        if ($dsNameCache.ContainsKey($dsKey)) {
                            $datastoreName = $dsNameCache[$dsKey]
                        } else {
                            try {
                                $dsView = Get-View -Id $backing.Datastore -Property Name -ErrorAction SilentlyContinue
                                $datastoreName = $dsView.Name
                                $dsNameCache[$dsKey] = $datastoreName
                            } catch { }
                        }
                    }
                }
                elseif ($backing -is [VMware.Vim.VirtualDiskRawDiskMappingVer1BackingInfo]) {
                    $isRDM = $true
                    $rdmCount++
                    $rdmDeviceName = $backing.DeviceName
                    $rdmCompatMode = $backing.CompatibilityMode  # physicalMode / virtualMode
                    $diskType = if ($rdmCompatMode -eq "physicalMode") { "RDM (Physical)" } else { "RDM (Virtual)" }

                    if ($backing.Datastore) {
                        $dsKey = $backing.Datastore.ToString()
                        if ($dsNameCache.ContainsKey($dsKey)) {
                            $datastoreName = $dsNameCache[$dsKey]
                        } else {
                            try {
                                $dsView = Get-View -Id $backing.Datastore -Property Name -ErrorAction SilentlyContinue
                                $datastoreName = $dsView.Name
                                $dsNameCache[$dsKey] = $datastoreName
                            } catch { }
                        }
                    }
                }
                else {
                    $diskType = $backing.GetType().Name
                }

                $ctrlInfo = $scsiControllerMap[$dev.ControllerKey]

                $diskResults.Add([PSCustomObject]@{
                    VMName           = $vmName
                    DiskLabel        = $dev.DeviceInfo.Label
                    CapacityGB       = $capacityGB
                    DiskType         = $diskType
                    Datastore        = $datastoreName
                    ControllerLabel  = if ($ctrlInfo) { $ctrlInfo.Label } else { "N/A" }
                    ControllerType   = if ($ctrlInfo) { $ctrlInfo.Type } else { "N/A" }
                    ControllerBusNum = if ($ctrlInfo) { $ctrlInfo.BusNumber } else { "N/A" }
                    UnitNumber       = $dev.UnitNumber
                    IsRDM            = $isRDM
                    RDM_DeviceName   = $rdmDeviceName
                    RDM_CompatMode   = $rdmCompatMode
                })
            }

            # ---- CD/DVD Drive (ISO Mount 확인) ----
            elseif ($dev -is [VMware.Vim.VirtualCdrom]) {
                if ($dev.Backing -is [VMware.Vim.VirtualCdromIsoBackingInfo]) {
                    $isoCount++
                    $isoResults.Add([PSCustomObject]@{
                        VMName         = $vmName
                        CDDriveLabel   = $dev.DeviceInfo.Label
                        ISOPath        = $dev.Backing.FileName
                        Connected      = $dev.Connectable.Connected
                        StartConnected = $dev.Connectable.StartConnected
                    })
                }
            }
        }

        # ---- Summary Row ----
        $summaryResults.Add([PSCustomObject]@{
            VMName              = $vmName
            PowerState          = $vmView.Runtime.PowerState
            GuestFullName       = $config.GuestFullName
            ESXiHost            = $esxiHostName
            Cluster             = $clusterName
            NumCPU              = $numCPU
            NumSockets          = $numSockets
            NumCoresPerSocket   = $coresPerSocket
            MemoryGB            = $memoryGB
            CpuHotAddEnabled    = $cpuHotAdd
            CpuHotRemoveEnabled = $cpuHotRemove
            MemHotAddEnabled    = $memHotAdd
            vNUMA_Status        = $vnumaStatus
            NetworkAdapterCount = $networkAdapterCount
            DiskCount           = $diskCount
            HasRDM              = ($rdmCount -gt 0)
            RDMCount            = $rdmCount
            HasISOMounted       = ($isoCount -gt 0)
            ISOMountedCount     = $isoCount
            HWVersion           = $config.Version
            VMToolsStatus       = $vmView.Guest.ToolsStatus
            VMToolsVersion      = $vmView.Guest.ToolsVersion
        })
    }
    catch {
        Write-Host "[경고] $($vmView.Name) 처리 중 오류 발생: $($_.Exception.Message)" -ForegroundColor Yellow
        $summaryResults.Add([PSCustomObject]@{
            VMName        = $vmView.Name
            PowerState    = "ERROR"
            GuestFullName = "수집 실패: $($_.Exception.Message)"
        })
    }
}

Write-Progress -Activity "VM 정보 수집 중" -Completed
#endregion

#region CSV Export
Write-Host "`n결과를 CSV로 저장 중..." -ForegroundColor Yellow

$summaryResults | Export-Csv -Path $summaryCsv -NoTypeInformation -Encoding UTF8
$networkResults | Export-Csv -Path $networkCsv -NoTypeInformation -Encoding UTF8
$diskResults    | Export-Csv -Path $diskCsv    -NoTypeInformation -Encoding UTF8
$isoResults     | Export-Csv -Path $isoCsv     -NoTypeInformation -Encoding UTF8

Write-Host "`n=======================================================" -ForegroundColor Green
Write-Host " 수집 완료!" -ForegroundColor Green
Write-Host "=======================================================" -ForegroundColor Green
Write-Host " - VM 총 개수        : $totalCount"
Write-Host " - RDM 보유 VM 수    : $(($summaryResults | Where-Object {$_.HasRDM -eq $true}).Count)"
Write-Host " - ISO 마운트 VM 수  : $(($summaryResults | Where-Object {$_.HasISOMounted -eq $true}).Count)"
Write-Host " - 결과 폴더         : $outputFolder"
Write-Host "=======================================================" -ForegroundColor Green
#endregion

#region 연결 종료 여부 확인
$disconnect = Read-Host "`nvCenter 연결을 종료하시겠습니까? (Y/N)"
if ($disconnect -eq 'Y' -or $disconnect -eq 'y') {
    Disconnect-VIServer -Server $viConnection -Confirm:$false
    Write-Host "vCenter 연결이 종료되었습니다." -ForegroundColor Cyan
}
#endregion
