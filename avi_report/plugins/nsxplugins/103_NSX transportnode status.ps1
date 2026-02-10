param([string]$Server, $SessionId, [string]$XsrfToken)

# SSL 및 TLS 보안 설정
$null = [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
$null = [Net.SecurityProtocolType]::Tls12
$Headers = @{ "X-XSRF-TOKEN" = $XsrfToken; "Accept" = "application/json" }

try {
    # 1. 매핑 데이터 준비 (vSphere Cluster & Edge Cluster)
    $vSphereClusterMap = @{}
    $EdgeClusterMap = @{}
    $UpgradeVersionMap = @{}

    # vSphere Cluster 매핑
    $CompRes = Invoke-RestMethod -Method Get -Uri "https://$Server/api/v1/fabric/compute-collections" -Headers $Headers -WebSession $SessionId
    foreach ($c in $CompRes.results) { $vSphereClusterMap[$c.external_id] = $c.display_name }

    # Edge Cluster 매핑
    $EdgeClusRes = Invoke-RestMethod -Method Get -Uri "https://$Server/api/v1/edge-clusters" -Headers $Headers -WebSession $SessionId
    foreach ($ec in $EdgeClusRes.results) { $EdgeClusterMap[$ec.id] = $ec.display_name }

    # 2. Upgrade Nodes 정보 수집 (버전 정보 최우선 순위)
    try {
        $UpgradeRes = Invoke-RestMethod -Method Get -Uri "https://$Server/api/v1/upgrade/nodes" -Headers $Headers -WebSession $SessionId
        foreach ($un in $UpgradeRes.results) {
            # ID를 키로 하여 component_version 저장
            $UpgradeVersionMap[$un.id] = $un.component_version
        }
    } catch {
        Write-Warning "Upgrade Nodes API 호출 실패"
    }

    # 3. Transport Node 목록 조회
    $NodeRes = Invoke-RestMethod -Method Get -Uri "https://$Server/api/v1/transport-nodes" -Headers $Headers -WebSession $SessionId
    $ReportEntries = New-Object System.Collections.Generic.List[PSCustomObject]

    if ($null -eq $NodeRes -or $null -eq $NodeRes.results) {
        return [PSCustomObject]@{ NodeName="N/A"; NodeType="N/A"; Cluster="N/A"; version="No Data"; AgentStatus="UNKNOWN"; Health="CRITICAL" }
    }

    foreach ($tn in $NodeRes.results) {
        $TnId = $tn.id
        $NodeType = $tn.node_deployment_info.resource_type
        
        # 4. 버전 결정 로직
        # 우선순위: 1. Upgrade API 버전 -> 2. Status API 버전 -> 3. Deployment Info 버전
        $LiveVersion = "N/A"
        if ($UpgradeVersionMap.ContainsKey($TnId)) {
            $LiveVersion = $UpgradeVersionMap[$TnId]
        }

        $AgentStatus = "UNKNOWN"
        try {
            $StatusRes = Invoke-RestMethod -Method Get -Uri "https://$Server/api/v1/transport-nodes/$TnId/status" -Headers $Headers -WebSession $SessionId
            $AgentStatus = $StatusRes.mgmt_connection_status
            
            # Upgrade API에 데이터가 없을 경우에만 Status API 참조
            if ($LiveVersion -eq "N/A") {
                $LiveVersion = if ($StatusRes.software_version) { $StatusRes.software_version } else { $tn.node_deployment_info.os_version }
            }
        } catch {}

        # 5. 통합 Cluster 이름 결정 로직
        $FinalClusterName = "Manual"
        if ($NodeType -eq "HostNode") {
            $CompId = $tn.node_deployment_info.compute_id
            if ($CompId -and $vSphereClusterMap.ContainsKey($CompId)) { $FinalClusterName = $vSphereClusterMap[$CompId] }
        } 
        elseif ($NodeType -eq "EdgeNode") {
            $FoundEdgeCluster = $EdgeClusRes.results | Where-Object { $_.members.transport_node_id -contains $TnId } | Select-Object -First 1
            $FinalClusterName = if ($FoundEdgeCluster) { $FoundEdgeCluster.display_name } else { "Standalone Edge" }
        }

        # 6. 결과 생성
        $ReportEntries.Add([PSCustomObject]@{
            NodeName    = $tn.display_name
            NodeType    = $NodeType
            Cluster     = $FinalClusterName
            version     = $LiveVersion
            AgentStatus = $AgentStatus
            Health      = if ($AgentStatus -eq "UP") { "OK" } else { "CRITICAL" }
        })
    }

    return $ReportEntries | Sort-Object Cluster, NodeName

} catch {
    # 예외 발생 시 오류 객체 반환
    return [PSCustomObject]@{
        NodeName    = "Error"
        NodeType    = "Fatal"
        Cluster     = "None"
        version     = "Error"
        AgentStatus = "ERROR"
        Health      = "CRITICAL"
        Message     = $_.Exception.Message
    }
}