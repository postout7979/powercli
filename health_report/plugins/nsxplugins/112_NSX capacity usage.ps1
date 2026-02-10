param(
    [string]$Server,
    $SessionId, 
    [string]$XsrfToken
)

# SSL 및 TLS 보안 설정
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
$null = [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Headers = @{ 
    "X-XSRF-TOKEN" = $XsrfToken
    "Accept"       = "application/json"
}

try {
    # 1. API 호출
    $Uri = "https://$Server/policy/api/v1/infra/capacity/dashboard/usage"
    $Response = Invoke-RestMethod -Method Get -Uri $Uri -Headers $Headers -WebSession $SessionId

    # 2. 결과 저장용 배열 생성 (다른 플러그인과 일관성 유지)
    $ReportEntries = New-Object System.Collections.Generic.List[PSCustomObject]

    # 응답 데이터가 있는지 확인
    if ($null -ne $Response -and $null -ne $Response.capacity_usage) {
        
        foreach ($item in $Response.capacity_usage) {
            # 사용률 포맷팅 (소수점 2자리 보존)
            $UsageVal = [double]$item.current_usage_percentage
            $UsageString = "{0:N2} %" -f $UsageVal

            # Severity를 기반으로 한 Health 상태 (메인 HTML 리포트 배지 연동용)
            $Health = "OK"
            if ($item.severity -eq "WARNING") { $Health = "WARNING" }
            elseif ($item.severity -eq "CRITICAL" -or $item.severity -eq "ERROR") { $Health = "CRITICAL" }

            # 3. 표준 PSCustomObject 생성
            $obj = [PSCustomObject]@{
                Category    = $item.display_name
                Current     = $item.current_usage_count
                MaxLimit    = $item.max_supported_count
                Usage       = $UsageString
                Severity    = $item.severity
                Health      = $Health
            }
            $ReportEntries.Add($obj)
        }
    }

    # 4. 최종 결과 반환 (정렬 후 리스트 전체를 한 번에 반환)
    # 메인 실행기에서 이 return 값을 받아 변수에 저장하거나 HTML로 변환하게 됩니다.
    return $ReportEntries | Sort-Object { [double]($_.Usage -replace ' %','') } -Descending

} catch {
    Write-Warning "[$Server] Capacity Usage 플러그인 실행 중 오류: $($_.Exception.Message)"
    return $null
}