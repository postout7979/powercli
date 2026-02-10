param([string]$Server, $SessionId, [string]$XsrfToken, [string]$version)

$null = [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
$Headers = @{ 
    "Accept"        = "application/json"
    "X-Avi-Version" = $version
    "X-CSRFToken"   = $XsrfToken 
}

try {
    $ReportEntries = New-Object System.Collections.Generic.List[PSCustomObject]
    
    # Virtual Service Inventory API 호출
    $Uri = "https://$Server/api/virtualservice-inventory"
    $Response = Invoke-RestMethod -Method Get -Uri $Uri -Headers $Headers -WebSession $SessionId -ErrorAction Stop

    foreach ($vs in $Response.results) {
        
        # [수정] 객체에서 실제 숫자 점수(health_score)만 추출
        $RawScore = $null
        if ($null -ne $vs.runtime.health_score.health_score) {
            $RawScore = $vs.runtime.health_score.health_score
        } elseif ($null -ne $vs.health_score.health_score) {
            $RawScore = $vs.health_score.health_score
        }

        # 소수점 제거 및 "N/A" 처리
        $FinalScore = if ($null -ne $RawScore) { [Math]::Round([double]$RawScore) } else { "N/A" }

        # 운영 상태 추출
        $OperState = if ($vs.runtime.oper_status.state) { $vs.runtime.oper_status.state } else { "UNKNOWN" }

        $ReportEntries.Add([PSCustomObject]@{
            VSName      = $vs.config.name
            VIP         = if ($vs.config.vip[0].ip_address.addr) { $vs.config.vip[0].ip_address.addr } else { "N/A" }
            Port        = $vs.config.services[0].port
            State       = $OperState
            # [수정] 이제 @{...} 형태가 아닌 '100'과 같은 숫자만 표시됩니다.
            HealthScore = $FinalScore
            Health      = if ($OperState -eq "OPER_UP" -and ($FinalScore -eq "N/A" -or $FinalScore -ge 80)) { "OK" } else { "CRITICAL" }
        })
    }
    return $ReportEntries
} catch {
    return $null
}