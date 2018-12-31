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
1.1 - 31-12-2018 - Nick de Wijer - Added support for multiple Apigee API endpoints by dynamicly creating the headers of a result entry.

#>

# Global Variables 
$global:scriptName = $myInvocation.MyCommand.Name                                 #Get Scriptname
$global:loggingEnabled = $true
$global:loggingToConsole = $true
$global:loggingtoFile = $true
$global:logFile = ${env:Temp} + "\" + $scriptName.Replace(".ps1", ".log")         #Set Windows location for logging file based on script name in temp directory.
#$global:logFile = ${env:TMPDIR} + "\" + $scriptName.Replace(".ps1", ".log")         #Set OSX location for logging file based on script name in temp directory.

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$global:loop = 0
$global:maxLoop = 2
$global:scriptPath = $PSScriptRoot

#Apigee Variables

# traffic API settings
$global:tokenURL = "https://login.apigee.com/oauth/token"
$global:apiURL = "https://apimonitoring.enterprise.apigee.com"
$global:apiQuery = "/metrics/traffic"
$global:apiVariables = @{
    org      = '';
    interval = '1m';
    groupBy  = 'statusCode';
    env      = 'prod';
    from     = '-6min';
    to       = '-1min';
}

<#
# latency API settings
$global:apiQuery = "/metrics/latency"
$global:apiVariables = @{
    org      = '';
    percentile = "95";
    interval = '1m';
    windowsize = '1m';
    select = 'totalLatency,targetLatency';
    groupBy  = 'org,env,region,proxy';
    env      = 'prod';
    from     = '-6min';
    to       = '-1min';
}
#>

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
    <#
    .SYNOPSIS
    Renews Refresh token
    
    .DESCRIPTION
    When the refresh token has expired, Apigee will give back an 403. The script will connect to the AWS Security account holding the Apigee User credentials
    and uses that to generate a new refresh token that it saves to the local file.

    As this also generates a fresh Access token, next to the Refresh token, this is saved as well and the function is returned true, any other case will cause an catch/stopall.
    
    .NOTES

    #>


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
        Log "Successfully retrieved Secretmanager Secret"
    }
    catch {StopAll("Cannot access AWS secret.", 103)}   

    $secretTable = $secret.secretString | ConvertFrom-Json

    $resultHeaders = @{}
    $resultHeaders.Add("Authorization", "Basic ZWRnZWNsaTplZGdlY2xpc2VjcmV0")
    $resultHeaders.Add("Accept", "application/json;charset=utf-8")
    $body = @{username = $secretTable.user; password = $secretTable.secret; grant_type = 'password'}

    try {
        $result = Invoke-WebRequest -Uri $tokenURL -Headers $resultHeaders -Body $body -Method POST -UseBasicParsing
    }
    catch { StopAll("Cannot access Apigee: " + $_.Exception.Response, 104)}

    $resultJson = $result | ConvertFrom-Json

    try {
        Set-Content -Path $scriptPath/accesstoken -Value ("Bearer " + $resultJson.access_token)
        Log "Successfully written access token"
    }
    catch {
        StopAll ("Cannot write to Accesstoken file", 102)
    }

    try {
        Set-Content -Path $scriptPath/refreshtoken -Value ($resultJson.refresh_token)
        Log "Successfully written refresh token"
    }
    catch {
        StopAll ("Cannot write to Accesstoken file", 102)
    }
    if ((Test-Path -Path $scriptPath/refreshtoken) -and (Test-Path -Path $scriptPath/accesstoken)) { 
        return $true
    }
    else {
        StopAll("Here be dragons. (Renewing refresh token)", 666)
    }
}

function RenewAccessToken {
    
    <#  

    .SYNOPSIS
    Refeshes the Apigee Access token using the refresh token.
    
    .DESCRIPTION
    Grabs the Apigee refresh token and uses that to generate a new access token. If it gets an 403, it will move into the RenewRefreshToken function and
    return this function as the Refresh renewal also renews the access token. Any other situation will Catch/Stopall.

    #>

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
                    Log "Successfully retrieved refresh token"
                    break
                }
                catch {StopAll("Cannot access refresh token", 102)}
            }
            else {
                Log "no Refresh token, renewing."
                if (RenewRefreshToken -eq $true) {return $true}
            }
            $loop++
        } until ($refreshtoken)

        if ($loop -gt $maxloop) {
            StopAll("Cannot renew access token, loop higher than $maxloop.", 110)
        }
        
        $headersRefreshToken = @{}
        $headersRefreshToken.Add("Authorization", "Basic ZWRnZWNsaTplZGdlY2xpc2VjcmV0")
        $headersRefreshToken.Add("Accept", "application/json;charset=utf-8")
        $bodyRefreshToken = @{grant_type = 'refresh_token'; refresh_token = $refreshtoken}

        $accessTokenRequest = try {
            Invoke-WebRequest -Uri $tokenURL -Headers $headersRefreshToken -Method Post -Body $bodyRefreshToken -UseBasicParsing
            Log "Successfully renewed access token"
        }
        catch { $_.Exception.Response }

        if ($accessTokenRequest.StatusCode -eq "Unauthorized") {
            if (RenewRefreshToken -eq $true) {return $true}
        }
        $loop++
    } until ($accessTokenRequest.StatusCode -eq 200)

    $accessTokenJson = $accessTokenRequest.Content | ConvertFrom-Json

    try {
        Set-Content -Path $scriptPath/accesstoken -Value ("Bearer " + $accessTokenJson.access_token)
        Log "Successfully set access token"
        return $true
    }
    catch {
        StopAll ("Cannot write to Accesstoken file", 102)
    }
    StopAll("Here be dragons. (Renewing access token)", 666)
}

