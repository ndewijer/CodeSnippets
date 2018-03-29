Update-HostStorageCache
$MaxSize = (Get-PartitionSupportedSize -DriveLetter e).sizeMax
Resize-Partition -DriveLetter e -Size $MaxSize