<#
.SYNOPSIS
    Deletes resources created by the SCG Assessment integration script from VMware Aria Operations (AOP).
.DESCRIPTION
    Updated to delete all related Resource Kinds:
    SCG_Group, SCG_vCenter, SCG_ESXi, SCG_VM, SCG_Generic, SCG_Assessment_Object
.PARAMETER AopServer
    Aria Operations IP or FQDN
.PARAMETER AopUser
    Aria Operations Username
.PARAMETER AopPassword
    Aria Operations Password
#>

param (
    [string]$AopServer = "192.168.0.210",
    [string]$AopUser = "admin",
    [string]$AopPassword = "password123!" 
)

# Ignore SSL certificate errors
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

# Constants
$ADAPTER_KIND  = "SCG_Assessment_Adapter"
# Updated list of all potential resource kinds to clean up
$TARGET_KINDS  = @("SCG_Group", "SCG_Root", "SCG_vCenter", "SCG_ESXi", "SCG_VM", "SCG_Generic", "SCG_Assessment_Object", "SCG_Section", "SCG_Root", "SCG_Parent")

# ---------------------------------------------------------
# Helper Functions
# ---------------------------------------------------------
function Get-AopToken {
    $url = "https://$AopServer/suite-api/api/auth/token/acquire"
    $body = @{ username = $AopUser; password = $AopPassword } | ConvertTo-Json
    $headers = @{ "Content-Type" = "application/json"; "Accept" = "application/json" }
    
    try {
        $response = Invoke-RestMethod -Uri $url -Method Post -Body $body -Headers $headers -TimeoutSec 10
        return $response.token
    } catch {
        Write-Error "Failed to acquire AOP token: $($_.Exception.Message)"
        exit
    }
}

# ---------------------------------------------------------
# Main Execution
# ---------------------------------------------------------
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "       SCG Resource Cleanup Utility           " -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan

Write-Host ""
Write-Host "[CONN] Connecting to Aria Operations ($AopServer)..." -ForegroundColor Cyan
$Token = Get-AopToken
Write-Host "  -> Auth Success!" -ForegroundColor Green

$allResources = @()

# 1. Find Resources (Loop through each Kind)
Write-Host ""
Write-Host "[INFO] Searching for SCG resources..." -ForegroundColor Cyan
$headers = @{
    "Authorization" = "vRealizeOpsToken $Token"
    "Accept"        = "application/json"
}

$baseUrl = "https://$AopServer/suite-api/api/resources"

foreach ($kind in $TARGET_KINDS) {
    # Safe URL construction
    $searchUrl = "{0}?adapterKind={1}&resourceKind={2}" -f $baseUrl, $ADAPTER_KIND, $kind
    
    try {
        $response = Invoke-RestMethod -Uri $searchUrl -Method Get -Headers $headers
        if ($response.resourceList) {
            $allResources += $response.resourceList
        }
    } catch {
        # Quietly fail if kind doesn't exist
    }
}

if ($allResources.Count -eq 0) {
    Write-Host "  -> No resources found. Nothing to delete." -ForegroundColor Yellow
    exit
}

$count = $allResources.Count
Write-Host "  -> Found $count resource(s) in total." -ForegroundColor Yellow
foreach ($res in $allResources) {
    Write-Host "     * [$($res.resourceKey.resourceKindKey)] $($res.resourceKey.name)" -ForegroundColor Gray
}

# 2. Confirm Deletion
Write-Host ""
Write-Host "WARNING: This will delete ALL listed resources above." -ForegroundColor Red
$confirm = Read-Host "Are you sure you want to proceed? (y/n)"
if ($confirm -ne 'y') {
    Write-Host "Cancelled."
    exit
}

# 3. Delete Resources
Write-Host ""
Write-Host "[PROC] Deleting resources..." -ForegroundColor Cyan

foreach ($res in $allResources) {
    $resId = $res.identifier
    $resName = $res.resourceKey.name
    $resKind = $res.resourceKey.resourceKindKey
    
    Write-Host "  [-] Deleting ($resKind): $resName ... " -NoNewline
    
    $deleteUrl = "https://$AopServer/suite-api/api/resources/$resId"
    
    try {
        Invoke-RestMethod -Uri $deleteUrl -Method Delete -Headers $headers | Out-Null
        Write-Host "OK" -ForegroundColor Green
    } catch {
        Write-Host "Failed" -ForegroundColor Red
        Write-Error "    $($_.Exception.Message)"
    }
}

Write-Host ""
Write-Host "[DONE] Cleanup completed." -ForegroundColor Cyan
