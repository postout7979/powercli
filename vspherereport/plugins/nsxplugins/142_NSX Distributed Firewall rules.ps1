param([string]$Server, $SessionId, [string]$XsrfToken)

$null = [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
$null = [Net.SecurityProtocolType]::Tls12
$Headers = @{ "X-XSRF-TOKEN" = $XsrfToken; "Accept" = "application/json" }

try {
    # 1. DFW Security Policy 목록 호출
    $Uri = "https://$Server/policy/api/v1/infra/domains/default/security-policies"
    $Response = Invoke-RestMethod -Method Get -Uri $Uri -Headers $Headers -WebSession $SessionId

    $ReportEntries = New-Object System.Collections.Generic.List[PSCustomObject]

    if ($null -ne $Response.results) {
        foreach ($policy in $Response.results) {
            $PolicyName = $policy.display_name
            
            # 2. 각 Policy 하위의 Rules 추출 (DFW는 Rule이 Policy 객체 안에 포함되어 오는 경우가 많음)
            # 만약 포함되어 있지 않다면 하위 API를 호출하도록 설계
            $RuleUri = "https://$Server/policy/api/v1/infra/domains/default/security-policies/$($policy.id)/rules"
            $RuleRes = Invoke-RestMethod -Method Get -Uri $RuleUri -Headers $Headers -WebSession $SessionId

            foreach ($rule in $RuleRes.results) {
                $ReportEntries.Add([PSCustomObject]@{
                    Section_Name = $PolicyName
                    Rule_Name    = $rule.display_name
                    Source       = $rule.source_groups -join ", "
                    Destination  = $rule.destination_groups -join ", "
                    Services     = $rule.services -join ", "
                    Action       = $rule.action
                    Logged       = $rule.logged
                    Health       = if ($rule.action -eq "DROP" -or $rule.action -eq "REJECT") { "WARNING" } else { "OK" }
                })
            }
        }
    }
    return $ReportEntries
} catch { return $null }