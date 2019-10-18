<#

.NAME
disable-old-keys.ps1

.SYNOPSIS  
Disables API keys not defined in SSM Parameter store
 
.DESCRIPTION 
Loads in defined environments, logs in to these accounts using credentials defined in the SSM Parameter store. 
It disables the API Key not defined in the SSM Parameter store.
 
.INPUTS 
None

.OUTPUTS 
None
 
.EXAMPLE 
C:\PS> disable-old-keys.ps1

Exit Codes: 
  0 = success
101 - 0x80070065 = File not Found
102 - 0x80070066 = Access Denied, filesystem
103 - 0x80070067 = Access Denied, AWS

Author:
1.0 - 24-09-2019 - Nick de Wijer

#>

# Global Variables 
$global:scriptName = $myInvocation.MyCommand.Name                                 #Get Scriptname
$global:LoggingEnabled = $true
$global:LoggingToConsole = $true
$global:LoggingtoFile = $false
#$global:LoggingFile = ${env:Temp} + "\" + $scriptName.Replace(".ps1", ".Logging")         #Set Windows location for Logging file based on script name in temp directory.
$global:LoggingFile = ${env:TMPDIR} + "\" + $scriptName.Replace(".ps1", ".Logging")         #Set OSX location for Logging file based on script name in temp directory.

$global:scriptPath = $PSScriptRoot

#AWS Variables

$userAccountAutomation = ""
$accessKeyAutomation = ""
$secretKeyAutomation = ""


$AWSEnv = @{
    "dev" = @{ 
        SSM    = "/envs/dev/" 
        region = "eu-central-1"
        User   = "cicd-dev"
    }
    "tst" = @{ 
        SSM    = "/envs/tst/" 
        region = "eu-west-1"
        User   = "cicd-test"
    }
    "prd" = @{ 
        SSM    = "/envs/prd/" 
        region = "eu-west-1"
        User   = "cicd-prd"
    }
}

# Import Libraries

# Import SnapIns and Modules
Import-Module AWSPowerShell


function main {
    param (
    )
    $startDate = Get-Date
    Logging ("------ Starting Logging for $ScriptName on " + $startDate.ToShortDateString() + " at " + $startDate.ToShortTimeString() + " ------")    

    #load in Automation account creds
    $autoCreds = New-AWSCredential  -AccessKey $accessKeyAutomation -SecretKey $secretKeyAutomation 


    Logging "check for connectivity to AWS, correct creds for Automation Account"
    try {
        $getautoident = Get-STSCallerIdentity -Credential $autoCreds
    }
    catch {
        StopAll("Invalid credentials to automation account", 103) 
    }

    
    if ($getautoident.Arn -match $userAccountAutomation) { Logging "Loggged into correct account" } else { StopAll("Incorrect user identity", 103) }
    Set-DefaultAWSRegion -Region "eu-west-1"


    foreach ($env in $AWSEnv.keys) {

        logging "Try to retrieve current credentials for environment $env"
        try {
            $AWSEnv.$env.Add("accesskey", (Get-SSMParameter -Credential $autoCreds -Name "$($AWSEnv.$env.ssm)access_key" -WithDecryption $true).Value)
            $AWSEnv.$env.Add("secretkey", (Get-SSMParameter -Credential $autoCreds -Name "$($AWSEnv.$env.ssm)secret_key" -WithDecryption $true).Value)   
        }
        catch {
            StopAll("Incorrect retreive credentials for $env from SSM Parameter store.", 103) 
        }

        $envCreds = New-AWSCredential -AccessKey $AWSEnv.$env.oldaccesskey -SecretKey $AWSEnv.$env.oldsecretkey

        Logging "check for connectivity to AWS, correct creds for $env account"
        try {
            $getautoident = Get-STSCallerIdentity -Credential $envCreds
        }
        catch {
            StopAll("Invalid credentials to $env account", 103) 
        }
        if ($getautoident.Arn -match $AWSEnv.$env.User) { Logging "Loggged into correct account ($env)" } else { StopAll("Incorrect user identity for account $env", 103) }
        
        logging "Getting IAM keys for user $($AWSEnv.$env.user)"

        try {
            $IAMKeys = Get-IAMAccessKey -Credential $envCreds -UserName $AWSEnv.$env.user 
        }
        catch {
            StopAll("Could not retreive IAM keys for user $($AWSEnv.$env.user)", 103) 
        }

        logging "Disabling any other keys than those defined in SSM Parameter store"
        
        foreach ($key in $IAMKeys) {
            if ($key.AccessKeyId -ne $AWSEnv.$env.accesskey) {
                
                try {
                    Update-IAMAccessKey -Credential $envCreds -UserName $AWSEnv.$env.user -AccessKeyId $key.AccessKeyId -Status Inactive  -Force
                }
                catch {
                    StopAll("Could not set IAM key $($key.AccessKeyId) to inactive.", 103) 
                }
            }
        }
    }

    $stopDate = Get-Date
    $timespan = New-TimeSpan $startDate $stopDate
    Logging ("------ Script Completion on " + $stopDate.ToShortDateString() + " at " + $stopDate.ToShortTimeString() + ". Duration: " + $timespan.TotalSeconds + " seconds ------`n")
}


Function Logging($LoggingText) {

    <#  

    .SYNOPSIS
    Log function, writes to Log file in location defined in Global Variables
    
    .DESCRIPTION
    Timestamps entries and then depending on enabled, writes to Log location found in Global Variables and/or Console.
    

    .EXAMPLE
    Logging ("This happend.")
    #>

    if ($LoggingEnabled -eq $true) {
        Try {
            $LoggingEntry = (Get-Date -Format G) + " | " + $LoggingText
            if ($LoggingtoFile) {
                $LoggingEntry | Out-File -Append -FilePath $LoggingFile
            }
            if ($LoggingToConsole) {
                Write-Host $LoggingEntry
            }
        }
        Catch { Write-Warning "Unable to write to Logging location $LoggingFile (101) | $LoggingText" }
    }
}

# Error function
Function StopAll($stopText, $exitCode) {

    <#  

    .SYNOPSIS
    Gracefull exit function
    
    .DESCRIPTION
    Function to exit the script with an exit code defined by either the user or the script (-1). 
    It writes to the Logging with the error passed to the function and/or the message specified when calling this function

    .EXAMPLE
    StopAll("Exit message", exitcode)
    
    StopAll("Everything went well", 1)
    StopAll("The world is ending", 666)
    #>

    Logging "---!!! Stopping execution. Reason: $stopText"
    If ($error.count -gt 0) { Logging ("Last error: " + $error[0]) }
    Write-Warning "---!!! Stopping execution. Reason: $stopText"
    $date = Get-Date
    Logging ("------ Script Completion on " + $date.ToShortDateString() + " at " + $date.ToShortTimeString() + " ------")
    If ($exitCode) { Exit $exitCode }
    Else { Exit -1 }
}
main
