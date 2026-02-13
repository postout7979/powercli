# Global Security Settings
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }

function Test-NodeConnection {
    param ([string]$IP)
    return Test-Connection -ComputerName $IP -Count 1 -Quiet -ErrorAction SilentlyContinue
}

function Get-K8sParsedDetails {
    param ([string]$IP, [string]$Endpoint)
    
    # Re-apply security protocols for the current thread
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
    
    $url = "https://$($IP):6443/$($Endpoint)?verbose"
    $items = New-Object System.Collections.Generic.List[PSObject]
    
    try {
        $webClient = New-Object System.Net.WebClient
        $content = $webClient.DownloadString($url)

        if ($Endpoint -eq "version") {
            $json = $content | ConvertFrom-Json
            $json.PSObject.Properties | ForEach-Object {
                $items.Add([PSCustomObject]@{ Name = $_.Name; Status = $_.Value; IsOk = $true })
            }
        } else {
            # Standard K8s verbose parsing
            $lines = $content -split "`n" | Where-Object { $_ -match "\[\+\]" }
            foreach ($line in $lines) {
                $cleanLine = $line.Replace("[+]", "").Trim()
                if ($cleanLine.ToLower().EndsWith("ok")) {
                    $name = $cleanLine.Substring(0, $cleanLine.Length - 2).Trim()
                    $items.Add([PSCustomObject]@{ Name = $name; Status = "OK"; IsOk = $true })
                } else {
                    $items.Add([PSCustomObject]@{ Name = $cleanLine; Status = "FAIL"; IsOk = $false })
                }
            }
        }
    }
    catch {
        $items.Add([PSCustomObject]@{ Name = "API Request Failed"; Status = $_.Exception.Message; IsOk = $false })
    }
    return $items
}