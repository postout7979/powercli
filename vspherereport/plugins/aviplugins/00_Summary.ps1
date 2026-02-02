param([string]$Server, $SessionId, [string]$XsrfToken, [string]$version)
$Headers = @{ "Accept" = "application/json"; "X-Avi-Version" = $version; "X-CSRFToken" = $XsrfToken }

# 각 API의 count 값만 빠르게 가져와서 반환
$SE_Count = (Invoke-RestMethod -Uri "https://$Server/api/serviceengine" -Headers $Headers -WebSession $SessionId).count
$VS_Count = (Invoke-RestMethod -Uri "https://$Server/api/virtualservice" -Headers $Headers -WebSession $SessionId).count
$Pool_Count = (Invoke-RestMethod -Uri "https://$Server/api/pool" -Headers $Headers -WebSession $SessionId).count

return [PSCustomObject]@{
    ServiceEngines  = $SE_Count
    VirtualServices = $VS_Count
    Pools           = $Pool_Count
}