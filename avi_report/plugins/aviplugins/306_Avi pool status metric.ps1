param([string]$Server, $SessionId, [string]$XsrfToken, [string]$version)

$null = [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
$Headers = @{ 
    "Accept"        = "application/json"
    "X-Avi-Version" = $version
    "X-CSRFToken"   = $XsrfToken 
}

try {
    $ReportEntries = New-Object System.Collections.Generic.List[PSCustomObject]
    
    # 1. Pool 리스트(Config) 조회
    $PoolUri = "https://$Server/api/pool"
    $PoolRes = Invoke-RestMethod -Method Get -Uri $PoolUri -Headers $Headers -WebSession $SessionId -ErrorAction Stop

    foreach ($p in $PoolRes.results) {
        $PoolUuid = $p.uuid
        $PoolName = $p.name
        
        # [로직 1] Server Ratio 계산 (사용자 지정 기준)
        # Total: servers 배열의 전체 항목 수
        # Up: 각 항목 중 vm_ref 필드가 존재하는 항목 수
        $TotalServers = 0
        $UpServers = 0
        
        if ($null -ne $p.servers) {
            $TotalServers = $p.servers.Count
            foreach ($srv in $p.servers) {
                # vm_ref가 존재하면 정상 할당/가동 서버로 간주
                if ($null -ne $srv.vm_ref) {
                    $UpServers++
                }
            }
        }

        # [로직 2] LB Algorithm 추출
        $LbAlgo = if ($p.lb_algorithm) { $p.lb_algorithm } else { "N/A" }

        # [로직 3] 운영 상태 조회 (런타임 API)
        $OperState = "UNKNOWN"
        try {
            $RuntimeUri = "https://$Server/api/pool/$PoolUuid/runtime"
            $Rt = Invoke-RestMethod -Method Get -Uri $RuntimeUri -Headers $Headers -WebSession $SessionId
            $OperState = if ($Rt.oper_status.state) { $Rt.oper_status.state } else { "UNKNOWN" }
        } catch { }

        # 리포트 데이터 구성 (성능 지표 제외)
        $ReportEntries.Add([PSCustomObject]@{
            Pool_Name       = $PoolName
            Status          = $OperState
            LB_Algorithm    = $LbAlgo
            Server_Ratio    = "$($UpServers) / $($TotalServers)"
            Health          = if ($OperState -eq "OPER_UP" -and $UpServers -gt 0) { "OK" } else { "CRITICAL" }
        })
    }
    return $ReportEntries | Sort-Object Pool_Name
} catch {
    return $null
}