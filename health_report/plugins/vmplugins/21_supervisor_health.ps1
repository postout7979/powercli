param($Server, $SessionId)
$null = [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}

$Headers = @{
    "vmware-api-session-id" = $SessionId
    "Accept" = "application/json"
}

try {
    # 1. 일반 클러스터 이름 매핑용 사전 데이터 수집
    # namespace-management API는 cluster-123 같은 ID만 주므로 이름을 찾기 위해 필요합니다.
    $ClusterMapUri = "https://$Server/api/vcenter/cluster"
    $ClusterMapRes = Invoke-RestMethod -Method Get -Uri $ClusterMapUri -Headers $Headers
    $ClusterNameLookup = @{}
    foreach ($cl in $ClusterMapRes) {
        $ClusterNameLookup[$cl.cluster] = $cl.name
    }

    # 2. Supervisor Cluster 목록 수집
    $Uri = "https://$Server/api/vcenter/namespace-management/clusters"
    $Response = Invoke-RestMethod -Method Get -Uri $Uri -Headers $Headers -ErrorAction Stop
    
    # API 응답이 .value에 들어있는지 확인 (Invoke-RestMethod 특성에 따라 다름)
    $Clusters = if ($null -ne $Response.value) { $Response.value } else { $Response }

    if ($null -eq $Clusters -or $Clusters.Count -eq 0) {
        return $null
    }

    $Results = foreach ($c in $Clusters) {
        # 기본 상태값 추출
        $ConfigStatus = if ($c.config_status) { $c.config_status } else { "UNKNOWN" }
        $K8sStatus    = if ($c.kubernetes_status) { $c.kubernetes_status } else { "N/A" }
        
        # 실제 vSphere 클러스터 이름 매핑
        $FriendlyName = if ($ClusterNameLookup.ContainsKey($c.cluster)) { $ClusterNameLookup[$c.cluster] } else { $c.cluster }

        # API Endpoint 정보 추출 (Load Balancer IP 등)
        $ApiEndpoint = "Not Assigned"
        if ($null -ne $c.api_endpoints -and $c.api_endpoints.Count -gt 0) {
            $ApiEndpoint = $c.api_endpoints[0]
        }

        [PSCustomObject]@{
            ClusterName      = $FriendlyName     # ESXi 클러스터 이름
            API_Server       = $ApiEndpoint      # K8s API 엔드포인트 주소
            ClusterID        = $c.cluster        # MoRef ID
            ConfigStatus     = $ConfigStatus     # Tanzu 구성 상태
            K8sStatus        = $K8sStatus        # Kubernetes 동작 상태
            Status           = if ($ConfigStatus -eq "RUNNING") { "ok" } else { "critical" }
        }
    }
    return $Results | Sort-Object ClusterName

} catch {
    # 404 에러 등은 Workload Management가 아예 활성화되지 않은 경우임
    return $null
}