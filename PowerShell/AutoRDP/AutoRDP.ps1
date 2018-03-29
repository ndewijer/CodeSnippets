<#
.NAME
AutoRDP.ps1

.SYNOPSIS  
Create a Remote Desktop Connection manager (rdg) file of the ExactOnline environment.
 
.DESCRIPTION 
Pulls all servers in AD and adds them to a newly created rdg in freshly created groups based on their naming convention.
 
.INPUTS 
None

.OUTPUTS 
fully functional Remote Desktop Connection manager file.
 
.EXAMPLE 
C:\PS> AutoRDP.ps1

Exit Codes: 
  0 = success
101 - 0x80070065 = Unable to create log file
102 - 0x80070066 = Insufficient Rights

Author:
1.0 - 22-12-2016 - Nick de Wijer

#>

# Global Variables 
$global:scriptName = $myInvocation.MyCommand.Name                            #Get Scriptname
$global:logFile = ${env:Temp} + "\" + $scriptName.Replace(".ps1",".log")     #Set location for logging file based on script name in temp directory.
$global:rootGroup = "Rackspace"                                              #Set top level group within RDG where groups can be automaticly created.

$global:fileLocation = "$PSScriptRoot\RDCAdmin.rdg"                          #Set location of RDG file
$global:LoggingEnabled = $false                                              #Enable/Disable Logging

# Import Libaries

# Import SnapIns and Modules
Import-Module ActiveDirectory


function main {

    #Start logging
    $date = Get-Date
    Log ("------ Starting Logging for $ScriptName on " + $date.ToShortDateString() + " at " + $date.ToShortTimeString() + " ------")

    #Setup basic XML structure required by Remote Desktop Connection Manager.
    basicRDPStructure $fileLocation

    #Get sites within forest
    $sites = (Get-ADForest).Domains | %{ Get-ADDomainController -Filter * -Server $_ } | select -ExpandProperty site -Unique

    #Create site groups
    $sites | %{ createGroup $fileLocation $_ $rootGroup }

    #Get all computer objects from ExactOnline forest.
    $servers = get-adcomputer -LDAPFilter "(&(objectCategory=computer)(operatingSystem=Windows Server*)(!serviceprincipalname=*MSClusterVirtualServer*)(!(userAccountControl:1.2.840.113556.1.4.803:=2)))" -Property name,dnshostname,description #| sort-object Name | select name,dnshostname,description
    
    #Create a server entry in the XML for each server found by the LDAP query
    foreach ($server in $servers) {
            createServer $fileLocation ($server.Name).toUpper() ($server.DNSHostName).toUpper() $null $server.description
    }
    
    #End logging
    $date = Get-Date
    Log ("------ Script Completion on " + $date.ToShortDateString() + " at " + $date.ToShortTimeString() + " ------")
}

