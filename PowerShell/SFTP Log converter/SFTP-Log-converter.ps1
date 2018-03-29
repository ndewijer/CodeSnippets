<#
.NAME
SFTP-Log-converter.ps1

.SYNOPSIS  
Convert WSFTP XML Logs to CSV

.DESCRIPTION 
Pulls most recent WSFTP log file to the work directory, it reads and compares to its previous version (if any). It then adds the newly found entries to the logfile.

.INPUTS 
WSFTP XML based log file.

.OUTPUTS 
CSV log file

.EXAMPLE 
C:\PS> AutoRDP.ps1

Exit Codes: 
  0 = success
101 - 0x80070065 = Unable to create log file
102 - 0x80070066 = Insufficient Rights
103 - 0x80070067 = Folder does not exist

Author:
1.2 - 12-09-2017 - Nick de Wijer

#>


# Global Variables 
$global:scriptName = $myInvocation.MyCommand.Name                             #Get Scriptname
$global:logFile = ${env:Temp} + "\" + $scriptName.Replace(".ps1",".log")      #Set location for logging file based on script name in temp directory.

$global:wsftpLogLocation = "F:\LOGS\FTP\Logs"                                 #Set location of WSFTP Log Directory
$global:workDirectory = "$PSScriptRoot\Workfolder"                            #Set location of script work directory
$global:splunkLogDirectory = "F:\LOGS\FTP\CSV-Logs"                           #Set location of file indexed by Splunk
$global:tempFileLocation = "$global:workDirectory\temp.txt"                   #Set location of temp file to save comparison
$global:deleteAfter = 7                                                       #Days to save old logs before deleting them.

$global:LoggingEnabled = $false                                               #Enable/Disable Logging

$global:newFile                                                               #Define new, to process, log file
$global:currentFile                                                           #Define current file in work directory
$global:oldFile                                                               #Define old log file to compare to

# Import Libraries

# Import SnapIns and Modules

Function main {
    
    #Start logging
    $startDate = Get-Date
    Log ("------ Starting Logging for $ScriptName on " + $startDate.ToShortDateString() + " at " + $startDate.ToShortTimeString() + " ------")

    #call main functions
    if($LoggingEnabled) {$measurePull = Measure-Command -Expression {pullAndCompare}; Log ("Log Pull and Compare completed in: " + $measurePull.TotalSeconds + " Seconds." )} else {pullAndCompare}
    if($LoggingEnabled) {$measureFormat = Measure-Command -Expression {formatLog}; Log ("Log format and write completed in: " + $measureFormat.TotalSeconds + " Seconds." )} else {formatLog}

    #clean up old logs
    deleteOldLogs

    #End logging
    $stopDate = Get-Date
    $timespan = New-TimeSpan $startDate $stopDate
    
    Log ("------ Script Completion on " + $stopDate.ToShortDateString() + " at " + $stopDate.ToShortTimeString() + ". Duration: " + $timespan.TotalSeconds + " seconds ------")
}

