param([string]$Server, $SessionId, [string]$XsrfToken)

$null = [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
$null = [Net.SecurityProtocolType]::Tls12
$Headers = @{ "X-XSRF-TOKEN" = $XsrfToken; "Accept" = "application/json" }

try {
    # 1. Edge Cluster 이름 매핑 준비
    $ClusterMap = @{}
    $ClusterRes = Invoke-RestMethod -Method Get -Uri "https://$Server/policy/api/v1/infra/sites/default/enforcement-points/default/edge-clusters" -Headers $Headers -WebSession $SessionId
    foreach ($c in $ClusterRes.results) { $ClusterMap[$c.id] = $c.display_name }

    $ReportEntries = New-Object System.Collections.Generic.List[PSCustomObject]

    # 2. Tier-0/1 게이트웨이 수집
    $T0Res = Invoke-RestMethod -Method Get -Uri "https://$Server/policy/api/v1/infra/tier-0s" -Headers $Headers -WebSession $SessionId
    $T1Res = Invoke-RestMethod -Method Get -Uri "https://$Server/policy/api/v1/infra/tier-1s" -Headers $Headers -WebSession $SessionId
    $Gateways = @($T0Res.results) + @($T1Res.results)

    foreach ($gw in $Gateways) {
        $GwId = $gw.id
        $Tier = if ($gw.resource_type -eq "Tier0") { "Tier-0" } else { "Tier-1" }
        
        # 3. Edge Cluster 이름 추출 (Locale Services)
        $EClusterName = "Distributed"
        $LocUri = "https://$Server/policy/api/v1/infra/$($gw.resource_type -replace 'Tier','tier-')s/$GwId/locale-services"
        $LocRes = Invoke-RestMethod -Method Get -Uri $LocUri -Headers $Headers -WebSession $SessionId
        if ($LocRes.results.Count -gt 0 -and $null -ne $LocRes.results[0].edge_cluster_path) {
            $Uuid = $LocRes.results[0].edge_cluster_path.Split('/')[-1]
            $EClusterName = if ($ClusterMap.ContainsKey($Uuid)) { $ClusterMap[$Uuid] } else { $Uuid }
        }

        # 4. 연결 정보 (Tier-1의 경우 연결된 T0 표시)
        $ConnInfo = "External Uplink"
        if ($Tier -eq "Tier-1") {
            $ConnInfo = if ($gw.tier0_path) { "Linked to: " + $gw.tier0_path.Split('/')[-1] } else { "Standalone" }
        }

        # 5. 결과 개체 생성 (핵심 5개 컬럼)
        $ReportEntries.Add([PSCustomObject]@{
            Tier         = $Tier
            GatewayName  = $gw.display_name
            EdgeCluster  = $EClusterName
            HA_Mode      = if ($gw.ha_mode) { $gw.ha_mode } else { "DISTRIBUTED" }
            Connectivity = $ConnInfo
        })
    }

    return $ReportEntries | Sort-Object Tier, GatewayName
} catch { return $null }