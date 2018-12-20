#Code I got from RE:Invent. Add windows activation status to SSM Compliance

$log = @()
try {
    if (Get-Module -ListAvailable -Name AWSPowershell) {
        Import-Module AWSPowershell
    }
    else { 
        Write-Host 'AWS Tools for Windows PowerShell not installed. Please install the latest version of the AWS Tools for Windows PowerShell and try again.'
        Write-Host 'Download location: https://aws.amazon.com/powershell/'
        Exit 255
    }
    $log += ('Checking Windows Activation Status')
    $LicenseNumber = (Get-CimInstance -ClassName SoftwareLicensingProduct | where {$_.PartialProductKey}).licensestatus
    $date = Get-Date
    $item = New-Object Amazon.SimpleSystemsManagement.Model.ComplianceItemEntry
    $item.Id = "LicenseStatus"
    $item.Severity = "High"
    $item.Status = "NON_COMPLIANT"
    $item.Title = "WindowsActivationStatus"
    if ($LicenseNumber -ne $null) {
        if ($LicenseNumber -eq 1) { 
            $item.Status = "COMPLIANT"
            $item.Severity = "INFORMATIONAL"
        } 
    }
    else { 
        $log += ('Activation Status Not Found')
    } 
    $log += "Compliance Status: $($item.Status.Value)"
    Write-SSMComplianceItem -ResourceId $env:AWS_SSM_INSTANCE_ID -Region $env:AWS_SSM_REGION_NAME -ComplianceType Custom:WindowsActivationStatus -ExecutionSummary_ExecutionTime $date -Item $item -ResourceType  "ManagedInstance"
    Write-Output $log
}
catch [Exception] {
    $msg = "Exception thrown Details: $_.Exception.Message, $log"
    Write-Error $msg
    exit -1
}
