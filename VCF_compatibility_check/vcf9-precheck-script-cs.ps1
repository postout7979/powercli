# ====================================================
# 0. Initial Environment Setup & PowerCLI Auto-Installation
# ====================================================
# 사용 예시: .\vcf9-precheck-script-cs.ps1 -HCLPath "C:\HCL"
#   -HCLPath        : VMware HCL CSV 4종(CPU_Series, IO_Devices, Systems_Servers, vSAN_I_O_Controller)이
#                      들어있는 폴더 경로. 미지정 시 스크립트와 같은 위치의 'HCL' 폴더 -> 스크립트 폴더 순으로 자동 탐색합니다.
#   ⚠ 경로 끝에 백슬래시(\)는 붙이지 마세요. (예: "C:\HCL" (O) / "C:\HCL\" (X))
param(
    [Parameter(Mandatory = $false)]
    [string]$HCLPath
)

Write-Host "===============================================================================" -ForegroundColor Cyan
Write-Host "          vSphere Inventory Report - 초기 환경 셋팅 및 모듈 확인" -ForegroundColor Cyan
Write-Host "===============================================================================" -ForegroundColor Cyan

# 1. 스크립트 실행 정책 변경 (현재 세션 스코프에서 차단 방지)
if ((Get-ExecutionPolicy) -match "Restricted") {
    Write-Host "[INIT] PowerShell 실행 정책을 RemoteSigned로 변경합니다..." -ForegroundColor Yellow
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Confirm:$false -Force
}

# 2. 최신 보안 프로토콜 (TLS 1.2) 활성화 - 모듈 다운로드 시 필수
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# 3. VMware.PowerCLI 모듈 존재 여부 확인 및 자동 설치
if (-not (Get-Module -ListAvailable -Name VMware.PowerCLI)) {
    Write-Host "[INIT] VMware.PowerCLI 모듈이 발견되지 않았습니다. 자동 설치를 시도합니다..." -ForegroundColor Yellow
    
    # NuGet 패키지 공급자 설치 여부 확인 및 설치
    if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
        Write-Host " -> NuGet 패키지 공급자를 먼저 설치합니다..." -ForegroundColor Gray
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
    }

    # PSGallery 신뢰 설정
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue

    # PowerCLI 설치 (인터넷 연결 필요)
    Write-Host " -> 인터넷 마켓(PSGallery)에서 VMware.PowerCLI 모듈을 설치 중입니다..." -ForegroundColor Gray
    Write-Host "    (환경에 따라 3~5분 정도 소요될 수 있습니다. 창을 닫지 마세요.)" -ForegroundColor DarkGray
    try {
        Install-Module -Name VMware.PowerCLI -Scope CurrentUser -AllowClobber -Force | Out-Null
        Write-Host "[SUCCESS] VMware.PowerCLI 모듈이 성공적으로 설치되었습니다!" -ForegroundColor Green
    } catch {
        Write-Host "===============================================================================" -ForegroundColor Red
        Write-Host "[ERROR] 인터넷 연결이 없거나 모듈 자동 설치에 실패했습니다." -ForegroundColor Red
        Write-Host ""
        Write-Host "[오프라인(폐쇄망) 설치 가이드]" -ForegroundColor Cyan
        Write-Host "공식 가이드: https://techdocs.broadcom.com/us/en/vmware-cis/vcf/power-cli/latest/powercli/installing-vmware-vsphere-powercli/install-powercli-offline.html" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host " [Step 1] 인터넷이 되는 PC에서 PowerCLI ZIP 파일 다운로드:" -ForegroundColor Yellow
        Write-Host "          https://developer.broadcom.com/tools/vmware-powercli/latest/" -ForegroundColor Yellow
        Write-Host "          (위 Broadcom Developer Portal에서 ZIP 파일을 내려받아 이 서버로 전송하세요)" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host " [Step 2] 이 서버의 PowerShell에서 모듈 설치 경로 확인:" -ForegroundColor Yellow
        Write-Host "          `$env:PSModulePath" -ForegroundColor Yellow
        Write-Host "          (출력된 경로 중 하나에 ZIP 내용을 압축 해제하세요)" -ForegroundColor DarkGray
        Write-Host "          (예: C:\Program Files\WindowsPowerShell\Modules)" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host " [Step 3] 복사된 파일 차단 해제 (Windows 필수):" -ForegroundColor Yellow
        Write-Host "          Get-ChildItem -Path '<압축 해제한 경로>' -Recurse | Unblock-File" -ForegroundColor Yellow
        Write-Host ""
        Write-Host " [Step 4] 설치 확인:" -ForegroundColor Yellow
        Write-Host "          Get-Module VMware* -ListAvailable" -ForegroundColor Yellow
        Write-Host "          (VMware 모듈 목록이 출력되면 설치 완료. 이후 이 스크립트를 다시 실행하세요)" -ForegroundColor DarkGray
        Write-Host "===============================================================================" -ForegroundColor Red
        Exit
    }
} else {
    Write-Host "[OK] VMware.PowerCLI 모듈이 이미 설치되어 있습니다." -ForegroundColor Green
}

# 4. PowerCLI 세션 환경 설정 (인증서 무시 및 CEIP 비활성화)
Write-Host "[INIT] PowerCLI 접속 보안 환경 정책을 구성합니다..." -ForegroundColor Gray
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false -Scope Session -WarningAction SilentlyContinue | Out-Null
Set-PowerCLIConfiguration -ParticipateInCEIP $false -Confirm:$false -Scope User -WarningAction SilentlyContinue | Out-Null
[Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}


# ----------------------------------------------------
# 0. vCenter Connection Settings & Environment Setup
# ----------------------------------------------------
Write-Host "`n===============================================================================" -ForegroundColor Cyan
Write-Host "                  vSphere Inventory Report - vCenter 연결" -ForegroundColor Cyan
Write-Host "===============================================================================" -ForegroundColor Cyan

$vCenter = Read-Host "▶ vCenter IP 또는 FQDN을 입력하세요"
if ([string]::IsNullOrWhiteSpace($vCenter)) {
    Write-Host "[ERROR] vCenter 주소는 비어 둘 수 없습니다." -ForegroundColor Red
    Exit
}

Write-Host "`n▶ vCenter 접속 계정(예: administrator@vsphere.local)과 비밀번호를 입력하세요..." -ForegroundColor Yellow
$Credential = Get-Credential

$TimeStamp = Get-Date -Format "yyyyMMdd_HHmm"
$DirName   = "vSphere_Inventory_$TimeStamp"
$ReportDir = if ($PSScriptRoot) { Join-Path $PSScriptRoot $DirName } else { ".\$DirName" }
$ZipPath   = "$ReportDir.zip"

if (-not (Test-Path $ReportDir)) { New-Item -ItemType Directory -Path $ReportDir | Out-Null }

try {
    Write-Host "`nConnecting to vCenter ($vCenter)..." -ForegroundColor Cyan
    $DefaultServer = Connect-VIServer -Server $vCenter -Credential $Credential -WarningAction SilentlyContinue
} catch {
    Write-Host "[ERROR] vCenter 연결에 실패했습니다. 주소, 계정 정보 또는 네트워크 상태를 확인하세요." -ForegroundColor Red
    Exit
}

# ----------------------------------------------------
# Pre-fetch Base Data & Optimization
# ----------------------------------------------------
Write-Host "Fetching Base Infrastructure Data (This may take a moment)..." -ForegroundColor Cyan
$Clusters      = Get-Cluster
$VMHosts       = Get-VMHost
$AllVMs        = Get-VM
$AllDatastores = Get-Datastore

Write-Host "Building Memory Lookup Tables for Fast Processing..." -ForegroundColor Cyan
$HostsByCluster = $VMHosts | Group-Object -Property @{Expression={$_.Parent.Name}} -AsHashTable -AsString
$VMsByCluster   = $AllVMs | Group-Object -Property @{Expression={$_.VMHost.Parent.Name}} -AsHashTable -AsString
$VMsByHost      = $AllVMs | Group-Object -Property @{Expression={$_.VMHost.Name}} -AsHashTable -AsString

# ----------------------------------------------------
# vCenter Server Component Version Extraction
# ----------------------------------------------------
Write-Host "Extracting vCenter Server Details..." -ForegroundColor Cyan
$vcInstance = $DefaultServer[0]
$vCenterReport = [PSCustomObject]@{
    "vCenter_Instance" = $vcInstance.Name
    "Version"          = $vcInstance.Version
    "BuildNumber"      = $vcInstance.Build
    "User"             = $vcInstance.User
}
$vCenterReport | Export-Csv -Path "$ReportDir\vCenter_Info.csv" -NoTypeInformation -Encoding UTF8

# ----------------------------------------------------
# 1. Extract Cluster Status
# ----------------------------------------------------
Write-Host "[1/12] Extracting Cluster info..." -ForegroundColor Cyan
$ClusterReport = foreach ($Cluster in $Clusters) {
    $HostsInCluster = $HostsByCluster[$Cluster.Name]
    $VMsInCluster   = $VMsByCluster[$Cluster.Name]
    
    $TotalCapGB  = 0; $TotalFreeGB = 0; $DSNames = "N/A"
    
    if ($HostsInCluster) {
        $Datastores = $HostsInCluster | Get-Datastore | Select-Object -Unique
        if ($Datastores) {
            $DSNames     = ($Datastores.Name) -join ", "
            $TotalCapGB  = [Math]::Round(($Datastores.CapacityGB | Measure-Object -Sum).Sum, 2)
            $TotalFreeGB = [Math]::Round(($Datastores.FreeSpaceGB | Measure-Object -Sum).Sum, 2)
        }
    }
    
    [PSCustomObject]@{
        "ClusterName"         = $Cluster.Name
        "HostCount"           = if ($HostsInCluster) { @($HostsInCluster).Count } else { 0 }
        "VMCount"             = if ($VMsInCluster) { @($VMsInCluster).Count } else { 0 }
        "TotalCPUCores"       = if ($HostsInCluster) { ($HostsInCluster.NumCpu | Measure-Object -Sum).Sum } else { 0 }
        "TotalMemoryGB"       = if ($HostsInCluster) { [Math]::Round(($HostsInCluster.MemoryTotalGB | Measure-Object -Sum).Sum, 2) } else { 0 }
        "ConnectedDatastores" = $DSNames
        "DS_TotalCapacityGB"  = $TotalCapGB
        "DS_TotalUsedGB"      = [Math]::Round(($TotalCapGB - $TotalFreeGB), 2)
        "DS_TotalFreeGB"      = $TotalFreeGB
    }
}
if ($ClusterReport) { $ClusterReport | Export-Csv -Path "$ReportDir\Clusters.csv" -NoTypeInformation -Encoding UTF8 }

