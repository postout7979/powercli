<#
.SYNOPSIS
    Parses SCG assessment result JSON files and pushes metrics to Aria Operations with a 3-level hierarchy.
.DESCRIPTION
    Structure:
      [Root] SCG_ROOT (Kind: SCG_Root)
        |
        |-- [Parent] SCG_Group_ESXi (Kind: SCG_Parent)
        |     |-- [Object] SCG-host-01 (Kind: SCG_ESXi)
        |     |-- [Object] SCG-host-02
        |
        |-- [Parent] SCG_Group_VM (Kind: SCG_Parent)
        |     |-- [Object] SCG-vm-01 (Kind: SCG_VM)
        |
        |-- [Parent] SCG_Group_vCenter (Kind: SCG_Parent)
              |-- [Object] SCG-vc-01 (Kind: SCG_vCenter)

    * Feature: Restored 3-category classification.
    * Feature: Root node 'SCG_ROOT' aggregates all categories.
    * Feature: Robust Relationship linking (Root -> Parent -> Child).
    * Fix: Changed Relationship API Payload key from 'add' to 'uuids' to resolve 400 Bad Request.
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

# ---------------------------------------------------------
# Constant Definitions
# ---------------------------------------------------------
$ADAPTER_KIND    = "SCG_Assessment_Adapter"
$IDENTIFIER_NAME = "ObjectID"

# Resource Kinds Hierarchy
$KIND_ROOT       = "SCG_Root"
$KIND_PARENT     = "SCG_Parent" 

# ---------------------------------------------------------
# Helper: Map Object Type to Resource Kind
# ---------------------------------------------------------
function Get-ResourceKind {
    param([string]$Type)
    switch ($Type) {
        "vCenter" { return "SCG_vCenter" }
        "ESXi"    { return "SCG_ESXi" }
        "VM"      { return "SCG_VM" }
        Default   { return "SCG_Generic" }
    }
}

# ---------------------------------------------------------
# [Step 1] Select Folder and Load JSON File
# ---------------------------------------------------------
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "       SCG Result to Aria Ops Importer        " -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan

$CurrentPath = $PSScriptRoot
$SubFolders = Get-ChildItem -Path $CurrentPath -Directory

if ($SubFolders.Count -eq 0) {
    $TargetFolder = $CurrentPath
} else {
    Write-Host ""
    Write-Host "[Select Folder] Select the folder containing the JSON file:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $SubFolders.Count; $i++) {
        Write-Host "  [$($i+1)] $($SubFolders[$i].Name)"
    }
    Write-Host "  [0] Current Folder ($CurrentPath)"
    
    do {
        $selection = Read-Host "Enter the number"
    } while ($selection -notmatch "^\d+$" -or [int]$selection -gt $SubFolders.Count)

    if ([int]$selection -eq 0) { $TargetFolder = $CurrentPath }
    else { $TargetFolder = $SubFolders[[int]$selection - 1].FullName }
}

# --- Select JSON File ---
$JsonFiles = Get-ChildItem -Path $TargetFolder -Filter "*.json"

if ($JsonFiles.Count -eq 0) {
    Write-Error "Error: No .json files found in the selected folder: $TargetFolder"
    exit
}

Write-Host ""
Write-Host "[Select File] Select the JSON file to process:" -ForegroundColor Yellow
for ($i = 0; $i -lt $JsonFiles.Count; $i++) {
    Write-Host "  [$($i+1)] $($JsonFiles[$i].Name)"
}

do {
    $fileSelection = Read-Host "Enter the number"
} while ($fileSelection -notmatch "^\d+$" -or [int]$fileSelection -lt 1 -or [int]$fileSelection -gt $JsonFiles.Count)

$JsonFile = $JsonFiles[[int]$fileSelection - 1].FullName
Write-Host "[INFO] Selected file: $JsonFile" -ForegroundColor Green
# ---------------------------------------------------------

Write-Host "[INFO] Loading file..." -ForegroundColor Green
try {
    # Encoding fix: explicitly use UTF8
    $JsonData = Get-Content $JsonFile -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
    Write-Error "Failed to read JSON file. Please check the encoding."
    exit
}

# ---------------------------------------------------------
# [Step 2] Aggregate Data
# ---------------------------------------------------------
Write-Host "[INFO] Reading object data..." -ForegroundColor Cyan

# Structure to hold individual items
$AllItems = @()

