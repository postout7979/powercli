param([string]$Server, $SessionId, [string]$XsrfToken)

$null = [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
$null = [Net.SecurityProtocolType]::Tls12
$Headers = @{ "X-XSRF-TOKEN" = $XsrfToken; "Accept" = "application/json" }

try {
    # 1. Transport Nodes 수량 집계 (Host vs Edge)
    $TnUri = "https://$Server/api/v1/transport-nodes"
    $TnRes = Invoke-RestMethod -Method Get -Uri $TnUri -Headers $Headers -WebSession $SessionId
    
    $HostCount = ($TnRes.results | Where-Object { $_.node_deployment_info.resource_type -eq "HostNode" -or $_.node_deployment_info -match "Host" }).Count
    if ($null -eq $HostCount) { $HostCount = 0 }
    
    $EdgeCount = ($TnRes.results | Where-Object { $_.node_deployment_info.resource_type -eq "EdgeNode" -or $_.node_deployment_info -match "Edge" }).Count
    if ($null -eq $EdgeCount) { $EdgeCount = 0 }

    # 2. Tier-0 Gateways 수량 집계
    $T0Uri = "https://$Server/policy/api/v1/infra/tier-0s"
    $T0Res = Invoke-RestMethod -Method Get -Uri $T0Uri -Headers $Headers -WebSession $SessionId
    $T0Count = if ($T0Res.results) { $T0Res.results.Count } else { 0 }

    # 3. Tier-1 Gateways 수량 집계
    $T1Uri = "https://$Server/policy/api/v1/infra/tier-1s"
    $T1Res = Invoke-RestMethod -Method Get -Uri $T1Uri -Headers $Headers -WebSession $SessionId
    $T1Count = if ($T1Res.results) { $T1Res.results.Count } else { 0 }

    # 메인 스크립트 대시보드에서 사용할 수 있도록 단일 개체로 반환
    return [PSCustomObject]@{
        Host_Nodes = $HostCount
        Edge_Nodes = $EdgeCount
        Tier_0     = $T0Count
        Tier_1     = $T1Count
    }
} catch {
    return $null
}