# ----------------------------------------------------
# 2. Extract Host Level Status & Hardware
# ----------------------------------------------------
# --- 라이선스 키: $null 전달로 전체 일괄 조회 후 해시테이블 캐싱 (호스트별 개별 호출 제거) ---
$LicenseLookup = @{}
try {
    $SI = Get-View ServiceInstance -ErrorAction Stop
    $LicManager = Get-View $SI.Content.LicenseManager -ErrorAction Stop
    if ($LicManager.LicenseAssignmentManager) {
        $LicAssignMgr = Get-View $LicManager.LicenseAssignmentManager -ErrorAction Stop
        # $null 전달 시 전체 엔티티 할당 정보를 한 번에 반환 (vSphere 8 검증된 방식)
        $AllAssignments = $LicAssignMgr.QueryAssignedLicenses($null)
        foreach ($A in $AllAssignments) {
            $LicenseLookup[$A.EntityId] = $A.AssignedLicense.LicenseKey
        }
        Write-Host "[INFO] 라이선스 키 정보 일괄 조회 완료 ($($LicenseLookup.Count)건)" -ForegroundColor Gray
    }
} catch {
    Write-Host "[WARN] 라이선스 할당 정보 조회 실패, N/A로 처리합니다: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host "[2/12] Extracting Host Performance & Hardware Info..." -ForegroundColor Cyan
$HostReport = @(); $HWReport = @()
$TotalHosts = @($VMHosts).Count
$Count = 0

foreach ($HostObj in $VMHosts) {
    $Count++
    Write-Progress -Activity "Processing Hosts" -Status "Host: $($HostObj.Name)" -PercentComplete (($Count / $TotalHosts) * 100)

    $CpuUsagePct = if ($HostObj.CpuTotalMhz -gt 0) { [Math]::Round(($HostObj.CpuUsageMhz / $HostObj.CpuTotalMhz * 100), 2) } else { 0 }
    $MemUsagePct = if ($HostObj.MemoryTotalGB -gt 0) { [Math]::Round(($HostObj.MemoryUsageGB / $HostObj.MemoryTotalGB * 100), 2) } else { 0 }

    $HostReport += [PSCustomObject]@{
        "HostName"      = $HostObj.Name
        "Cluster"       = $HostObj.Parent.Name
        "State"         = $HostObj.ConnectionState
        "ESXi_Version"  = $HostObj.Version
        "BuildNumber"   = $HostObj.Build
        "CPU_Usage_Pct" = $CpuUsagePct
        "Mem_Usage_Pct" = $MemUsagePct
    }

    if ($HostObj.ConnectionState -eq "Connected") {
        $SysInfo = $HostObj.ExtensionData.Hardware.SystemInfo
        $CpuInfo = $HostObj.ExtensionData.Hardware.CpuInfo
        $BiosInfo = $HostObj.ExtensionData.Hardware.BiosInfo
        
        $ServiceTag = ($SysInfo.OtherIdentifyingInfo | Where-Object {$_.IdentifierType.Key -eq "ServiceTag"}).IdentifierValue
        if (-not $ServiceTag) { $ServiceTag = $SysInfo.Uuid }

        $HWReport += [PSCustomObject]@{
            "HostName"           = $HostObj.Name
            "Cluster"            = $HostObj.Parent.Name
            "Vendor"             = $SysInfo.Vendor
            "Model"              = $SysInfo.Model
            "ServiceTag_UUID"    = $ServiceTag
            "License_Key"        = if ($LicenseLookup.ContainsKey($HostObj.ExtensionData.MoRef.Value)) { $LicenseLookup[$HostObj.ExtensionData.MoRef.Value] } else { "N/A" }
            "CPU_Model"          = if ($HostObj.ExtensionData.Hardware.CpuPkg) { $HostObj.ExtensionData.Hardware.CpuPkg[0].Description } else { "N/A" }
            "CPU_Vendor"         = if ($HostObj.ExtensionData.Hardware.CpuPkg) { $HostObj.ExtensionData.Hardware.CpuPkg[0].Vendor } else { "N/A" }
            "CPU_Sockets"        = $CpuInfo.NumCpuPackages
            "CPU_CoresPerSocket" = if ($CpuInfo.NumCpuPackages -gt 0) { $CpuInfo.NumCpuCores / $CpuInfo.NumCpuPackages } else { 0 }
            "Total_Cores"        = $CpuInfo.NumCpuCores
            "Memory_GB"          = [Math]::Round($HostObj.ExtensionData.Hardware.MemorySize / 1GB, 2)
            "BIOS_Version"       = $BiosInfo.BiosVersion
            "ESXi_FullVersion"   = $HostObj.ExtensionData.Config.Product.FullName
        }
    }
}
if ($HostReport) { $HostReport | Export-Csv -Path "$ReportDir\Hosts_Perf.csv" -NoTypeInformation -Encoding UTF8 }
if ($HWReport) { $HWReport | Export-Csv -Path "$ReportDir\Hosts_Hardware.csv" -NoTypeInformation -Encoding UTF8 }

# ----------------------------------------------------
# 3. Extract VM Level Status & Disk (VMTools 정보 추가됨)
# ----------------------------------------------------
Write-Host "[3/12] Extracting VM Status & Disks (with VMTools Versions)..." -ForegroundColor Cyan
$VMReport = @(); $DiskReport = @()
$PoweredOnVMs = $AllVMs | Where-Object {$_.PowerState -eq "PoweredOn"}

$Stats = Get-Stat -Entity $PoweredOnVMs -Stat "cpu.ready.summation","cpu.costop.summation" -MaxSamples 1 -Realtime -WarningAction SilentlyContinue
$StatsLookup = if ($Stats) { $Stats | Group-Object -Property @{Expression={$_.Entity.Id}} -AsHashTable } else { @{} }

$TotalVMs = @($AllVMs).Count
$Count = 0

foreach ($VM in $AllVMs) {
    $Count++
    if ($Count % 10 -eq 0) { Write-Progress -Activity "Processing VMs" -Status "VM: $($VM.Name)" -PercentComplete (($Count / $TotalVMs) * 100) }

    $ReadyPct = 0; $CostopPct = 0; $CpuUsageMhz = 0; $MemActiveMB = 0; $MemConsumedMB = 0; $MemColdMB = 0

    if ($VM.PowerState -eq "PoweredOn") {
        $VMStats = $StatsLookup[$VM.Id]
        if ($VMStats) {
            $ReadyMs = ($VMStats | Where-Object {$_.MetricId -eq "cpu.ready.summation"} | Measure-Object Value -Sum).Sum
            $CostopMs = ($VMStats | Where-Object {$_.MetricId -eq "cpu.costop.summation"} | Measure-Object Value -Sum).Sum
            $ReadyPct = if ($ReadyMs) { [Math]::Round(($ReadyMs / 20000) * 100, 2) } else { 0 }
            $CostopPct = if ($CostopMs) { [Math]::Round(($CostopMs / 20000) * 100, 2) } else { 0 }
        }

        $QStats = $VM.ExtensionData.Summary.QuickStats
        $CpuUsageMhz = $QStats.OverallCpuUsage
        $MemActiveMB = $QStats.GuestMemoryUsage
        $MemConsumedMB = $QStats.HostMemoryUsage
        $MemColdMB = if (($MemConsumedMB - $MemActiveMB) -gt 0) { $MemConsumedMB - $MemActiveMB } else { 0 }
    }

    # VM Tools 상세 정보 바인딩
    $ToolsVersion = if ($VM.ExtensionData.Guest.ToolsVersion) { $VM.ExtensionData.Guest.ToolsVersion } else { "N/A" }
    $ToolsStatus  = if ($VM.ExtensionData.Guest.ToolsStatus) { $VM.ExtensionData.Guest.ToolsStatus } else { "N/A" }

    $VMReport += [PSCustomObject]@{
        "VMName"          = $VM.Name
        "PowerState"      = $VM.PowerState
        "Cluster"         = if ($VM.VMHost) { $VM.VMHost.Parent.Name } else { "N/A" }
        "ESXi_Host"       = if ($VM.VMHost) { $VM.VMHost.Name } else { "N/A" }
        "NumCPU"          = $VM.NumCpu
        "MemoryGB"        = $VM.MemoryGB
        "VMTools_Version" = $ToolsVersion  # ★ 요구사항: VM Tools 버전 추가
        "VMTools_Status"  = $ToolsStatus   # ★ 요구사항: VM Tools 작동 상태 추가 (예: toolsOk, toolsOld)
        "CPU_Ready_Pct"   = "$ReadyPct %"
        "CPU_Costop_Pct"  = "$CostopPct %"
        "CPU_Usage_MHz"   = $CpuUsageMhz
        "Mem_Active_MB"   = $MemActiveMB
        "Mem_Consumed_MB" = $MemConsumedMB
        "Mem_Cold_MB"     = $MemColdMB
        "ProvisionedGB"   = [Math]::Round($VM.ProvisionedSpaceGB, 2)
        "UsedSpaceGB"     = [Math]::Round($VM.UsedSpaceGB, 2)
    }

    foreach ($Device in $VM.ExtensionData.Config.Hardware.Device) {
        if ($Device -is [VMware.Vim.VirtualDisk]) {
            $IsRDM = $Device.Backing -is [VMware.Vim.VirtualDiskRawDiskMappingVer1BackingInfo]
            $IsShared = ($Device.Backing.Sharing -eq "sharingMultiWriter")
            $IsThick = ($Device.Backing -is [VMware.Vim.VirtualDiskFlatVer2BackingInfo] -and $Device.Backing.ThinProvisioned -eq $false)

            if ($IsRDM -or $IsShared -or $IsThick) {
                $CapacityGB = if ($Device.CapacityInBytes) { [Math]::Round($Device.CapacityInBytes / 1GB, 2) } else { [Math]::Round($Device.CapacityInKB / 1MB, 2) }
                $DiskType = if ($IsRDM) { "RDM" } elseif ($IsShared) { "Shared" } else { "Thick" }
                
                $DiskReport += [PSCustomObject]@{
                    "VMName"     = $VM.Name
                    "Cluster"    = $VM.VMHost.Parent.Name
                    "DiskName"   = $Device.DeviceInfo.Label
                    "DiskType"   = $DiskType
                    "CapacityGB" = $CapacityGB
                    "IsRDM"      = $IsRDM
                    "IsShared"   = $IsShared
                    "IsThick"    = $IsThick
                }
            }
        }
    }
}
Write-Progress -Activity "Processing VMs" -Completed
if ($VMReport) { $VMReport | Export-Csv -Path "$ReportDir\VMs_Status.csv" -NoTypeInformation -Encoding UTF8 }
if ($DiskReport) { $DiskReport | Export-Csv -Path "$ReportDir\Special_Disks(RDM_Shared_Thick).csv" -NoTypeInformation -Encoding UTF8 }

# ----------------------------------------------------
# 4. Extract Datastores Status
# ----------------------------------------------------
Write-Host "[4/12] Building Advanced Storage/LUN Mapping Lookup Tables..." -ForegroundColor Cyan
$LUNLookup = @{}
$ConnectedHosts = $VMHosts | Where-Object {$_.ConnectionState -eq "Connected"}

foreach ($H in $ConnectedHosts) {
    $storageDevice = $H.ExtensionData.Config.StorageDevice
    if (-not $storageDevice) { continue }
    
    $KeyToLunId = @{}
    foreach ($adapter in $storageDevice.ScsiTopology.Adapter) {
        foreach ($target in $adapter.Target) {
            foreach ($tLun in $target.Lun) {
                $KeyToLunId[$tLun.ScsiLun] = $tLun.Lun
            }
        }
    }
    
    $PathInfo = @{}
    foreach ($mpLun in $storageDevice.MultipathInfo.Lun) {
        $PathInfo[$mpLun.Id] = @{
            Policy = $mpLun.Policy.Policy
            SATP   = $mpLun.StorageArrayTypePolicy
        }
    }
    
    foreach ($lun in $storageDevice.ScsiLun) {
        if ([string]::IsNullOrWhiteSpace($lun.CanonicalName)) { continue }
        if ($LUNLookup.ContainsKey($lun.CanonicalName)) { continue } 
        
        $lunId = if ($KeyToLunId.ContainsKey($lun.Key)) { $KeyToLunId[$lun.Key] } else { "N/A" }
        $mp = if ($PathInfo.ContainsKey($lun.CanonicalName)) { $PathInfo[$lun.CanonicalName] } else { $null }
        
        $LUNLookup[$lun.CanonicalName] = @{
            LunId           = $lunId
            Vendor          = $lun.Vendor
            Model           = $lun.Model
            MultipathPolicy = if ($mp) { $mp.Policy } else { "N/A" }
            SATP            = if ($mp) { $mp.SATP } else { "N/A" }
        }
    }
}

Write-Host "Fetching Bulk Datastore IOPS Performance Counters (Past 2 Hours)..." -ForegroundColor Cyan
$DSStats = Get-Stat -Entity $AllDatastores -Stat "datastore.numberReadAveraged.average","datastore.numberWriteAveraged.average" -Start (Get-Date).AddHours(-2) -ErrorAction SilentlyContinue

if ($DSStats) {
    $DSStatsLookup = $DSStats | Group-Object -Property @{Expression={$_.Entity.Id}} -AsHashTable -AsString
} else {
    $DSStatsLookup = @{}
}

Write-Host "Extracting All Datastores with Comprehensive Storage & IOPS Details..." -ForegroundColor Cyan
$DSReport = foreach ($DS in $AllDatastores) {
    $AssignedCluster = ($Clusters | Where-Object {$_.ExtensionData.Datastore -contains $DS.Id}).Name | Select-Object -First 1
    $CapGB   = [Math]::Round($DS.CapacityGB, 2)
    $FreeGB  = [Math]::Round($DS.FreeSpaceGB, 2)
    $UsedGB  = [Math]::Round(($CapGB - $FreeGB), 2)
    $FreePct = if ($CapGB -gt 0) { [Math]::Round(($FreeGB / $CapGB) * 100, 2) } else { 0 }

    $ReadIOPS = 0; $WriteIOPS = 0; $TotalIOPS = 0
    $MyStats = $DSStatsLookup[$DS.Id]
    if ($MyStats) {
        $ReadSamples = $MyStats | Where-Object { $_.MetricId -eq "datastore.numberReadAveraged.average" } | Measure-Object -Property Value -Average
        $WriteSamples = $MyStats | Where-Object { $_.MetricId -eq "datastore.numberWriteAveraged.average" } | Measure-Object -Property Value -Average
        
        if ($ReadSamples.Average) { $ReadIOPS = [Math]::Round($ReadSamples.Average, 2) }
        if ($WriteSamples.Average) { $WriteIOPS = [Math]::Round($WriteSamples.Average, 2) }
        $TotalIOPS = [Math]::Round(($ReadIOPS + $WriteIOPS), 2)
    }

    $VMFS_Version    = "N/A"; $BlockSizeMB     = "N/A"
    $RemoteHost      = "N/A"; $RemotePath      = "N/A"
    $CanonicalNames  = "N/A"; $LUN_IDs         = "N/A"
    $DiskVendors     = "N/A"; $DiskModels      = "N/A"
    $MultipathPolicy = "N/A"; $SATP            = "N/A"

    $dsInfo = $DS.ExtensionData.Info
    if ($DS.Type -match "VMFS") {
        if ($dsInfo.Vmfs) {
            $VMFS_Version = $dsInfo.Vmfs.Version
            $BlockSizeMB  = $dsInfo.Vmfs.BlockSizeMb
            
            $cNames = @(); $lIds = @(); $vendors = @(); $models = @(); $mpPolicies = @(); $satps = @()

            foreach ($extent in $dsInfo.Vmfs.Extent) {
                $cName = $extent.DiskName
                $cNames += $cName
                
                if ($LUNLookup.ContainsKey($cName)) {
                    $lunData = $LUNLookup[$cName]
                    $lIds += $lunData.LunId
                    if ($lunData.Vendor) { $vendors += $lunData.Vendor.Trim() }
                    if ($lunData.Model) { $models += $lunData.Model.Trim() }
                    $mpPolicies += $lunData.MultipathPolicy
                    $satps += $lunData.SATP
                }
            }

            $CanonicalNames  = ($cNames | Select-Object -Unique) -join ", "
            $LUN_IDs         = ($lIds | Select-Object -Unique) -join ", "
            $DiskVendors     = ($vendors | Select-Object -Unique) -join ", "
            $DiskModels      = ($models | Select-Object -Unique) -join ", "
            $MultipathPolicy = ($mpPolicies | Select-Object -Unique) -join ", "
            $SATP            = ($satps | Select-Object -Unique) -join ", "
        }
    }
    elseif ($DS.Type -match "NFS") {
        if ($dsInfo.Nas) {
            $RemoteHost = $dsInfo.Nas.RemoteHost
            $RemotePath = $dsInfo.Nas.RemotePath
        }
    }
    elseif ($DS.Type -match "vSAN") {
        $CanonicalNames  = "Internal vSAN Object Block"
        $MultipathPolicy = "vSAN Default Storage Policy Driven"
    }

    [PSCustomObject]@{
        "Cluster"             = if ($AssignedCluster) { $AssignedCluster } else { "N/A" }
        "DatastoreName"       = $DS.Name
        "Storage_Type"        = $DS.Type
        "Total_Cap_GB"        = $CapGB
        "Used_GB"             = $UsedGB
        "Free_GB"             = $FreeGB
        "Free_Percentage"     = "$FreePct %"
        "Read_IOPS_Avg"       = $ReadIOPS
        "Write_IOPS_Avg"      = $WriteIOPS
        "Total_IOPS_Avg"      = $TotalIOPS
        "LUN_IDs"             = $LUN_IDs
        "CanonicalNames"      = $CanonicalNames
        "Storage_Vendor"      = $DiskVendors
        "Storage_Model"       = $DiskModels
        "Multipath_Policy"    = $MultipathPolicy
        "SATP_Policy"         = $SATP
        "VMFS_Version"        = $VMFS_Version
        "BlockSizeMB"         = $BlockSizeMB
        "RemoteHost_NFS"      = $RemoteHost
        "RemotePath_NFS"      = $RemotePath
        "SIOC_Enabled"        = $DS.StorageIOControlEnabled
        "Thin_Provision_Supp" = $DS.ExtensionData.Capability.ThinProvisioningSupported
    }
}
if ($DSReport) { $DSReport | Export-Csv -Path "$ReportDir\Datastores.csv" -NoTypeInformation -Encoding UTF8 }

# ----------------------------------------------------
# 5. Extract Virtual Switches
# ----------------------------------------------------
Write-Host "[5/12] Extracting Virtual Switches & VDS Versions..." -ForegroundColor Cyan
$VswitchReport = @()

$VDSSwitches = Get-VDSwitch -ErrorAction SilentlyContinue
$VDSCache = @{}
foreach ($vds in $VDSSwitches) {
    $VDSCache[$vds.Name] = $vds.Version
}

foreach ($H in $VMHosts) {
    if ($H.ConnectionState -eq "Connected") {
        $Switches = Get-VirtualSwitch -VMHost $H -ErrorAction SilentlyContinue
        foreach ($vSwitch in $Switches) {
            
            $IsDVS = $vSwitch.GetType().Name -match "Distributed"
            $SwitchType = if ($IsDVS) { "DVS (VDS)" } else { "Standard" }
            $SwitchVersion = "N/A"
            if ($IsDVS -and $VDSCache.ContainsKey($vSwitch.Name)) {
                $SwitchVersion = $VDSCache[$vSwitch.Name]
            }

            $VswitchReport += [PSCustomObject]@{
                "Cluster"        = $H.Parent.Name
                "HostName"       = $H.Name
                "SwitchName"     = $vSwitch.Name
                "SwitchType"     = $SwitchType
                "Switch_Version" = $SwitchVersion
                "NumPorts"       = $vSwitch.NumPorts
                "MTU"            = $vSwitch.Mtu
            }
        }
    }
}
if ($VswitchReport) { $VswitchReport | Export-Csv -Path "$ReportDir\Virtual_Switches.csv" -NoTypeInformation -Encoding UTF8 }

# ----------------------------------------------------
# 6. Build ESXCLI Cache for Advanced Hardware Queries
# ----------------------------------------------------
Write-Host "[6/12] Building Advanced ESXCLI Cache for Driver/Firmware Versions (Takes time)..." -ForegroundColor Cyan
$EsxCliCache = @{}
$VibCache = @{}
$TotalEsx = @($ConnectedHosts).Count
$CountEsx = 0

foreach ($H in $ConnectedHosts) {
    $CountEsx++
    Write-Progress -Activity "Caching ESXCLI Data" -Status "Host: $($H.Name)" -PercentComplete (($CountEsx / $TotalEsx) * 100)
    
    $cli = Get-EsxCli -VMHost $H -V2 -ErrorAction SilentlyContinue
    $EsxCliCache[$H.Name] = $cli
    if ($cli) {
        try { $VibCache[$H.Name] = $cli.software.vib.list.Invoke() } catch {}
    }
}
Write-Progress -Activity "Caching ESXCLI Data" -Completed

# ----------------------------------------------------
# 7. Extract Physical NIC Details
# ----------------------------------------------------
Write-Host "[7/12] Extracting Physical NICs..." -ForegroundColor Cyan
$PnicReport = @()
foreach ($H in $ConnectedHosts) {
    $esxcli = $EsxCliCache[$H.Name]
    # nic.list 결과를 이름 기준 해시테이블로 인덱싱 (이후 O(1) 조회 가능)
    $NicListHash = @{}
    if ($esxcli) {
        try {
            $NicList = $esxcli.network.nic.list.Invoke()
            foreach ($n in $NicList) { $NicListHash[$n.Name] = $n }
        } catch {}
    }

    foreach ($P in $H.ExtensionData.Config.Network.Pnic) {
        $Model = "N/A"; $MTU = "N/A"; $Driver = "N/A"; $AutoNeg = "N/A"
        $DriverVersion = "N/A"; $FirmwareVersion = "N/A"

        $PciDev = $H.ExtensionData.Hardware.PciDevice | Where-Object { $_.Id -eq $P.Pci }
        if ($PciDev) { $Model = "$($PciDev.VendorName) $($PciDev.DeviceName)" }

        # nic.list 캐시에서 O(1) 조회 (nic.get 개별 API 호출 제거)
        $nicCli = $NicListHash[$P.Device]
        if ($nicCli) {
            $MTU    = $nicCli.MTU
            $Driver = $nicCli.Driver
            if ([string]::IsNullOrWhiteSpace($Model) -or $Model -eq "N/A") { $Model = $nicCli.Description }
            # nic.list 에 Speed 및 AutoNegotiate 정보가 포함된 경우 활용
            if ($null -ne $nicCli.AutoNegotiate) { $AutoNeg = $nicCli.AutoNegotiate }
        }

        # 드라이버 버전/펌웨어는 ExtensionData(이미 로드된 데이터)에서 추출 — 추가 API 호출 없음
        $PnicInfo = $H.ExtensionData.Config.Network.Pnic | Where-Object { $_.Device -eq $P.Device }
        if ($PnicInfo) {
            if ($PnicInfo.Driver) { $Driver = $PnicInfo.Driver }
        }
        # 펌웨어 버전은 별도 ExtensionData 키가 없으므로 ESXCLI VIB 캐시에서 드라이버명으로 추정 (가능 시)
        if ($DriverVersion -eq "N/A" -and $Driver -ne "N/A" -and $VibCache[$H.Name]) {
            $DriverVib = $VibCache[$H.Name] | Where-Object { $_.Name -like "*$Driver*" } | Select-Object -First 1
            if ($DriverVib) { $DriverVersion = $DriverVib.Version }
        }

        $PnicReport += [PSCustomObject]@{
            "Cluster"          = $H.Parent.Name
            "HostName"         = $H.Name
            "Device"           = $P.Device
            "Model"            = $Model
            "MAC"              = $P.Mac
            "MTU"              = $MTU
            "AutoNeg"          = $AutoNeg
            "Driver"           = $Driver
            "Driver_Version"   = $DriverVersion
            "Firmware_Version" = $FirmwareVersion
            "PCIe_ID"          = $P.Pci
        }
    }
}
if ($PnicReport) { $PnicReport | Export-Csv -Path "$ReportDir\Physical_NICs.csv" -NoTypeInformation -Encoding UTF8 }

# ----------------------------------------------------
# 8. Extract Physical HBAs (Fibre Channel)
# ----------------------------------------------------
Write-Host "[8/12] Extracting Physical HBAs (FibreChannel)..." -ForegroundColor Cyan
$HbaReport = foreach ($H in $ConnectedHosts) {
    $esxcli = $EsxCliCache[$H.Name]
    $vibs = $VibCache[$H.Name]
    $StorageSystem = Get-View $H.ExtensionData.ConfigManager.StorageSystem
    
    foreach ($Hba in $StorageSystem.StorageDeviceInfo.HostBusAdapter) {
        if ($Hba -is [VMware.Vim.HostFibreChannelHba]) {
            $DriverVersion = "N/A"
            $FirmwareVersion = if ($Hba.FirmwareVersion) { $Hba.FirmwareVersion } else { "N/A" }
            $DriverName = $Hba.DriverName
            
            if ($esxcli -and $DriverName) {
                try {
                    $modArgs = $esxcli.system.module.get.CreateArgs()
                    $modArgs.module = $DriverName
                    $modInfo = $esxcli.system.module.get.Invoke($modArgs)
                    if ($modInfo -and $modInfo.Version) { $DriverVersion = $modInfo.Version }
                } catch {}
                
                if ($DriverVersion -eq "N/A" -and $vibs) {
                    $safeName = $DriverName.Replace("_","-")
                    $matchedVib = $vibs | Where-Object { $_.Name -match $safeName } | Select-Object -First 1
                    if ($matchedVib) { $DriverVersion = $matchedVib.Version }
                }
            }

            $wwnString = "N/A"
            if ($Hba.PortWorldWideName) {
                $wwnString = ('{0:x16}' -f $Hba.PortWorldWideName) -replace '(..)(?!$)', '$1:'
            }

            [PSCustomObject]@{
                "Cluster"          = $H.Parent.Name
                "HostName"         = $H.Name
                "Device"           = $Hba.Device
                "Model"            = $Hba.Model
                "Driver"           = $DriverName
                "Driver_Version"   = $DriverVersion
                "Firmware_Version" = $FirmwareVersion
                "Speed_Gbps"       = if ($Hba.Speed) { $Hba.Speed / 1000 } else { "N/A" }
                "Status"           = $Hba.Status
                "WWN"              = $wwnString
            }
        }
    }
}
if ($HbaReport) { $HbaReport | Export-Csv -Path "$ReportDir\HBA_Cards.csv" -NoTypeInformation -Encoding UTF8 }

# ----------------------------------------------------
# 9. Extract RAID Controllers
# ----------------------------------------------------
Write-Host "[9/12] Extracting Physical RAID Controllers..." -ForegroundColor Cyan
$RaidReport = foreach ($H in $ConnectedHosts) {
    $esxcli = $EsxCliCache[$H.Name]
    $vibs = $VibCache[$H.Name]
    $StorageSystem = Get-View $H.ExtensionData.ConfigManager.StorageSystem
    
    foreach ($Hba in $StorageSystem.StorageDeviceInfo.HostBusAdapter) {
        if ($Hba -is [VMware.Vim.HostHostBusAdapter] -and $Hba -isnot [VMware.Vim.HostFibreChannelHba] -and $Hba -isnot [VMware.Vim.HostInternetScsiHba]) {
            
            $Model = $Hba.Model
            if ([string]::IsNullOrWhiteSpace($Model)) {
                $PciDev = $H.ExtensionData.Hardware.PciDevice | Where-Object { $_.Id -eq $Hba.Pci }
                if ($PciDev) { $Model = "$($PciDev.VendorName) $($PciDev.DeviceName)" }
            }

            $DriverName = if ($Hba.DriverName) { $Hba.DriverName } elseif ($Hba.Driver) { $Hba.Driver } else { "N/A" }
            $DriverVersion = "N/A"
            $FirmwareVersion = "N/A" 
            
            if ($Hba.FirmwareVersion) { $FirmwareVersion = $Hba.FirmwareVersion }

            if ($esxcli -and $DriverName -ne "N/A") {
                try {
                    $modArgs = $esxcli.system.module.get.CreateArgs()
                    $modArgs.module = $DriverName
                    $modInfo = $esxcli.system.module.get.Invoke($modArgs)
                    if ($modInfo -and $modInfo.Version) { $DriverVersion = $modInfo.Version }
                } catch {}
                
                if ($DriverVersion -eq "N/A" -and $vibs) {
                    $safeName = $DriverName.Replace("_","-")
                    $matchedVib = $vibs | Where-Object { $_.Name -match $safeName } | Select-Object -First 1
                    if ($matchedVib) { $DriverVersion = $matchedVib.Version }
                }
            }

            [PSCustomObject]@{
                "Cluster"          = $H.Parent.Name
                "HostName"         = $H.Name
                "Device"           = $Hba.Device
                "Model"            = if ($Model) { $Model } else { "N/A" }
                "Driver"           = $DriverName
                "Driver_Version"   = $DriverVersion
                "Firmware_Version" = $FirmwareVersion
                "PCIDeviceID"      = $Hba.Pci
            }
        }
    }
}
if ($RaidReport) { $RaidReport | Export-Csv -Path "$ReportDir\RAID_Controllers.csv" -NoTypeInformation -Encoding UTF8 }

# ----------------------------------------------------
# 10. Hardware Compatibility Check (VCF9 / ESXi 9.0 & 9.1 HCL)
# ----------------------------------------------------
Write-Host "[10/12] Checking Hardware Compatibility against VCF9 HCL Data (ESXi 9.0 / 9.1)..." -ForegroundColor Cyan

function Format-ReleaseText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return "N/A" }
    return ($Text -replace '[\r\n]+', ', ').Trim()
}

