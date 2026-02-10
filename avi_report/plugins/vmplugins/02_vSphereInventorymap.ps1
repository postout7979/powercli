param($Server, $SessionId)

# ---------------------------------------------------------------------------
# [INFO]
# ESXi Host의 토폴로지 위치(Datacenter > Cluster)와 관리 IP(vmk0)를 점검합니다.
# 최적화: 루프 내 API 반복 호출을 방지하기 위해 상위 객체(Parent) 정보를 캐싱합니다.
# ---------------------------------------------------------------------------

try {
    # 1. 호스트 정보 조회 (Parent, Product, Vnic, Runtime)
    #    Runtime.ConnectionState를 추가하여 연결 상태 확인
    $HostViews = Get-View -ViewType HostSystem -Property Name, Parent, Config.Product, Config.Network.Vnic, Runtime.ConnectionState -ErrorAction Stop

    # 상위 객체(Cluster/Datacenter) 조회 결과를 저장할 캐시 (API 호출 최소화)
    $ViewCache = @{}
    
    $Data = foreach ($hv in $HostViews) {
        
        # 2. 클러스터 및 데이터센터 찾기 (계층 구조 추적)
        $ParentId = $hv.Parent.Value
        
        # 캐시에 부모 정보가 없으면 조회 후 저장
        if (-not $ViewCache.ContainsKey($ParentId)) {
            $ParentView = Get-View -Id $hv.Parent -Property Name, Parent -ErrorAction SilentlyContinue
            
            # 클러스터 여부 확인 (Standalone 호스트는 ComputeResource임)
            $ClusterName = if ($ParentView.MoRef.Type -eq "ClusterComputeResource") { $ParentView.Name } else { "Standalone" }
            
            # 데이터센터 찾기 (재귀적으로 부모를 타고 올라감)
            $CurrentObj = $ParentView
            $DatacenterName = "Unknown"
            
            # 최대 10단계 상위까지만 탐색 (무한 루프 방지)
            for ($i=0; $i -lt 10; $i++) {
                if ($null -eq $CurrentObj -or $null -eq $CurrentObj.Parent) { break }
                
                # 부모 객체 로드
                $CurrentObj = Get-View -Id $CurrentObj.Parent -Property Name, Parent -ErrorAction SilentlyContinue
                
                if ($CurrentObj.MoRef.Type -eq "Datacenter") {
                    $DatacenterName = $CurrentObj.Name
                    break
                }
            }
            
            # 결과 캐싱 (Hashtable에 저장)
            $ViewCache[$ParentId] = @{
                Cluster = $ClusterName
                Datacenter = $DatacenterName
            }
        }
        
        # 캐시된 정보 사용
        $TopoInfo = $ViewCache[$ParentId]

        # 3. vmk0 IP 추출 (IPv4만 필터링)
        $vmk0 = $hv.Config.Network.Vnic | Where-Object { $_.Device -eq "vmk0" }
        $vmk0_IP = "N/A"
        if ($vmk0) {
            # IPv4 주소가 여러 개일 수 있으므로 첫 번째 것 선택
            $vmk0_IP = $vmk0.Spec.Ip.IpAddress
        }

        # 4. 상태 및 버전 정보 정리
        $Status = if ($hv.Runtime.ConnectionState -eq "Connected") { "OK" } else { "WARN" }
        $VersionStr = "$($hv.Config.Product.Version) (Build $($hv.Config.Product.Build))"

        [PSCustomObject]@{
            Datacenter  = $TopoInfo.Datacenter
            Cluster     = $TopoInfo.Cluster
            HostName    = $hv.Name
            vmk0_IP     = $vmk0_IP
            Version     = $VersionStr
            Status      = $Status
        }
    }
    
    # 데이터센터 > 클러스터 > 호스트 순 정렬
    return $Data | Sort-Object Datacenter, Cluster, HostName

} catch {
    Write-Host " [!] Error querying Host Topology: $($_.Exception.Message)" -ForegroundColor Red
    return $null
}