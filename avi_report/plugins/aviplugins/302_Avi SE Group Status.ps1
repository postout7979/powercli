param([string]$Server, $SessionId, [string]$XsrfToken, [string]$version)

$null = [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
$Headers = @{ 
    "Accept"        = "application/json"
    "X-Avi-Version" = $version
    "X-CSRFToken"   = $XsrfToken 
}

try {
    $ReportEntries = New-Object System.Collections.Generic.List[PSCustomObject]
    
    # 1. 모든 Service Engine 인벤토리 조회 (그룹 매핑용)
    $SeUri = "https://$Server/api/serviceengine-inventory?include_name=true"
    $SeRes = Invoke-RestMethod -Method Get -Uri $SeUri -Headers $Headers -WebSession $SessionId -ErrorAction Stop
    
    # SE 그룹 ID를 Key로 하여 소속된 SE 이름들을 저장할 해시테이블 생성
    $SeMapping = @{}
    foreach ($se in $SeRes.results) {
        $GroupId = $se.config.se_group_ref.Split("/")[-1].Split("#")[0] # UUID 추출
        if (-not $SeMapping.ContainsKey($GroupId)) {
            $SeMapping[$GroupId] = New-Object System.Collections.Generic.List[string]
        }
        $SeMapping[$GroupId].Add($se.config.name)
    }

    # 2. SE 그룹 리스트 조회
    $SegUri = "https://$Server/api/serviceenginegroup"
    $SegRes = Invoke-RestMethod -Method Get -Uri $SegUri -Headers $Headers -WebSession $SessionId -ErrorAction Stop

    foreach ($seg in $SegRes.results) {
        $GroupId = $seg.uuid
        
        # 매핑된 해시테이블에서 해당 그룹의 SE 이름들을 가져옴
        $SeNames = if ($SeMapping.ContainsKey($GroupId)) {
            $SeMapping[$GroupId] -join ", "
        } else {
            "No SE Assigned"
        }

        $ReportEntries.Add([PSCustomObject]@{
            SEGroupName      = $seg.name
            MaxSEs           = $seg.max_vs_per_se
            # [수정] 매핑을 통해 확인된 실제 SE 이름 목록
            CurrentSE_Names  = $SeNames
            HighAvailability = $seg.ha_mode
            Status           = "ACTIVE"
            Health           = if ($SeNames -eq "No SE Assigned") { "WARNING" } else { "OK" }
        })
    }
    return $ReportEntries
} catch {
    return $null
}