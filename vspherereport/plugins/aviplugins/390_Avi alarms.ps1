param([string]$Server, $SessionId, [string]$XsrfToken, [string]$version)

$null = [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
$Headers = @{ 
    "Accept"        = "application/json"
    "X-Avi-Version" = $version
    "X-CSRFToken"   = $XsrfToken 
}

try {
    $ReportEntries = New-Object System.Collections.Generic.List[PSCustomObject]
    $ThreeDaysAgo = (Get-Date).AddDays(-3)
    
    $AlertUri = "https://$Server/api/alert"
    $AlertRes = Invoke-RestMethod -Method Get -Uri $AlertUri -Headers $Headers -WebSession $SessionId -ErrorAction Stop

    if ($null -ne $AlertRes.results -and $AlertRes.count -gt 0) {
        foreach ($alert in $AlertRes.results) {
            
            # [수정] 날짜 파싱 로직 강화
            # Get-Date는 ISO 8601 형식을 유연하게 처리하며, 실패 시 에러가 아닌 null을 반환하도록 처리
            $AlertTime = $null
            try {
                if ($alert.timestamp -match "^\d{4}-\d{2}-\d{2}") {
                    # 소수점 마이크로초가 너무 길 경우를 대비해 앞의 19자리(초 단위)까지만 잘라서 처리하거나
                    # DateTimeOffset을 사용하여 표준 ISO 형식을 강제 변환합니다.
                    $AlertTime = [DateTimeOffset]::Parse($alert.timestamp).DateTime
                }
            } catch {
                # 파싱 실패 시 원본 문자열을 남기거나 건너뜁니다.
                Continue
            }

            # 3. 3일 이내 필터링 (파싱 성공 시에만)
            if ($null -ne $AlertTime -and $AlertTime -ge $ThreeDaysAgo) {
                $ReportEntries.Add([PSCustomObject]@{
                    Time        = $AlertTime.ToString("yyyy-MM-dd HH:mm:ss")
                    Severity    = $alert.level.Replace("ALERT_LOW", "LOW").Replace("ALERT_MEDIUM", "MEDIUM").Replace("ALERT_HIGH", "HIGH")
                    Name        = $alert.name
                    Target      = $alert.obj_name
                    Description = $alert.description
                })
            }
        }
    }

    if ($ReportEntries.Count -eq 0) {
        $ReportEntries.Add([PSCustomObject]@{
            Time        = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Severity    = "NORMAL"
            Name        = "No Recent Alarms"
            Target      = "-"
            Description = "No alarms from 3 days before."
        })
    }

    return $ReportEntries | Sort-Object Time -Descending
} catch {
    Write-Host "Alarm Plugin Error: $($_.Exception.Message)" -ForegroundColor Red
    return $null
}