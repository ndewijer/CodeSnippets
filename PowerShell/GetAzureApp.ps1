
$AzureADAuthority = "https://login.microsoftonline.com/{0}/oauth2/token" -f "xxx"
$resourceURL = "https://graph.windows.net/"
$powerShellClientId = "1950a258-227b-4e31-a9cf-717495945fc2"
$params = @{
    "resource"   = $resourceURL;
    "client_id"  = $powerShellClientId;
    "grant_type" = "password";
    "username"   = "";
    "password"   = "";
    "scope"      = "openid";
}	
$azureResponse = Invoke-RestMethod -Method Post -Uri $AzureADAuthority -Body $params -Verbose -Debug
$token = $azureResponse.access_token;

$requestheader = @{
    "Authorization" = "Bearer $token"
    "Content-Type"  = "application/json"
}

$uri = "https://graph.windows.net/{0}/applications/{1}?api-version=1.6" -f "xxx", "dc54e5c3-368b-473c-8723-b17b6a2aac0e"
$application = (Invoke-RestMethod -Method Get -Headers $requestheader -Uri $uri)    

$application.appRoles | ft
