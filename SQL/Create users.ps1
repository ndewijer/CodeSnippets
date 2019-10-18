$databaseServers = "a", "b", "c"
$accounts = "1", "2"

$databaseServers | % {
    $server = $_

    $accounts | % {
        $query = 
        "
USE [master]
GO

IF NOT EXISTS (SELECT name FROM [sys].[server_principals] WHERE name = N'$_')
Begin        
	CREATE LOGIN [$_] FROM WINDOWS WITH DEFAULT_DATABASE=[master], DEFAULT_LANGUAGE=[us_english];
	ALTER SERVER ROLE [dbcreator] ADD MEMBER [$_];
end
       "
        Invoke-Sqlcmd -Query $query -ServerInstance $server
    }
}
