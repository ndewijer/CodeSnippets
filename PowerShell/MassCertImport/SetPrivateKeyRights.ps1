<#

.NAME
SetPrivateKeyRights.ps1

.SYNOPSIS  
Matches certificate to ad account and adds account with defined rights to the private key
 
.DESCRIPTION 
Using the search string and account list defined within the script, it modifies the private key of any matching certificate with the relevant user account.
 
.INPUTS 
None

.OUTPUTS 
None
 
.EXAMPLE 
C:\PS> SetPrivateKeyRights.ps1

Exit Codes: 
  0 = success
101 - 0x80070065 = Unable to create log file
102 - 0x80070066 = Insufficient Rights

Author:
1.0 - 28-11-2017 - Nick de Wijer

#>

# Global Variables 
$global:scriptName = $myInvocation.MyCommand.Name                            #Get Scriptname
$global:logFile = ${env:Temp} + "\" + $scriptName.Replace(".ps1", ".log")     #Set location for logging file based on script name in temp directory.
$global:LoggingEnabled = $false                                              #Enable/Disable Logging                              

# Import Libaries

# Import SnapIns and Modules

# Main function
function main {

  # Start logging
  $date = Get-Date
  Log ("------ Starting Logging for $scriptName on " + $date.ToShortDateString() + " at " + $date.ToShortTimeString() + " ------")

  #Define worker process accounts
  $accounts = @{
    'NL' = 'xx';
    'BE' = 'xx';
    'UK' = 'xx';
    'FR' = 'xx';
    'ES' = 'xx';
    'DE' = 'xx';
    'US' = 'xx';
  }

  $certSubject = ""

  #Define all certs in the personal computer store that matches the like
  $Certs = Get-ChildItem -path cert:\LocalMachine\My | Where-Object {$_.Subject -like $certSubject}
  
  foreach ($Cert in $Certs) {
  
    #get imported certificate object from store
    $Certificate = Get-Item "Cert:\LocalMachine\my\$($Cert.Thumbprint)"
    
    #link country and worker process account
    $Certificate.Subject -match '\((\w{2})\)$'
    $country = $Matches[1]
    $account = $accounts."$country"
  
    try {
      #read certificate
      $certGUID = $Certificate.PrivateKey.CspKeyContainerInfo.UniqueKeyContainerName
      $certFile = Get-Item -path "$ENV:ProgramData\Microsoft\Crypto\RSA\MachineKeys\$certGUID"
      $certFileKeyAcl = (Get-Item -Path $certFile.FullName).GetAccessControl("Access") 
    }
    catch { StopAll("Cannot access $certFile.", 102) }
    
    try {
      #defines and sets permisisons on private key
      $permission = $account,"FullControl","Allow" 
      $accessRule = new-object System.Security.AccessControl.FileSystemAccessRule $permission 
      $certFileKeyAcl.AddAccessRule($accessRule) 
      Set-Acl $certFile.FullName $certFileKeyAcl 
    }
    catch { StopAll("Cannot modify $certFile.", 102) }
  }

  # End logging
  $date = Get-Date
  Log ("------ Script Completion on " + $date.ToShortDateString() + " at " + $date.ToShortTimeString() + " ------")
}

# Log function
Function Log($logText) {
  if ($LoggingEnabled -eq $true) {
    Try {(Get-Date -Format G) + "|" + $logText|Out-File -Append -FilePath $logFile}
    Catch {Write-Warning "Unable to write to log location $logFile (101) | $logText"}
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

# Run main function!
Main