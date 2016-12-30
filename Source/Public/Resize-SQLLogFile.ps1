Function Resize-SQLLogFile {
    <#
    .SYNOPSIS
        Shrink log files on selected databases
    .DESCRIPTION
        Use this script to shrink log files for SQL databases.  You simply tell the script the name of the 
        SQL server and it will display a list of databases in a graphical window.  Select the databases you
        want to shrink and click on "OK".

        Fully supports AlwaysOn Availability Groups.

        If you run the script but the log file does not shrink much, you may need to run a full backup, since the log
        won't shrink until it's been backed up.  Check the LastBackup field in the graphical window.

    .PARAMETER Instance
        Server name and instance you want to query.  If you are using the DEFAULT instance, just put the server
        name, if using an Availability Group use the AG listener name, if there is a specific instance on the SQL
        server you want to query use SERVERNAME\INSTANCENAME.

    .PARAMETER Database
        The script will also shrink the database, if wanted.  Specify the -Database switch to trigger that action.  

    .INPUTS
        None
    .OUTPUTS
        ID           
        Database      
        FileSizeMB    
        LogSizeMB    
        LastBackup   
        NewFileSizeMB 
        NewLogSizeMB 

    .EXAMPLE
        Resize-SQLLogFile -Instance ag-01

        Script will display all databases on AG-01 (which is a SQL AlwaysOn Availability Group).  Select the databases
        you wish to shrink and click on OK.

    .EXAMPLE
        Resize-SQLLogFile -Instance AG-01 -Database

        Same as the previous example, but now will shrink the database file instead.

    .NOTES
        Author:             Martin Pugh
        Date:               1/1/2015
      
        Changelog:
            1/1/15          MLP - Initial Release
            2/18/16         MLP - Renamed to Resize-SQLLogFile
    #>
    #requires -Version 3
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [Alias("Server","ComputerName")]
        [string]$Instance,
        [switch]$Database
    )


    Write-Verbose "$(Get-Date): Resize-SQLLogFile begins"
    $DBsQuery = @"
WITH fs
AS
(
    SELECT database_id, name, type, size * 8.0 / 1024 AS size
    FROM sys.master_files
)
SELECT 
    db.name AS Name,
    db.database_id AS ID,
    CAST(ROUND((SELECT SUM(size) FROM fs WHERE type = 0 AND fs.database_id = db.database_id),2) AS DECIMAL(12,2)) AS FileSizeMB,
    CAST(ROUND((SELECT SUM(size) FROM fs WHERE type = 1 AND fs.database_id = db.database_id),2) AS DECIMAL(12,2)) AS LogSizeMB,
    (SELECT MAX(bus.backup_finish_date) FROM msdb.dbo.backupset AS bus JOIN fs ON bus.database_name = fs.name) AS LastBackup
FROM sys.databases AS db
"@

    Write-Verbose "$(Get-Date): Gathering database size and backup information"
    $DBs = Invoke-SQLQuery -Instance $Instance -Database Master -MultiSubnetFailover -Query $DBsQuery | Select ID,Name,FileSizeMB,LogSizeMB,LastBackup

    #Now display
    $Selected = @($DBs | Out-GridView -Title "Databases on $Instance - Select databases/logs you wish to shrink" -OutputMode Multiple)
    
    #Shrink them
    Write-Verbose "$(Get-Date): $($Selected.Count) databases/logs have been selected to be shrunk"
    ForEach ($Select in $Selected)
    {
        $Type = [int](-not $Database)
        $Name = (Invoke-SQLQuery -Instance $Instance -Database Master -MultiSubnetFailover -Query "Select name From sys.master_files Where database_id = '$($Select.ID)' And type = $Type").Name
        If ($Name)
        {
            Write-Verbose "$(Get-Date): Shrinking $($Select.Name) database/log file: $Name"
            $Result = Invoke-SQLQuery -Instance $Instance -Database $Select.Name -MultiSubnetFailover -Query "DBCC SHRINKFILE($Name,1)"
            If ($Result)
            {
                $BackupByDBQuery = @"
WITH fs
AS
(
    SELECT database_id, type, size * 8.0 / 1024 AS size
    FROM sys.master_files
)
SELECT 
    db.name,
    db.database_id,
    CAST(ROUND((SELECT SUM(size) FROM fs WHERE type = 0 AND fs.database_id = db.database_id),2) AS DECIMAL(12,2)) AS FileSizeMB,
    CAST(ROUND((SELECT SUM(size) FROM fs WHERE type = 1 AND fs.database_id = db.database_id),2) AS DECIMAL(12,2)) AS LogSizeMB
FROM sys.databases as db
WHERE name = '$($Select.Name)'
"@

                $NewSizes = Invoke-SQLQuery -Instance $Instance -Database Master -MultiSubnetFailover -Query $BackupByDBQuery
                $Select | Add-Member -MemberType NoteProperty -Name NewFileSizeMB -Value ($NewSizes.FileSizeMB)
                $Select | Add-Member -MemberType NoteProperty -Name NewLogSizeMB -Value ($NewSizes.LogSizeMB)
                Write-Output $Select
            }   
        }
        Else
        {
            Throw "Something went wrong getting logical name for $($Select.Database), aborting script"
        }
    }
    Write-Verbose "$(Get-Date): Resize-SQLLogFile completed"
}

