<#
.SYNOPSIS
    Aria Operations (vROps) 8.x REST API를 통해 전체 VM의 CPU/Memory/Disk/Network
    성능 지표(Peak, Avg)를 지정 기간에 대해 수집하여 CSV로 출력합니다.

.DESCRIPTION
    - 실행 시 Aria Operations 서버 주소, 계정, 인증 소스를 프롬프트로 입력받습니다.
    - -Days 파라미터로 조회 기간(직전 N일)을 지정할 수 있습니다. (기본값: 30일)
    - resources/stats/query API를 AVG / MAX 두 가지 rollUpType으로 각각 호출하여
      기간 전체에 대한 평균값과 최고값을 함께 수집합니다.
    - VM 단위 집계(CPU/Memory/Disk/Network) CSV와 별개로, 각 VM의 SCSI 컨트롤러:유닛
      (예: scsi0:0, scsi0:1)별 Virtual Disk 읽기/쓰기 처리량을 자동 탐색하여
      별도의 "_VirtualDiskDetail.csv" 파일로 수집합니다.
    - Windows PowerShell 5.1 호환 (TLS 1.2 강제 설정, 자체서명 인증서 허용 포함)

.PARAMETER Days
    조회할 직전 기간(일). 기본값 30 (직전 1개월 상당)

.PARAMETER OutputPath
    결과 CSV 파일 경로. 기본값: .\AriaOps_VM_Performance_yyyyMMdd_HHmmss.csv

.PARAMETER PageSize
    리소스 목록 조회 시 페이지 크기 (기본 1000)

.PARAMETER BatchSize
    stats/query 호출 시 한 번에 조회할 VM 개수 (기본 50)

.EXAMPLE
    .\Get-AriaOpsVMPerformance.ps1
    # 프롬프트로 서버/계정 입력 후 직전 30일 데이터 수집

.EXAMPLE
    .\Get-AriaOpsVMPerformance.ps1 -Days 7
    # 직전 7일 데이터 수집
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [int]$Days = 30,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = ".\AriaOps_VM_Performance_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv",

    [Parameter(Mandatory = $false)]
    [int]$PageSize = 1000,

    [Parameter(Mandatory = $false)]
    [int]$BatchSize = 50
)

$ErrorActionPreference = "Stop"

# ----------------------------------------------------------------------------
# 0. TLS 1.2 강제 + 자체서명 인증서 허용 (Windows PowerShell 5.1 호환)
# ----------------------------------------------------------------------------
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if (-not ("TrustAllCertsPolicy" -as [type])) {
    Add-Type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(
        ServicePoint srvPoint, X509Certificate certificate,
        WebRequest request, int certificateProblem) {
        return true;
    }
}
"@
}
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

# ----------------------------------------------------------------------------
# 1. 접속 정보 입력 (프롬프트)
# ----------------------------------------------------------------------------
Write-Host "=== Aria Operations 접속 정보 입력 ===" -ForegroundColor Cyan

$AriaOpsServer = Read-Host "Aria Operations 서버 주소 (FQDN 또는 IP, 예: aria-ops.corp.local)"
$AriaOpsUser   = Read-Host "계정 (Username)"
$SecurePwd     = Read-Host "비밀번호 (Password)" -AsSecureString
$AuthSourceIn  = Read-Host "인증 소스 (AuthSource, 로컬 계정이면 Enter로 스킵 -> 'local')"

if ([string]::IsNullOrWhiteSpace($AuthSourceIn)) {
    $AuthSource = "local"
} else {
    $AuthSource = $AuthSourceIn
}

# SecureString -> 평문 (API 호출용, 메모리 내 임시 사용 후 즉시 폐기)
$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePwd)
$PlainPwd = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)

$BaseUrl = "https://$AriaOpsServer/suite-api/api"

Write-Host ""
Write-Host "조회 기간: 직전 $Days 일 (Days 파라미터로 조정 가능)" -ForegroundColor Cyan
Write-Host ""

