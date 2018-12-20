<#

.NAME
ApigeeMetricsImport.ps1

.SYNOPSIS  
Gets Apigee API data and outputs to console
 
.DESCRIPTION 
Calls API of Apigee. If unauthorized, it will renew Access (and Refresh) tokens where required.
Writen using API Information supplied by Apigee: https://docs.apigee.com/api-platform/system-administration/management-api-tokens
 
.INPUTS 
None

.OUTPUTS 
None
 
.EXAMPLE 
C:\PS> ApigeeMetricsImport.ps1

Exit Codes: 
  0 = success
101 - 0x80070065 = File not Found
102 - 0x80070066 = Access Denied, filesystem
103 - 0x80070067 = Access Denied, AWS
104 - 0x80070068 = Access Denied, Apigee
110 - 0x9008006E = Loop higher than defined


Author:
1.0 - 20-12-2018 - Nick de Wijer

#>

# Global Variables 
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$global:LoggingEnabled = $true
$global:loop = 0
$global:maxLoop = 2
$global:scriptPath = $PSScriptRoot

#Apigee Variables
$global:tokenURL = "https://login.apigee.com/oauth/token"
$global:apiURL = "https://apimonitoring.enterprise.apigee.com"
$global:apiQuery = "/metrics/traffic"
$global:apiVariables = @{
    org      = 'exactonline';
    interval = '1m';
    groupBy  = 'statusCode';
    env      = 'prod';
    from     = '-6m';
    to       = '-1m';
}

#AWS Variables
$global:awsDestinationAccountId = ""
$global:awsTakeRoleARN = ""
$global:awsTakeRoleSessionName = ""
$global:awsSecretID = ""
$global:awsSecretRegion = ""

# Import Libraries

# Import SnapIns and Modules
Import-Module AWSPowerShell

function RenewRefreshToken {
    param (
    )
    if ($loop -gt $maxloop) {
        StopAll("Cannot access AWS secret. Loop higher than $maxloop.", 110)
    }
    try {
        if ( (Get-EC2InstanceMetadata -Category IdentityDocument | ConvertFrom-Json | Select -ExpandProperty accountId) -eq $awsDestinationAccountId) {
            $params = @{}
        }
        else {
            $params = @{
                Credential = (Use-STSRole -RoleArn $awsTakeRoleARN -RoleSessionName $awsTakeRoleSessionName).Credentials
                Region     = $awsSecretRegion
            }
        }

        $secret = Get-SECSecretValue @params -SecretId $awsSecretID
    }
    catch {StopAll("Cannot access AWS secret.", 103)}   

    $secretTable = $secret.secretString | ConvertFrom-Json

    $resultHeaders = @{}
    $resultHeaders.Add("Authorization", "Basic ZWRnZWNsaTplZGdlY2xpc2VjcmV0")
    $resultHeaders.Add("Accept", "application/json;charset=utf-8")
    $body = @{username = $secretTable.user; password = $secretTable.secret; grant_type = 'password'}

    try {
        $result = Invoke-WebRequest -Uri $tokenURL -Headers $resultHeaders -Body $body -Method POST
    }
    catch { StopAll("Cannot access Apigee: " + $_.Exception.Response, 104)}

    $resultJson = $result | ConvertFrom-Json

    try {
        Set-Content -Path $scriptPath/accesstoken -Value ("Bearer " + $resultJson.access_token)
    }
    catch {
        StopAll ("Cannot write to Accesstoken file", 102)
    }

    try {
        Set-Content -Path $scriptPath/refreshtoken -Value ($resultJson.refresh_token)
    }
    catch {
        StopAll ("Cannot write to Accesstoken file", 102)
    }
}

function RenewAccessToken {
    param (
    )
    Log "Getting refreshtoken Token"
    
    do {
        do {
            if ($loop -gt $maxloop) {
                StopAll("Cannot access refresh token, loop higher than $maxloop.", 110)
            }
            if (Test-Path -Path $scriptPath/refreshtoken) {
                try {
                    $refreshtoken = get-content -path $scriptPath/refreshtoken
                    break
                }
                catch {StopAll("Cannot access refresh token", 102)}
            }
            else {
                Log "no Refresh token, renewing."
            
                RenewRefreshToken
                $loop++
            }
        } until ($refreshtoken)

        if ($loop -gt $maxloop) {
            StopAll("Cannot renew access token, loop higher than $maxloop.", 110)
        }
        
        $headersRefreshToken = @{}
        $headersRefreshToken.Add("Authorization", "Basic ZWRnZWNsaTplZGdlY2xpc2VjcmV0")
        $headersRefreshToken.Add("Accept", "application/json;charset=utf-8")
        $bodyRefreshToken = @{grant_type = 'refresh_token'; refresh_token = $refreshtoken}

        $accessTokenRequest = try {
            Invoke-WebRequest -Uri $tokenURL -Headers $headersRefreshToken -Method Post -Body $bodyRefreshToken
        }
        catch { $_.Exception.Response }

        if ($accessTokenRequest.StatusCode -eq "Unauthorized") {
            RenewRefreshToken
            $loop++
        }

    } until ($accessTokenRequest.StatusCode -eq 200)


    $accessTokenJson = $accessTokenRequest.Content | ConvertFrom-Json

    try {
        Set-Content -Path $scriptPath/accesstoken -Value ("Bearer " + $accessTokenJson.access_token)
        return $true
    }
    catch {
        StopAll ("Cannot write to Accesstoken file", 102)
    }
    StopAll("Here be dragons. (Renewing refresh token)", 666)
    
}

