function connect-Vcenter {
    param(
        [string]$Server,
        [PSCredential]$Credential
    )

    # Self-signed 인증서 허용
    add-type @"
        using System.Net;
        using System.Security.Cryptography.X509Certificates;
        public class TrustAllCertsPolicy : ICertificatePolicy {
            public bool CheckValidationResult(ServicePoint srvPoint, X509Certificate certificate, WebRequest request, int certificateProblem) {
                return true;
            }
        }
"@

	$null = [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

    $User = $Credential.UserName
    $Pass = $Credential.GetNetworkCredential().Password
    $AuthHeader = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${User}:${Pass}"))

    try {	
		# API Login
        $Uri = "https://$Server/api/session"
        $Response = Invoke-RestMethod -Method Post -Uri $Uri -Headers @{ "Authorization" = "Basic ${AuthHeader}" }
        Write-Host ">>> Successfully connected to vCenter: $Server" -ForegroundColor Green
        return $Response # Session ID 반환
    } catch {
        Write-Host ">>> Login Failed: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}
