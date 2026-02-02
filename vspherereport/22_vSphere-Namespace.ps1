param($Server, $SessionId)

# ---------------------------------------------------------------------------
# [INFO]
# vSphere with Tanzu (Workload Management)의 네임스페이스 상태를 점검합니다.
# vCenter 7.0u3 이상에서 지원하는 v2 API를 사용합니다.
# ---------------------------------------------------------------------------

$Headers = @{
    "vmware-api-session-id" = $SessionId
    "Accept"                = "application/json"
}

$baseUrl = "https://$Server/api"

try {
    # [STEP 1] 모든 네임스페이스 리스트 가져오기
    # GET /vcenter/namespaces/instances (v2 엔드포인트 사용)
    # 404/403 에러 발생 시(기능 미사용 등)를 대비해 try-catch 내부 처리
    $nsListUrl = "$baseUrl/vcenter/namespaces/instances/v2"
    
    try {
        $namespaces = Invoke-RestMethod -Uri $nsListUrl -Method Get -Headers $Headers -ErrorAction Stop
    } catch {
        # API 호출 자체가 실패한 경우 (예: Workload Management 미사용)
        # 메인 리포트에서 "데이터 없음"으로 처리되도록 null 반환
        return $null
    }

    if ($null -eq $namespaces -or $namespaces.Count -eq 0) {
        # 네임스페이스가 하나도 없는 경우
        return $null
    }

    $allReports = foreach ($nsSummary in $namespaces) {
        $namespaceName = $nsSummary.namespace
        
        # [STEP 2] 각 네임스페이스 상세 정보 조회
        $nsDetailUrl = "$baseUrl/vcenter/namespaces/instances/v2/$namespaceName"
        try {
            $nsInfo = Invoke-RestMethod -Uri $nsDetailUrl -Method Get -Headers $Headers -ErrorAction Stop

            if ($null -ne $nsInfo) {
                
                # 리소스 통계 (Stats가 비어있을 경우 0 처리)
                $CpuUsed = if ($nsInfo.stats.cpu_used) { $nsInfo.stats.cpu_used } else { 0 }
                $MemUsed = if ($nsInfo.stats.memory_used) { [Math]::Round($nsInfo.stats.memory_used / 1024, 2) } else { 0 }
                $StrUsed = if ($nsInfo.stats.storage_used) { [Math]::Round($nsInfo.stats.storage_used / 1024, 2) } else { 0 }

                # 상태 메시지 (RUNNING -> 초록색 배지 적용을 위해 대문자 변환)
                $StatusRaw = $nsInfo.config_status
                $StatusBadge = if ($StatusRaw) { $StatusRaw.ToUpper() } else { "UNKNOWN" }
                
                # 상세 메시지 요약
                $Msg = if ($nsInfo.messages -and $nsInfo.messages.Count -gt 0) { 
                    $nsInfo.messages[0].details.localized 
                } else { "Normal" }

                [PSCustomObject]@{
                    Namespace       = $namespaceName
                    Supervisor      = $nsInfo.supervisor
                    ConfigStatus    = $StatusBadge
                    "CPU(MHz)"      = $CpuUsed
                    "Mem(GB)"       = $MemUsed
                    "Storage(GB)"   = $StrUsed
                    Networks        = ($nsInfo.networks -join ", ")
                    Message         = $Msg
                }
            }
        }
        catch {
            # 특정 네임스페이스 조회 실패 시 에러 행 추가
            [PSCustomObject]@{
                Namespace       = $namespaceName
                Supervisor      = "Error"
                ConfigStatus    = "WARN: Check API"
                "CPU(MHz)"      = 0
                "Mem(GB)"       = 0
                "Storage(GB)"   = 0
                Networks        = "-"
                Message         = $_.Exception.Message
            }
        }
    }

    # 최종 결과 회신
    return $allReports
}
catch {
    Write-Host " [!] Error querying Namespaces: $($_.Exception.Message)" -ForegroundColor Red
    return $null
}