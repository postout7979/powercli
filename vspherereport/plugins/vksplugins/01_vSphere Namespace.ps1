# Plugin.ps1
param (
    [Parameter(Mandatory=$true)]
    [string]$apiServer,
    
    [Parameter(Mandatory=$true)]
    [string]$plainToken
)

# SSL 인증서 검증 무시 (자체 서명 인증서 사용 시 필수)
#$null = [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(ServicePoint srvPoint, X509Certificate certificate, WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@

$ApiServer = "172.18.10.111"
$headers = @{
    "Authorization" = "Bearer eyJhbGciOiJSUzI1NiIsImtpZCI6IlJNWS1JM1YtRHBzcTBXNmx4bXgzZGVLT3dvaFhrWVdwS3RDWGt0Z1NSX2sifQ.eyJhdWQiOlsiaHR0cHM6Ly9rdWJlcm5ldGVzLmRlZmF1bHQuc3ZjLmNsdXN0ZXIubG9jYWwiXSwiZXhwIjoxNzY4MzIwMjA2LCJpYXQiOjE3NjgzMTY2MDYsImlzcyI6Imh0dHBzOi8va3ViZXJuZXRlcy5kZWZhdWx0LnN2Yy5jbHVzdGVyLmxvY2FsIiwianRpIjoiOTRmNjZhZDgtNWQ5My00MWVkLWFkNTYtY2M3ZjdhZDQ2NWM4Iiwia3ViZXJuZXRlcy5pbyI6eyJuYW1lc3BhY2UiOiJkZWZhdWx0Iiwic2VydmljZWFjY291bnQiOnsibmFtZSI6InJlYWQtb25seS11c2VyIiwidWlkIjoiOTBhN2RlMTctYTM3Yy00N2UxLWJlZmEtYTNmZDU3OTFhMzM3In19LCJuYmYiOjE3NjgzMTY2MDYsInN1YiI6InN5c3RlbTpzZXJ2aWNlYWNjb3VudDpkZWZhdWx0OnJlYWQtb25seS11c2VyIn0.Ph8ZOmrVHOT6gZLT1UtWGGT_QREqfon6RKjl-8i4coMafYXtI5UstgZN5RsF0AMpiuc8iI6vuWxGbC7b2BhjDxMClEB6J8OVa1eLndLYLsTbIC4dqCd_t84Il2INJpEunXTbpup_ZXatoYfWjt-9nv9DF3Ly8Z5z4ZX3Ro7ux7-kIkCtrjvvrf-efaIbXSG5dMl9EEqYeC_dDBgctTdHDnP625t_zbsFFpbNU_uDhhTRWEkRs_9RwcmL2iD8oUpwAURIntdc7R2OCDxUfqSbmW641Gnq2vDO7Q9Od_3JppzSqFfR9W6N0W2_qgn-0aJpFBK58SvUjyRBjL_KElmGIw"
    "Accept"        = "application/json"
}

try {
    # Namespaces 정보 추출
    $url = "https://${ApiServer}:6443/api/v1/namespaces"
	$url
    $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
    
    # 필요한 정보만 가공하여 반환
    $namespaces = $response.items | Select-Object `
        @{Name="Name"; Expression={$_.metadata.name}},
        @{Name="Status"; Expression={$_.status.phase}},
        @{Name="CreationTimestamp"; Expression={$_.metadata.creationTimestamp}}
    
    return $namespaces | ConvertTo-Json
}
catch {
    Write-Error "API 호출 실패: $_"
    return $null
}