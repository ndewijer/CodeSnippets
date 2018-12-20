<#

.NAME
CycleSMPassword.ps1

.SYNOPSIS  
Cycles the secretvalue within a secret.
 
.DESCRIPTION 
Lambdafunction that will generate a new password for the secret calling this lambda function and replaces the old one.
 
.INPUTS 
None

.OUTPUTS 
None
 
.EXAMPLE 
C:\PS> CycleSMPassword.ps1 -arn -token -step

Exit Codes: 
  0 = success
101 - 0x80070065 = Unable to create log file
102 - 0x80070066 = Insufficient Rights
110 - 0x9008006E = Rotation not enabled

Author:
0.1 -11-12-2018 - Nick de Wijer

#>

#Requires -Modules @{ModuleName='AWSPowerShell.NetCore';ModuleVersion='3.3.390.0'}

function lambda_handler {
    param (
        #[string[]]$arn = $LambdaInput.SecretId, 
        [string]$arn = "arn:aws:secretsmanager:eu-west-1:825569476208:secret:secret_netwrix_Auditor2-e6hkS3",
        [string]$token = $LambdaInput.ClientRequestToken,
        [string]$step = $LambdaInput.Step
    )

    Log ("------ Starting Logging for " + $LambdaContext.FunctionName + " version " + $LambdaContext.FunctionVersion + " on " + $date.ToShortDateString() + " at " + $date.ToShortTimeString() + " ------")
    
    $secretData = Get-SECSecret -SecretId $arn
    
    if ($secretData.RotationEnabled -eq $false) {
        StopAll([string]::Format('Rotation for secret {0} is not enabled.', $secretData.Name), 100)
    }
    if ($secretData.VersionIdsToStages.Values -match $token) { 
        StopAll([string]::Format('Secret version {0} has no stage for rotation of secret {1}', $token, $secretData.Name), 111)
    }
    if ($secretData.VersionIdsToStages.Values -match "AWSCURRENT") {
        Log ([string]::Format('Secret version {0} has no stage for rotation of secret {1}', $token, $secretData.Name))
        exit 0
    }
    elseif ($secretData.VersionIdsToStages.Values -notmatch "AWSPENDING") {
        StopAll([string]::Format('Secret version {0} not set as AWSPENDING for rotation of secret {1}', $token, $secretData.Name), 112)
    }

    if ($step -eq "createSecret") {
        create_secret($secretData.Name, $arn, $token, $step)
    }
    elseif ($step -eq "setSecret") {
        set_secret($secretData.Name, $arn, $token, $step)
    }
    elseif ($step -eq "testSecret") {
        test_secret($secretData.Name, $arn, $token, $step)
    } 
    elseif ($step -eq "FinishSecret") {
        finish_secret($secretData.Name, $arn, $token, $step)
    }
    else {
        StopAll([string]::Format('Invalid step parameter {0} for secret {1}', $step, $secretData.Name), 114)
    }

    Log ("------ Function Completion on " + $date.ToShortDateString() + " at " + $date.ToShortTimeString() + " ------")
}

function create_secret {
    param (
        [string]$name,
        [string]$arn, 
        [string]$token,
        [string]$step
    )
    
    try {
        $currentsecretJSON = Get-SECSecretValue -SecretId $arn -VersionStage "AWSCURRENT"
    }
    catch {StopAll([string]::Format('createSecret: Cannot retrieve secret {0}.', $name), 114)}
    
    $secretobject = $currentsecretJSON | ConvertFrom-Json
    
    try {
        $newsecretvalue = Get-SECRandomPassword
    }
    catch {StopAll([string]::Format('createSecret: Cannot generate new password for secret {0}.', $name), 115)}
    
    $secretobject.secret = $newsecretvalue
    $newsecretJSON = $secretobject | ConvertTo-Json

    try {
        Update-SECSecret -SecretId $arn -SecretString $newsecretJSON
        Log([string]::Format("createSecret: Successfully put secret for ARN {0} and version {1}.", $name, $token))
    }
    catch {StopAll([string]::Format('createSecret: Cannot update secret {0}.', $name), 116)}
    
}

function set_secret {
    param (
        [string]$name,
        [string]$arn, 
        [string]$token,
        [string]$step
    )
    #todo
}

function test_secret {
    param (
        [string]$name,
        [string]$arn, 
        [string]$token,
        [string]$step
    )
    #todo
}

function finish_secret {
    param (
        [string]$name,
        [string]$arn, 
        [string]$token,
        [string]$step
    )
    
    $currentVersion = "none"

    try {
        $secretJSON = Get-SECSecret -SecretId $arn
    }
    catch {StopAll([string]::Format('finishSecret: Cannot retrieve secret {0}.', $name), 114)}

    $secretJSON.VersionIdsToStages | % {
        if ($secretJSON.VersionIdsToStages.Values -match "AWSCURRENT") {
            if ($secretJSON.VersionIdsToStages.Values -eq $token) {
                Log ([string]::Format('finishSecret: Version {0} already marked as AWSCURRENT for {1}', $secretJSON.VersionIdsToStages.Values, $name))
                exit
            }
            $currentVersion = $secretJSON.VersionIdsToStages.Values
        }
    }
    try {
        Update-SECSecretVersionStage -SecretId $arn -MoveToVersionId $token -RemoveFromVersionId $currentVersion
        Log ([string]::Format('finishSecret: Successfully set AWSCURRENT stage to version {0} for secret {1}.', $secretJSON.VersionIdsToStages.Values, $name))
    }
    catch {
        catch {StopAll([string]::Format('finishSecret: Cannot update secret version {0} from stage {1} to stage {2}.', $name, $secretJSON.VersionIdsToStages.Values, $token), 117)}
    } 

}

# Log function
Function Log($logText) {
    if ($LoggingEnabled -eq $true) {
        Try {(Get-Date -Format G) + "|" + $logText| write-host}
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

lambda_handler

