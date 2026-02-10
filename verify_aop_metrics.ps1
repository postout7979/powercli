<#
.SYNOPSIS
    Verifies that SCG Assessment metrics have been successfully pushed to VMware Aria Operations.
.DESCRIPTION
    1. Connects to AOP.
    2. Retrieves all resources created by the SCG Adapter.
    3. Fetches and displays the latest metric values (Pass, Fail, Total, Info) for each resource.
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
$ADAPTER_KIND = "SCG_Assessment_Adapter"

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
Write-Host "       SCG Metric Verification Tool           " -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan

Write-Host ""
Write-Host "[CONN] Connecting to Aria Operations ($AopServer)..." -ForegroundColor Cyan
$Token = Get-AopToken
Write-Host "  -> Auth Success!" -ForegroundColor Green

# 1. Find All SCG Resources
Write-Host ""
Write-Host "[INFO] Searching for SCG resources..." -ForegroundColor Cyan
$headers = @{
    "Authorization" = "vRealizeOpsToken $Token"
    "Accept"        = "application/json"
}

$baseUrl = "https://$AopServer/suite-api/api/resources"
$searchUrl = "{0}?adapterKind={1}" -f $baseUrl, $ADAPTER_KIND

try {
    $response = Invoke-RestMethod -Uri $searchUrl -Method Get -Headers $headers
    $resources = $response.resourceList
} catch {
    Write-Error "Failed to search resources: $($_.Exception.Message)"
    exit
}

if (-not $resources) {
    Write-Host "  -> No resources found for adapter '$ADAPTER_KIND'." -ForegroundColor Yellow
    exit
}

$count = $resources.Count
Write-Host "  -> Found $count resource(s). Checking metrics..." -ForegroundColor Yellow

# 2. Check Metrics for Each Resource
foreach ($res in $resources) {
    $resId = $res.identifier
    $resName = $res.resourceKey.name
    $resKind = $res.resourceKey.resourceKindKey
    
    Write-Host "`n--------------------------------------------------" -ForegroundColor DarkGray
    Write-Host " Resource: $resName" -ForegroundColor White
    Write-Host " Kind    : $resKind" -ForegroundColor DarkGray
    
    # Get Latest Stats
    $statsUrl = "https://$AopServer/suite-api/api/resources/$resId/stats/latest"
    
    try {
        $statsResp = Invoke-RestMethod -Uri $statsUrl -Method Get -Headers $headers
        $statList = $statsResp.'values-list'.stat
        
        # Filter SCG metrics
        $scgMetrics = $statList | Where-Object { $_.'statKey'.key -like "SCG|Assessment|*" }
        
        if ($scgMetrics) {
            foreach ($m in $scgMetrics) {
                $keyName = $m.'statKey'.key.Replace("SCG|Assessment|", "")
                $val = $m.data[0] # Latest value
                
                # Color code output
                if ($keyName -eq "Fail" -and $val -gt 0) {
                    Write-Host "   - $keyName : $val" -ForegroundColor Red
                } elseif ($keyName -eq "Pass") {
                    Write-Host "   - $keyName : $val" -ForegroundColor Green
                } else {
                    Write-Host "   - $keyName : $val" -ForegroundColor Gray
                }
            }
        } else {
            Write-Host "   [WARNING] No SCG metrics found yet." -ForegroundColor Yellow
        }
        
    } catch {
        Write-Host "   [ERROR] Failed to fetch stats: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`n[DONE] Verification completed." -ForegroundColor Cyan