#pulls log. compares changes and saves changes to temporary file
function pullAndCompare {
    
    try {
        if ((Test-Path -PathType Container $global:wsftpLogLocation) -eq $false ) { StopAll("Folder does not exist: $global:wsftpLogLocation", 103) }
    } catch { StopAll("Cannot access $global:wsftpLogLocation.", 102) }

    try {
        if ((Test-Path -PathType Container $global:workDirectory) -eq $false ) { New-Item -ItemType Directory $global:workDirectory  }
    } catch { StopAll("Cannot create $global:workDirectory.", 102) }

    #finds newest log file in WSFTP Logging directory then defines names of the current and old files in the working directory
    $global:newFile = Get-ChildItem -Path $global:wsftpLogLocation | Sort-Object LastAccessTime -Descending | Select-Object -First 1
    $global:currentFile = $global:workDirectory + "\" + $global:newFile.name
    $global:oldFile = $global:workDirectory + "\" + $global:newFile.name + ".old"

    #if Old files exists, delete it. If no Oldfile exists, it is created. Required for comparison, later.
    if (Test-Path ($global:oldFile)) { Remove-Item $global:oldFile } else {Add-Content $global:oldFile "<?xml version=`"1.0`" encoding=`"utf-8`" ?>`r`n<log>`r`n</log>"}
    #If the current log exists, it is renamed to old to prepare the compare with the new log.
    if (Test-Path ($global:currentFile)) { Move-Item $global:currentFile ($global:currentFile + ".old") } 
    #The latest WSFTP log is copied over to the working directory
    Copy-Item $global:newFile.FullName $global:workDirectory
    
    #compare old and new log file for changes
    try {$compare = Compare-Object $(get-content $global:currentFile) $(get-content $global:oldFile)
    } Catch { StopAll("Cannot access either $global:currentFile or $global:oldFile.", 102) }
    
    
    #prepare the temporary storage file
    if (Test-Path $global:tempFileLocation) { Remove-Item $global:tempFileLocation}
    
    try {
        #Trims and writes the new entries found by the compare-object to a temporary file 
        Add-Content $global:tempFileLocation "<Logs>"
        $tempWriter = New-Object System.IO.StreamWriter $global:tempFileLocation
        $tempWriter.WriteLine("<logs>")
        $compare | ForEach-Object { $tempWriter.WriteLine(($_.InputObject).trim()) } 
        $tempWriter.WriteLine("</logs>")
    } Catch { StopAll("Cannot write to $global:tempFileLocation.", 102) }

    try {
        $tempWriter.Close()
        $tempWriter.Dispose()
    } Catch { StopAll("Cannot close file:$global:tempFileLocation.", 102) }
}

#function to add dashes to blank entries in log
function dashNull([string]$value) {  
    if (($value -eq $null) -or ($value -eq "")){
        $result = "-"
    } else {
        $result = $value
    }
    return $result
}

#pulls data from temporary file, processes the XML entries and converts them to CSV. Then appends to log file.
function formatLog {

    #pulls data from temp file. XML structured
    try {
        $doc = [XML] (Get-Content $global:tempFileLocation -ErrorAction Stop)
    } Catch { StopAll("Cannot access $fileLocation.", 102) }

    try {
        if ((Test-Path -PathType Container $global:splunkLogDirectory) -eq $false ) { New-Item -ItemType Directory $global:splunkLogDirectory  }
    } catch { StopAll("Cannot create $global:workDirectory.", 102) }

    $splunkLogLocation = $global:splunkLogDirectory + "\" + $global:newFile.BaseName + "-ftp.log"

    #tests if log file exists. Creates it and adds header if it does not.
    if ((Test-Path $splunkLogLocation) -eq $false) {
        try {
            Add-Content $splunkLogLocation "LogTime;logDescription;logService;logSessionid;logType;logSeverity;logUser;logLstnconnaddr;logCliconnaddr;logCmd;logParams;logAbsfile;logFilesize;logTranstime;logSguid"
        } Catch { StopAll("Cannot write to  $splunkLogLocation.", 102) }
    }

    #create data writer
    try {
        $logFileStream = New-Object System.IO.FileStream $splunkLogLocation ,'Append','Write','Read'
        $logWriter = New-Object System.IO.StreamWriter($logFileStream)

        #Converts the XML entries to CSV
        foreach ($entry in $doc.logs.entry){
        
            $logTime = [datetime]::ParseExact((dashNull $entry.log_time), "yyyyMMdd-HH:mm:ss", $null).ToString("dd-MM-yyyy HH:mm:ss")
            $logDescription = dashNull $entry.description.'#cdata-section' 
            $logService = dashNull $entry.service 
            $logSessionid = dashNull $entry.sessionid 
            $logType = dashNull $entry.type 
            $logSeverity = dashNull $entry.severity 
            $logUser = dashNull $entry.user 
            $logHost = dashNull $entry.host 
            $logLstnconnaddr = dashNull $entry.lstnconnaddr 
            $logCliconnaddr = dashNull $entry.cliconnaddr 
            $logCmd = dashNull $entry.cmd 
            $logParams = dashNull $entry.params.'#cdata-section'  
            $logAbsfile = dashNull $entry.absfile.'#cdata-section'  
            $logFilesize = dashNull $entry.filesize 
            $logTranstime = dashNull $entry.transtime 
            $logSguid = dashNull $entry.sguid 

            $string = $logTime + ";" + $logDescription + ";" + $logService + ";" + $logSessionid + ";" + $logType + ";" + $logSeverity + ";" + $logUser + ";" + $logHost + ";" + $logLstnconnaddr + ";" + $logCliconnaddr + ";" + $logCmd + ";" + $logParams + ";" + $logAbsfile + ";" + $logFilesize + ";" + $logTranstime + ";" + $logSguid

            $logWriter.WriteLine($string)
        }
    } Catch { StopAll("Cannot write to $logFileStream.", 102) }
    
    try {
        $logWriter.Close()
        $logWriter.Dispose()
        $logFileStream.Dispose()
    } Catch { StopAll("Cannot close file:$logFileStream.", 102) }
}

Function deleteOldLogs {
    Try {Get-ChildItem -Path $workDirectory -Recurse -Force | Where-Object { !$_.PSIsContainer -and $_.CreationTime -lt ((Get-Date).AddDays(-$deleteAfter)) } | Remove-Item -force}
    Catch{ StopAll("Unable to delete old logs.", 102)}
    
}

# Log function
Function Log($logText){
    if ($LoggingEnabled -eq $true){
        Try{(Get-Date -Format G) + "|" + $logText|Out-File -Append -FilePath $logFile}
        Catch{Write-Warning "Unable to write to log location $logFile (101) | $logText"}
    }
}

# Error function
Function StopAll($stopText, $exitCode){
       Log "---!!! Stopping execution. Reason: $stopText"
       If($error.count -gt 0){Log ("Last error: " + $error[0])}
       Write-Warning "---!!! Stopping execution. Reason: $stopText"
    $date = Get-Date
    Log ("------ Script Completion on " + $date.ToShortDateString() + " at " + $date.ToShortTimeString() + " ------")
    If($exitCode){Exit $exitCode}
    Else{Exit -1}
}

# Run main function!
main
