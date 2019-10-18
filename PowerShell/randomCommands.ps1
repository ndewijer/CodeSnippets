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