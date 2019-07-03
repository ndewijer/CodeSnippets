Update-HostStorageCache

sleep 10

get-volume | ForEach-Object { 

    $max_partition = Get-PartitionSupportedSize -DriveLetter $_.DriveLetter
    $current_partition = Get-Partition -DriveLetter $_.DriveLetter

    if ( ($max_partition.SizeMax) / ($current_partition.Size) -gt 1.1) {
        Resize-Partition -DriveLetter $_.DriveLetter -Size $max_partition.SizeMax
    }
}