function createServer([string]$fileLocation, [string]$name, [string]$fqdn, [string]$parent="", [string]$description="")
{   
    #Start logging inside function
    Log "Creating Server $name inside $parent"

    #Open XML and read content into memory
    try {
        $xml = [XML] (Get-Content $fileLocation -ErrorAction Stop)
    } Catch { StopAll("Cannot access $fileLocation.", 102) }

    #Regular Expression to recognize new naming convention: [6 Digit RackSpace device ID]-[2 Letter Country][2 Letter DC][2 Letter Role][2 Digit Device Number]
    $regex = "(\d{6})-(\w{2})([a-zA-Z0-9]{2})(\w{2})(\d{2})"
    $match = [regex]::Match($name,$regex)
    
    #If match successfull, split out servername into it's components for future use or exit function if no match.
    if ($match.Success) {
        $hostAssetId = $match.Captures.Groups[1].value
        $hostCountry = $match.Captures.Groups[2].value
        $hostDC = $match.Captures.Groups[3].value
        $hostType = $match.Captures.Groups[4].value
        $hostEnum = $match.Captures.Groups[5].value
    } else {
        log "Warning: Server does not match new naming convention. Will not be added."
        return
    }
    
    #Switch for DC Locations
    switch ($hostDC) {
        "dcA" {$parent = "DatacenterA"}
        "dcB" {$parent = "DatacenterB"}
    }

    #Switch for Server types
    switch ($hostType) {
        "DB" {$serverCategory = "Database Server"}
        "DC" {$serverCategory = "Domain Controller"}
        "WS" {$serverCategory = "Web Server"}
        #UNKNOWN, Will use host type.
        default { $serverCategory = $hostType }
    }

    #Try to find right group within the right DC based on previous two switches.
    $checkHostTypeFolder = $xml.SelectSingleNode("//properties[@name='$parent']/../group/properties[@name='$serverCategory']")
    
    #If unsuccessfull, a group will have to be created and afterwards, the XML reloaded into memory.
    if (!$checkHostTypeFolder) { 

        log "$serverCategory group does not yet exist under $parent."
        createGroup $fileLocation "$serverCategory" "$parent" 

        try {
            $xml = [XML] (Get-Content $fileLocation -ErrorAction Stop)
        } Catch { StopAll("Cannot access $fileLocation.", 102) }
    }

    #Select the right group within the right DC based on previous two switches.
    $node = $xml.SelectSingleNode("//properties[@name='$parent']/../group/properties[@name='$serverCategory']")

    #Create server object inside the XML
    $childName = $xml.CreateElement("name")
    $childNameVal = $xml.CreateTextNode($fqdn)
    $childName.AppendChild($childNameVal)

    $childDisp = $xml.CreateElement("displayName")
    $childDispVal = $xml.CreateTextNode($name)
    $childDisp.AppendChild($childDispVal)

    $childComm = $xml.CreateElement("comment")
    if ($description)
    {
        $childCommVal = $xml.CreateTextNode($description)    
        $childComm.AppendChild($childCommVal)
    }
    
    $childCred = $xml.CreateElement("logonCredentials")
    $childCred.SetAttribute("inherit", "FromParent")
    $childConn = $xml.CreateElement("connectionSettings")
    $childConn.SetAttribute("inherit", "FromParent")
    $childGate = $xml.CreateElement("gatewaySettings")
    $childGate.SetAttribute("inherit", "FromParent")
    $childRemo = $xml.CreateElement("remoteDesktop")
    $childRemo.SetAttribute("inherit", "FromParent")
    $childLoca = $xml.CreateElement("localResources")
    $childLoca.SetAttribute("inherit", "FromParent")
    $childSecu = $xml.CreateElement("securitySettings")
    $childSecu.SetAttribute("inherit", "FromParent")
    $childDiss = $xml.CreateElement("displaySettings")
    $childDiss.SetAttribute("inherit", "FromParent")

    $child = $xml.CreateElement("server")  
    $child.AppendChild($childName)
    $child.AppendChild($childDisp)
    $child.AppendChild($childComm)
    $child.AppendChild($childCred)
    $child.AppendChild($childConn)
    $child.AppendChild($childGate)
    $child.AppendChild($childRemo)
    $child.AppendChild($childLoca)
    $child.AppendChild($childSecu)
    $child.AppendChild($childDiss) 

    #Add new server node to parent node.
    $node.ParentNode.AppendChild($child)

    #Save XML
    $xml.Save($fileLocation)

    #End logging of Function
    log "sever $name has successfully been created"
}

function createGroup([string]$fileLocation, [string]$name, [string]$parent)
{   
     #Start logging inside function
    log "creating group $name under $parent"

    #Open XML and read content into memory
    try {
        $xml = [XML] (Get-Content $fileLocation -ErrorAction Stop)
    } Catch { StopAll("Cannot access $fileLocation.", 102) }

    #Select correct parent group to create group in
    $node = $xml.SelectSingleNode("//name[text()='$parent']")
    
    #if (!$node) { StopAll("Cannot find requested parent: '$parent' to add group under. Exiting.")}
    
    #If parent cannot be found, create parent group and reload XML
    if (!$node) {
        log "cannot find parent group: $parent, creating parent."
        createGroup $parent $rootGroup

         #Open XML and read content into memory
        try {
            $xml = [XML] (Get-Content $fileLocation -ErrorAction Stop)
        } Catch { StopAll("Cannot access $fileLocation.", 102) }
    }

    #Select parent group to make group under
    $node = $xml.SelectSingleNode("//name[text()='$parent']")
        
    $childName = $xml.CreateElement("name")
    $childNameVal = $xml.CreateTextNode($name)
    $childName.AppendChild($childNameVal)

    $childExpa = $xml.CreateElement("expanded")
    $childExpaVal = $xml.CreateTextNode("False")
    $childExpa.AppendChild($childExpaVal)
    $childComm = $xml.CreateElement("comment")
    $childCred = $xml.CreateElement("logonCredentials")
    $childCred.SetAttribute("inherit", "FromParent")
    $childConn = $xml.CreateElement("connectionSettings")
    $childConn.SetAttribute("inherit", "FromParent")
    $childGate = $xml.CreateElement("gatewaySettings")
    $childGate.SetAttribute("inherit", "FromParent")
    $childRemo = $xml.CreateElement("remoteDesktop")
    $childRemo.SetAttribute("inherit", "FromParent")
    $childLoca = $xml.CreateElement("localResources")
    $childLoca.SetAttribute("inherit", "FromParent")
    $childSecu = $xml.CreateElement("securitySettings")
    $childSecu.SetAttribute("inherit", "FromParent")
    $childDisp = $xml.CreateElement("displaySettings")
    $childDisp.SetAttribute("inherit", "FromParent")

    $child = $xml.CreateElement("properties")
    $child.SetAttribute("name", $name)
    
    $child.AppendChild($childName)  
    $child.AppendChild($childexpa)
    $child.AppendChild($childComm)
    $child.AppendChild($childCred)
    $child.AppendChild($childConn)
    $child.AppendChild($childGate)
    $child.AppendChild($childRemo)
    $child.AppendChild($childLoca)
    $child.AppendChild($childSecu)
    $child.AppendChild($childDisp) 

    $group = $xml.CreateElement("group")
    $group.AppendChild($child)

    $node.ParentNode.ParentNode.AppendChild($group)

    $xml.Save($fileLocation)
    
    #End logging function
    log "$name created"
}

