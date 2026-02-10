param($Server, $SessionId)
$Headers = @{"vmware-api-session-id" = $SessionId; "Accept" = "application/json"}


# Using ConfigurationEx property which contains vSAN settings for ClusterComputeResource
$ClusterViews = Get-View -ViewType ClusterComputeResource -Property Name, ConfigurationEx, OverallStatus

$Data = foreach ($cv in $ClusterViews) {
	# Check if vSAN is enabled in ConfigurationEx
	$vsanConfig = $cv.ConfigurationEx.VsanConfigInfo
	
	if ($vsanConfig -and $vsanConfig.Enabled) {
		
		# Performance Service Status is under PerfServiceConfig
		$PerfServiceEnabled = $vsanConfig.PerfServiceConfig.Enabled
		
		# Stats DB Health (Check if the performance service is functional)
		$StatsHealth = if ($PerfServiceEnabled) { "Healthy" } else { "N/A (Disabled)" }
		
		[PSCustomObject]@{
			ClusterName     = $cv.Name
			vSAN_Enabled    = $true
			PerfService     = if ($PerfServiceEnabled) { "Enabled" } else { "Disabled" }
			StatsDB_Status  = $StatsHealth
			# OverallStatus reflects the health of objects within the cluster
			PolicyCompliance = $cv.OverallStatus 
		}
	} else {
		# Skip clusters where vSAN is not enabled
		continue
	}
}

if ($null -eq $Data) { return $null }
return $Data