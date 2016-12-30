Function Get-SQLBackupFileName {
    <#
    .SYNOPSIS
        Simple script to list all databases, backup date and cooresponding backup file
    .PARAMETER Instance
        Name or names of the database instances you wish to query
    .INPUTS
        None
    .OUTPUTS
        [PSCustomObject]
    .EXAMPLE
        Get-SQLBackupFileName -Instance SQL-AG-01
    .EXAMPLE
        Get-SQLBackupFileName -Instance SQL-AG-01,SQL-AG-02,SQL-AG-03
    .NOTES
        Author:             Martin Pugh
        Twitter:            @thesurlyadm1n
        Spiceworks:         Martin9700
        Blog:               www.thesurlyadmin.com
      
        Changelog:
            1.0             Initial Release
    #>
    [CmdletBinding()]
    Param (
        [string[]]$Instance
    )

    $Query = @"
SELECT bs.database_name AS Name,
	bs.backup_finish_date AS LastBackup,
	bmf.physical_device_name AS BackupFile
FROM msdb.dbo.backupmediafamily AS bmf
JOIN msdb.dbo.backupset AS bs
	ON bmf.media_set_id = bs.media_set_id
WHERE bs.type = 'D'
ORDER BY bs.database_name, bs.backup_finish_date DESC
"@
    Invoke-SQLQuery -Instance $Instance -Database Master -Query $Query -NoInstance -MultiSubnetFailover
}