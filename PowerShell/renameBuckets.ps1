$buckets = Get-ChildItem -Path "D:\Thawed\[bucket]"

$count = 1

foreach ($bucket in $buckets) {
    
    $newBucketName = $bucket.name.Split('_')[0] + "_" + $bucket.name.Split('_')[1] + "_" + $bucket.name.Split('_')[2] + "_" + $count
    Rename-Item $bucket.FullName $newBucketName
    
    $count++
}