if (-not $JsonData.Data) {
    Write-Error "Invalid JSON format: 'Data' key is missing in the selected file."
    exit
}

foreach ($sectionName in "vCenter", "ESXi", "VM") {
    if ($JsonData.Data.$sectionName) {
        $items = $JsonData.Data.$sectionName
        
        foreach ($item in $items) {
            $type = if ($item.Type) { $item.Type } else { $sectionName }
            
            # Add to list with normalized properties
            $AllItems += [PSCustomObject]@{
                Name  = $item.Name
                Type  = $type
                Pass  = [int]$item.Pass
                Fail  = [int]$item.Fail
                Info  = [int]$item.Info
                Total = [int]$item.Pass + [int]$item.Fail + [int]$item.Info
            }
        }
    }
}
Write-Host "  -> Identified $($AllItems.Count) target objects." -ForegroundColor Gray

# ---------------------------------------------------------
# [Step 3] Define AOP API Functions
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

function Get-Or-Create-Resource {
    param($Token, $Name, $Description, $ResourceKind)
    
    $headers = @{
        "Authorization" = "vRealizeOpsToken $Token"
        "Accept"        = "application/json"
        "Content-Type"  = "application/json"
    }

    # 1. Check existing resource (GET)
    $baseUrl = "https://$AopServer/suite-api/api/resources"
    $query = "adapterKind=$ADAPTER_KIND" + "&" + "resourceKind=$ResourceKind" + "&" + "name=$Name"
    $searchUrl = "$baseUrl?$query"
    
    try {
        $exists = Invoke-RestMethod -Uri $searchUrl -Method Get -Headers $headers
        if ($exists.resourceList) {
            return $exists.resourceList[0].identifier
        }
    } catch { }

    # 2. Create if not exists
    Write-Host "  [NEW] Creating: $Name ($ResourceKind)" -ForegroundColor Yellow
    $createUrl = "https://$AopServer/suite-api/api/resources/adapterkinds/$ADAPTER_KIND"
    
    $identifierObj = @{
        identifierType = @{ name = $IDENTIFIER_NAME; dataType = "STRING" }
        value = $Name
    }
    
    $idJson = $identifierObj | ConvertTo-Json -Depth 2
    $resourceIdentifiersJson = "[$idJson]"
    
    $finalPayload = @"
{
    "name": "$Name",
    "description": "$Description",
    "resourceKey": {
        "name": "$Name",
        "adapterKindKey": "$ADAPTER_KIND",
        "resourceKindKey": "$ResourceKind",
        "resourceIdentifiers": $resourceIdentifiersJson
    }
}
"@

    try {
        $created = Invoke-RestMethod -Uri $createUrl -Method Post -Body $finalPayload -Headers $headers -ContentType "application/json"
        return $created.identifier
    } catch {
        # Error Handling for 422 (Already Exists)
        $statusCode = $_.Exception.Response.StatusCode
        $statusInt = [int]$statusCode

        if ($statusInt -eq 422 -or $statusInt -eq 409) {
            # Fallback: Query Resource by Name/Adapter/Kind
            $queryUrl = "https://$AopServer/suite-api/api/resources/query"
            $queryPayload = @{
                resourceKind = @($ResourceKind)
                adapterKind  = @($ADAPTER_KIND)
                name         = @($Name)
            } | ConvertTo-Json

            try {
                $queryResponse = Invoke-RestMethod -Uri $queryUrl -Method Post -Body $queryPayload -Headers $headers -ContentType "application/json"
                if ($queryResponse.resourceList) {
                    return $queryResponse.resourceList[0].identifier
                }
            } catch {
                Write-Error "Failed to recover existing resource ID for $Name."
            }
        } else {
            Write-Error "Resource Creation Failed ($Name). Status: $statusInt."
        }
        return $null
    }
}

