param([string]$Server, $SessionId, [string]$XsrfToken, [string]$version)

$null = [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
$Headers = @{ 
    "Accept"        = "application/json"
    "X-Avi-Version" = $version
    "X-CSRFToken"   = $XsrfToken 
}

try {
    # 1. SE Group 이름 매핑 테이블 생성
    $SegUri = "https://$Server/api/serviceenginegroup"
    $SegRes = Invoke-RestMethod -Method Get -Uri $SegUri -Headers $Headers -WebSession $SessionId -ErrorAction Stop
    
    # UUID를 Key로, Name을 Value로 하는 해시테이블 생성
    $GroupMap = @{}
    foreach ($group in $SegRes.results) {
        $GroupMap[$group.uuid] = $group.name
    }

    $ReportEntries = New-Object System.Collections.Generic.List[PSCustomObject]
    
    # 2. Service Engine Inventory API 호출
    $Uri = "https://$Server/api/serviceengine-inventory"
    $Response = Invoke-RestMethod -Method Get -Uri $Uri -Headers $Headers -WebSession $SessionId -ErrorAction Stop

    if ($null -ne $Response.results) {
        foreach ($se in $Response.results) {
            
            $SeName = $se.config.name
            $SeIp   = if ($se.config.mgmt_ip.addr) { $se.config.mgmt_ip.addr } else { "N/A" }
            $OperState = if ($se.runtime.oper_status.state) { $se.runtime.oper_status.state } else { "UNKNOWN" }
            $RawScore = $se.runtime.health_score.health_score
            $FinalScore = if ($null -ne $RawScore) { [Math]::Round([double]$RawScore) } else { "N/A" }

            # --- SE Group UUID 추출 및 매핑 테이블에서 이름 찾기 ---
            $SeGroup = "Unknown-Group"
            if ($se.config.se_group_ref) {
                # 경로에서 UUID만 추출 (예: .../serviceenginegroup/segroup-abcd-1234#Name)
                # #이 있으면 앞부분만 취하고, 마지막 / 뒤의 값을 가져옴
                $GroupUuid = $se.config.se_group_ref.Split("#")[0].Split("/")[-1]
                
                if ($GroupMap.ContainsKey($GroupUuid)) {
                    $SeGroup = $GroupMap[$GroupUuid]
                } else {
                    # 매핑 테이블에 없는 경우(직접 이름이 붙어있는 경우 대비)
                    $SeGroup = $se.config.se_group_ref.Split("#")[-1]
                }
            }

            $ReportEntries.Add([PSCustomObject]@{
                SEName       = $SeName
                ManagementIP = $SeIp
                SEGroup      = $SeGroup
                State        = $OperState
                HealthScore  = $FinalScore
                Health       = if ($OperState -eq "OPER_UP" -and ($FinalScore -eq "N/A" -or $FinalScore -ge 80)) { "OK" } else { "CRITICAL" }
            })
        }
    }
    
    return $ReportEntries | Sort-Object SEName
} catch {
    Write-Error $_.Exception.Message
    return $null
}