function basicRDPStructure([string]$fileLocation)
{
    Log "Creating basic XML Structure"
    
    #delete document if exists
    if (Test-Path $fileLocation) { Remove-Item $fileLocation }
    
    # Create The Document
    $xmlWriter = New-Object System.XML.XmlTextWriter($fileLocation,$null)
 
    # Set The Formatting
    $xmlWriter.Formatting = "Indented"
    $xmlWriter.Indentation = "4"
    
    # Write the XML Decleration
    $xmlWriter.WriteStartDocument()

    # Write Root Element
    $xmlWriter.WriteStartElement("RDCMan")
    $xmlWriter.WriteAttributeString("schemaVersion", "1")
        
        #Write version
        $xmlWriter.WriteStartElement("version")
        $xmlWriter.WriteString("2.2")
        $xmlWriter.WriteEndElement()

        #setup file
        $xmlWriter.WriteStartElement("file")

            #setup properties
            $xmlWriter.WriteStartElement("properties")
    
                #write name
                $xmlWriter.WriteStartElement("name")
                $xmlWriter.WriteString("EOL")
                $xmlWriter.WriteEndElement()

                #write expanded
                $xmlWriter.WriteStartElement("expanded")
                $xmlWriter.WriteString("True")
                $xmlWriter.WriteEndElement()

                #write comment
                $xmlWriter.WriteStartElement("comment")
                $xmlWriter.WriteEndElement()

                    #write logonCredentials
                    $xmlWriter.WriteStartElement("logonCredentials")
                    $xmlWriter.WriteAttributeString("inherit", "None")

                    #write userName
                    $xmlWriter.WriteStartElement("userName")
                    $xmlWriter.WriteEndElement()

                    #write domain
                    $xmlWriter.WriteStartElement("domain")
                    $xmlWriter.WriteEndElement()

                    #write password
                    $xmlWriter.WriteStartElement("password")
                    $xmlWriter.WriteAttributeString("storeAsClearText", "False")
                    $xmlWriter.WriteEndElement()
    
                #close logonCredentials
                $xmlWriter.WriteEndElement()

                #write connectionSettings
                $xmlWriter.WriteStartElement("connectionSettings")
                $xmlWriter.WriteAttributeString("inherit", "FromParent")
                $xmlWriter.WriteEndElement()

                #write gatewaySettings
                $xmlWriter.WriteStartElement("gatewaySettings")
                $xmlWriter.WriteAttributeString("inherit", "FromParent")
                $xmlWriter.WriteEndElement()

                #write remoteDesktop
                $xmlWriter.WriteStartElement("remoteDesktop")
                $xmlWriter.WriteAttributeString("inherit", "FromParent")
                $xmlWriter.WriteEndElement()


                #write localResources 
                $xmlWriter.WriteStartElement("localResources")
                $xmlWriter.WriteAttributeString("inherit", "FromParent")
                
                    #Write audioRedirection
                    $xmlWriter.WriteStartElement("audioRedirection")
                    $xmlWriter.WriteString("0")
                    $xmlWriter.WriteEndElement()

                    #Write audioRedirectionQuality
                    $xmlWriter.WriteStartElement("audioRedirectionQuality")
                    $xmlWriter.WriteString("0")
                    $xmlWriter.WriteEndElement()

                    #Write audioCaptureRedirection
                    $xmlWriter.WriteStartElement("audioCaptureRedirection")
                    $xmlWriter.WriteString("0")
                    $xmlWriter.WriteEndElement()

                    #Write keyboardHook
                    $xmlWriter.WriteStartElement("keyboardHook")
                    $xmlWriter.WriteString("2")
                    $xmlWriter.WriteEndElement()

                    #Write redirectClipboard
                    $xmlWriter.WriteStartElement("redirectClipboard")
                    $xmlWriter.WriteString("True")
                    $xmlWriter.WriteEndElement()

                    #Write redirectDrives
                    $xmlWriter.WriteStartElement("redirectDrives")
                    $xmlWriter.WriteString("True")
                    $xmlWriter.WriteEndElement()

                    #Write redirectPorts
                    $xmlWriter.WriteStartElement("redirectPorts")
                    $xmlWriter.WriteString("False")
                    $xmlWriter.WriteEndElement()

                    #Write redirectPrinters
                    $xmlWriter.WriteStartElement("redirectPrinters")
                    $xmlWriter.WriteString("False")
                    $xmlWriter.WriteEndElement()

                    #Write redirectSmartCards
                    $xmlWriter.WriteStartElement("redirectSmartCards")
                    $xmlWriter.WriteString("False")
                    $xmlWriter.WriteEndElement()
               

                #close localResources
                $xmlWriter.WriteEndElement()

                #write securitySettings
                $xmlWriter.WriteStartElement("securitySettings")
                $xmlWriter.WriteAttributeString("inherit", "FromParent")
                $xmlWriter.WriteEndElement()

                #write displaySettings
                $xmlWriter.WriteStartElement("displaySettings")
                $xmlWriter.WriteAttributeString("inherit", "FromParent")
                $xmlWriter.WriteEndElement()

            #close properties
            $xmlWriter.WriteEndElement()

            #setup group
            $xmlWriter.WriteStartElement("group")

                #setup group
                $xmlWriter.WriteStartElement("properties")

                    #write name
                        $xmlWriter.WriteStartElement("name")
                        $xmlWriter.WriteString("Rackspace")
                        $xmlWriter.WriteEndElement()

                    #write expanded
                    $xmlWriter.WriteStartElement("expanded")
                    $xmlWriter.WriteString("True")
                    $xmlWriter.WriteEndElement()

                    #write comment
                    $xmlWriter.WriteStartElement("comment")
                    $xmlWriter.WriteEndElement()

                        #write logonCredentials
                        $xmlWriter.WriteStartElement("logonCredentials")
                        $xmlWriter.WriteAttributeString("inherit", "None")

                        #write userName
                        $xmlWriter.WriteStartElement("userName")
                        $xmlWriter.WriteEndElement()

                        #write domain
                        $xmlWriter.WriteStartElement("domain")
                        $xmlWriter.WriteEndElement()

                        #write password
                        $xmlWriter.WriteStartElement("password")
                        $xmlWriter.WriteAttributeString("storeAsClearText", "False")
                        $xmlWriter.WriteEndElement()
    
                    #close logonCredentials
                    $xmlWriter.WriteEndElement()

                    #write connectionSettings
                    $xmlWriter.WriteStartElement("connectionSettings")
                    $xmlWriter.WriteAttributeString("inherit", "FromParent")
                    $xmlWriter.WriteEndElement()

                    #write gatewaySettings
                    $xmlWriter.WriteStartElement("gatewaySettings")
                    $xmlWriter.WriteAttributeString("inherit", "FromParent")
                    $xmlWriter.WriteEndElement()

                    #write remoteDesktop
                    $xmlWriter.WriteStartElement("remoteDesktop")
                    $xmlWriter.WriteAttributeString("inherit", "FromParent")
                    $xmlWriter.WriteEndElement()


                    #write localResources 
                    $xmlWriter.WriteStartElement("localResources")
                    $xmlWriter.WriteAttributeString("inherit", "FromParent")
                    $xmlWriter.WriteEndElement()

                    #write securitySettings
                    $xmlWriter.WriteStartElement("securitySettings")
                    $xmlWriter.WriteAttributeString("inherit", "FromParent")
                    $xmlWriter.WriteEndElement()

                    #write displaySettings
                    $xmlWriter.WriteStartElement("displaySettings")
                    $xmlWriter.WriteAttributeString("inherit", "FromParent")
                    $xmlWriter.WriteEndElement()

                #close properties
                $xmlWriter.WriteEndElement()

            #close group
            $xmlWriter.WriteEndElement()

    #close file
    $xmlWriter.WriteEndElement()

    # Write close tag for root element and finish document
    $xmlWriter.WriteEndElement()
    $xmlWriter.WriteEndDocument()
    $xmlWriter.Finalize
    $xmlWriter.Flush()
    $xmlWriter.Close()

    Log "Basic XML Structure created and saved to $fileLocation"
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
Main