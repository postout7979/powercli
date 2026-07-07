# ====================================================
# 0. Initial Environment Setup & PowerCLI Auto-Installation
# ====================================================
# 사용 예시: .\vcf9-precheck-script-cs.ps1
# 이 스크립트는 vCenter 인벤토리 수집만 수행합니다.
# HCL 호환성 검사는 vcf9-hcl-check.ps1을 별도로 실행하세요:
#   .\vcf9-hcl-check.ps1 -InventoryPath "<이 스크립트가 생성한 폴더 경로>"
param()

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

# 호스트 CPU Ready는 Get-Stat으로 별도 수집 (Realtime 20초 샘플 기준)
# cpu.ready.summation 단위: ms / 20초 인터벌당 → %Ready = (Value / 20000) × 100
$HostReadyLookup = @{}
try {
    $HostReadyStats = Get-Stat -Entity $VMHosts -Stat "cpu.ready.summation" -MaxSamples 1 -Realtime -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
    foreach ($S in $HostReadyStats) {
        # 호스트 레벨의 cpu.ready는 전체 pCPU 합산값 → NumCpu로 나눠 평균 %Ready 산출
        $NumCpu = ($VMHosts | Where-Object { $_.Id -eq $S.Entity.Id } | Select-Object -First 1).NumCpu
        if (-not $NumCpu -or $NumCpu -eq 0) { $NumCpu = 1 }
        $HostReadyLookup[$S.Entity.Id] = [Math]::Round(($S.Value / ($NumCpu * 20000)) * 100, 2)
    }
} catch {}

