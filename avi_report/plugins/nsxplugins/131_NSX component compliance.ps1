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
    # 1. Compliance Status API 호출
    $Uri = "https://$Server/policy/api/v1/compliance/status"
    $Response = Invoke-RestMethod -Method Get -Uri $Uri -Headers $Headers -WebSession $SessionId

    # [방어적 코드] 응답이 없거나 필드가 없는 경우 에러 방지
    if ($null -eq $Response) {
        return @()
    }

    $Results = New-Object System.Collections.Generic.List[PSCustomObject]

    # 2. 비준수(Non-Compliant) 항목이 있는 경우
    if ($null -ne $Response.non_compliant_configs -and $Response.non_compliant_configs.Count -gt 0) {
        foreach ($issue in $Response.non_compliant_configs) {
            $Results.Add([PSCustomObject]@{
                Category    = $issue.reported_by.target_type
                TargetName  = $issue.reported_by.target_display_name
                Description = $issue.description
                Code        = $issue.non_compliance_code
                Status      = "NON_COMPLIANT"
                Health      = "CRITICAL"
            })
        }
    } 
    # 3. 모든 설정이 준수 상태인 경우
    else {
        $Results.Add([PSCustomObject]@{
            Category    = "System Global"
            TargetName  = "All Configs"
            Description = "No non-compliance issues found."
            Code        = "-"
            Status      = "COMPLIANT"
            Health      = "OK"
        })
    }

    return $Results

} catch {
    Write-Warning "Compliance Status 조회 중 에러 발생: $($_.Exception.Message)"
    return $null
}