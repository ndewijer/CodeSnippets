<#

.NAME
change-api-keys.ps1

.SYNOPSIS  
Generates new API keys for defined users on defined accounts
 
.DESCRIPTION 
Loads in defined environments, logs in to these accounts using credentials defined in the SSM Parameter store. 
It deletes any inactive keys to make room and generates a new API key that is then put back into the SSM Parameter store.

.INPUTS 
None

.OUTPUTS 
None
 
.EXAMPLE 
C:\PS> change-api-keys.ps1

Exit Codes: 
  0 = success
101 - 0x80070065 = File not Found
102 - 0x80070066 = Access Denied, filesystem
103 - 0x80070067 = Access Denied, AWS



Author:
1.0 - 23-09-2019 - Nick de Wijer

#>

# Global Variables 
$global:scriptName = $myInvocation.MyCommand.Name                                 #Get Scriptname
$global:LoggingEnabled = $true
$global:LoggingToConsole = $true
$global:LoggingtoFile = $false
#chose your poison
#$global:LoggingFile = ${env:Temp} + "\" + $scriptName.Replace(".ps1", ".Logging")         #Set Windows location for Logging file based on script name in temp directory.
#$global:LoggingFile = ${env:TMPDIR} + "\" + $scriptName.Replace(".ps1", ".Logging")         #Set OSX location for Logging file based on script name in temp directory.

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
            $AWSEnv.$env.Add("oldaccesskey", (Get-SSMParameter -Credential $autoCreds -Name "$($AWSEnv.$env.ssm)access_key" -WithDecryption $true).Value)
            $AWSEnv.$env.Add("oldsecretkey", (Get-SSMParameter -Credential $autoCreds -Name "$($AWSEnv.$env.ssm)secret_key" -WithDecryption $true).Value)   
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
        Logging "$($IAMKeys.count) key(s) found"

        if ($IAMKeys.count -eq 2) {
            Logging "2 IAM keys already exist. Checking for inactive keys."

            if ($IAMKeys.Status -match "Inactive") {
                foreach ($key in $IAMKeys) {
                    if ($key.Status -eq "inactive") {
                        Logging "Inactive key found: $($key.AccessKeyId)"
                        Logging "Attempting to remove key"
                    
                        try {
                            Remove-IAMAccessKey -Credential $envCreds -UserName $AWSEnv.$env.user -AccessKeyId $key.AccessKeyId  -Force
                        }
                        catch {
                            StopAll("Could not remove inactive key: $($key.AccessKeyId)", 103) 
                        }
                    }
                }
            }
            else {
                logging "No inactive keys to delete. Skipping $env."
                continue
            }
        }
        
        Logging "Generating new IAM Key"

        try {
            $newkey = New-IAMAccessKey -Credential $envCreds -UserName $AWSEnv.$env.user
            sleep 10 # Wait period to prevent race condition
        }
        catch {
            StopAll("Could not generate new IAM key for user $($AWSEnv.$env.user)", 103) 
        }

        Logging "New key generated. Confirming validity"

        $envCredsNew = New-AWSCredential -AccessKey $newkey.AccessKeyId -SecretKey $newkey.SecretAccessKey

        Logging "check for connectivity to AWS, correct creds for $env account"
        try {
            $getautoident = Get-STSCallerIdentity -Credential $envCredsNew
        }
        catch {
            StopAll("Invalid credentials to $env account", 103) 
        }
        if ($getautoident.Arn -match $AWSEnv.$env.User) { Logging "Loggged into correct account ($env)" } else { StopAll("Incorrect user identity for account $env", 103) }
        
        $AWSEnv.$env.Add("newaccesskey", $newkey.AccessKeyId)
        $AWSEnv.$env.Add("newsecretkey", $newkey.SecretAccessKey)
    
        Logging "Credentials confirmed, writing new keys to SSM Parameter store."
        try {
            Write-SSMParameter -Credential $autoCreds -Name "$($AWSEnv.$env.ssm)access_key" -Value $AWSEnv.$env.newaccesskey -Type "SecureString" -Overwrite $true
            Write-SSMParameter -Credential $autoCreds -Name "$($AWSEnv.$env.ssm)secret_key" -Value $AWSEnv.$env.newsecretkey -Type "SecureString" -Overwrite $true

        }
        catch {
            Logging "Unable to write keys to SSM Parameter store. Deleting new key."
            
            try {
                Remove-IAMAccessKey -Credential $envCreds -UserName $AWSEnv.$env.user -AccessKeyId $newkey.AccessKeyId  -Force
                StopAll("Key deleted from IAM user $($AWSEnv.$env.user) after failing to write to SSM Parameter store")
            }
            catch {
                StopAll("Unable to delete new key: $($newkey.AccessKeyId) after failing to write to SSM Parameter store.", 103) 
            }
        }

        $file = "~/Desktop/credentials.txt"

        Add-Content $file ("[ci-$Env]")
        Add-Content $file ("#aws_access_key_id = $($AWSEnv.$env.oldaccesskey) OLD")
        Add-Content $file ("#aws_secret_access_key = $($AWSEnv.$env.oldsecretkey) OLD")
        Add-Content $file ("aws_access_key_id = $($AWSEnv.$env.newaccesskey)")
        Add-Content $file ("aws_secret_access_key = $($AWSEnv.$env.newsecretkey)")
        Add-Content $file ""
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
