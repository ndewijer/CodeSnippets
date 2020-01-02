Reset-computermachinepassword / Test-ComputerSecureChannel -Repair

###

Test port with Test-NetConnection (TNC) on other side
$listener = [System.Net.Sockets.TcpListener]5666
$listener.Start();
$listener.Stop();

###

$cn = 'localhost'
([wmiclass]\\$cn\root\cimv2:win32_process).Create('powershell Enable-PSRemoting -Force')

###


Update-HostStorageCache
sleep 10
get-volume | ForEach-Object { 
    $max_partition = Get-PartitionSupportedSize -DriveLetter $_.DriveLetter
    $current_partition = Get-Partition -DriveLetter $_.DriveLetter
    if ( ($max_partition.SizeMax) / ($current_partition.Size) -gt 1.1) {
        Resize-Partition -DriveLetter $_.DriveLetter -Size $max_partition.SizeMax
    }
}

###

 
$computer = Get-WmiObject Win32_computersystem -EnableAllPrivileges;
$computer.AutomaticManagedPagefile = $false;
$computer.Put();
$CurrentPageFile = Get-WmiObject -Query "select * from Win32_PageFileSetting where name='c:\\pagefile.sys'";
$CurrentPageFile.delete();
Set-WMIInstance -Class Win32_PageFileSetting -Arguments @{name = "d:\pagefile.sys"; InitialSize = 0; MaximumSize = 0 };
 