# --- 제조사/모델명 "유사도" 매칭용 함수 (완전히 동일한 명칭이 아니어도 핵심 토큰이 겹치면 매칭) ---
function Get-Tokens {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    return @(($Text.ToLower() -split '[^a-z0-9]+') | Where-Object { $_.Length -ge 2 })
}

function Get-TokenWeight {
    param([string]$Token)
    # 숫자가 포함된 토큰(모델 넘버/SKU 등 실제 식별자)에 일반 단어보다 더 높은 가중치 부여
    if ($Token -match '[0-9]') { return 3 } else { return 1 }
}

function Get-SimilarityScore {
    param([string]$Detected, [string]$HCLValue)
    $hTokens = @(Get-Tokens $HCLValue)
    if ($hTokens.Count -eq 0) { return 0 }
    $dTokens = @(Get-Tokens $Detected)

    $TotalWeight = 0; $MatchWeight = 0
    foreach ($t in $hTokens) {
        $w = Get-TokenWeight -Token $t
        $TotalWeight += $w
        if ($dTokens -contains $t) { $MatchWeight += $w }
    }
    if ($TotalWeight -eq 0) { return 0 }
    return [Math]::Round(($MatchWeight / $TotalWeight) * 100, 0)
}

function Find-BestHCLMatch {
    param([array]$Table, [hashtable]$Index, [string]$Detected, [string[]]$Fields)
    if (-not $Table -or @($Table).Count -eq 0) { return $null }

    # 탐지된 문자열의 토큰 중 숫자 포함 토큰(모델번호) 우선, 없으면 첫 토큰으로 후보 그룹 선택
    $DetTokens = @(Get-Tokens $Detected)
    $Candidates = $null
    if ($Index) {
        foreach ($t in ($DetTokens | Sort-Object { -([int]($_ -match '[0-9]')) })) {
            if ($Index.ContainsKey($t)) { $Candidates = $Index[$t]; break }
        }
        # 인덱스에 매칭되는 그룹이 없으면 전체 테이블로 폴백
        if (-not $Candidates) { $Candidates = $Table }
    } else {
        $Candidates = $Table
    }

    $Best = $null; $BestScore = -1
    foreach ($Row in $Candidates) {
        $HCLText = ($Fields | ForEach-Object { $Row.$_ }) -join ' '
        $Score = Get-SimilarityScore -Detected $Detected -HCLValue $HCLText
        if ($Score -gt $BestScore) { $BestScore = $Score; $Best = $Row }
    }
    if ($null -eq $Best) { return $null }
    return [PSCustomObject]@{ Row = $Best; Score = $BestScore }
}

