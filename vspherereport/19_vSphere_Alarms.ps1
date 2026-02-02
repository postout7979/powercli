param($Server, $SessionId)

# ---------------------------------------------------------------------------
# [INFO]
# ESXi Host에 발생한 Triggered Alarm(경보) 상태를 조회합니다.
# 성능 최적화: 알람 정의(Definition)를 매번 조회하지 않고 해시테이블에 캐싱합니다.
# Return: 알람이 없으면 $null을 반환합니다.
# ---------------------------------------------------------------------------

try {
    # 1. 호스트 및 알람 상태 조회 (TriggeredAlarmState가 있는 호스트만 필터링 가능하지만, 전체 조회 후 로직 처리)
    $HostViews = Get-View -ViewType HostSystem -Property Name, TriggeredAlarmState -ErrorAction Stop

    $Alarms = @()
    $AlarmDefCache = @{} # 알람 이름 캐싱용 해시테이블 (API 호출 횟수 획기적 감소)

    foreach ($hv in $HostViews) {
        # 알람이 없는 호스트는 스킵
        if ($null -eq $hv.TriggeredAlarmState) { continue }

        foreach ($ta in $hv.TriggeredAlarmState) {
            # 2. Red(Critical) 또는 Yellow(Warning) 상태인 알람만 추출
            if ($ta.OverallStatus -match "red|yellow") {
                
                # 3. 알람 이름 조회 (캐싱 로직)
                #    동일한 알람(예: Host Connection Lost)이 여러 호스트에 떴을 때,
                #    API를 매번 호출하지 않고 메모리에서 가져옴.
                $AlarmId = $ta.Alarm.Value
                if (-not $AlarmDefCache.ContainsKey($AlarmId)) {
                    try {
                        $DefView = Get-View -Id $ta.Alarm -Property Info.Name -ErrorAction SilentlyContinue
                        $AlarmDefCache[$AlarmId] = if ($DefView) { $DefView.Info.Name } else { "Unknown Alarm" }
                    } catch {
                        $AlarmDefCache[$AlarmId] = "Unknown Alarm"
                    }
                }
                $AlarmName = $AlarmDefCache[$AlarmId]

                # 4. 상태값 변환 (HTML 리포트 배지 색상 적용)
                #    red -> CRITICAL / yellow -> WARN
                $StatusStr = if ($ta.OverallStatus -eq "red") { "CRITICAL" } else { "WARN" }

                $Alarms += [PSCustomObject]@{ 
                    Entity    = $hv.Name
                    AlarmName = $AlarmName
                    Status    = $StatusStr
                    Time      = $ta.Time.ToString("yyyy-MM-dd HH:mm")
                    # message 필드는 TriggeredAlarmState에 직접 포함되지 않으므로 제거하거나 Acknowledged 여부로 대체
                    Acknowledged = if ($ta.Acknowledged) { "Yes" } else { "No" }
                }
            }
        }
    }

    # 5. 결과 반환 처리
    #    알람이 하나도 없으면 $null 반환 (메인 리포트에서 '데이터 없음' 처리됨)
    if ($Alarms.Count -eq 0) {
        return $null
    }

    return $Alarms

} catch {
    # 에러 발생 시에도 $null 반환하여 리포트 생성 중단 방지
    Write-Host " [!] Error checking Alarms: $($_.Exception.Message)" -ForegroundColor Red
    return $null
}