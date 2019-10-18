add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

$headers = @{}
$headers.Add("Authorization","Splunk A3C70A6C-95F1-4E94-BDDA-B04613F59625")
$headers.Add("X-Splunk-Request-Channel","FE0ECFAD-13D5-401B-847D-77833BD77131")

Invoke-WebRequest -Uri https://xx:8088/services/collector -Headers $headers -Method Post -Body '{"sourcetype":"akamai:cm:json", "event":"Hello, World!"}'
Invoke-WebRequest -Uri https://xx:8088/services/collector/ack -Headers $headers -Method Post -Body '{"acks":[10]}'