foreach ($HostObj in $VMHosts) {
    $Count++
    Write-Progress -Activity "Processing Hosts" -Status "Host: $($HostObj.Name)" -PercentComplete (($Count / $TotalHosts) * 100)

    $CpuUsageMhz = $HostObj.CpuUsageMhz
    $CpuUsagePct = if ($HostObj.CpuTotalMhz -gt 0) { [Math]::Round(($HostObj.CpuUsageMhz / $HostObj.CpuTotalMhz * 100), 2) } else { 0 }
    $MemUsageGB  = [Math]::Round($HostObj.MemoryUsageGB, 2)
    $MemUsagePct = if ($HostObj.MemoryTotalGB -gt 0) { [Math]::Round(($HostObj.MemoryUsageGB / $HostObj.MemoryTotalGB * 100), 2) } else { 0 }
    $HostReadyPct = if ($HostReadyLookup.ContainsKey($HostObj.Id)) { $HostReadyLookup[$HostObj.Id] } else { "N/A" }

    $HostReport += [PSCustomObject]@{
        "HostName"       = $HostObj.Name
        "Cluster"        = $HostObj.Parent.Name
        "State"          = $HostObj.ConnectionState
        "ESXi_Version"   = $HostObj.Version
        "BuildNumber"    = $HostObj.Build
        "CPU_Usage_MHz"  = $CpuUsageMhz
        "CPU_Usage_Pct"  = "$CpuUsagePct %"
        "CPU_Ready_Pct"  = if ($HostReadyPct -ne "N/A") { "$HostReadyPct %" } else { "N/A" }
        "Mem_Usage_GB"   = $MemUsageGB
        "Mem_Usage_Pct"  = "$MemUsagePct %"
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
            "CPU_Usage_MHz"      = $CpuUsageMhz
            "CPU_Usage_Pct"      = "$CpuUsagePct %"
            "CPU_Ready_Pct"      = if ($HostReadyPct -ne "N/A") { "$HostReadyPct %" } else { "N/A" }
            "Mem_Total_GB"       = [Math]::Round($HostObj.ExtensionData.Hardware.MemorySize / 1GB, 2)
            "Mem_Usage_GB"       = $MemUsageGB
            "Mem_Usage_Pct"      = "$MemUsagePct %"
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
            $ReadyMs  = ($VMStats | Where-Object {$_.MetricId -eq "cpu.ready.summation"}  | Measure-Object Value -Sum).Sum
            $CostopMs = ($VMStats | Where-Object {$_.MetricId -eq "cpu.costop.summation"} | Measure-Object Value -Sum).Sum
            # 정확한 공식: (summation_ms / (NumCPU × 20000ms)) × 100
            # cpu.ready.summation은 전체 vCPU 합산값이므로 NumCPU로 나눠 평균 %Ready를 산출
            $NumCpuDivisor = if ($VM.NumCpu -gt 0) { $VM.NumCpu } else { 1 }
            $ReadyPct  = if ($ReadyMs)  { [Math]::Round(($ReadyMs  / ($NumCpuDivisor * 20000)) * 100, 2) } else { 0 }
            $CostopPct = if ($CostopMs) { [Math]::Round(($CostopMs / ($NumCpuDivisor * 20000)) * 100, 2) } else { 0 }
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
# 10. ESX Memory Page Info (for NVMe Memory Tiering)
# ----------------------------------------------------
# Collects per-host real-time memory page breakdown:
#   Allocated / Consumed / Active / Cold (= Consumed - Active)
# Cold memory is the primary candidate for NVMe tiering offload.
# Uses Realtime Get-Stat counters first; falls back to QuickStats if unavailable.
Write-Host "[10/12] Collecting ESX Memory Page Info (NVMe Memory Tiering assessment)..." -ForegroundColor Cyan

$MemPageReport = @()
$TotalHostsMP  = @($VMHosts).Count
$CountMP       = 0

# Bulk fetch realtime mem stats for all hosts in one call (performance optimisation)
$MemStats = $null
try {
    $MemStats = Get-Stat -Entity $VMHosts -Stat "mem.consumed.average","mem.active.average" `
                         -Realtime -MaxSamples 1 -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
} catch {}

$MemStatsLookup = @{}
if ($MemStats) {
    foreach ($S in $MemStats) {
        $id = $S.Entity.Id
        if (-not $MemStatsLookup.ContainsKey($id)) { $MemStatsLookup[$id] = @() }
        $MemStatsLookup[$id] += $S
    }
}

foreach ($H in $VMHosts) {
    $CountMP++
    Write-Progress -Activity "ESX Memory Page" -Status "Host: $($H.Name)" -PercentComplete (($CountMP / $TotalHostsMP) * 100)

    $ConsumedMB = 0; $ActiveMB = 0; $StatSource = "QuickStats"

    $HostStats = $MemStatsLookup[$H.Id]
    if ($HostStats) {
        $cKB = ($HostStats | Where-Object { $_.MetricId -eq "mem.consumed.average" } | Select-Object -First 1).Value
        $aKB = ($HostStats | Where-Object { $_.MetricId -eq "mem.active.average"   } | Select-Object -First 1).Value
        if ($cKB -gt 0) {
            $ConsumedMB = $cKB / 1024
            $ActiveMB   = if ($aKB) { $aKB / 1024 } else { 0 }
            $StatSource = "Realtime"
        }
    }

    # Fallback: QuickStats (already cached in ExtensionData)
    if ($StatSource -eq "QuickStats") {
        $QS = $H.ExtensionData.Summary.QuickStats
        $ConsumedMB = if ($QS.MemoryUsage)  { $QS.MemoryUsage  } else { 0 }
        $ActiveMB   = if ($QS.ActiveMemory) { $QS.ActiveMemory } else { 0 }
    }

    $AllocatedGB  = [Math]::Round($H.MemoryTotalGB, 2)
    $ConsumedGB   = [Math]::Round($ConsumedMB / 1024, 2)
    $ActiveGB     = [Math]::Round($ActiveMB   / 1024, 2)
    $ColdGB       = [Math]::Round([Math]::Max($ConsumedGB - $ActiveGB, 0), 2)
    $MemUsagePct  = if ($AllocatedGB -gt 0) { [Math]::Round(($ConsumedGB / $AllocatedGB) * 100, 2) } else { 0 }
    $ActivePct    = if ($ConsumedGB  -gt 0) { [Math]::Round(($ActiveGB   / $ConsumedGB)  * 100, 2) } else { 0 }
    $ColdPct      = if ($ConsumedGB  -gt 0) { [Math]::Round(($ColdGB     / $ConsumedGB)  * 100, 2) } else { 0 }

    # NVMe Tiering 적합 여부 판단 (Cold 비율 20% 이상이면 후보)
    $TieringCandidate = if ($ColdGB -ge 1 -and $ColdPct -ge 20) { "Yes" } else { "No" }

    $MemPageReport += [PSCustomObject]@{
        "Cluster"              = $H.Parent.Name
        "HostName"             = $H.Name
        "Allocated_Mem_GB"     = $AllocatedGB
        "Consumed_Mem_GB"      = $ConsumedGB
        "Mem_Usage_Pct"        = "$MemUsagePct %"
        "Active_Mem_GB"        = $ActiveGB
        "Active_Pct_of_Consumed" = "$ActivePct %"
        "Cold_Mem_GB"          = $ColdGB
        "Cold_Pct_of_Consumed" = "$ColdPct %"
        "NVMe_Tiering_Candidate" = $TieringCandidate
        "Stat_Source"          = $StatSource
    }
}
Write-Progress -Activity "ESX Memory Page" -Completed
if ($MemPageReport) { $MemPageReport | Export-Csv -Path "$ReportDir\ESX_Memory_Page.csv" -NoTypeInformation -Encoding UTF8 }

# ----------------------------------------------------
# 11 & 12. Finalize
# ----------------------------------------------------
Write-Host "[11/12] Disconnecting from vCenter..." -ForegroundColor Cyan
Disconnect-VIServer -Server $vCenter -Confirm:$false | Out-Null

Write-Host "===============================================================================" -ForegroundColor Green
Write-Host "[12/12] SUCCESS: All inventory reports have been saved." -ForegroundColor Green
Write-Host "Output Folder: $ReportDir" -ForegroundColor Yellow
Write-Host ""
Write-Host "-------------------------------------------------------------------------------" -ForegroundColor Cyan
Write-Host " Hardware Compatibility Check (HCL)" -ForegroundColor Cyan
Write-Host "-------------------------------------------------------------------------------" -ForegroundColor Cyan
Write-Host " Compatibility check is not performed by this script." -ForegroundColor White
Write-Host " To run the HCL compatibility check, use the standalone script:" -ForegroundColor White
Write-Host ""
Write-Host "   .\vcf9-hcl-check.ps1 -InventoryPath '$ReportDir'" -ForegroundColor Yellow
Write-Host ""
Write-Host " Requirements:" -ForegroundColor DarkGray
Write-Host "   - Place HCL CSV files (CPU_Series, IO_Devices, Systems_Servers, vSAN_IO_Controller)" -ForegroundColor DarkGray
Write-Host "     in the 'hcl' subfolder next to vcf9-hcl-check.ps1" -ForegroundColor DarkGray
Write-Host "   - Or specify the HCL folder path: -HCLPath `"C:\your\hcl`"" -ForegroundColor DarkGray
Write-Host "   - ESXi 9.0 / 9.1 version-specific files: use filenames containing '9_0' or '9_1'" -ForegroundColor DarkGray
Write-Host "-------------------------------------------------------------------------------" -ForegroundColor Cyan
Write-Host "===============================================================================" -ForegroundColor Green