function Push-Metrics {
    param($Token, $ResourceId, $Stats)
    
    $url = "https://$AopServer/suite-api/api/resources/$ResourceId/stats"
    $headers = @{
        "Authorization" = "vRealizeOpsToken $Token"
        "Content-Type"  = "application/json"
    }
    
    # Use UTC Origin for correct timestamp
    $origin = New-Object -TypeName System.DateTime -ArgumentList 1970, 1, 1, 0, 0, 0, 0, ([System.DateTimeKind]::Utc)
    $ts = [int64]((Get-Date).ToUniversalTime() - $origin).TotalMilliseconds

    $valTotal = [double]$Stats.Total
    $valPass  = [double]$Stats.Pass
    $valFail  = [double]$Stats.Fail
    $valInfo  = [double]$Stats.Info

    # Manually construct JSON to ensure arrays are preserved
    $itemTotal = '{ "statKey": "SCG|Assessment|Total", "timestamps": [' + $ts + '], "values": [' + $valTotal + '] }'
    $itemPass  = '{ "statKey": "SCG|Assessment|Pass",  "timestamps": [' + $ts + '], "values": [' + $valPass  + '] }'
    $itemFail  = '{ "statKey": "SCG|Assessment|Fail",  "timestamps": [' + $ts + '], "values": [' + $valFail  + '] }'
    $itemInfo  = '{ "statKey": "SCG|Assessment|Info",  "timestamps": [' + $ts + '], "values": [' + $valInfo  + '] }'

    $finalJsonPayload = '{ "stat-content": [ ' + $itemTotal + ', ' + $itemPass + ', ' + $itemFail + ', ' + $itemInfo + ' ] }'

    try {
        Invoke-RestMethod -Uri $url -Method Post -Body $finalJsonPayload -Headers $headers -ContentType "application/json" | Out-Null
        # Return success
        return $true
    } catch {
        Write-Error "Metric Push Failed: $($_.Exception.Message)"
        return $false
    }
}