# ----------------------------------------------------------------------------
# 2. 인증 (Token 획득)
# ----------------------------------------------------------------------------
function Get-AriaOpsToken {
    param($BaseUrl, $User, $Pwd, $AuthSource)

    $body = @{
        username   = $User
        password   = $Pwd
        authSource = $AuthSource
    } | ConvertTo-Json

    try {
        $resp = Invoke-RestMethod -Uri "$BaseUrl/auth/token/acquire" `
            -Method Post -Body $body -ContentType "application/json" `
            -Headers @{ Accept = "application/json" }
        return $resp.token
    }
    catch {
        Write-Host "인증 실패: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}

Write-Host "Aria Operations 인증 중..." -ForegroundColor Yellow
$Token = Get-AriaOpsToken -BaseUrl $BaseUrl -User $AriaOpsUser -Pwd $PlainPwd -AuthSource $AuthSource
$PlainPwd = $null   # 평문 비밀번호 메모리에서 제거

$AuthHeader = @{
    Authorization = "vRealizeOpsToken $Token"
    Accept        = "application/json"
}
Write-Host "인증 성공" -ForegroundColor Green
Write-Host ""

# ----------------------------------------------------------------------------
# 3. 전체 VirtualMachine 리소스 목록 조회 (페이징)
# ----------------------------------------------------------------------------
function Get-AllVMResources {
    param($BaseUrl, $AuthHeader, $PageSize)

    $allResources = New-Object System.Collections.Generic.List[object]
    $page = 0
    do {
        $uri = "$BaseUrl/resources?resourceKind=VirtualMachine&adapterKind=VMWARE&page=$page&pageSize=$PageSize"
        $resp = Invoke-RestMethod -Uri $uri -Method Get -Headers $AuthHeader

        if ($resp.resourceList) {
            foreach ($r in $resp.resourceList) {
                $allResources.Add([PSCustomObject]@{
                    ResourceId = $r.identifier
                    VMName     = $r.resourceKey.name
                })
            }
        }

        $totalPages = [math]::Ceiling($resp.pageInfo.totalCount / $PageSize)
        $page++
        Write-Host ("  VM 목록 조회 중... {0}/{1} 페이지" -f $page, [math]::Max($totalPages,1)) -ForegroundColor DarkGray
    } while ($page -lt $totalPages)

    return $allResources
}

Write-Host "VM 목록 조회 중..." -ForegroundColor Yellow
$VMList = Get-AllVMResources -BaseUrl $BaseUrl -AuthHeader $AuthHeader -PageSize $PageSize
Write-Host "총 $($VMList.Count)개 VM 확인됨" -ForegroundColor Green
Write-Host ""

if ($VMList.Count -eq 0) {
    Write-Host "조회된 VM이 없습니다. 스크립트를 종료합니다." -ForegroundColor Red
    return
}

# ----------------------------------------------------------------------------
# 4. 기간(epoch ms) 계산
# ----------------------------------------------------------------------------
$EndDate   = Get-Date
$BeginDate = $EndDate.AddDays(-1 * $Days)

function ConvertTo-EpochMillis {
    param([datetime]$Date)
    return [DateTimeOffset]::new($Date.ToUniversalTime()).ToUnixTimeMilliseconds()
}

$BeginMs = ConvertTo-EpochMillis -Date $BeginDate
$EndMs   = ConvertTo-EpochMillis -Date $EndDate

# ----------------------------------------------------------------------------
# 5. 수집할 statKey 정의
#    - AVG/MAX 롤업 대상: 사용률/처리량/레이턴시 등 (기간 전체 평균/최고값)
#    - SUM  롤업 대상   : summation 계열 카운터 (기간 전체 누적 발생 건수)
#    ※ statKey 표기는 VMware Aria Operations / vRealize Operations 공식
#      Metric Definitions 문서 기준 (disk|, net|, mem|, cpu|, guestfilesystem|)
# ----------------------------------------------------------------------------
$StatKeys_AvgMax = @(
    # --- CPU ---
    "cpu|usage_average",              # CPU 사용률 (%)
    "cpu|usagemhz_average",           # CPU 사용량 (MHz)
    "cpu|readyPct",                   # CPU Ready (%) - 호스트 CPU 경합(contention) 지표

    # --- Memory ---
    "mem|usage_average",              # Memory 사용률 (%)
    "mem|active_average",             # Active Memory (KB)
    "mem|consumed_average",           # Consumed Memory (KB) - 실제 호스트 물리 메모리 소비량
    "mem|swapped_average",            # Swapped Memory (KB) - 메모리 부족 시 디스크로 스왑된 양
    # mem|vmmemctl_average(벌룬)은 이 환경에서 수집되지 않아 제거함 (2026-07-15 확인)

    # --- Disk (호스트/VM 관점 disk| 그룹) ---
    "disk|usage_average",             # Disk 전체 처리량 (KBps) - 일부 VM만 수집됨
    # disk|totalLatency_average, totalReadLatency_average, totalWriteLatency_average,
    # commandsAveraged_average 는 이 환경에서 전혀 수집되지 않아 제거함 (2026-07-15 확인)

    # --- Virtual Disk (가상 디스크 관점 virtualDisk| 그룹, "Aggregate of all Instances")
    #     레이턴시/IOPS 계열(totalLatency, totalReadLatency, totalWriteLatency,
    #     commandsAveraged, numberReadAveraged, numberWriteAveraged)은 이 환경에서
    #     전혀 수집되지 않아 제거함 (2026-07-15 확인). 처리량(read/write_average)만 유지.
    "virtualDisk|read_average",              # VD 읽기 처리량 (KBps)
    "virtualDisk|write_average",             # VD 쓰기 처리량 (KBps)

    # --- Network ---
    "net|usage_average",              # Network 전체 처리량 (KBps)
    # net|droppedPct는 이 환경에서 수집되지 않아 제거함 (2026-07-15 확인). 대신
    # net|droppedRx_summation / droppedTx_summation (SUM 롤업)으로 드롭 발생 여부 확인.

    # --- Guest OS ---
    "guestfilesystem|percentage_total"  # Guest OS 전체 파일시스템 사용률 (%) - VMware Tools 필요
)

$StatKeys_Sum = @(
    # summation 계열: 기간 전체 누적 건수 확인용 (SUM 롤업으로 별도 조회)
    "net|droppedRx_summation",        # 수신 패킷 드롭 누적 건수
    "net|droppedTx_summation"         # 송신 패킷 드롭 누적 건수
)

$StatKeys = $StatKeys_AvgMax + $StatKeys_Sum

# statKey -> 결과 컬럼 접두어 매핑 (AVG/MAX 대상)
$StatColumnMap = @{
    "cpu|usage_average"                = "CPU_Pct"
    "cpu|usagemhz_average"             = "CPU_MHz"
    "cpu|readyPct"                     = "CPU_ReadyPct"
    "mem|usage_average"                = "Mem_Pct"
    "mem|active_average"               = "Mem_Active_KB"
    "mem|consumed_average"             = "Mem_Consumed_KB"
    "mem|swapped_average"              = "Mem_Swapped_KB"
    "disk|usage_average"               = "Disk_KBps"
    "virtualDisk|read_average"         = "VD_ReadThroughput_KBps"
    "virtualDisk|write_average"        = "VD_WriteThroughput_KBps"
    "net|usage_average"                = "Net_KBps"
    "guestfilesystem|percentage_total" = "GuestFS_UsagePct"
}

# statKey -> 결과 컬럼명 매핑 (SUM 대상, Avg/Peak 구분 없이 누적 총합 1개 컬럼)
$StatColumnMap_Sum = @{
    "net|droppedRx_summation" = "Net_DroppedRx_Total"
    "net|droppedTx_summation" = "Net_DroppedTx_Total"
}

# ----------------------------------------------------------------------------
# 6. stats/query 호출 함수 (기간 전체를 1개 구간으로 롤업)
# ----------------------------------------------------------------------------
function Get-StatsForResources {
    param(
        [string]$BaseUrl,
        [hashtable]$AuthHeader,
        [string[]]$ResourceIds,
        [string[]]$StatKeys,
        [long]$BeginMs,
        [long]$EndMs,
        [string]$RollUpType   # AVG or MAX
    )

    $body = @{
        resourceId      = $ResourceIds
        statKey         = $StatKeys
        begin           = $BeginMs
        end             = $EndMs
        rollUpType      = $RollUpType
        intervalType    = "MONTHS"
        intervalQuantity = 1
    } | ConvertTo-Json

    $resp = Invoke-RestMethod -Uri "$BaseUrl/resources/stats/query" -Method Post `
        -Body $body -ContentType "application/json" -Headers $AuthHeader

    return $resp
}

# ----------------------------------------------------------------------------
# 6-1. VM별 Virtual Disk 인스턴스(SCSI 컨트롤러:유닛) 탐색 함수
#      GET /resources/{id}/stats/latest 로 현재 수집 중인 모든 statKey를 조회한 뒤
#      "virtualDisk:<instance>|<metric>" 형태의 키에서 인스턴스명(예: scsi0:0)을 추출한다.
#      (예: virtualDisk:scsi0:0|totalLatency_average -> instance = scsi0:0)
# ----------------------------------------------------------------------------
function Get-VirtualDiskInstances {
    param(
        [string]$BaseUrl,
        [hashtable]$AuthHeader,
        [string]$ResourceId
    )

    $instances = New-Object System.Collections.Generic.List[string]

    try {
        $resp = Invoke-RestMethod -Uri "$BaseUrl/resources/$ResourceId/stats/latest" `
            -Method Get -Headers $AuthHeader

        # API 응답 스키마가 버전에 따라 stat-list / stats 두 가지 형태로 올 수 있어 둘 다 처리
        $statArray = $null
        if ($resp.values) {
            foreach ($val in $resp.values) {
                if ($val.'stat-list' -and $val.'stat-list'.stat) {
                    $statArray = $val.'stat-list'.stat
                } elseif ($val.stats -and $val.stats.stat) {
                    $statArray = $val.stats.stat
                }
            }
        } elseif ($resp.'stat-list' -and $resp.'stat-list'.stat) {
            $statArray = $resp.'stat-list'.stat
        } elseif ($resp.stats -and $resp.stats.stat) {
            $statArray = $resp.stats.stat
        }

        if ($statArray) {
            foreach ($stat in $statArray) {
                $key = $stat.statKey.key
                if ($key -and $key -like "virtualDisk:*|*") {
                    # "virtualDisk:scsi0:0|totalLatency_average" -> groupPart = "virtualDisk:scsi0:0"
                    $groupPart = $key.Substring(0, $key.IndexOf('|'))
                    $colonIdx = $groupPart.IndexOf(':')
                    if ($colonIdx -ge 0) {
                        $instance = $groupPart.Substring($colonIdx + 1)
                        if (-not $instances.Contains($instance)) {
                            $instances.Add($instance)
                        }
                    }
                }
            }
        }
    }
    catch {
        # 개별 VM 조회 실패는 전체를 중단시키지 않고 건너뜀 (권한 문제, 삭제된 VM 등)
    }

    return $instances
}

# ----------------------------------------------------------------------------
# 6-2. 전체 VM에 대해 Virtual Disk 인스턴스(SCSI 컨트롤러) 탐색
#      VM마다 1회씩 가벼운 GET 호출 (currentOnly 성격의 /stats/latest)이 발생하므로
#      VM 수가 매우 많은 환경에서는 다소 시간이 걸릴 수 있습니다.
# ----------------------------------------------------------------------------
Write-Host "SCSI 컨트롤러(Virtual Disk 인스턴스) 탐색 중..." -ForegroundColor Yellow

# 수집할 인스턴스별 metric -> 결과 컬럼명 매핑
# (레이턴시/IOPS 계열은 이 환경에서 aggregate 레벨조차 수집되지 않는 것으로 확인되어 제외.
#  인스턴스 레벨도 동일하게 수집되지 않을 가능성이 높아 처리량만 유지함. 2026-07-15 확인)
$VirtualDiskInstanceMetrics = @{
    "read_average"                = "ReadThroughput_KBps"
    "write_average"               = "WriteThroughput_KBps"
}

# ResourceId -> 해당 VM의 인스턴스 목록(예: scsi0:0, scsi0:1, ...)
$VMDiskInstances = @{}
$AllInstancesSet = New-Object System.Collections.Generic.HashSet[string]

$discoverCount = 0
foreach ($v in $VMList) {
    $discoverCount++
    if ($discoverCount % 25 -eq 0) {
        Write-Host ("  인스턴스 탐색 중... {0}/{1}" -f $discoverCount, $VMList.Count) -ForegroundColor DarkGray
    }

    $foundInstances = Get-VirtualDiskInstances -BaseUrl $BaseUrl -AuthHeader $AuthHeader -ResourceId $v.ResourceId
    $VMDiskInstances[$v.ResourceId] = $foundInstances

    foreach ($inst in $foundInstances) {
        [void]$AllInstancesSet.Add($inst)
    }
}

$AllInstances = @($AllInstancesSet)
Write-Host ("발견된 SCSI 컨트롤러/유닛 인스턴스: {0}개 ({1})" -f $AllInstances.Count, ($AllInstances -join ", ")) -ForegroundColor Green
Write-Host ""

# Virtual Disk 인스턴스별 statKey 목록 구성 (예: virtualDisk:scsi0:0|totalLatency_average)
$VirtualDiskInstanceStatKeys = @()
foreach ($inst in $AllInstances) {
    foreach ($metricKey in $VirtualDiskInstanceMetrics.Keys) {
        $VirtualDiskInstanceStatKeys += "virtualDisk:${inst}|${metricKey}"
    }
}

# 인스턴스별 결과 저장 (VMName, ResourceId, DiskInstance 별로 한 행)
$DiskInstanceResultMap = @{}
foreach ($v in $VMList) {
    foreach ($inst in $VMDiskInstances[$v.ResourceId]) {
        $rowKey = "$($v.ResourceId)|$inst"
        $row = [ordered]@{
            VMName       = $v.VMName
            ResourceId   = $v.ResourceId
            DiskInstance = $inst
        }
        foreach ($colName in $VirtualDiskInstanceMetrics.Values) {
            $row["${colName}_Avg"]  = $null
            $row["${colName}_Peak"] = $null
        }
        $DiskInstanceResultMap[$rowKey] = $row
    }
}

# ----------------------------------------------------------------------------
# 7. VM을 배치 단위로 나눠 AVG / MAX 각각 조회 후 결과 병합
# ----------------------------------------------------------------------------
Write-Host "성능 데이터 수집 중 (배치 크기: $BatchSize)..." -ForegroundColor Yellow

# ResourceId -> VMName 매핑 (빠른 조회용)
$VMNameMap = @{}
foreach ($v in $VMList) { $VMNameMap[$v.ResourceId] = $v.VMName }

# 최종 결과 저장용: ResourceId 별로 통계값 누적
$ResultMap = @{}
foreach ($v in $VMList) {
    $ResultMap[$v.ResourceId] = [ordered]@{
        VMName = $v.VMName
        ResourceId = $v.ResourceId
    }
    foreach ($colPrefix in $StatColumnMap.Values) {
        $ResultMap[$v.ResourceId]["${colPrefix}_Avg"]  = $null
        $ResultMap[$v.ResourceId]["${colPrefix}_Peak"] = $null
    }
    foreach ($colName in $StatColumnMap_Sum.Values) {
        $ResultMap[$v.ResourceId][$colName] = $null
    }
}

$AllResourceIds = $VMList.ResourceId
$BatchCount = [math]::Ceiling($AllResourceIds.Count / $BatchSize)
$currentBatch = 0

for ($i = 0; $i -lt $AllResourceIds.Count; $i += $BatchSize) {
    $currentBatch++
    $chunk = $AllResourceIds[$i..([math]::Min($i + $BatchSize - 1, $AllResourceIds.Count - 1))]

    Write-Host ("  배치 {0}/{1} 처리 중 ({2}대)..." -f $currentBatch, $BatchCount, $chunk.Count) -ForegroundColor DarkGray

    # --- AVG / MAX 롤업 (사용률, 처리량, 레이턴시, IOPS 등) ---
    foreach ($rollUp in @("AVG", "MAX")) {
        try {
            $statResp = Get-StatsForResources -BaseUrl $BaseUrl -AuthHeader $AuthHeader `
                -ResourceIds $chunk -StatKeys $StatKeys_AvgMax -BeginMs $BeginMs -EndMs $EndMs -RollUpType $rollUp

            if (-not $statResp.values) { continue }

            foreach ($val in $statResp.values) {
                $rid = $val.resourceId
                if (-not $val.'stat-list'.stat) { continue }

                foreach ($stat in $val.'stat-list'.stat) {
                    $key = $stat.statKey.key
                    if (-not $StatColumnMap.ContainsKey($key)) { continue }
                    $colPrefix = $StatColumnMap[$key]

                    if ($stat.data -and $stat.data.Count -gt 0) {
                        # 롤업된 단일 구간이므로 마지막 값을 사용 (안전하게 최대값도 고려)
                        $value = ($stat.data | Measure-Object -Maximum).Maximum
                        $value = [math]::Round($value, 2)

                        if ($rollUp -eq "AVG") {
                            $ResultMap[$rid]["${colPrefix}_Avg"] = $value
                        } else {
                            $ResultMap[$rid]["${colPrefix}_Peak"] = $value
                        }
                    }
                }
            }
        }
        catch {
            Write-Host "    배치 $currentBatch ($rollUp) 조회 실패: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    # --- SUM 롤업 (네트워크 드롭 패킷 등 summation 계열 누적 총합) ---
    try {
        $sumResp = Get-StatsForResources -BaseUrl $BaseUrl -AuthHeader $AuthHeader `
            -ResourceIds $chunk -StatKeys $StatKeys_Sum -BeginMs $BeginMs -EndMs $EndMs -RollUpType "SUM"

        if ($sumResp.values) {
            foreach ($val in $sumResp.values) {
                $rid = $val.resourceId
                if (-not $val.'stat-list'.stat) { continue }

                foreach ($stat in $val.'stat-list'.stat) {
                    $key = $stat.statKey.key
                    if (-not $StatColumnMap_Sum.ContainsKey($key)) { continue }
                    $colName = $StatColumnMap_Sum[$key]

                    if ($stat.data -and $stat.data.Count -gt 0) {
                        $value = ($stat.data | Measure-Object -Sum).Sum
                        $ResultMap[$rid][$colName] = [math]::Round($value, 0)
                    }
                }
            }
        }
    }
    catch {
        Write-Host "    배치 $currentBatch (SUM) 조회 실패: $($_.Exception.Message)" -ForegroundColor Red
    }

    # --- SCSI 컨트롤러별 (Virtual Disk 인스턴스) AVG / MAX 롤업 ---
    if ($VirtualDiskInstanceStatKeys.Count -gt 0) {
        foreach ($rollUp in @("AVG", "MAX")) {
            try {
                $vdResp = Get-StatsForResources -BaseUrl $BaseUrl -AuthHeader $AuthHeader `
                    -ResourceIds $chunk -StatKeys $VirtualDiskInstanceStatKeys -BeginMs $BeginMs -EndMs $EndMs -RollUpType $rollUp

                if (-not $vdResp.values) { continue }

                foreach ($val in $vdResp.values) {
                    $rid = $val.resourceId
                    if (-not $val.'stat-list'.stat) { continue }

                    foreach ($stat in $val.'stat-list'.stat) {
                        $key = $stat.statKey.key   # 예: virtualDisk:scsi0:0|totalLatency_average
                        if (-not ($key -like "virtualDisk:*|*")) { continue }

                        $groupPart  = $key.Substring(0, $key.IndexOf('|'))
                        $metricPart = $key.Substring($key.IndexOf('|') + 1)
                        $colonIdx   = $groupPart.IndexOf(':')
                        if ($colonIdx -lt 0) { continue }
                        $instance = $groupPart.Substring($colonIdx + 1)

                        if (-not $VirtualDiskInstanceMetrics.ContainsKey($metricPart)) { continue }
                        $colName = $VirtualDiskInstanceMetrics[$metricPart]
                        $rowKey  = "$rid|$instance"
                        if (-not $DiskInstanceResultMap.ContainsKey($rowKey)) { continue }

                        if ($stat.data -and $stat.data.Count -gt 0) {
                            $value = ($stat.data | Measure-Object -Maximum).Maximum
                            $value = [math]::Round($value, 2)

                            if ($rollUp -eq "AVG") {
                                $DiskInstanceResultMap[$rowKey]["${colName}_Avg"] = $value
                            } else {
                                $DiskInstanceResultMap[$rowKey]["${colName}_Peak"] = $value
                            }
                        }
                    }
                }
            }
            catch {
                Write-Host "    배치 $currentBatch (SCSI 인스턴스 $rollUp) 조회 실패: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
}

Write-Host ""
Write-Host "데이터 수집 완료. CSV 저장 중..." -ForegroundColor Yellow

# ----------------------------------------------------------------------------
# 8. CSV 출력
# ----------------------------------------------------------------------------
$FinalResults = foreach ($rid in $ResultMap.Keys) {
    [PSCustomObject]$ResultMap[$rid]
}

$FinalResults = $FinalResults | Sort-Object VMName

$FinalResults | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

# --- SCSI 컨트롤러별(Virtual Disk 인스턴스) 상세 결과는 별도 CSV로 출력 ---
$DiskDetailOutputPath = $OutputPath -replace '\.csv$', '_VirtualDiskDetail.csv'
$FinalDiskDetailResults = foreach ($rowKey in $DiskInstanceResultMap.Keys) {
    [PSCustomObject]$DiskInstanceResultMap[$rowKey]
}

if ($FinalDiskDetailResults) {
    $FinalDiskDetailResults = $FinalDiskDetailResults | Sort-Object VMName, DiskInstance
    $FinalDiskDetailResults | Export-Csv -Path $DiskDetailOutputPath -NoTypeInformation -Encoding UTF8
} else {
    Write-Host "SCSI 컨트롤러(Virtual Disk) 인스턴스가 발견되지 않아 상세 CSV는 생성하지 않았습니다." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== 완료 ===" -ForegroundColor Green
Write-Host "대상 기간 : $($BeginDate.ToString('yyyy-MM-dd HH:mm')) ~ $($EndDate.ToString('yyyy-MM-dd HH:mm')) (직전 $Days 일)"
Write-Host "대상 VM 수: $($FinalResults.Count)"
Write-Host "출력 파일 : $OutputPath"
if ($FinalDiskDetailResults) {
    Write-Host "SCSI 상세 : $DiskDetailOutputPath ($($FinalDiskDetailResults.Count)개 디스크 인스턴스)"
}
