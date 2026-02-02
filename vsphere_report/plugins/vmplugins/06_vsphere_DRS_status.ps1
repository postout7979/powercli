param($Server, $SessionId)

# ---------------------------------------------------------------------------
# [INFO]
# vSphere 클러스터의 핵심 기능인 HA 및 DRS 활성화 여부를 점검합니다.
# 불필요한 API 헤더를 제거하고, Boolean 값을 직관적인 문자열(Enabled/Disabled)로 변환했습니다.
# HA/DRS가 비활성화된 경우 'CRITICAL' 또는 'WARN' 상태로 표시합니다.
# ---------------------------------------------------------------------------

try {
    # 1. 클러스터 설정 정보 조회
    #    DasConfig = HA, DrsConfig = DRS
    $ClusterViews = Get-View -ViewType ClusterComputeResource -Property Name, Configuration.DasConfig.Enabled, Configuration.DrsConfig.Enabled, Configuration.DrsConfig.DefaultVmBehavior -ErrorAction Stop

    # 클러스터가 없는 경우
    if ($null -eq $ClusterViews -or $ClusterViews.Count -eq 0) {
        return $null
    }

    $Data = foreach ($cv in $ClusterViews) {
        
        # 2. HA 상태 변환
        if ($cv.Configuration.DasConfig.Enabled) {
            $HA_Status = "Enabled"
        } else {
            $HA_Status = "CRITICAL: Disabled" # 중요 기능이므로 꺼져있으면 빨간색 표시
        }

        # 3. DRS 상태 변환
        if ($cv.Configuration.DrsConfig.Enabled) {
            $DRS_Status = "Enabled"
            # DRS Mode (예: fullyAutomated -> FullyAutomated)
            # API가 소문자로 시작하는 경우가 있어 첫 글자 대문자 처리 정도만 수행하거나 그대로 사용
            $RawMode = $cv.Configuration.DrsConfig.DefaultVmBehavior
            $DRS_Mode = if ($RawMode) { $RawMode.ToString() } else { "Unknown" }
        } else {
            $DRS_Status = "WARN: Disabled" # DRS는 상황에 따라 끌 수도 있으므로 WARN 처리
            $DRS_Mode = "N/A"
        }

        # 4. 결과 객체 생성
        [PSCustomObject]@{
            ClusterName = $cv.Name
            "HA Status" = $HA_Status
            "DRS Status"= $DRS_Status
            "DRS Mode"  = $DRS_Mode
        }
    }
    
    return $Data

} catch {
    Write-Host " [!] Error querying Cluster HA/DRS: $($_.Exception.Message)" -ForegroundColor Red
    return $null
}