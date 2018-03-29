$buckets = Get-ChildItem -Path "D:\Thawed\[bucket]" -Depth 1 -Filter "db_*"


    foreach ($bucket in $buckets) {

    Write-Host $bucket.FullName

    while (@(Get-Job -State Running).Count -ge 15) {
        Start-Sleep -Seconds 2
    }

    Start-Job -Name thawBucket -scriptblock {  
        param($bucket)
         
         $cmd = "C:\Program Files\Splunk\bin\splunk.exe"
         $arg1 = "rebuild"
         $arg2 = $bucket.FullName

        & $cmd $arg1 $arg2
         } -ArgumentList $bucket
    }
