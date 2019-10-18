$regions = @{ }
$regions.Add('1', 'eu-west-1')
$regions.Add('2', 'eu-central-1')
$regions.Add('3', 'eu-west-1')

foreach ($region in $regions) {
  
    $awsauth = @{
        Credential = (Use-STSRole -RoleArn "arn:aws:iam::xxx:role/xxxRole" -RoleSessionName "xxx").Credentials
        Region     = $regions[$key]
    }

    $instances = Get-EC2Instance @awsauth

    $arrInstances = New-Object System.Collections.ArrayList

    foreach ($instance in $instances.Instances) {
        $ObjInstances = New-Object psobject
        $ObjInstances | Add-Member -MemberType NoteProperty -Name "InstanceID" -Value "" -Force
        $ObjInstances | Add-Member -MemberType NoteProperty -Name "Hostname" -Value "" -Force
        $ObjInstances | Add-Member -MemberType NoteProperty -Name "OS" -Value "" -Force
        $ObjInstances | Add-Member -MemberType NoteProperty -Name "InstanceType" -Value "" -Force
        $ObjInstances | Add-Member -MemberType NoteProperty -Name "PrimaryIP" -Value "" -Force
        $ObjInstances | Add-Member -MemberType NoteProperty -Name "SecurityGroups" -Value "" -Force
        $ObjInstances | Add-Member -MemberType NoteProperty -Name "VPC" -Value "" -Force
        $ObjInstances | Add-Member -MemberType NoteProperty -Name "Subnet" -Value "" -Force

        $ObjInstances.InstanceID = $instance.InstanceId
        $ObjInstances.InstanceType = $instance.InstanceType
        $ObjInstances.PrimaryIP = $instance.PrivateIpAddress
        $ObjInstances.SecurityGroups = $instance.SecurityGroups


        #Call Systemmanager for Hostname
        $SSM = Get-SSMInstanceInformation @awsauth -InstanceInformationFilterList @{Key = "InstanceIds"; ValueSet = "" + $instance.InstanceId + "" }
        $ObjInstances.Hostname = $ssm.ComputerName
        $ObjInstances.OS = $ssm.PlatformName

        #Call for VPC info
        $VPC = Get-EC2Vpc @awsauth -VpcId $instance.VpcId
        $ObjInstances.VPC = ($VPC.Tags | Where-Object { $_.Key -eq 'Name' }).value

        #Call for Subnet info
        $Subnet = Get-EC2Subnet @awsauth -SubnetId $instance.SubnetId
        $ObjInstances.Subnet = ($Subnet.Tags | Where-Object { $_.Key -eq 'Name' }).value

        [void]$arrInstances.Add($ObjInstances)
    }

    return $arrInstances
}