param($Server, $SessionId)

# ---------------------------------------------------------------------------
# [INFO]
# Cluster의 DRS 규칙(Affinity, Anti-Affinity, VM-Host Rules)을 점검합니다.
# 수정사항: 'KeepTogether' 속성 사용 중단 경고(Deprecated)를 해결하기 위해
#           객체의 클래스 이름(GetType)을 기반으로 규칙 유형을 판별하도록 변경했습니다.
# ---------------------------------------------------------------------------

try {
    # 1. 클러스터 목록 조회 (오류 시 중단)
    $Clusters = Get-Cluster -ErrorAction Stop

    $Results = @()

    foreach ($Cluster in $Clusters) {
        try {
            # 2. 해당 클러스터의 DRS 규칙 조회
            $Rules = Get-DrsRule -Cluster $Cluster -ErrorAction Stop
            
            foreach ($Rule in $Rules) {
                # 3. 규칙 유형 판별 로직 개선 (Deprecated 경고 해결)
                #    $Rule.GetType().Name을 확인하여 객체 타입 자체로 구분합니다.
                
                $ObjType = $Rule.GetType().Name
                $RuleType = "Unknown"

                # (1) VM-Host Rule (Type 속성 존재: MustRunOn, ShouldRunOn 등)
                if ($ObjType -match "VmHostRule") {
                    $RuleType = "VM-Host: $($Rule.Type)"
                }
                # (2) VM Anti-Affinity (서로 떨어뜨리기)
                elseif ($ObjType -match "AntiAffinity") {
                    $RuleType = "VM Anti-Affinity (Separate)"
                }
                # (3) VM Affinity (같이 두기 - AntiAffinity가 아니면서 Affinity가 포함된 경우)
                elseif ($ObjType -match "Affinity") {
                    $RuleType = "VM Affinity (Keep Together)"
                }

                # 4. 상태값 변환 (Enabled -> 초록색 배지 적용)
                $Status = if ($Rule.Enabled) { "Enabled" } else { "Disabled" }
                
                # 5. VM 목록 추출
                #    VM-Host 규칙의 경우 'VM' 속성이 없을 수 있으므로 체크
                $VMList = "N/A"
                if ($Rule.VM) {
                    $VMNames = $Rule.VM | ForEach-Object { $_.Name }
                    $VMList = $VMNames -join ", "
                }

                $Results += [PSCustomObject]@{
                    Cluster     = $Cluster.Name
                    RuleName    = $Rule.Name
                    Type        = $RuleType
                    Status      = $Status
                    VMCount     = if ($Rule.VM) { $Rule.VM.Count } else { 0 }
                    VMList      = $VMList
                }
            }
        } catch {
            # 특정 클러스터 조회 실패 시 로그
            Write-Host " [!] Error querying DRS rules for cluster '$($Cluster.Name)': $($_.Exception.Message)" -ForegroundColor DarkGray
        }
    }

    # 데이터가 없으면 null 반환
    if ($Results.Count -eq 0) {
        return $null
    }

    return $Results

} catch {
    Write-Host " [!] Error querying DRS Rules: $($_.Exception.Message)" -ForegroundColor Red
    return $null
}