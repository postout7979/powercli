function Disconnect-Vcenter {
    param(
        [string]$Server,
        [string]$SessionId
    )
$Headers = @{"vmware-api-session-id" = $SessionId; "Accept" = "application/json"}

    if ($SessionId) {
        try {
			# API Session logout
            $Uri = "https://$Server/api/session"
            Invoke-RestMethod -Method Delete -Uri $Uri -Headers $Headers
            Write-Host ">>> Successfully logged out from vCenter." -ForegroundColor Yellow
        } catch {
            Write-Host ">>> Logout Warning: $($_.Exception.Message)" -ForegroundColor Gray
        }
    }
}