function GetContent {
    <#  

    .SYNOPSIS
    Gets the requested content from the Apigee API endpoint
    
    .DESCRIPTION
    Based on the settings set in the global Apigee variables, it will use the access token to get the required data from the Apigee API. 
    If it gets an 403, it will call the RenewAccessToken function and will keep trying to get the data until it succeeds or hits the max loop count.
    
    Once successfull, it passes the result back as PSObject. Any other situation will Catch/Stopall.

    #>

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
                    Log "Successfully retrieved access token"
                    break
                }
                catch {StopAll("Cannot access access token", 102)}
            }
            else {
                Log "no access token, renewing."
                RenewAccessToken
            }
            $loop++
        } until ($accessToken)

        $resultHeaders = @{}
        $resultHeaders.Add("Authorization", $accessToken)
        
        try {
            $result = Invoke-WebRequest -Uri $apiURL$apiQuery -Headers $resultHeaders -Body $apiVariables -UseBasicParsing
            Log "Successfully retrieved api data"
        }
        catch { 
            if ($_.Exception.Response.StatusCode -eq "Unauthorized") {
                RenewAccessToken
            }
            else {StopAll("Here be dragons. (Getting Content, " + $_.Exception.Response.StatusCode + " )", 666)}
        }
        $loop++       
    } until ($result.StatusCode -eq 200)

    return $result.Content | ConvertFrom-Json
}

function main {

    <#  

    .SYNOPSIS
    Main function of the script. Calls for data, prepares it for human readability and sends it to Splunk
    
    .DESCRIPTION
    Requests data from the GetContent function. It parses the data to get the headers and key/value information within each entry. 
    Each entry is then places in an array. This final array can be used in any kind of way.

    .NOTES
    
    #>

    param (
    )
    $startDate = Get-Date
    Log ("------ Starting Logging for $ScriptName on " + $startDate.ToShortDateString() + " at " + $startDate.ToShortTimeString() + " ------")    

    #Get data from the API
    $resultJson = GetContent

    #Setup main array for entries
    $arrResults = New-Object System.Collections.ArrayList

    #Check if any data was returned from the API
    if ($resultJson.results.series) {
        Log "Converting API result to readable list"
        $resultJson.results.series | % {
            $series = $_
            $_.values | % {
                $values = $_

                #Create object to be placed in array
                $ObjResult = New-Object PsObject
                $ObjResult.PsObject.TypeNames.Insert(0, 'ObjResult')
                    
                #Add headers to object
                $series.tags.PSObject.Properties | % {
                    $ObjResult | Add-Member -MemberType NoteProperty -Name $_.Name -Value $_.value
                }
                
                #Add key/values to Object
                for ($i = 0; $i -lt $series.columns.count; $i++) {
                    $ObjResult | Add-Member -MemberType NoteProperty -Name $series.columns[$i] -Value '' 
                    if ($_[$i]) {
                        switch ($_[$i].getType().Name) {
                            'datetime' {$ObjResult.($series.columns[$i]) = $values[$i]; break }
                            'string' { $ObjResult.($series.columns[$i]) = $values[$i]; break }
                            'Int32' { $ObjResult.($series.columns[$i]) = [int]$values[$i]; break }
                            'Int64' { $ObjResult.($series.columns[$i]) = [int]$values[$i]; break }
                            'Decimal' { $ObjResult.($series.columns[$i]) = [decimal]$values[$i]; break }
                            'Double' { $ObjResult.($series.columns[$i]) = [decimal]$values[$i]; break }
                        }
                    }
                }
                #Change time to specific layout.
                $ObjResult.time = ([datetime]$ObjResult.time).ToString("yyyy-MM-ddTHH:mm:ss.fffK")

                #Add Object to array
                [void]$arrResults.Add($ObjResult)
            }   
        }
        Write-Output $arrResults | ft
        Log "Successfully converted API results"
       
    }
    else {
        Log "No results found"
    }
    
    $stopDate = Get-Date
    $timespan = New-TimeSpan $startDate $stopDate
    Log ("------ Script Completion on " + $stopDate.ToShortDateString() + " at " + $stopDate.ToShortTimeString() + ". Duration: " + $timespan.TotalSeconds + " seconds ------`n")
}

Function Log($logText) {

    <#  

    .SYNOPSIS
    Log function, writes to log file in location defined in Global Variables
    
    .DESCRIPTION
    Timestamps entries and then writes to log location found in Global Variables.

    .EXAMPLE
    Log ("This happend.")
    #>

    if ($loggingEnabled -eq $true) {
        Try {
            $logEntry = (Get-Date -Format G) + " | " + $logText
            if ($loggingtoFile) {
                $logEntry | Out-File -Append -FilePath $logFile
            }
            if ($loggingToConsole) {
                Write-Host $logEntry
            }
        }
        Catch {Write-Warning "Unable to write to log location $logFile (101) | $logText"}
    }
}

# Error function
Function StopAll($stopText, $exitCode) {

    <#  

    .SYNOPSIS
    Gracefull exit function
    
    .DESCRIPTION
    Function to exit the script with an exit code defined by either the user or the script (-1). 
    It writes to the log with the error passed to the function and/or the message specified when calling this function

    .EXAMPLE
    StopAll("Exit message", exitcode)
    
    StopAll("Everything went well", 1)
    StopAll("The world is ending", 666)
    #>

    Log "---!!! Stopping execution. Reason: $stopText"
    If ($error.count -gt 0) {Log ("Last error: " + $error[0])}
    Write-Warning "---!!! Stopping execution. Reason: $stopText"
    $date = Get-Date
    Log ("------ Script Completion on " + $date.ToShortDateString() + " at " + $date.ToShortTimeString() + " ------")
    If ($exitCode) {Exit $exitCode}
    Else {Exit -1}
}

main