# --- HCL 인덱스 빌드: 브랜드명/모델명의 모든 토큰을 키로 역인덱스 생성 ---
# (탐지된 장비명의 임의 토큰 → 매칭 후보 행 목록으로 즉시 좁혀줌)
function Build-HCLIndex {
    param([array]$Table, [string[]]$Fields)
    $Index = @{}
    if (-not $Table -or @($Table).Count -eq 0) { return $Index }
    foreach ($Row in $Table) {
        $HCLText = ($Fields | ForEach-Object { $Row.$_ }) -join ' '
        $Tokens = @(Get-Tokens $HCLText)
        foreach ($t in $Tokens) {
            if (-not $Index.ContainsKey($t)) { $Index[$t] = [System.Collections.Generic.List[object]]::new() }
            $Index[$t].Add($Row)
        }
    }
    return $Index
}

# --- CPU "모델 시리즈(세대)" 매칭용 함수: 세부 SKU가 아니라 세대 코드 기준으로 비교 ---
function Get-CpuFamilyCodes {
    param([string]$SeriesText)
    return @([regex]::Matches($SeriesText, '[0-9][0-9A-Za-z]{2,5}') | ForEach-Object { ($_.Value -replace '[^0-9]', '') } | Where-Object { $_.Length -ge 2 })
}

function Find-CpuFamilyMatch {
    param([string]$DetectedModel, [string]$Vendor, [array]$CpuTable)
    if (-not $CpuTable -or @($CpuTable).Count -eq 0 -or [string]::IsNullOrWhiteSpace($DetectedModel)) { return $null }
    $Skus = @([regex]::Matches($DetectedModel, '\b[0-9]{4}\b') | ForEach-Object { $_.Value })
    if ($Skus.Count -eq 0) { return $null }
    $IsIntel = $Vendor -match '(?i)intel'

    foreach ($Row in $CpuTable) {
        $Codes = Get-CpuFamilyCodes -SeriesText $Row.'CPU Series'
        foreach ($Sku in $Skus) {
            foreach ($Code in $Codes) {
                if ($Code.Length -lt 2) { continue }
                $IsMatch = $false
                if ($IsIntel) {
                    $IsMatch = ($Sku.Substring(0, 2) -eq $Code.Substring(0, 2))
                } else {
                    $IsMatch = ($Sku.Substring(3, 1) -eq $Code.Substring($Code.Length - 1)) -and ($Sku.Substring(0, 1) -eq $Code.Substring(0, 1))
                }
                if ($IsMatch) {
                    return [PSCustomObject]@{ Row = $Row; Sku = $Sku; Code = $Code }
                }
            }
        }
    }
    return $null
}

# --- ESXi 9.0 / 9.1 두 버전을 한 번에 판정하는 헬퍼 ---
function Get-VersionedMatch {
    param([array]$Table90, [array]$Table91, [hashtable]$Index90, [hashtable]$Index91,
          [string]$Detected, [string[]]$Fields, [int]$Threshold)
    $Match90 = Find-BestHCLMatch -Table $Table90 -Index $Index90 -Detected $Detected -Fields $Fields
    $Match91 = Find-BestHCLMatch -Table $Table91 -Index $Index91 -Detected $Detected -Fields $Fields
    $Status90 = if ($Match90 -and $Match90.Score -ge $Threshold) { "OK" } else { "MISMATCH" }
    $Status91 = if ($Match91 -and $Match91.Score -ge $Threshold) { "OK" } else { "MISMATCH" }

    $Best = $null
    if ($Match90 -and $Match91) { $Best = if ($Match90.Score -ge $Match91.Score) { $Match90 } else { $Match91 } }
    elseif ($Match90) { $Best = $Match90 } elseif ($Match91) { $Best = $Match91 }

    return [PSCustomObject]@{ Status90 = $Status90; Status91 = $Status91; Match90 = $Match90; Match91 = $Match91; Best = $Best }
}

function Get-VersionedCpuMatch {
    param([array]$CpuTable90, [array]$CpuTable91, [string]$DetectedModel, [string]$Vendor)
    $Match90 = Find-CpuFamilyMatch -DetectedModel $DetectedModel -Vendor $Vendor -CpuTable $CpuTable90
    $Match91 = Find-CpuFamilyMatch -DetectedModel $DetectedModel -Vendor $Vendor -CpuTable $CpuTable91
    $Status90 = if ($Match90) { "OK" } else { "MISMATCH" }
    $Status91 = if ($Match91) { "OK" } else { "MISMATCH" }
    $Best = if ($Match90) { $Match90 } elseif ($Match91) { $Match91 } else { $null }
    return [PSCustomObject]@{ Status90 = $Status90; Status91 = $Status91; Match90 = $Match90; Match91 = $Match91; Best = $Best }
}

$MatchThreshold = 50   # 유사도(%)가 이 값 이상이면 OK, 미달이면 MISMATCH (단, 가장 유사한 후보는 항상 함께 표시)

