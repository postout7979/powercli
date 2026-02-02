param(
    [string]$Server,
    $SessionId, 
    [string]$XsrfToken
)

# 1. 보안 및 헤더 설정
$null = [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
$null = [Net.SecurityProtocolType]::Tls12

$Headers = @{ 
    "X-XSRF-TOKEN" = $XsrfToken
    "Accept"       = "application/json"
}

try {
    # 2. Edge Cluster 및 Transport Node 목록 수집
    $ClusterUri = "https://$Server/api/v1/edge-clusters"
    $ClusterRes = Invoke-RestMethod -Method Get -Uri $ClusterUri -Headers $Headers -WebSession $SessionId

    $NodeUri = "https://$Server/api/v1/transport-nodes?node_types=EdgeNode"
    $NodeRes = Invoke-RestMethod -Method Get -Uri $NodeUri -Headers $Headers -WebSession $SessionId

    $ReportEntries = New-Object System.Collections.Generic.List[PSCustomObject]

    if ($null -ne $ClusterRes.results) {
        foreach ($cluster in $ClusterRes.results) {
            $ClusterName = $cluster.display_name
            
            foreach ($member in $cluster.members) {
                $NodeId = $member.transport_node_id
                $NodeInfo = $NodeRes.results | Where-Object { $_.id -eq $NodeId }
                
                # 3. 폼팩터(FormFactor) 추출 로직 강화
                # VM 배포 형식과 물리 배포 형식을 모두 체크합니다.
                $FormFactor = "N/A"
                if ($null -ne $NodeInfo.node_deployment_info) {
                    if ($null -ne $NodeInfo.node_deployment_info.deployment_config.form_factor) {
                        # VM 기반 Edge의 일반적인 경로
                        $FormFactor = $NodeInfo.node_deployment_info.deployment_config.form_factor
                    } elseif ($null -ne $NodeInfo.node_deployment_info.resource_reservation.form_factor) {
                        # 일부 버전 및 특정 구성에서의 경로
                        $FormFactor = $NodeInfo.node_deployment_info.resource_reservation.form_factor
                    } elseif ($NodeInfo.node_deployment_info.resource_type -eq "VirtualMachineDeploymentConfig") {
                        # deployment_config 자체가 존재할 때
                        $FormFactor = $NodeInfo.node_deployment_info.form_factor
                    }
                }

                # 4. 관리 연결 및 상태 정보 수집
                $StatusUri = "https://$Server/api/v1/transport-nodes/$NodeId/status"
                $MgmtConn = "UNKNOWN"
                $NodeStatus = "UNKNOWN"
                try {
                    $StatusRes = Invoke-RestMethod -Method Get -Uri $StatusUri -Headers $Headers -WebSession $SessionId
                    $MgmtConn = $StatusRes.mgmt_connection_status
                    $NodeStatus = $StatusRes.status
                } catch { }

                # 5. 결과 개체 생성
                $ReportEntries.Add([PSCustomObject]@{
                    EdgeCluster     = $ClusterName
                    EdgeNode        = if ($NodeInfo) { $NodeInfo.display_name } else { $NodeId }
                    ManagementIP    = if ($NodeInfo) { $NodeInfo.node_deployment_info.ip_addresses -join ", " } else { "N/A" }
                    FormFactor      = $FormFactor.ToUpper()
                    MGMT_CONN       = $MgmtConn
                    NodeStatus      = $NodeStatus
                    Health          = if ($MgmtConn -eq "UP" -and $NodeStatus -eq "UP") { "OK" } else { "CRITICAL" }
                })
            }
        }
    }

    return $ReportEntries | Sort-Object EdgeCluster, EdgeNode

} catch {
    Write-Warning "[$Server] Edge Inventory 수집 중 오류: $($_.Exception.Message)"
    return $null
}