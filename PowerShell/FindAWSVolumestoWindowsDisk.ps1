#slightly modified version of powershell on https://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/ec2-windows-volumes.html#windows-list-disks
function Get-EC2InstanceMetadata
{
	param([string]$Path)
	(Invoke-WebRequest -Uri "http://169.254.169.254/latest/$Path").Content 
}

function Convert-SCSITargetIdToDeviceName
{
    param([int]$SCSITargetId)
	If ($SCSITargetId -eq 0) {
		return "/dev/sda1"
	}
	$deviceName = "xvd"
	If ($SCSITargetId -gt 25) {
		$deviceName += [char](0x60 + [int]($SCSITargetId / 26))
	}
	$deviceName += [char](0x61 + $SCSITargetId % 26)
	return $deviceName
}

Try {
	$InstanceId = Get-EC2InstanceMetadata "meta-data/instance-id"
	$AZ = Get-EC2InstanceMetadata "meta-data/placement/availability-zone"
	$Region = $AZ.Remove($AZ.Length - 1)
	$BlockDeviceMappings = (Get-EC2Instance -Region $Region -Instance $InstanceId).Instances.BlockDeviceMappings
	$VirtualDeviceMap = @{}
	(Get-EC2InstanceMetadata "meta-data/block-device-mapping").Split("`n") | ForEach-Object {
		$VirtualDevice = $_
		$BlockDeviceName = Get-EC2InstanceMetadata "meta-data/block-device-mapping/$VirtualDevice"
		$VirtualDeviceMap[$BlockDeviceName] = $VirtualDevice
		$VirtualDeviceMap[$VirtualDevice] = $BlockDeviceName
	}
}
Catch {
	Write-Host "Could not access the AWS API, therefore, VolumeId is not available. 
	Verify that you provided your access keys." -ForegroundColor Yellow
}

Get-WmiObject -Class Win32_DiskDrive | ForEach-Object {
    $DiskDrive = $_
	$Volumes = Get-WmiObject -Query "ASSOCIATORS OF {Win32_DiskDrive.DeviceID='$($DiskDrive.DeviceID)'} WHERE AssocClass=Win32_DiskDriveToDiskPartition" | ForEach-Object {
		$DiskPartition = $_
		Get-WmiObject -Query "ASSOCIATORS OF {Win32_DiskPartition.DeviceID='$($DiskPartition.DeviceID)'} WHERE AssocClass=Win32_LogicalDiskToPartition"
	}
	If ($DiskDrive.PNPDeviceID -like "*PROD_PVDISK*") {
		$BlockDeviceName = Convert-SCSITargetIdToDeviceName($DiskDrive.SCSITargetId)
        $BlockDeviceName = "/dev/" + $BlockDeviceName
		$BlockDevice = $BlockDeviceMappings | Where-Object { $_.DeviceName -eq ($BlockDeviceName) }
		$VirtualDevice = If ($VirtualDeviceMap.ContainsKey($BlockDeviceName)) { $VirtualDeviceMap[$BlockDeviceName] } Else { $null }
	} ElseIf ($DiskDrive.PNPDeviceID -like "*PROD_AMAZON_EC2_NVME*") {
		$BlockDeviceName = Get-EC2InstanceMetadata "meta-data/block-device-mapping/ephemeral$($DiskDrive.SCSIPort - 2)"
		$BlockDevice = $null
		$VirtualDevice = If ($VirtualDeviceMap.ContainsKey($BlockDeviceName)) { $VirtualDeviceMap[$BlockDeviceName] } Else { $null }
	} Else {
		$BlockDeviceName = $null
		$BlockDevice = $null
		$VirtualDevice = $null

	}
	New-Object PSObject -Property @{
		Disk = $DiskDrive.Index;
		Partitions = $DiskDrive.Partitions;
		DriveLetter = If ($Volumes -eq $null) { "N/A" } Else { $Volumes.DeviceID };
		EbsVolumeId = If ($BlockDevice -eq $null) { "N/A" } Else { $BlockDevice.Ebs.VolumeId };
		Device = If ($BlockDeviceName -eq $null) { "N/A" } Else { $BlockDeviceName };
		VirtualDevice = If ($VirtualDevice -eq $null) { "N/A" } Else { $VirtualDevice };
		VolumeName = If ($Volumes -eq $null) { "N/A" } Else { $Volumes.VolumeName };
		AWSVolumeName = If ($BlockDevice -eq $null) { "N/A" } Else { (Get-EC2Volume -VolumeId $BlockDevice.Ebs.VolumeId).Tags.Value };
	}
} | Sort-Object Disk | Format-Table -AutoSize -Property Disk, Partitions, DriveLetter, EbsVolumeId, Device, VirtualDevice, VolumeName, AWSVolumeName
