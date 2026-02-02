param([string]$Server, $SessionId, [string]$XsrfToken, [string]$version)

$null = [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
$Headers = @{ 
    "Accept"        = "application/json"
    "X-Avi-Version" = $version
    "X-CSRFToken"   = $XsrfToken 
}

try {
    # 1. 클러스터 전역 버전 정보 조회 (/api/cluster/version)
    $VerUri = "https://$Server/api/cluster/version"
    $VerRes = Invoke-RestMethod -Method Get -Uri $VerUri -Headers $Headers -WebSession $SessionId -ErrorAction Stop
    $GlobalVersion = $VerRes.version

    # 2. 클러스터 설정 정보 조회 (/api/cluster - 노드 이름 매핑용)
    $ConfigUri = "https://$Server/api/cluster"
    $ConfigRes = Invoke-RestMethod -Method Get -Uri $ConfigUri -Headers $Headers -WebSession $SessionId -ErrorAction Stop
    
    # 3. 클러스터 런타임 정보 조회 (/api/cluster/runtime)
    $RuntimeUri = "https://$Server/api/cluster/runtime"
    $Response = Invoke-RestMethod -Method Get -Uri $RuntimeUri -Headers $Headers -WebSession $SessionId -ErrorAction Stop

    $ReportEntries = New-Object System.Collections.Generic.List[PSCustomObject]

    if ($null -ne $Response.node_states) {
        foreach ($node in $Response.node_states) {
            
            # 노드 이름 찾기 (런타임에는 IP만 있는 경우가 있어 Config에서 매핑)
            $NodeName = if ($node.name) { $node.name } 
                        else { ($ConfigRes.nodes | Where-Object { $_.ip.addr -eq $node.mgmt_ip.addr }).name }
            
            # [버전 추출 로직] 
            # 1. 노드 개별 버전 우선 확인 
            # 2. 없을 경우 클러스터 런타임 버전 확인 
            # 3. 마지막으로 전역 API 버전 확인
            $NodeVersion = if ($node.version) { $node.version } 
                           elseif ($Response.cluster_state.version) { $Response.cluster_state.version } 
                           else { $GlobalVersion }

            $ReportEntries.Add([PSCustomObject]@{
                ControllerName = if ($NodeName) { $NodeName } else { "Controller-Node" }
                IPAddress      = if ($node.mgmt_ip.addr) { $node.mgmt_ip.addr } else { "N/A" }
                Role           = $node.role
                Version        = $NodeVersion
                NodeStatus     = $node.state
                ClusterState   = $Response.cluster_state.state
                Health         = if ($node.state -eq "CLUSTER_NODE_UP" -and $Response.cluster_state.state -eq "CLUSTER_UP_HA_READY") { "OK" } else { "CRITICAL" }
            })
        }
    }
    return $ReportEntries
} catch {
    Write-Warning "Controller Cluster API Query Failed: $($_.Exception.Message)"
    return $null
}