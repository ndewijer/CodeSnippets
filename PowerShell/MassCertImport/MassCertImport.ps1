<#

.NAME
MassCertImport.ps1

.SYNOPSIS  
Grabs all certificates from a directory and imports them into the cert store
 
.DESCRIPTION 
User defined directory is scanned for .cer and .pfx cert files and imported. 
User also has to define in what scope (User or Computer) and if the private key is exportable, where relevant.

If there is a password text file in the directory of the PFX, the content will be used for all pfx files in the directory as password
If there is a identically named text file in the directory of the PFX, the content will be used for just that certificate as password

.INPUTS 
None

.OUTPUTS 
None
 
.EXAMPLE 
C:\PS> MassCertImport.ps1

Exit Codes: 
  0 = success
101 - 0x80070065 = Unable to create log file
102 - 0x80070066 = Insufficient Rights

Author:
1.0 - 22-12-2016 - Nick de Wijer

#>

# Global Variables 
$global:scriptName = $myInvocation.MyCommand.Name                            #Get Scriptname
$global:logFile = ${env:Temp} + "\" + $scriptName.Replace(".ps1", ".log")     #Set location for logging file based on script name in temp directory.
$global:loggingEnabled = $false                                              #Enable/Disable Logging                              
$global:certImportLevel = "localmachine"                                     #Define localmachine or CurrentUser to import new certs too
$global:certPath = "C:\Users\WIJE353636\OneDrive - Exact Group B.V\Documents\EIS Certs"  #Define path of certs
$global:privateKeyExport = $false                                            #Define if private key of imported cert is exportable

# Import Libaries

# Import SnapIns and Modules

# Main function
function main {

  # Start logging
  $date = Get-Date
  Log ("------ Starting Logging for $scriptName on " + $date.ToShortDateString() + " at " + $date.ToShortTimeString() + " ------")

  $certs = Get-ChildItem -Path $certPath -Recurse | Where-Object {$_.Attributes -notmatch 'directory'}

  foreach ($cert in $certs) {

    $certStore = $cert.Directory.Name
    
    
    if ($certStore -like "*root*") { $certStore = "AuthRoot" }
    elseif ($certStore -like "*personal*") { $certStore = "My" }
    elseif ($certStore -like "*intermediate*") { $certStore = "Ca" }
    else { $certStore = read-host ("Cannot determine certificate location for cert: " + $cert.BaseName) }
    
    if ($cert.Extension -eq ".cer") { 
      Import-Certificate -FilePath $cert.FullName -CertStoreLocation ("cert:\" + $certImportLevel + "\" + $certStore)
    }
    elseif ($cert.Extension -eq ".pfx") {
      if (Test-Path -Path ($cert.Directoryname + "\" + $cert.BaseName + ".txt")) { $pfxPass = get-content -path ($cert.Directoryname + "\" + $cert.BaseName + ".txt") }
      elseif (Test-Path -Path ($cert.Directoryname + "\password.txt")) { $pfxPass = get-content -Path ($cert.Directoryname + "\password.txt")}
      else { $pfxPass = $null }
           
      while ($pfxPass -eq $null) {$pfxPass = Read-Host ("Please supply password for PFX: " + $cert.BaseName) -AsSecureString}

      if ($privateKeyExport -eq $true) {
        Import-PfxCertificate -FilePath $cert.FullName -CertStoreLocation ("cert:\" + $certImportLevel + "\" + $certStore) -Password $pfxPass -Exportable 
      } 
      elseif ($privateKeyExport -eq $false) {
        Import-PfxCertificate -FilePath $cert.FullName -CertStoreLocation ("cert:\" + $certImportLevel + "\" + $certStore) -Password $pfxPass
      }
    }
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

