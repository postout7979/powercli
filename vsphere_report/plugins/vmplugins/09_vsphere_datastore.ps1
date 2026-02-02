param($Server, $SessionId)

# ---------------------------------------------------------------------------
# [INFO]
# vCenter에 연결된 모든 데이터스토어(VMFS, NFS, vSAN, vVOL)의 용량을 점검합니다.
# - vSAN 전용 필터를 제거하여 전체 조회로 변경했습니다.
# - 데이터스토어 유형(Type) 컬럼을 추가했습니다.
# - 사용률이 90% 이상이면 상태가 Green이어도 'CRITICAL' 배지를 표시합니다.
# ---------------------------------------------------------------------------

try {
    # 1. 모든 데이터스토어 조회 (Filter 제거)
    #    속성: 이름, 전체용량, 여유공간, 타입, 상태
    $DSViews = Get-View -ViewType Datastore -Property Name, Summary.Capacity, Summary.FreeSpace, Summary.Type, OverallStatus -ErrorAction Stop

    if ($null -eq $DSViews -or $DSViews.Count -eq 0) {
        return $null
    }

    $Data = foreach ($ds in $DSViews) {
        # 2. 용량 계산 (GB 단위)
        $TotalGB = [Math]::Round($ds.Summary.Capacity / 1GB, 1)
        $FreeGB  = [Math]::Round($ds.Summary.FreeSpace / 1GB, 1)
        $UsedGB  = [Math]::Round($TotalGB - $FreeGB, 1)
        
        # 0으로 나누기 방지 (마운트 해제된 데이터스토어 등 용량이 0일 수 있음)
        $UsedPct = if ($TotalGB -gt 0) { [Math]::Round(($UsedGB / $TotalGB) * 100, 1) } else { 0 }
        
        # 3. 상태값 변환 (HTML 리포트 배지 색상 적용)
        $RawStatus = $ds.OverallStatus
        switch ($RawStatus) {
            "green"  { $StatusStr = "GOOD" }
            "yellow" { $StatusStr = "WARN" }
            "red"    { $StatusStr = "CRITICAL" }
            "gray"   { $StatusStr = "UNKNOWN" }
            default  { $StatusStr = $RawStatus }
        }

        # 4. 사용률 기반 상태 오버라이드 (안전장치)
        #    상태가 정상이더라도 사용률이 높으면 경고 표시
        if ($UsedPct -ge 90) {
            $StatusStr = "CRITICAL: Full ($UsedPct%)"
        } elseif ($UsedPct -ge 80) {
            $StatusStr = "WARN: High Usage ($UsedPct%)"
        }

        # 5. 결과 객체 생성
        [PSCustomObject]@{
            Name        = $ds.Name
            Type        = $ds.Summary.Type.ToUpper() # VMFS, NFS, VSAN 등 대문자로 표시
            Health      = $StatusStr
            "Total(GB)" = $TotalGB
            "Used(GB)"  = $UsedGB
            "Free(GB)"  = $FreeGB
            "Used(%)"   = "$UsedPct%"
        }
    }
    
    # 보기 좋게 이름순 정렬
    return $Data | Sort-Object Name

} catch {
    Write-Host " [!] Error querying Datastores: $($_.Exception.Message)" -ForegroundColor Red
    return $null
}