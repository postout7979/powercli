param($Server, $SessionId)

# ---------------------------------------------------------------------------
# [INFO]
# vCenter 인벤토리 객체(Datacenter, Cluster, Host, VM)의 총 개수를 요약합니다.
# 최적화: Get-VM 대신 Get-View를 사용하여 수만 대의 VM 환경에서도 즉시 결과를 반환합니다.
# 추가기능: 단순히 전체 개수뿐만 아니라 '켜진 VM', '연결된 Host' 수를 같이 표시합니다.
# ---------------------------------------------------------------------------

try {
    # 1. Datacenter 개수 조회
    $DcViews = Get-View -ViewType Datacenter -Property Name
    $DcCount = if ($DcViews) { $DcViews.Count } else { 0 }

    # 2. Cluster 개수 조회
    $ClViews = Get-View -ViewType ClusterComputeResource -Property Name
    $ClCount = if ($ClViews) { $ClViews.Count } else { 0 }

    # 3. Host 개수 및 연결 상태 조회 (전체 / 연결됨)
    $HostViews = Get-View -ViewType HostSystem -Property Runtime.ConnectionState
    $HostTotal = if ($HostViews) { $HostViews.Count } else { 0 }
    
    if ($HostTotal -gt 0) {
        $HostConn  = ($HostViews | Where-Object { $_.Runtime.ConnectionState -eq "Connected" }).Count
        $HostStr   = "$HostTotal (Connected: $HostConn)"
    } else {
        $HostStr   = "0"
    }

    # 4. VM 개수 및 전원 상태 조회 (전체 / 켜짐)
    #    가장 무거운 작업이므로 Get-View가 필수적임
    $VmViews = Get-View -ViewType VirtualMachine -Property Runtime.PowerState
    $VmTotal = if ($VmViews) { $VmViews.Count } else { 0 }
    
    if ($VmTotal -gt 0) {
        $VmOn    = ($VmViews | Where-Object { $_.Runtime.PowerState -eq "poweredOn" }).Count
        $VmStr   = "$VmTotal (Powered On: $VmOn)"
    } else {
        $VmStr   = "0"
    }

    # 5. 결과 반환
    #    리포트의 가장 첫 섹션에 "Inventory Summary"로 표시하기 적합함
    return [PSCustomObject]@{
        "Total Datacenters" = $DcCount
        "Total Clusters"    = $ClCount
        "Total Hosts"       = $HostStr
        "Total VMs"         = $VmStr
    }

} catch {
    Write-Host " [!] Error querying Inventory Summary: $($_.Exception.Message)" -ForegroundColor Red
    return $null
}