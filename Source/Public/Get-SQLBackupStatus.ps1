Function Get-SQLBackupStatus {
    <#
    .SYNOPSIS
        Retrieve information about backups on a SQL Server(s).
    .PARAMETER Name
        Names or array of names for your SQL Servers
    .PARAMETER Threshold
        Determine if a job has failed to run.  A job is considered failed if it hasn't run in over a day, which will help you spot backups that have not run.  Threshold is in days.
    .INPUTS
        Text
        [Microsoft.ActiveDirectory.Management.ADComputer]
    .OUTPUTS
        [PSCustomObject]
    .EXAMPLE
        Get-SQLBackupStatus -Name SQL-AG-01
    .EXAMPLE
        Get-ADComputer -Filter {Name -like "SQL*"} | Get-SQLBackupStatus
        Get-ADComputer -Filter {Name -like "SQL*"} | Get-SQLBackupStatus -Threshold 2
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
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$true)]
        [Alias("ServerList","ComputerName")]
        [string[]]$Name,
        [int]$Threshold = 1
    )

    BEGIN {
        Write-Verbose "$(Get-Date): New-SQLBackupStatus starting..."

        $BKQuery = @"
SELECT bk.database_name AS Name,
	bk.recovery_model AS RecoveryModel,
	bk.backup_finish_date AS LastBackupDate,
	bk.Type,
	bk.backup_size AS LastBackupSize
FROM msdb.dbo.backupset AS bk 
INNER JOIN (
	SELECT database_name,
		MAX(backup_finish_date) AS LastBackupDate,
		Type
	FROM msdb.dbo.backupset
	GROUP BY database_name,Type
) AS bkmax
	ON bk.database_name = bkmax.database_name and
	bk.backup_finish_date = bkmax.LastBackupDate and
	bk.type = bkmax.type
"@
    }

    PROCESS {
        ForEach ($db in $Name)
        {
            Write-Verbose "$(Get-Date): Working on $db..."
            If (-not (Test-Connection ($db.Split("\")[0]) -Quiet -Count 2))
            {
                Write-Warning "$(Get-Date): Unable to ping $db, skipping server"
                Continue
            }
            $BaseName = $db.Split(".")[0]  #If FQDN was specified, get the hostname
            $Version = ([version](Invoke-Sqlquery -Instance $db -Database Master -Query "SELECT SERVERPROPERTY('productversion') AS [Version]").Version).Major
            $Databases = Invoke-SQLQuery -Instance $db -Database Master -Query "SELECT name,recovery_model_desc AS RecoveryModel FROM sys.databases WHERE name != 'tempdb' AND state = 0"
            $MirrorInfo = Invoke-SQLQuery -Instance $db -Database Master -Query "SELECT sys.name AS Name FROM sys.databases AS sys JOIN sys.database_mirroring AS mir ON sys.database_id = mir.database_id WHERE mir.mirroring_role = 2" | Select -ExpandProperty Name
            $Backup = Invoke-SQLQuery -Instance $db -Database Master -Query $BKQuery

            $AGInfo = @{}
            If ($Version -gt 10)
            {
                $AGInfo = Invoke-SQLQuery -Instance $db -Database Master -Query "SELECT adc.database_name AS Name,hadr.primary_replica AS [Primary] FROM sys.dm_hadr_availability_group_states AS hadr JOIN sys.availability_databases_cluster AS adc ON hadr.group_id = adc.group_id" | Group Name -AsHashTable
            }
            ForEach ($Database in $Databases)
            {
                If ($AGInfo)
                {
                    If ($AGInfo.ContainsKey($Database.Name) -and $AGInfo[$Database.Name].Primary -ne $BaseName)
                    {
                        #Database is in an AG, but not primary
                        Continue
                    }
                }
                If ($MirrorInfo -contains $Database.Name)
                {
                    #Database is part of a mirror, but is not primary
                    Continue
                }
                $LastFull = $Backup | Where { $_.Name -eq $Database.Name -and $_.Type -eq "D" }
                $LastDiff = $Backup | Where { $_.Name -eq $Database.Name -and $_.Type -eq "I" }
                If ($LastFull)
                {
                    $LastFull = $LastFull.LastBackupDate
                }
                If ($LastDiff)
                {
                    $LastDiff = $LastDiff.LastBackupDate
                }

                $LastBK = $null
                $LastBKDesc = $null
                $LastBK = $LastDiff
                If ($LastFull -gt $LastDiff)
                {
                    $LastBK = $LastFull
                    $LastBKDesc = "$(Get-Date $LastBK -format "g") (Full)"
                }
                ElseIf ($LastDiff)
                {
                    $LastBKDesc = "$(Get-Date $LastBK -format "g") (Diff)"
                }

                If ($LastBK)
                {
                    $DaysSince = (New-TimeSpan -Start $LastBK -End (Get-Date)).Days
                    $JobResult = "Succeeded"
                    If ($DaysSince -gt $Threshold)
                    {
                        $JobResult = "Failed"
                    }
                }
                Else
                {
                    $DaysSince = "Never"
                    $JobResult = ""
                }

                [PSCustomObject]@{
                    Server                   = $db
                    Database                 = If ($Database.Name.Length -gt 50) { $Database.Name.SubString(0,50) } Else { $Database.Name }  #Cutting the name length down to make the report look better
                    "Recovery Model"         = $Database.RecoveryModel
                    "Last Backup"            = $LastBKDesc
                    "Last T-Log Backup"      = $Backup | Where { $_.Name -eq $Database.Name -and $_.Type -eq "L" } | Select -ExpandProperty LastBackupDate
                    "Backup Size"            = Get-Size -Size ($Backup | Where { $_.Name -eq $Database.Name -and $_.LastBackupDate -eq $LastBK } | Select -ExpandProperty LastBackupSize)
                    "Days Since Last Backup" = $DaysSince
                    "Backup Status"          = $JobResult
            
                }
            }
        }
    }

    END {
        Write-Verbose "$(Get-Date): New-SQLBackupStatus completed"
    }
}
