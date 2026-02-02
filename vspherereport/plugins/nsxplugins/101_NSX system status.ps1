param(
    [string]$Server,
    $SessionId, 
    [string]$XsrfToken
)

# 1. SSL 인증서 무시 (전역 설정 방식)
# -SkipCertificateCheck 옵션 없이도 모든 웹 요청에서 SSL 오류를 무시합니다.
$null = [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
$null = [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# 2. 헤더 구성 (Cookie 제외)
# WebSession 옵션을 사용하므로 JSESSIONID는 자동으로 관리됩니다.
$Headers = @{ 
    "X-XSRF-TOKEN" = $XsrfToken
    "Accept"       = "application/json"
}

try {

    $NodeUri    = "https://$Server/api/v1/node"
    $StatusUri  = "https://$Server/api/v1/node/status"
    $ServiceUri = "https://$Server/api/v1/node/services/manager/status"
	
    $NodeInfo    = Invoke-RestMethod -Uri $NodeUri -Headers $Headers -WebSession $SessionId
    $NodeStatus  = Invoke-RestMethod -Uri $StatusUri -Headers $Headers -WebSession $SessionId
    $Services 	 = Invoke-RestMethod -Uri $ServiceUri -Headers $Headers -WebSession $SessionId

    # 6. 결과 반환
    return [PSCustomObject]@{
        NodeName      = $Server
        ServiceStatus = "$($Services.runtime_state)"
        Version        = $NodeInfo.node_version
        Uptime        = "$([Math]::Round($NodeStatus.uptime / 1000 / 3600 / 24, 1)) Days"
    }

} catch {
    Write-Warning "System Health 체크 중 오류 발생: $($_.Exception.Message)"
    return $null
}