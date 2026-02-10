param([string]$Server, $SessionId, [string]$XsrfToken)

$null = [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
$null = [Net.SecurityProtocolType]::Tls12
$Headers = @{ "X-XSRF-TOKEN" = $XsrfToken; "Accept" = "application/json" }

try {
    # 1. Gateway Firewall Policy 목록 호출 (default 도메인 기준)
    $Uri = "https://$Server/policy/api/v1/infra/domains/default/gateway-policies"
    $Response = Invoke-RestMethod -Method Get -Uri $Uri -Headers $Headers -WebSession $SessionId

    $ReportEntries = New-Object System.Collections.Generic.List[PSCustomObject]

    if ($null -ne $Response.results) {
        foreach ($policy in $Response.results) {
            $PolicyName = $policy.display_name
            
            # 2. 각 Policy 하위의 Rules 호출
            $RuleUri = "https://$Server/policy/api/v1/infra/domains/default/gateway-policies/$($policy.id)/rules"
            $RuleRes = Invoke-RestMethod -Method Get -Uri $RuleUri -Headers $Headers -WebSession $SessionId

            foreach ($rule in $RuleRes.results) {
                $ReportEntries.Add([PSCustomObject]@{
                    Policy_Name = $PolicyName
                    Rule_Name   = $rule.display_name
                    Source      = $rule.source_groups -join ", "
                    Destination = $rule.destination_groups -join ", "
                    Services    = $rule.services -join ", "
                    Action      = $rule.action
                    Enabled     = $rule.disabled -eq $false
                    Health      = if ($rule.disabled) { "WARNING" } else { "OK" }
                })
            }
        }
    }
    return $ReportEntries
} catch { return $null }