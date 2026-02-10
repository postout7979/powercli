param(
    [string]$Server,
    $SessionId, 
    [string]$XsrfToken
)

# SSL 및 보안 설정
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
$null = [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Headers = @{ 
    "X-XSRF-TOKEN" = $XsrfToken
    "Accept"        = "application/json"
}

try {
    # 1. Alarms API 호출
    $Uri = "https://$Server/api/v1/alarms"
    $Response = Invoke-RestMethod -Method Get -Uri $Uri -Headers $Headers -WebSession $SessionId

    $ReportEntries = New-Object System.Collections.Generic.List[PSCustomObject]
    
    # --- [필터링 기준 설정: 현재로부터 7일 전] ---
    $SevenDaysAgo = (Get-Date).AddDays(-7)

    if ($null -ne $Response -and $null -ne $Response.results) {
        foreach ($alarm in $Response.results) {
            
            # 2. 발생 시간 변환 (비교를 위해 객체 상태로 먼저 생성)
            $RawDateTime = $null
            $EventTimeString = "N/A"
            
            if ($null -ne $alarm.last_reported_time) {
                # Unix Milliseconds를 LocalDateTime 객체로 변환
                $RawDateTime = [System.DateTimeOffset]::FromUnixTimeMilliseconds($alarm.last_reported_time).LocalDateTime
                $EventTimeString = $RawDateTime.ToString("yyyy-MM-dd HH:mm:ss")
            }

            # --- [최근 7일 이내 데이터인지 검사] ---
            # 시간이 N/A이거나 7일보다 이전이면 스킵
            if ($null -eq $RawDateTime -or $RawDateTime -lt $SevenDaysAgo) {
                continue
            }

            # 심각도 처리
            $Severity = if ($null -ne $alarm.severity) { $alarm.severity.ToUpper() } else { "UNKNOWN" }

            # 3. 결과 개체 생성 (필터를 통과한 데이터만 추가됨)
            $obj = [PSCustomObject]@{
                Time        = $EventTimeString
                Severity    = $Severity
                AlarmName   = $alarm.event_type_display_name
                NodeName    = $alarm.node_resource_type
                Description = $alarm.description
                Status      = $alarm.status
            }
            $ReportEntries.Add($obj)
        }
    }

    # 4. 시간순 정렬 (최신 알람이 위로)
    return $ReportEntries | Sort-Object Time -Descending

} catch {
    Write-Warning "[$Server] Alarms 조회 중 오류: $($_.Exception.Message)"
    return $null
}