# HCL 폴더 자동 탐색: -HCLPath 미지정 시 '스크립트경로\HCL' -> '스크립트경로' 순으로 탐색
if (-not [string]::IsNullOrWhiteSpace($HCLPath)) {
    $HCLPath = $HCLPath.Trim().TrimEnd('\', '/')
}
if ([string]::IsNullOrWhiteSpace($HCLPath)) {
    $DefaultHCLSub = if ($PSScriptRoot) { Join-Path $PSScriptRoot "HCL" } else { ".\HCL" }
    $HCLPath = if (Test-Path $DefaultHCLSub) { $DefaultHCLSub } elseif ($PSScriptRoot) { $PSScriptRoot } else { "." }
}

function Get-HCLFileType {
    param([string]$FilePath)
    try {
        $HeaderLine = Get-Content -Path $FilePath -TotalCount 1 -Encoding UTF8 -ErrorAction Stop
    } catch { return $null }
    if ([string]::IsNullOrWhiteSpace($HeaderLine)) { return $null }

    # 파일명이 아니라 CSV 헤더(컬럼명) 내용으로 4종 HCL 파일을 식별 (파일명이 바뀌어도 안전)
    if ($HeaderLine -match 'CPUID' -and $HeaderLine -match 'CPU Series')   { return "CPU" }
    if ($HeaderLine -match 'Partner Name')                                 { return "Server" }
    if ($HeaderLine -match 'Device Type')                                  { return "IODevice" }
    if ($HeaderLine -match 'Brand Name' -and $HeaderLine -match 'Feature') { return "vSAN" }
    return $null
}

function Get-HCLFileVersion {
    param([string]$FileName)
    # 파일명에 9_0 / 9.0 표시가 있으면 ESXi 9.0 전용, 9_1 / 9.1 표시가 있으면 ESXi 9.1 전용 파일로 인식
    $Has90 = $FileName -match '9[_\.]0'
    $Has91 = $FileName -match '9[_\.]1'
    if ($Has90 -and -not $Has91) { return "9.0" }
    if ($Has91 -and -not $Has90) { return "9.1" }
    return "Both"   # 버전 표시가 없거나 모호하면 9.0/9.1 공통 데이터로 취급
}

function Import-HCLData {
    param([string]$Path)
    $Result = [PSCustomObject]@{
        CPU90 = @(); CPU91 = @()
        IODevice90 = @(); IODevice91 = @()
        Server90 = @(); Server91 = @()
        vSAN90 = @(); vSAN91 = @()
        FoundFiles = @()
    }
    if (-not (Test-Path $Path)) { return $Result }

    $CsvFiles = Get-ChildItem -Path $Path -Filter "*.csv" -File -ErrorAction SilentlyContinue
    foreach ($File in $CsvFiles) {
        $Type = Get-HCLFileType -FilePath $File.FullName
        if (-not $Type) { continue }
        try {
            $Data = Import-Csv -Path $File.FullName -Encoding UTF8 -ErrorAction Stop
        } catch { continue }

        $Version = Get-HCLFileVersion -FileName $File.Name

        switch ($Type) {
            "CPU"      { if ($Version -ne "9.1") { $Result.CPU90 += $Data };      if ($Version -ne "9.0") { $Result.CPU91 += $Data } }
            "IODevice" { if ($Version -ne "9.1") { $Result.IODevice90 += $Data }; if ($Version -ne "9.0") { $Result.IODevice91 += $Data } }
            "Server"   { if ($Version -ne "9.1") { $Result.Server90 += $Data };   if ($Version -ne "9.0") { $Result.Server91 += $Data } }
            "vSAN"     { if ($Version -ne "9.1") { $Result.vSAN90 += $Data };     if ($Version -ne "9.0") { $Result.vSAN91 += $Data } }
        }
        $Result.FoundFiles += "$($File.Name) -> $Type / ESXi $Version"
    }
    return $Result
}

$HCLData     = Import-HCLData -Path $HCLPath
$CpuHCL90    = $HCLData.CPU90;      $CpuHCL91    = $HCLData.CPU91
$IOHCL90     = $HCLData.IODevice90; $IOHCL91     = $HCLData.IODevice91
$SystemHCL90 = $HCLData.Server90;   $SystemHCL91 = $HCLData.Server91
$VsanHCL90   = $HCLData.vSAN90;     $VsanHCL91   = $HCLData.vSAN91

if ($HCLData.FoundFiles.Count -gt 0) {
    Write-Host "[INFO] '$HCLPath' 경로에서 인식된 HCL 파일:" -ForegroundColor Gray
    $HCLData.FoundFiles | ForEach-Object { Write-Host "       - $_" -ForegroundColor DarkGray }
}

# ── HCL 인덱스 사전 빌드: 한 번만 실행하고 이후 검사에서 재사용 ──
Write-Host "[INFO] HCL 데이터 인덱스 빌드 중..." -ForegroundColor Gray
$ServerFields  = @('Partner Name', 'Model')
$IOFields      = @('Brand Name', 'Model')
$Idx_Server90  = Build-HCLIndex -Table $SystemHCL90 -Fields $ServerFields
$Idx_Server91  = Build-HCLIndex -Table $SystemHCL91 -Fields $ServerFields
$Idx_Net90     = Build-HCLIndex -Table @($IOHCL90 | Where-Object { $_.'Device Type' -match 'Network' })     -Fields $IOFields
$Idx_Net91     = Build-HCLIndex -Table @($IOHCL91 | Where-Object { $_.'Device Type' -match 'Network' })     -Fields $IOFields
$Idx_Storage90 = Build-HCLIndex -Table @($IOHCL90 | Where-Object { $_.'Device Type' -notmatch 'Network' })  -Fields $IOFields
$Idx_Storage91 = Build-HCLIndex -Table @($IOHCL91 | Where-Object { $_.'Device Type' -notmatch 'Network' })  -Fields $IOFields
$Idx_Vsan90    = Build-HCLIndex -Table $VsanHCL90  -Fields $IOFields
$Idx_Vsan91    = Build-HCLIndex -Table $VsanHCL91  -Fields $IOFields
Write-Host "[INFO] HCL 인덱스 빌드 완료" -ForegroundColor Gray

$HasAnyHCLData = @($CpuHCL90 + $CpuHCL91 + $IOHCL90 + $IOHCL91 + $SystemHCL90 + $SystemHCL91 + $VsanHCL90 + $VsanHCL91).Count -gt 0

if (-not $HasAnyHCLData) {
    Write-Host "[WARN] HCL 호환성 데이터 파일을 '$HCLPath' 경로에서 찾을 수 없어 호환성 검사를 건너뜁니다." -ForegroundColor Yellow
    Write-Host "       (CPU_Series / IO_Devices / Systems_Servers / vSAN_IO_Controller CSV를 해당 경로 또는 -HCLPath 옵션 경로에 위치시켜 주세요. 파일명에 9_0 / 9_1 표시가 있으면 해당 버전 전용으로 인식합니다)" -ForegroundColor Yellow
} else {
    $IOHCL_Network_90 = @($IOHCL90 | Where-Object { $_.'Device Type' -match 'Network' })
    $IOHCL_Network_91 = @($IOHCL91 | Where-Object { $_.'Device Type' -match 'Network' })
    $IOHCL_Storage_90 = @($IOHCL90 | Where-Object { $_.'Device Type' -notmatch 'Network' })
    $IOHCL_Storage_91 = @($IOHCL91 | Where-Object { $_.'Device Type' -notmatch 'Network' })

    $ComplianceReport = @()

    # --- 1) Server 모델 & 2) CPU 호환성 ---
    foreach ($HW in $HWReport) {
        $DetectedServerText = "$($HW.Vendor) $($HW.Model)"
        $ServerMatch = Get-VersionedMatch -Table90 $SystemHCL90 -Table91 $SystemHCL91 -Index90 $Idx_Server90 -Index91 $Idx_Server91 -Detected $DetectedServerText -Fields @('Partner Name', 'Model') -Threshold $MatchThreshold

        $ServerScore = if ($ServerMatch.Best) { $ServerMatch.Best.Score } else { 0 }
        $ServerHCLText = if ($ServerMatch.Best) { "$($ServerMatch.Best.Row.'Partner Name') $($ServerMatch.Best.Row.Model)" } else { "N/A" }
        $ServerNote = if ($ServerMatch.Best) {
            "VCF Supported(Confirm w/Vendor): $($ServerMatch.Best.Row.'VCF Supported. Confirm w/Vendor')  /  지원 버전: $(Format-ReleaseText $ServerMatch.Best.Row.'Supported Releases')"
        } else { "HCL Systems/Servers 참조 데이터 없음" }
        if ($ServerMatch.Status90 -eq "MISMATCH" -or $ServerMatch.Status91 -eq "MISMATCH") {
            $ServerNote = "[가장 유사한 후보, 수동 확인 필요] " + $ServerNote
        }

        # 물리 코어 수 산정: 소켓당 코어가 16 미만이면 16으로 상향 적용
        $Sockets        = if ($HW.CPU_Sockets -and [int]$HW.CPU_Sockets -gt 0) { [int]$HW.CPU_Sockets } else { 0 }
        $CoresPerSocket = if ($HW.CPU_CoresPerSocket -and [int]$HW.CPU_CoresPerSocket -gt 0) { [int]$HW.CPU_CoresPerSocket } else { 0 }
        $EffCoresPerSocket = if ($CoresPerSocket -lt 16) { 16 } else { $CoresPerSocket }
        $EffTotalCores  = $Sockets * $EffCoresPerSocket
        $CoreNote       = if ($CoresPerSocket -lt 16 -and $Sockets -gt 0) {
            "(실제 소켓당 ${CoresPerSocket}코어 → 최소 16코어로 상향 산정)"
        } else { "" }

        $ComplianceReport += [PSCustomObject]@{
            "Cluster"               = if ($HW.Cluster) { $HW.Cluster } else { "N/A" }
            "HostName"              = $HW.HostName
            "Category"              = "Server"
            "Detected"              = $DetectedServerText
            "CPU_Sockets"           = $Sockets
            "CoresPerSocket_Actual" = $CoresPerSocket
            "CoresPerSocket_Eff"    = $EffCoresPerSocket
            "Total_Cores_Eff"       = $EffTotalCores
            "Core_Note"             = $CoreNote
            "HCL_Match"             = $ServerHCLText
            "Match_Score(%)"        = $ServerScore
            "ESXi_9.0"              = $ServerMatch.Status90
            "ESXi_9.1"              = $ServerMatch.Status91
            "Note"                  = $ServerNote
        }

        # CPU: 세부 SKU가 아니라 "모델 시리즈(세대)" 일치 여부로만 판단
        $DetectedCpuText = "$($HW.CPU_Vendor) / $($HW.CPU_Model)"
        $CpuMatch = Get-VersionedCpuMatch -CpuTable90 $CpuHCL90 -CpuTable91 $CpuHCL91 -DetectedModel $HW.CPU_Model -Vendor $HW.CPU_Vendor

        $CpuScore = if ($CpuMatch.Best) { 100 } else { 0 }
        $CpuHCLText = if ($CpuMatch.Best) { $CpuMatch.Best.Row.'CPU Series' } else { "N/A" }
        $CpuNote = if ($CpuMatch.Best) {
            "탐지된 SKU '$($CpuMatch.Best.Sku)' ↔ Series 코드 '$($CpuMatch.Best.Code)' 세대 기준 일치 / 지원 버전: $(Format-ReleaseText $CpuMatch.Best.Row.'Supported Releases')"
        } elseif (@($CpuHCL90 + $CpuHCL91).Count -gt 0) {
            "CPU_Series 목록에서 동일 세대(Series)를 찾을 수 없음 (수동 확인 필요)"
        } else {
            "CPU 비교용 HCL 데이터(CPU_Series) 없음"
        }

        $ComplianceReport += [PSCustomObject]@{
            "Cluster"        = if ($HW.Cluster) { $HW.Cluster } else { "N/A" }
            "HostName"       = $HW.HostName
            "Category"       = "CPU"
            "Detected"       = $DetectedCpuText
            "HCL_Match"      = $CpuHCLText
            "Match_Score(%)" = $CpuScore
            "ESXi_9.0"       = $CpuMatch.Status90
            "ESXi_9.1"       = $CpuMatch.Status91
            "Note"           = $CpuNote
        }
    }

    # --- 3) NIC 호환성 (제조사+모델명 유사도) ---
    foreach ($Nic in $PnicReport) {
        $DetectedNicText = "$($Nic.Device) / $($Nic.Model)"
        $NicMatch = Get-VersionedMatch -Table90 $IOHCL_Network_90 -Table91 $IOHCL_Network_91 -Index90 $Idx_Net90 -Index91 $Idx_Net91 -Detected $Nic.Model -Fields @('Brand Name', 'Model') -Threshold $MatchThreshold

        $NicScore = if ($NicMatch.Best) { $NicMatch.Best.Score } else { 0 }
        $NicHCLText = if ($NicMatch.Best) { "$($NicMatch.Best.Row.'Brand Name') $($NicMatch.Best.Row.Model)" } else { "N/A" }
        $NicNote = if ($NicMatch.Best) { "지원 버전: $(Format-ReleaseText $NicMatch.Best.Row.'Supported Releases')" } else { "IO Devices(Network) HCL 참조 데이터 없음" }
        if ($NicMatch.Status90 -eq "MISMATCH" -or $NicMatch.Status91 -eq "MISMATCH") {
            $NicNote = "[가장 유사한 후보, 수동 확인 필요] " + $NicNote
        }

        $ComplianceReport += [PSCustomObject]@{
            "Cluster"        = if ($Nic.Cluster) { $Nic.Cluster } else { "N/A" }
            "HostName"       = $Nic.HostName
            "Category"       = "NIC"
            "Detected"       = $DetectedNicText
            "HCL_Match"      = $NicHCLText
            "Match_Score(%)" = $NicScore
            "ESXi_9.0"       = $NicMatch.Status90
            "ESXi_9.1"       = $NicMatch.Status91
            "Note"           = $NicNote
        }
    }

    # --- 4) Storage Controller(HBA/RAID) 호환성 (제조사+모델명 유사도, vSAN 지원여부 별도 표기) ---
    foreach ($Ctrl in (@($HbaReport) + @($RaidReport))) {
        $DetectedCtrlText = "$($Ctrl.Device) / $($Ctrl.Model)"
        $CtrlMatch = Get-VersionedMatch -Table90 $IOHCL_Storage_90 -Table91 $IOHCL_Storage_91 -Index90 $Idx_Storage90 -Index91 $Idx_Storage91 -Detected $Ctrl.Model -Fields @('Brand Name', 'Model') -Threshold $MatchThreshold
        $VsanMatch = Get-VersionedMatch -Table90 $VsanHCL90 -Table91 $VsanHCL91 -Index90 $Idx_Vsan90 -Index91 $Idx_Vsan91 -Detected $Ctrl.Model -Fields @('Brand Name', 'Model') -Threshold $MatchThreshold

        $CtrlScore = if ($CtrlMatch.Best) { $CtrlMatch.Best.Score } else { 0 }
        $CtrlHCLText = if ($CtrlMatch.Best) { "$($CtrlMatch.Best.Row.'Brand Name') $($CtrlMatch.Best.Row.Model)" } else { "N/A" }
        $CtrlNote = if ($CtrlMatch.Best) { "ESXi 지원 버전: $(Format-ReleaseText $CtrlMatch.Best.Row.'Supported Releases')" } else { "IO Devices HCL 참조 데이터 없음" }
        if ($CtrlMatch.Status90 -eq "MISMATCH" -or $CtrlMatch.Status91 -eq "MISMATCH") {
            $CtrlNote = "[가장 유사한 후보, 수동 확인 필요] " + $CtrlNote
        }

        if ($VsanMatch.Best) {
            $CtrlNote += "  |  vSAN 후보: $($VsanMatch.Best.Row.'Brand Name') $($VsanMatch.Best.Row.Model) (유사도 $($VsanMatch.Best.Score)%, $($VsanMatch.Best.Row.Type -replace '[\r\n]+','/') / $($VsanMatch.Best.Row.Feature), 9.0:$($VsanMatch.Status90)/9.1:$($VsanMatch.Status91))"
        } else {
            $CtrlNote += "  |  vSAN I/O Controller 목록에 유사 후보 없음 (vSAN 미사용 시 무관)"
        }

        $ComplianceReport += [PSCustomObject]@{
            "Cluster"        = if ($Ctrl.Cluster) { $Ctrl.Cluster } else { "N/A" }
            "HostName"       = $Ctrl.HostName
            "Category"       = "Storage_Controller"
            "Detected"       = $DetectedCtrlText
            "HCL_Match"      = $CtrlHCLText
            "Match_Score(%)" = $CtrlScore
            "ESXi_9.0"       = $CtrlMatch.Status90
            "ESXi_9.1"       = $CtrlMatch.Status91
            "Note"           = $CtrlNote
        }
    }

    if ($ComplianceReport) {
        # --- Part(분류)별로 CSV 파일을 각각 분리해서 출력 ---
        $ComplianceReport | Group-Object Category | ForEach-Object {
            $SafeName = $_.Name -replace '[^a-zA-Z0-9]', ''
            $_.Group | Export-Csv -Path "$ReportDir\Compatibility_$SafeName.csv" -NoTypeInformation -Encoding UTF8
        }

        # --- HTML 리포트 생성 ---
        function ConvertTo-SafeHtml {
            param([string]$Text)
            if ($null -eq $Text) { return "" }
            return [System.Net.WebUtility]::HtmlEncode($Text)
        }

        function Get-StatusBadgeHtml {
            param([string]$Status)
            if ($Status -eq "OK") { return '<span class="badge badge-ok">OK</span>' }
            else { return '<span class="badge badge-mismatch">MISMATCH</span>' }
        }

        function Get-RowClass {
            param([string]$Status90, [string]$Status91)
            if ($Status90 -eq "OK" -and $Status91 -eq "OK") { return "row-ok" }
            if ($Status90 -eq "MISMATCH" -and $Status91 -eq "MISMATCH") { return "row-mismatch" }
            return "row-partial"
        }

        function New-CategoryTableHtml {
            param([array]$Rows)
            $sb = New-Object System.Text.StringBuilder
            [void]$sb.AppendLine('<table class="data-table">')
            [void]$sb.AppendLine('<tr><th>Host</th><th>탐지된 정보 (Detected)</th><th>HCL 매칭 / 최유사 후보</th><th>유사도</th><th>ESXi 9.0</th><th>ESXi 9.1</th><th>비고</th></tr>')
            foreach ($R in $Rows) {
                $RowClass = Get-RowClass -Status90 $R.'ESXi_9.0' -Status91 $R.'ESXi_9.1'
                [void]$sb.AppendLine("<tr class=`"$RowClass`">")
                [void]$sb.AppendLine("<td>$(ConvertTo-SafeHtml $R.HostName)</td>")
                [void]$sb.AppendLine("<td>$(ConvertTo-SafeHtml $R.Detected)</td>")
                [void]$sb.AppendLine("<td>$(ConvertTo-SafeHtml $R.HCL_Match)</td>")
                [void]$sb.AppendLine("<td>$($R.'Match_Score(%)')%</td>")
                [void]$sb.AppendLine("<td>$(Get-StatusBadgeHtml $R.'ESXi_9.0')</td>")
                [void]$sb.AppendLine("<td>$(Get-StatusBadgeHtml $R.'ESXi_9.1')</td>")
                [void]$sb.AppendLine("<td>$(ConvertTo-SafeHtml $R.Note)</td>")
                [void]$sb.AppendLine("</tr>")
            }
            [void]$sb.AppendLine('</table>')
            return $sb.ToString()
        }

        # 전체 요약: Part별 / 버전별(9.0, 9.1) 일치-불일치 수량
        $CategorySummary = $ComplianceReport | Group-Object Category | ForEach-Object {
            $Ok90 = @($_.Group | Where-Object { $_.'ESXi_9.0' -eq "OK" }).Count
            $Mis90 = $_.Count - $Ok90
            $Ok91 = @($_.Group | Where-Object { $_.'ESXi_9.1' -eq "OK" }).Count
            $Mis91 = $_.Count - $Ok91
            [PSCustomObject]@{
                Category = $_.Name
                Total    = $_.Count
                Ok90     = $Ok90;  Mis90 = $Mis90;  Rate90 = if ($_.Count -gt 0) { [Math]::Round(($Ok90 / $_.Count) * 100, 0) } else { 0 }
                Ok91     = $Ok91;  Mis91 = $Mis91;  Rate91 = if ($_.Count -gt 0) { [Math]::Round(($Ok91 / $_.Count) * 100, 0) } else { 0 }
            }
        }
        $TotalAll    = $ComplianceReport.Count
        $TotalOk90   = @($ComplianceReport | Where-Object { $_.'ESXi_9.0' -eq "OK" }).Count
        $TotalMis90  = $TotalAll - $TotalOk90
        $TotalOk91   = @($ComplianceReport | Where-Object { $_.'ESXi_9.1' -eq "OK" }).Count
        $TotalMis91  = $TotalAll - $TotalOk91
        $TotalRate90 = if ($TotalAll -gt 0) { [Math]::Round(($TotalOk90 / $TotalAll) * 100, 0) } else { 0 }
        $TotalRate91 = if ($TotalAll -gt 0) { [Math]::Round(($TotalOk91 / $TotalAll) * 100, 0) } else { 0 }

        $Html = New-Object System.Text.StringBuilder

        # ── 호스트 단위 집계: 물리 코어 수는 HWReport에서 가져옴 ──
        $HWLookup = @{}
        foreach ($hw in $HWReport) { $HWLookup[$hw.HostName] = $hw }

        $HostSummary = $ComplianceReport | Group-Object HostName | ForEach-Object {
            $Rows    = $_.Group
            $hw      = $HWLookup[$_.Name]
            $Cores   = if ($hw -and $hw.Total_Cores) { [int]$hw.Total_Cores } else { 0 }
            $Cluster = ($Rows | Select-Object -First 1).Cluster
            [PSCustomObject]@{
                HostName = $_.Name
                Cluster  = $Cluster
                Cores    = $Cores
                AllOk90  = (@($Rows | Where-Object { $_.'ESXi_9.0' -ne "OK" }).Count -eq 0)
                AllOk91  = (@($Rows | Where-Object { $_.'ESXi_9.1' -ne "OK" }).Count -eq 0)
            }
        }

        $TotalHostsAll  = $HostSummary.Count
        $Full90Hosts    = @($HostSummary | Where-Object { $_.AllOk90 })
        $Mis90Hosts     = @($HostSummary | Where-Object { -not $_.AllOk90 })
        $Full91Hosts    = @($HostSummary | Where-Object { $_.AllOk91 })
        $Mis91Hosts     = @($HostSummary | Where-Object { -not $_.AllOk91 })
        $Full90Cores    = ($Full90Hosts  | Measure-Object -Property Cores -Sum).Sum
        $Mis90Cores     = ($Mis90Hosts   | Measure-Object -Property Cores -Sum).Sum
        $Full91Cores    = ($Full91Hosts  | Measure-Object -Property Cores -Sum).Sum
        $Mis91Cores     = ($Mis91Hosts   | Measure-Object -Property Cores -Sum).Sum
        if ($null -eq $Full90Cores) { $Full90Cores = 0 }
        if ($null -eq $Mis90Cores)  { $Mis90Cores  = 0 }
        if ($null -eq $Full91Cores) { $Full91Cores = 0 }
        if ($null -eq $Mis91Cores)  { $Mis91Cores  = 0 }

        $ClusterHostSummary = $HostSummary | Group-Object Cluster | ForEach-Object {
            $cHosts     = $_.Group
            $cf90       = @($cHosts | Where-Object { $_.AllOk90 })
            $cm90       = @($cHosts | Where-Object { -not $_.AllOk90 })
            $cf91       = @($cHosts | Where-Object { $_.AllOk91 })
            $cm91       = @($cHosts | Where-Object { -not $_.AllOk91 })
            $cf90c      = ($cf90 | Measure-Object -Property Cores -Sum).Sum; if ($null -eq $cf90c) { $cf90c = 0 }
            $cm90c      = ($cm90 | Measure-Object -Property Cores -Sum).Sum; if ($null -eq $cm90c) { $cm90c = 0 }
            $cf91c      = ($cf91 | Measure-Object -Property Cores -Sum).Sum; if ($null -eq $cf91c) { $cf91c = 0 }
            $cm91c      = ($cm91 | Measure-Object -Property Cores -Sum).Sum; if ($null -eq $cm91c) { $cm91c = 0 }
            [PSCustomObject]@{
                Cluster          = $_.Name
                TotalHosts       = $cHosts.Count
                Full90Count      = $cf90.Count; Full90Cores = $cf90c
                Mis90Count       = $cm90.Count; Mis90Cores  = $cm90c
                Mis90HostNames   = ($cm90 | ForEach-Object { $_.HostName }) -join ', '
                Full91Count      = $cf91.Count; Full91Cores = $cf91c
                Mis91Count       = $cm91.Count; Mis91Cores  = $cm91c
                Mis91HostNames   = ($cm91 | ForEach-Object { $_.HostName }) -join ', '
            }
        } | Sort-Object Cluster

        # ── Part 요약 (Category별/버전별) ──
        $CategorySummary = $ComplianceReport | Group-Object Category | ForEach-Object {
            $Ok90 = @($_.Group | Where-Object { $_.'ESXi_9.0' -eq "OK" }).Count
            $Ok91 = @($_.Group | Where-Object { $_.'ESXi_9.1' -eq "OK" }).Count
            [PSCustomObject]@{
                Category = $_.Name; Total = $_.Count
                Ok90 = $Ok90; Mis90 = $_.Count - $Ok90; Rate90 = if ($_.Count -gt 0) { [Math]::Round(($Ok90/$_.Count)*100,0) } else { 0 }
                Ok91 = $Ok91; Mis91 = $_.Count - $Ok91; Rate91 = if ($_.Count -gt 0) { [Math]::Round(($Ok91/$_.Count)*100,0) } else { 0 }
            }
        }
        $TotalAll = $ComplianceReport.Count
        $TotalOk90 = @($ComplianceReport | Where-Object { $_.'ESXi_9.0' -eq "OK" }).Count; $TotalMis90 = $TotalAll - $TotalOk90
        $TotalOk91 = @($ComplianceReport | Where-Object { $_.'ESXi_9.1' -eq "OK" }).Count; $TotalMis91 = $TotalAll - $TotalOk91
        $TotalRate90 = if ($TotalAll -gt 0) { [Math]::Round(($TotalOk90/$TotalAll)*100,0) } else { 0 }
        $TotalRate91 = if ($TotalAll -gt 0) { [Math]::Round(($TotalOk91/$TotalAll)*100,0) } else { 0 }

        # ── HTML 헬퍼 함수 ──
        function ConvertTo-SafeHtml { param([string]$Text); if ($null -eq $Text) { return "" }; return [System.Net.WebUtility]::HtmlEncode($Text) }
        function Get-Badge { param([string]$Status); if ($Status -eq "OK") { return '<span class="badge ok">OK</span>' } else { return '<span class="badge miss">MISMATCH</span>' } }
        function Get-RowClass { param([string]$s90,[string]$s91); if ($s90 -eq "OK" -and $s91 -eq "OK") { "tr-ok" } elseif ($s90 -eq "MISMATCH" -and $s91 -eq "MISMATCH") { "tr-miss" } else { "tr-partial" } }

        function New-CategoryTableHtml {
            param([array]$Rows, [string]$Category = "")
            $sb = New-Object System.Text.StringBuilder
            [void]$sb.AppendLine('<div class="table-wrap"><table>')
            if ($Category -eq "Server") {
                [void]$sb.AppendLine('<thead><tr><th>Host</th><th>탐지 정보</th><th>소켓</th><th>소켓당 코어(실제)</th><th>소켓당 코어(산정)</th><th>총 코어(산정)</th><th>코어 비고</th><th>HCL 최유사 후보</th><th>유사도</th><th>ESXi 9.0</th><th>ESXi 9.1</th><th>비고</th></tr></thead><tbody>')
                foreach ($R in $Rows) {
                    $rc = Get-RowClass -s90 $R.'ESXi_9.0' -s91 $R.'ESXi_9.1'
                    $coreNoteHtml = if (-not [string]::IsNullOrWhiteSpace($R.Core_Note)) { "<span style=`"color:#b45309;font-weight:600`">$(ConvertTo-SafeHtml $R.Core_Note)</span>" } else { "" }
                    [void]$sb.AppendLine("<tr class=`"$rc`"><td>$(ConvertTo-SafeHtml $R.HostName)</td><td>$(ConvertTo-SafeHtml $R.Detected)</td><td>$($R.CPU_Sockets)</td><td>$($R.CoresPerSocket_Actual)</td><td>$($R.CoresPerSocket_Eff)</td><td><strong>$($R.Total_Cores_Eff)</strong></td><td class=`"note`">$coreNoteHtml</td><td>$(ConvertTo-SafeHtml $R.HCL_Match)</td><td>$($R.'Match_Score(%)')%</td><td>$(Get-Badge $R.'ESXi_9.0')</td><td>$(Get-Badge $R.'ESXi_9.1')</td><td class=`"note`">$(ConvertTo-SafeHtml $R.Note)</td></tr>")
                }
            } else {
                [void]$sb.AppendLine('<thead><tr><th>Host</th><th>탐지 정보</th><th>HCL 최유사 후보</th><th>유사도</th><th>ESXi 9.0</th><th>ESXi 9.1</th><th>비고</th></tr></thead><tbody>')
                foreach ($R in $Rows) {
                    $rc = Get-RowClass -s90 $R.'ESXi_9.0' -s91 $R.'ESXi_9.1'
                    [void]$sb.AppendLine("<tr class=`"$rc`"><td>$(ConvertTo-SafeHtml $R.HostName)</td><td>$(ConvertTo-SafeHtml $R.Detected)</td><td>$(ConvertTo-SafeHtml $R.HCL_Match)</td><td>$($R.'Match_Score(%)')%</td><td>$(Get-Badge $R.'ESXi_9.0')</td><td>$(Get-Badge $R.'ESXi_9.1')</td><td class=`"note`">$(ConvertTo-SafeHtml $R.Note)</td></tr>")
                }
            }
            [void]$sb.AppendLine('</tbody></table></div>')
            return $sb.ToString()
        }

        function New-VersionCardPair {
            param([int]$FullCount,[int]$FullCores,[int]$MisCount,[int]$MisCores,[string]$Version)
            return @"
<div class="ver-group">
  <div class="ver-label">ESXi $Version</div>
  <div class="card-row">
    <div class="kpi-card green">
      <div class="kpi-icon">✓</div>
      <div class="kpi-body">
        <div class="kpi-val">$FullCount</div>
        <div class="kpi-sub">100% 일치 호스트</div>
        <div class="kpi-detail">물리 코어 합계 $FullCores 코어</div>
      </div>
    </div>
    <div class="kpi-card red">
      <div class="kpi-icon">✗</div>
      <div class="kpi-body">
        <div class="kpi-val">$MisCount</div>
        <div class="kpi-sub">불일치 호스트</div>
        <div class="kpi-detail">물리 코어 합계 $MisCores 코어</div>
      </div>
    </div>
  </div>
</div>
"@
        }

        $SharedCss = @"
:root {
  --bg:#f0f2f5; --surface:#fff; --border:#e2e8f0;
  --primary:#1e3a5f; --primary-lt:#e8edf5;
  --green:#16a34a; --green-lt:#dcfce7; --green-dk:#14532d;
  --red:#dc2626;   --red-lt:#fee2e2;   --red-dk:#7f1d1d;
  --yellow:#d97706; --yellow-lt:#fef3c7; --yellow-dk:#78350f;
  --gray:#64748b;  --gray-lt:#f8fafc;
  --radius:12px; --shadow:0 1px 3px rgba(0,0,0,.08),0 4px 16px rgba(0,0,0,.06);
  font-family:'Malgun Gothic','Apple SD Gothic Neo',Arial,sans-serif;
}
*{box-sizing:border-box;margin:0;padding:0}
body{background:var(--bg);color:#1e293b;padding:28px 32px;font-size:14px;line-height:1.6}
.page-header{margin-bottom:32px;display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:10px}
.page-header h1{font-size:22px;font-weight:700;color:var(--primary);margin-bottom:4px}
.page-meta{color:var(--gray);font-size:12px}
.back-link{font-size:13px;font-weight:600;color:var(--primary);text-decoration:none;background:var(--primary-lt);padding:7px 14px;border-radius:8px;white-space:nowrap}
.back-link:hover{background:var(--primary);color:#fff}

/* ── KPI 카드 ── */
.section-title{font-size:15px;font-weight:700;color:var(--primary);margin:28px 0 14px;display:flex;align-items:center;gap:8px}
.section-title::before{content:'';display:inline-block;width:4px;height:18px;background:var(--primary);border-radius:2px}
.version-block{display:flex;gap:24px;margin-bottom:12px;width:100%}
.ver-group{display:flex;flex-direction:column;gap:8px;flex:1;min-width:0}
.ver-label{font-size:12px;font-weight:700;color:var(--primary);letter-spacing:.05em;text-transform:uppercase;padding:4px 0}
.card-row{display:flex;gap:12px;width:100%}
.kpi-card{display:flex;align-items:center;gap:16px;background:var(--surface);border-radius:var(--radius);padding:20px 24px;box-shadow:var(--shadow);flex:1;min-width:0;border-left:5px solid}
.kpi-card.green{border-color:var(--green)}
.kpi-card.red{border-color:var(--red)}
.kpi-icon{font-size:22px;font-weight:900}
.kpi-card.green .kpi-icon{color:var(--green)}
.kpi-card.red   .kpi-icon{color:var(--red)}
.kpi-val{font-size:30px;font-weight:700;line-height:1}
.kpi-sub{font-size:12px;font-weight:600;color:var(--gray);margin-top:4px}
.kpi-detail{font-size:17px;font-weight:700;color:#1e293b;margin-top:4px}

/* ── 클러스터 구분 ── */
.cluster-section{background:var(--surface);border-radius:var(--radius);box-shadow:var(--shadow);padding:22px 24px;margin-bottom:24px}
.cluster-header{display:flex;align-items:center;justify-content:space-between;margin-bottom:16px;flex-wrap:wrap;gap:8px}
.cluster-name{font-size:15px;font-weight:700;color:var(--primary)}
.cluster-name a{color:var(--primary);text-decoration:none;border-bottom:1.5px dashed var(--primary)}
.cluster-name a:hover{color:#0f2440;border-bottom-style:solid}
.cluster-cards{display:flex;gap:16px;width:100%;margin-bottom:18px}
.cluster-ver-group{display:flex;flex-direction:column;gap:6px;flex:1;min-width:0}
.cluster-ver-label{font-size:11px;font-weight:700;color:var(--gray);letter-spacing:.05em}
.cluster-card-row{display:flex;gap:8px;width:100%}
.c-card{display:flex;align-items:center;gap:10px;border-radius:10px;padding:12px 16px;flex:1;min-width:0;border:1.5px solid}
.c-card.green{background:var(--green-lt);border-color:var(--green)}
.c-card.red{background:var(--red-lt);border-color:var(--red)}
.c-icon{font-size:17px;font-weight:900}
.c-card.green .c-icon{color:var(--green)}
.c-card.red   .c-icon{color:var(--red)}
.c-val{font-size:22px;font-weight:700;line-height:1}
.c-sub{font-size:11px;color:var(--gray);margin-top:2px}
.c-detail{font-size:15px;font-weight:700;color:#1e293b;margin-top:2px}

/* ── 범례 요약 테이블 ── */
.summary-table-wrap{overflow-x:auto;margin-bottom:16px}
.summary-table-wrap table{width:100%;border-collapse:collapse;font-size:13px}
.summary-table-wrap th{background:var(--primary);color:#fff;padding:8px 12px;font-weight:600;text-align:left}
.summary-table-wrap td{padding:7px 12px;border-bottom:1px solid var(--border)}
.summary-table-wrap tr:last-child td{font-weight:700;background:var(--gray-lt)}
.summary-table-wrap tr:hover td{background:var(--primary-lt)}

/* ── 상세 테이블 ── */
.cat-section{margin-bottom:20px}
.cat-title{font-size:13px;font-weight:700;color:var(--primary);margin-bottom:8px;padding:6px 12px;background:var(--primary-lt);border-radius:6px;display:inline-block}
.table-wrap{overflow-x:auto}
.table-wrap table{width:100%;border-collapse:collapse;font-size:12px}
.table-wrap th{background:var(--primary);color:#fff;padding:7px 10px;font-weight:600;white-space:nowrap;text-align:left}
.table-wrap td{padding:6px 10px;border-bottom:1px solid var(--border);vertical-align:top}
.table-wrap .note{max-width:340px;font-size:11px;color:var(--gray)}
.tr-ok:hover td{background:#f0fdf4}
.tr-miss td{background:#fff5f5}
.tr-miss:hover td{background:#fee2e2}
.tr-partial td{background:#fffbeb}
.tr-partial:hover td{background:#fef3c7}

.badge{display:inline-flex;align-items:center;padding:2px 9px;border-radius:20px;font-size:11px;font-weight:700;letter-spacing:.02em}
.badge.ok{background:var(--green-lt);color:var(--green-dk)}
.badge.miss{background:var(--red-lt);color:var(--red-dk)}

.divider{height:1px;background:var(--border);margin:20px 0}
.tag-total{display:inline-block;padding:2px 8px;border-radius:4px;background:var(--primary-lt);color:var(--primary);font-size:11px;font-weight:600}
"@

        # 클러스터명 -> 파일명 안전 변환 (클러스터별 상세 HTML 파일명에 사용)
        function Get-SafeFileName {
            param([string]$Text)
            if ([string]::IsNullOrWhiteSpace($Text)) { return "unknown" }
            return ($Text -replace '[^a-zA-Z0-9_\-]', '_')
        }

        [void]$Html.AppendLine(@"
<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>VCF9 하드웨어 호환성 검사 결과</title>
<style>
$SharedCss
</style>
</head>
<body>
<div class="page-header">
  <h1>VCF9 하드웨어 호환성 검사 결과</h1>
  <div class="page-meta">생성 시각: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss") &nbsp;|&nbsp; vCenter: $(ConvertTo-SafeHtml $vCenter) &nbsp;|&nbsp; 판정 기준: 유사도 ${MatchThreshold}% 이상 = OK</div>
</div>

<div class="section-title">전체 호스트 호환성 현황</div>
<div class="version-block">
$(New-VersionCardPair -FullCount $Full90Hosts.Count -FullCores $Full90Cores -MisCount $Mis90Hosts.Count -MisCores $Mis90Cores -Version "9.0")
$(New-VersionCardPair -FullCount $Full91Hosts.Count -FullCores $Full91Cores -MisCount $Mis91Hosts.Count -MisCores $Mis91Cores -Version "9.1")
</div>

<div class="section-title">클러스터별 호환성 현황</div>
"@)

        foreach ($CHS in $ClusterHostSummary) {
            $ClusterFileName = "Compatibility_Cluster_$(Get-SafeFileName $CHS.Cluster).html"
            [void]$Html.AppendLine('<div class="cluster-section">')
            [void]$Html.AppendLine("<div class=`"cluster-header`"><span class=`"cluster-name`">📦 클러스터: <a href=`"$ClusterFileName`">$(ConvertTo-SafeHtml $CHS.Cluster)</a></span><span class=`"tag-total`">총 $($CHS.TotalHosts) 호스트</span></div>")
            [void]$Html.AppendLine('<div class="cluster-cards">')
            foreach ($ver in @(@{V="9.0";fc=$CHS.Full90Count;fco=$CHS.Full90Cores;mc=$CHS.Mis90Count;mco=$CHS.Mis90Cores;mh=$CHS.Mis90HostNames},@{V="9.1";fc=$CHS.Full91Count;fco=$CHS.Full91Cores;mc=$CHS.Mis91Count;mco=$CHS.Mis91Cores;mh=$CHS.Mis91HostNames})) {
                $misLabel = if ([string]::IsNullOrWhiteSpace($ver.mh)) { "없음" } else { $ver.mh }
                [void]$Html.AppendLine(@"
<div class="cluster-ver-group">
  <div class="cluster-ver-label">ESXi $($ver.V)</div>
  <div class="cluster-card-row">
    <div class="c-card green"><div class="c-icon">✓</div><div><div class="c-val">$($ver.fc)</div><div class="c-sub">100% 일치</div><div class="c-detail">$($ver.fco) 코어</div></div></div>
    <div class="c-card red"><div class="c-icon">✗</div><div><div class="c-val">$($ver.mc)</div><div class="c-sub">불일치</div><div class="c-detail">$($ver.mco) 코어</div></div></div>
  </div>
  $(if ($ver.mc -gt 0) { "<div style=`"font-size:11px;color:#7f1d1d;margin-top:4px`">불일치 호스트: $(ConvertTo-SafeHtml $misLabel)</div>" })
</div>
"@)
            }
            [void]$Html.AppendLine('</div></div>')
        }

        [void]$Html.AppendLine('<div class="section-title">Part별 항목 수 요약</div>')
        [void]$Html.AppendLine('<div class="summary-table-wrap"><table>')
        [void]$Html.AppendLine('<thead><tr><th>분류(Part)</th><th>총 항목</th><th>9.0 일치</th><th>9.0 불일치</th><th>9.0 일치율</th><th>9.1 일치</th><th>9.1 불일치</th><th>9.1 일치율</th></tr></thead><tbody>')
        foreach ($S in $CategorySummary) {
            [void]$Html.AppendLine("<tr><td>$(ConvertTo-SafeHtml $S.Category)</td><td>$($S.Total)</td><td>$($S.Ok90)</td><td>$($S.Mis90)</td><td>$($S.Rate90)%</td><td>$($S.Ok91)</td><td>$($S.Mis91)</td><td>$($S.Rate91)%</td></tr>")
        }
        [void]$Html.AppendLine("<tr><td>전체</td><td>$TotalAll</td><td>$TotalOk90</td><td>$TotalMis90</td><td>$TotalRate90%</td><td>$TotalOk91</td><td>$TotalMis91</td><td>$TotalRate91%</td></tr>")
        [void]$Html.AppendLine('</tbody></table></div>')

        [void]$Html.AppendLine('</body></html>')

        $HtmlReportPath = "$ReportDir\Compatibility_Report.html"
        $Html.ToString() | Out-File -FilePath $HtmlReportPath -Encoding UTF8

        # ── 클러스터별 상세: 클러스터마다 독립된 HTML 파일로 생성 ──
        $CategoryOrder = @("Server","CPU","NIC","Storage_Controller")
        $ClusterGroups = $ComplianceReport | Group-Object Cluster | Sort-Object Name
        $ClusterFileList = @()

        foreach ($CG in $ClusterGroups) {
            $ClusterFileName = "Compatibility_Cluster_$(Get-SafeFileName $CG.Name).html"
            $ClusterFileList += $ClusterFileName

            $ClusterHtml = New-Object System.Text.StringBuilder
            [void]$ClusterHtml.AppendLine(@"
<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>VCF9 호환성 상세 - $(ConvertTo-SafeHtml $CG.Name)</title>
<style>
$SharedCss
</style>
</head>
<body>
<div class="page-header">
  <div>
    <h1>클러스터: $(ConvertTo-SafeHtml $CG.Name) - 호환성 상세</h1>
    <div class="page-meta">생성 시각: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss") &nbsp;|&nbsp; vCenter: $(ConvertTo-SafeHtml $vCenter) &nbsp;|&nbsp; 판정 기준: 유사도 ${MatchThreshold}% 이상 = OK</div>
  </div>
  <a class="back-link" href="Compatibility_Report.html">← 전체 요약으로 돌아가기</a>
</div>
"@)

            $ExistingCats = @($CG.Group.Category | Select-Object -Unique)
            $OrderedCats  = @($CategoryOrder | Where-Object { $ExistingCats -contains $_ })
            $OtherCats    = @($ExistingCats | Where-Object { $CategoryOrder -notcontains $_ })
            foreach ($Cat in (@($OrderedCats)+@($OtherCats))) {
                $CatRows = @($CG.Group | Where-Object { $_.Category -eq $Cat } | Sort-Object HostName)
                [void]$ClusterHtml.AppendLine("<div class=`"cat-section`"><div class=`"cat-title`">$(ConvertTo-SafeHtml $Cat) <span class=`"tag-total`">$($CatRows.Count)건</span></div>")
                [void]$ClusterHtml.AppendLine((New-CategoryTableHtml -Rows $CatRows -Category $Cat))
                [void]$ClusterHtml.AppendLine('</div>')
            }

            [void]$ClusterHtml.AppendLine('</body></html>')
            $ClusterHtmlPath = "$ReportDir\$ClusterFileName"
            $ClusterHtml.ToString() | Out-File -FilePath $ClusterHtmlPath -Encoding UTF8
        }

        # --- 콘솔 요약 출력 ---
        $Mismatches = $ComplianceReport | Where-Object { $_.'ESXi_9.0' -eq "MISMATCH" -or $_.'ESXi_9.1' -eq "MISMATCH" }
        Write-Host ""
        Write-Host "===============================================================================" -ForegroundColor Yellow
        Write-Host " VCF9 하드웨어 호환성 검사 결과 요약 (ESXi 9.0 / 9.1 각각 판정)" -ForegroundColor Yellow
        Write-Host "===============================================================================" -ForegroundColor Yellow
        Write-Host " 총 검사 항목: $($ComplianceReport.Count)건  |  ESXi 9.0 불일치: $($TotalMis90)건  |  ESXi 9.1 불일치: $($TotalMis91)건  |  판정 기준: 유사도 $MatchThreshold% 이상 = OK" -ForegroundColor Gray

        if ($Mismatches) {
            $Mismatches | Sort-Object HostName, Category | ForEach-Object {
                Write-Host (" [불일치] {0,-25} {1,-20} {2,-45} (9.0:{3} / 9.1:{4})" -f $_.HostName, $_.Category, $_.Detected, $_.'ESXi_9.0', $_.'ESXi_9.1') -ForegroundColor Red
                Write-Host ("           ↳ 가장 유사한 HCL 후보: {0} (유사도 {1}%)" -f $_.HCL_Match, $_.'Match_Score(%)') -ForegroundColor DarkGray
            }
        } else {
            Write-Host " 모든 항목이 ESXi 9.0 / 9.1 HCL과 일치합니다." -ForegroundColor Green
        }
        Write-Host "===============================================================================" -ForegroundColor Yellow
        Write-Host " ※ CPU는 세부 SKU가 아닌 '모델 시리즈(세대)' 기준으로, 그 외 항목은 제조사/모델명 '유사도(%)' 기준으로 ESXi 9.0/9.1 각각 판정한 best-effort 결과입니다." -ForegroundColor DarkGray
        Write-Host " 상세 결과: Compatibility_Server.csv / Compatibility_CPU.csv / Compatibility_NIC.csv / Compatibility_StorageController.csv" -ForegroundColor Gray
        Write-Host " HTML 요약 리포트: Compatibility_Report.html" -ForegroundColor Gray
        Write-Host " 클러스터별 상세 HTML ($($ClusterFileList.Count)개): $($ClusterFileList -join ', ')" -ForegroundColor Gray
        Write-Host "===============================================================================" -ForegroundColor Yellow
    }
}

# ----------------------------------------------------
# 11 & 12. Finalize, Zip Compression and Cleanup
# ----------------------------------------------------
Write-Host "[11/12] Disconnecting from vCenter..." -ForegroundColor Cyan
Disconnect-VIServer -Server $vCenter -Confirm:$false | Out-Null

if (Test-Path $ReportDir) {
    Write-Host "Compressing all generated CSV reports into a single ZIP file..." -ForegroundColor Yellow
    Compress-Archive -Path $ReportDir -DestinationPath $ZipPath -Force
    
    Write-Host "Cleaning up raw uncompressed directory..." -ForegroundColor Gray
    Remove-Item -Path $ReportDir -Recurse -Force
}

Write-Host "===============================================================================" -ForegroundColor Green
Write-Host "[12/12] SUCCESS: Environment configured and exact ONE ZIP report generated!" -ForegroundColor Green
Write-Host "Output Archive File: $ZipPath" -ForegroundColor Yellow
Write-Host "===============================================================================" -ForegroundColor Green