param([string]$Server, $SessionId, [string]$XsrfToken, [string]$version)

$null = [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
$Headers = @{ 
    "Accept"        = "application/json"
    "X-Avi-Version" = $version
    "X-CSRFToken"   = $XsrfToken 
}

try {
    $ReportEntries = New-Object System.Collections.Generic.List[PSCustomObject]
    
    # GSLB Service Inventory API 호출 (설정과 런타임 상태를 한 번에 가져옴)
    $Uri = "https://$Server/api/gslbservice-inventory"
    $Response = Invoke-RestMethod -Method Get -Uri $Uri -Headers $Headers -WebSession $SessionId -ErrorAction Stop

    if ($null -ne $Response.results) {
        foreach ($gs in $Response.results) {
            
            # GSLB 서비스 기본 정보
            $GsName = $gs.config.name
            $Fqdn   = $gs.config.domain_names -join ", "
            
            # 서비스 전체 운영 상태
            $GsStatus = if ($gs.runtime.oper_status.state) { $gs.runtime.oper_status.state } else { "UNKNOWN" }

            # 각 그룹(Pool) 내의 멤버(Site/VS) 상세 정보 추출
            foreach ($group in $gs.config.groups) {
                $GroupName = $group.name
                $Priority  = $group.priority

                foreach ($member in $group.members) {
                    # 멤버 사이트 이름 및 IP
                    $SiteName = $member.cluster_uuid # UUID가 이름으로 매핑되지 않은 경우
                    $VsIp     = if ($member.ip.addr) { $member.ip.addr } else { "N/A" }
                    
                    # 해당 멤버의 실시간 런타임 상태 확인 (inventory 구조 활용)
                    # runtime.group_state 내에서 현재 멤버의 uuid와 일치하는 상태를 찾습니다.
                    $MemberState = "UNKNOWN"
                    if ($null -ne $gs.runtime.groups) {
                        $matchGroup = $gs.runtime.groups | Where-Object { $_.name -eq $GroupName }
                        $matchMember = $matchGroup.members | Where-Object { $_.cluster_uuid -eq $member.cluster_uuid }
                        if ($matchMember) { $MemberState = $matchMember.oper_status.state }
                    }

                    $ReportEntries.Add([PSCustomObject]@{
                        GslbService = $GsName
                        FQDN        = $Fqdn
                        Group       = $GroupName
                        Priority    = $Priority
                        SiteName    = $SiteName
                        MemberIP    = $VsIp
                        Status      = $MemberState
                        Health      = if ($MemberState -eq "OPER_UP") { "OK" } else { "CRITICAL" }
                    })
                }
            }
        }
    }
    
    return $ReportEntries | Sort-Object GslbService, Group
} catch {
    Write-Warning "GSLB Service API 호출 실패: $($_.Exception.Message)"
    return $null
}