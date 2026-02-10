function Remove-NSXSession {
    param (
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$NsxAuthObject
    )
    $logoutUrl = "https://172.18.10.102/api/session/destroy"

	$xsrftoken = $NsxAuthObject.XsrfToken
	$websession = $NsxAuthObject.WebSession

    $headers = @{
        "x-xsrf-token" = $xsrftoken
        "Content-Type" = "application/json"
    }
	$headers
    try {
        # POST 메소드를 호출하여 세션 파기
        Invoke-WebRequest -Uri $logoutUrl -Method POST -WebSession $websession -Headers $headers
        Write-Host "Success NSX session closing." -ForegroundColor Cyan
    }
    catch {
        Write-Warning "Error during session close: $_"
    }
}