# New Function: Add-Relationship with Specific API Logic
function Add-Relationship {
    param($Token, $ParentId, $ChildIds)
    
    if (-not $ChildIds -or $ChildIds.Count -eq 0) { return }

    $headers = @{
        "Authorization" = "vRealizeOpsToken $Token"
        "Content-Type"  = "application/json"
        "Accept"        = "application/json"
    }

    # Step 1: Set Parent for each Child (Update target: Child)
    # URL: .../resources/{childID}/relationships/parent
    Write-Host "    -> Linking Parent ($ParentId) to Children..." -NoNewline
    
    foreach ($childId in $ChildIds) {
        $url = "https://$AopServer/suite-api/api/resources/$childId/relationships/parent"
        # Payload: Add ParentID - key must be 'uuids' for this endpoint variant
        $payload = '{ "uuids": ["' + $ParentId + '"] }'
        
        try {
            Invoke-RestMethod -Uri $url -Method Put -Body $payload -Headers $headers | Out-Null
            Write-Host "." -NoNewline
        } catch {
            # Capture error details if possible
            # Write-Warning " [!] Link Failed for child $childId"
        }
    }
    Write-Host " Done."

    # Step 2: Set Children for Parent (Update target: Parent)
    # URL: .../resources/{parentID}/relationships/children
    $url = "https://$AopServer/suite-api/api/resources/$ParentId/relationships/children"
    
    # Construct "id1","id2" string
    $quotedIds = @()
    foreach ($id in $ChildIds) {
        $quotedIds += "`"$id`""
    }
    $idsString = $quotedIds -join ","
    
    # Payload: Add ChildIDs - key must be 'uuids' to avoid 400 violations
    $payload = '{ "uuids": [' + $idsString + '] }'

    try {
        Invoke-RestMethod -Uri $url -Method Put -Body $payload -Headers $headers | Out-Null
        Write-Host "    -> Linked Children list to Parent." -ForegroundColor Green
    } catch {
        # Capture detailed error
        $errDetails = $_.Exception.Response.GetResponseStream()
        if ($errDetails) {
            $reader = New-Object System.IO.StreamReader($errDetails)
            $errBody = $reader.ReadToEnd()
            Write-Warning "Parent-Child Link Error: $($_.Exception.Response.StatusCode). Details: $errBody"
        } else {
            Write-Warning "Parent-Child Link Error: $($_.Exception.Message)"
        }
    }
}

# ---------------------------------------------------------
# [Step 4] Execution (Main Logic)
# ---------------------------------------------------------
Write-Host ""
Write-Host "[CONN] Connecting to Aria Operations ($AopServer)..." -ForegroundColor Cyan
$Token = Get-AopToken
Write-Host "  -> Auth Success!" -ForegroundColor Green

# Stats & Child ID Containers
$ParentGroups = @{
    "vCenter" = @{ ChildIds = @(); Stats = @{ Pass=0; Fail=0; Info=0; Total=0 } }
    "ESXi"    = @{ ChildIds = @(); Stats = @{ Pass=0; Fail=0; Info=0; Total=0 } }
    "VM"      = @{ ChildIds = @(); Stats = @{ Pass=0; Fail=0; Info=0; Total=0 } }
}
$RootStats = @{ Pass=0; Fail=0; Info=0; Total=0 }
$ParentIdsForRoot = @()

# 1. Process Individual Items (Children)
foreach ($item in $AllItems) {
    $resourceName = "SCG-$($item.Name)"
    $targetKind   = Get-ResourceKind -Type $item.Type
    
    Write-Host "[OBJ] $resourceName ($targetKind)" -NoNewline
    
    # Create/Get Child Resource
    $resId = Get-Or-Create-Resource `
        -Token $Token `
        -Name $resourceName `
        -Description "SCG Assessment Result for $($item.Type)" `
        -ResourceKind $targetKind
    
    if ($resId) {
        # Push Child Metrics
        $metricSuccess = Push-Metrics -Token $Token -ResourceId $resId -Stats $item
        
        if ($metricSuccess) {
            Write-Host " [OK]" -ForegroundColor Green
            
            # Add to Parent Group Data ONLY if metric push succeeded
            if ($ParentGroups.ContainsKey($item.Type)) {
                $ParentGroups[$item.Type].ChildIds += $resId
                $ParentGroups[$item.Type].Stats.Pass  += $item.Pass
                $ParentGroups[$item.Type].Stats.Fail  += $item.Fail
                $ParentGroups[$item.Type].Stats.Info  += $item.Info
                $ParentGroups[$item.Type].Stats.Total += $item.Total
            }
        } else {
            Write-Host " [Metric Fail]" -ForegroundColor Red
        }
    }
}

# 2. Process Parent Resources (Group Nodes)
Write-Host ""
Write-Host "--------------------------------------------------"
Write-Host "[PARENT] Processing Category Groups..." -ForegroundColor Cyan

foreach ($type in $ParentGroups.Keys) {
    $groupData = $ParentGroups[$type]
    
    if ($groupData.ChildIds.Count -gt 0) {
        $parentName = "SCG_Group_$type"
        
        Write-Host ""
        Write-Host "[*] Parent: $parentName ($KIND_PARENT)" -ForegroundColor Yellow
        Write-Host "    Totals - Pass: $($groupData.Stats.Pass), Fail: $($groupData.Stats.Fail)" -ForegroundColor Gray
        
        # Create Parent Resource
        $parentId = Get-Or-Create-Resource `
            -Token $Token `
            -Name $parentName `
            -Description "Parent SCG Group for $type" `
            -ResourceKind $KIND_PARENT
            
        if ($parentId) {
            # Push Metrics
            $metricSuccess = Push-Metrics -Token $Token -ResourceId $parentId -Stats $groupData.Stats
            
            if ($metricSuccess) {
                # Link Children to Parent
                Add-Relationship -Token $Token -ParentId $parentId -ChildIds $groupData.ChildIds
                
                # Collect for Root
                $ParentIdsForRoot += $parentId
                $RootStats.Pass  += $groupData.Stats.Pass
                $RootStats.Fail  += $groupData.Stats.Fail
                $RootStats.Info  += $groupData.Stats.Info
                $RootStats.Total += $groupData.Stats.Total
            }
        }
    }
}

# 3. Process Root Resource
Write-Host ""
Write-Host "--------------------------------------------------"
Write-Host "[ROOT] Processing Assessment Root..." -ForegroundColor Cyan

if ($RootStats.Total -gt 0) {
    $rootName = "SCG_ROOT"
    
    Write-Host "[*] Root: $rootName ($KIND_ROOT)" -ForegroundColor Yellow
    Write-Host "    Grand Totals - Pass: $($RootStats.Pass), Fail: $($RootStats.Fail)" -ForegroundColor Gray
    
    # Create Root Resource
    $rootId = Get-Or-Create-Resource `
        -Token $Token `
        -Name $rootName `
        -Description "Overall SCG Assessment Summary Root" `
        -ResourceKind $KIND_ROOT
        
    if ($rootId) {
        # Push Metrics
        $metricSuccess = Push-Metrics -Token $Token -ResourceId $rootId -Stats $RootStats
        
        if ($metricSuccess) {
            # Link Parents to Root
            Add-Relationship -Token $Token -ParentId $rootId -ChildIds $ParentIdsForRoot
        }
    }
}

Write-Host ""
Write-Host "[DONE] All tasks completed successfully." -ForegroundColor Cyan