function GetContent {
    param (
    )   

    do {
        do {
            if ($loop -gt $maxloop) {
                StopAll("Cannot access refresh token, loop higher than $maxloop.", 110)
            }
            if (test-path -Path $scriptPath/accessToken) {
                try {
                    $accessToken = get-content -path $scriptPath/accessToken
                    break
                }
                catch {StopAll("Cannot access access token", 102)}
            }
            else {
                Log "no access token, renewing."
                
                RenewAccessToken
                $loop++
            }
        } until ($accessToken)

        $resultHeaders = @{}
        $resultHeaders.Add("Authorization", $accessToken)
        
        try {
            $result = Invoke-WebRequest -Uri $apiURL$apiQuery -Headers $resultHeaders -Body $apiVariables
        }
        catch { 
            if ($_.Exception.Response.StatusCode -eq "Unauthorized") {
                RenewAccessToken
                $loop++
            }
            else {StopAll("Here be dragons. (Getting Content, " + $_.Exception.Response.StatusCode + " )", 666)}
        }       
    } until ($result.StatusCode -eq 200)
      
    return $result.Content | ConvertFrom-Json
}

function main {
    param (
    )
    
    $resultJson = GetContent

    $arrResults = New-Object System.Collections.ArrayList
    if ($resultJson.results.series) {
        $resultJson.results.series | % {
            $series = $_
            $ObjResult = New-Object PsObject
            $ObjResult.PsObject.TypeNames.Insert(0, 'ObjResult')
            
            $ObjResult | Add-Member -MemberType NoteProperty -Name env -Value $_.tags.env
            $ObjResult | Add-Member -MemberType NoteProperty -Name faultCodeName -Value $_.tags.statusCode
            $ObjResult | Add-Member -MemberType NoteProperty -Name intervalSeconds -Value $_.tags.intervalSeconds
            $ObjResult | Add-Member -MemberType NoteProperty -Name org -Value $_.tags.org
            $ObjResult | Add-Member -MemberType NoteProperty -Name region -Value $_.tags.region

            for ($i = 0; $i -lt $_.columns.count; $i++) {
                $ObjResult | Add-Member -MemberType NoteProperty -Name $series.columns[$i] -Value '' 

                switch ($series.values[$i][$i].getType().Name) {
                    'datetime' {$ObjResult.($series.columns[$i]) = $series.values[$i][$i].ToString("o"); break }
                    'string' { $ObjResult.($series.columns[$i]) = $series.values[$i][$i]; break }
                    'Int32' { $ObjResult.($series.columns[$i]) = [int]$series.values[$i][$i]; break }
                    'Int64' { $ObjResult.($series.columns[$i]) = [int]$series.values[$i][$i]; break }
                    'Decimal' { $ObjResult.($series.columns[$i]) = [decimal]$series.values[$i][$i]; break }
                    'Double' { $ObjResult.($series.columns[$i]) = [decimal]$series.values[$i][$i]; break }
                }

            }
            [void]$arrResults.Add($ObjResult)
        }
        Write-Output $arrResults | ft
    }
    else {
        Log "No results found"
    }
}

Function Log($logText) {
    if ($LoggingEnabled -eq $true) {
        Try {write-host (Get-Date -Format G)  "|"  $logText }
        Catch {Write-Warning "Unable to write log to console. | $logText"}
    }
}

# Error function
Function StopAll($stopText, $exitCode) {
    Log "---!!! Stopping execution. Reason: $stopText"
    If ($error.count -gt 0) {Log ("Last error: " + $error[0])}
    Write-Warning "---!!! Stopping execution. Reason: $stopText"
    $date = Get-Date
    Log ("------ Script Completion on " + $date.ToShortDateString() + " at " + $date.ToShortTimeString() + " ------")
    If ($exitCode) {Exit $exitCode}
    Else {Exit -1}
}

main
