param([string]$Server, $SessionId, [string]$XsrfToken)

$null = [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
$null = [Net.SecurityProtocolType]::Tls12
$Headers = @{ "X-XSRF-TOKEN" = $XsrfToken; "Accept" = "application/json" }

try {
    $ReportEntries = New-Object System.Collections.Generic.List[PSCustomObject]

    # 1. License Usage API 호출
    $Uri = "https://$Server/api/v1/licenses/licenses-usage"
    try {
        $LicenseRes = Invoke-RestMethod -Method Get -Uri $Uri -Headers $Headers -WebSession $SessionId -ErrorAction Stop
    } catch {
        $ReportEntries.Add([PSCustomObject]@{
            Feature      = "<span style='color:red;'>라이선스 조회 실패</span>"
            CapacityType = "-"
            UsageCount   = "에러: $($_.Exception.Message)"
            Health       = "CRITICAL"
        })
        return $ReportEntries
    }

    # 2. 결과 파싱 및 필터링
    if ($null -ne $LicenseRes.feature_usage_info) {
        foreach ($fInfo in $LicenseRes.feature_usage_info) {
            $FeatureName = $fInfo.feature
            
            if ($null -ne $fInfo.capacity_usage) {
                foreach ($usage in $fInfo.capacity_usage) {
                    # [핵심 수정] usage_count가 0보다 큰 경우에만 리스트에 추가
                    if ($usage.usage_count -gt 0) {
                        $ReportEntries.Add([PSCustomObject]@{
                            Feature      = $FeatureName
                            CapacityType = $usage.capacity_type
                            UsageCount   = $usage.usage_count
                            Health       = "OK"
                        })
                    }
                }
            }
        }
    }

    # 3. 빈 값 대응: 만약 모든 count가 0이라서 표시할 데이터가 없는 경우
    if ($ReportEntries.Count -eq 0) {
        $ReportEntries.Add([PSCustomObject]@{
            Feature      = "No Active Usage"
            CapacityType = "-"
            UsageCount   = "모든 항목의 사용량이 0입니다."
            Health       = "OK"
        })
    }

    return $ReportEntries
} catch {
    return $null
}