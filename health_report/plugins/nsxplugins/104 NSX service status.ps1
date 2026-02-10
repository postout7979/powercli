param(
    [string]$Server,
    $SessionId, 
    [string]$XsrfToken
)

# 1. 출력 억제 및 보안 설정 (Tls12 오염 방지)
$null = [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
$null = [Net.SecurityProtocolType]::Tls12

$Headers = @{ 
    "X-XSRF-TOKEN" = $XsrfToken
    "Accept"       = "application/json"
}

#서비스 리스트 정의
$ServiceList = @(
    "manager",
	"auth",
    "search",
    "node-mgmt",
	"node-stats",
	"cluster_manager",
	"cm-inventory",
	"controller",
	"datastore",
	"datastore_nonconfig",
	"nsx-message-bus",
	"nsx-platform-client",
	"liagent",
	"ntp",
	"http",
	"snmp",
	"ssh",
	"idps-reporting",
	"install-upgrade",
	"messaging-manager",
	"migration-coordinator",
	"nsx-upgrade-agent",
	"site_manager",
	"ui-service",
	"syslog"
)

try {
    $ReportEntries = New-Object System.Collections.Generic.List[PSCustomObject]

    foreach ($ServiceName in $ServiceList) {
        # 3. 각 서비스의 status API 경로 생성
        $Uri = "https://$Server/api/v1/node/services/$ServiceName/status"
        
        try {
            # 서비스별 상태 호출 (timeout 5초 설정으로 지연 방지)
            $Response = Invoke-RestMethod -Method Get -Uri $Uri -Headers $Headers -WebSession $SessionId -TimeoutSec 5 -ErrorAction Stop

            if ($null -ne $Response -and $null -ne $Response.runtime_state) {
                $State = $Response.runtime_state

                # 4. 상태 기반 Health 결정 (running이 아니면 CRITICAL)
                $Health = if ($State -eq "running") { "OK" } else { "CRITICAL" }

                $ReportEntries.Add([PSCustomObject]@{
                    ServiceName  = $ServiceName
                    RuntimeState = $State
                    Health       = $Health
                })
            }
        } catch {
            # 서비스가 없거나 응답이 없는 경우
            $ReportEntries.Add([PSCustomObject]@{
                ServiceName  = $ServiceName
                RuntimeState = "NOT_FOUND/ERROR"
                Health       = "WARNING"
            })
        }
    }

    # 5. 상태가 좋지 않은 서비스를 상단으로, 그 다음 서비스 이름순 정렬
    return $ReportEntries | Sort-Object Health, ServiceName -Descending

} catch {
    Write-Warning "[$Server] 전체 서비스 점검 중 치명적 오류: $($_.Exception.Message)"
    return $null
}