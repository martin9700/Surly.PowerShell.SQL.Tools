Function Get-Size {
    Param (
        [float]$Size
    )

    If ($Size -ge 1000000000)
    {
        Write-Output ("{0:N2} GB" -f ($Size / 1gb))
    }
    ElseIf ($Size -gt 0)
    {
        Write-Output ("{0:N2} MB" -f ($Size / 1mb))
    }
    Else
    {
        Write-Output $null
    }
}
Function Get-SQLDate {
    Param (
        [int]$Date,
        [int]$Time
    )

    $RunDate = $Date.ToString()
    $RunTime = $Time.ToString().PadLeft(6,"0")
    Return Get-Date ("$($RunDate.SubString(4,2))/$($RunDate.SubString(6,2))/$($RunDate.Substring(0,4)) $($RunTime.SubString(0,2)):$($RunTime.SubString(2,2)):$($RunTime.SubString(4,2))")
}
Function Get-SQLTime {
    Param (
        [int]$Time
    )

    $Duration = $Time.ToString().PadLeft(6,"0")
    Return New-TimeSpan -Hours $Duration.SubString(0,2) -Minutes $Duration.SubString(2,2) -Seconds $Duration.SubString(4,2)
}
Function ValidateAGClusterObject {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true)]
        [object[]]$InputObject
    )

    BEGIN {
        $ValidatePropertySet = "AvailabilityGroup","AvailabilityDatabases","ListenerDNSName","AvailabilityGroupID"
        Write-Verbose "$(Get-Date): Validating object..."
    }

    PROCESS {
        ForEach ($AGObject in $InputObject)
        {
            $Properties = $AGObject | Get-Member -MemberType NoteProperty | Select -ExpandProperty Name
            If (@(Compare-Object -ReferenceObject $ValidatePropertySet -DifferenceObject $Properties | Where SideIndicator -eq "<=").Count)
            {
                Write-Error "Input object did not contain required properties, you must use Get-AGCluster to pipe into this function"
                Exit 999
            }
        }
    }
}
Function Get-AGCluster
{
    <#
    .SYNOPSIS
        Get very basic Availability Group cluster information

    .DESCRIPTION
        Script will give you some basic AG cluster information, such as what is the primary replica,
        what databases are in the AG, listener configuration, and health of the AG.

    .PARAMETER ComputerName
        Specify one node in the AG cluster

    .PARAMETER AGListener
        Specify the Availability Group you want to query by using the Listener DNS name.  

    .INPUTS
        None

    .OUTPUTS
        [PSCustomObject]
            Name                                   Name of the AG 
            PrimaryReplicaServerName               Server that is the primary in the AG
            AvailabilityReplicas                   Names of all the servers in the AG
            AvailabilityDatabases                  Names of all of the databases currently added to the AG
            HealthState                            Simple state information of the health of the AG
            Listeners                              IP addresses, Ports and networks monitored that the AG is configured for

    .EXAMPLE
        Import-Module PS.SQL
        Get-AGCluster -ComputerName SQL-AG-01

        Get basic information about all of the AG's on SQL-AG-01 cluster

        AvailabilityGroup        : ag1
        PrimaryReplicaServerName : SQL-AG-01
        AvailabilityReplicas     : {SQL-AG-01, SQL-AG-02, SQL-AG-03}
        AvailabilityDatabases    : {TestAGDatabase, TestAGDatabase10, TestAGDatabase70}
        Listeners                : {@{ip_address=192.168.4.50; port=1433; network_subnet_ip=192.168.4.0; network_subnet_ipv4_mask=255.255.255.0}, @{ip_address=192.168.6.50; port=1433; network_subnet_ip=192.168.6.0; network_subnet_ipv4_mask=255.255.255.0}}
        HealthState              : HEALTHY

    .NOTES
        Author:             Martin Pugh
        Date:               12/16/14
      
        Changelog:
            12/16/14        MLP - Initial Release
            12/20/16        MLP - Complete rewrite, now uses SQL queries.  Added AvailabilityGroup to query
            2/19/16         MLP - Added to PS.SQL
            3/15/16         MLP - Fixed position settings
            5/11/16         MLP - Added PSTypeName to object
            5/12/16         MLP - Eliminated AGListener and renamed ComputerName to Name. Script now detects if it's attached to a AG or computername and filters output accordingly.
    #>
    #requires -Version 3.0

    [CmdletBinding()]
    [OutputType("SQL.AvailabilityGroup.Object")]
    Param (
        [Parameter(Mandatory=$true,
            Position=0)]
        [Alias("ComputerName")]
        [string[]]$Name
    )

    Write-Verbose "$(Get-Date): Get-AGCluster started"

    $AGs = ForEach ($Instance in $Name)
    {
        Write-Verbose "Retrieving Availability Group information from $Instance..."
        Try {
            $AGInfo = Invoke-SQLQuery -Instance $Instance -Database Master -MultiSubnetFailover -Query "SELECT agc.name,ags.primary_replica FROM sys.availability_groups_cluster AS agc JOIN sys.dm_hadr_availability_group_states AS ags ON agc.group_id = ags.group_id" -ErrorAction Stop
        }
        Catch {
            Write-Error "Unable to connect to $Instance because: $_"
            Continue
        }
        $AGNames = $AGInfo | Select -ExpandProperty Name

        #Check if this is an AG or computer name that we've connected to
        If ($AGNames -contains $Instance)
        {
            $AGInfo = $AGInfo | Where Name -eq $Instance
        }
        Write-Output $AGInfo
    }

    If ($AGs)
    {
        ForEach ($AGName in $AGs)
        {
            Write-Verbose "$(Get-Date): Retrieving information for $($AGName.Name)..."
            $AG = Invoke-SQLQuery -Instance $AGName.primary_replica -Database Master -MultiSubnetFailover -Query "SELECT ag.name,ag.group_id,ag_state.primary_replica,ag_state.synchronization_health_desc FROM sys.availability_groups_cluster AS ag JOIN sys.dm_hadr_availability_group_states AS ag_state ON ag.group_id = ag_state.group_id WHERE name = '$($AGName.Name)'" 
            $Nodes = Invoke-SQLQuery -Instance $AGName.primary_replica -Database Master -MultiSubnetFailover -Query "SELECT replica_server_name,availability_mode_desc FROM sys.availability_replicas WHERE group_id = '$($AG.group_id)'"
            [PSCustomObject]@{
                PSTypeName               = "SQL.AvailabilityGroup.Object"
                AvailabilityGroup        = $AG.Name
                AvailabilityGroupID      = $AG.group_id
                PrimaryReplicaServerName = $AG.Primary_replica
                AvailabilityReplicas     = @($Nodes | Select -ExpandProperty replica_server_name)
                SynchronousNodes         = @($Nodes | Where availability_mode_desc -eq "SYNCHRONOUS_COMMIT" | Select -ExpandProperty replica_server_name)
                ASynchronousNodes        = @($Nodes | Where availability_mode_desc -eq "ASYNCHRONOUS_COMMIT" | Select -ExpandProperty replica_server_name)
                AvailabilityDatabases    = @(Invoke-SQLQuery -Instance $AGName.primary_replica -Database Master -MultiSubnetFailover -Query "SELECT database_name FROM sys.availability_databases_cluster WHERE group_id = '$($AG.group_id)'" | Select -ExpandProperty database_name)
                ListenerDNSName          = @(Invoke-SQLQuery -Instance $AGName.primary_replica -Database Master -MultiSubnetFailover -Query "SELECT dns_name FROM sys.availability_group_listeners WHERE group_id ='$($AG.group_id)'" | Select -ExpandProperty dns_name)
                Listeners                = @(Invoke-SQLQuery -Instance $AGName.primary_replica -Database Master -MultiSubnetFailover -Query "SELECT list.port,list_detail.ip_address,list_detail.network_subnet_ip,list_detail.network_subnet_ipv4_mask FROM sys.availability_group_listeners AS list JOIN sys.availability_group_listener_ip_addresses AS list_detail ON list.listener_id = list_detail.listener_id WHERE list.group_id ='$($AG.group_id)'" | Select ip_address,port,network_subnet_ip,network_subnet_ipv4_mask)
                HealthState              = $AG.synchronization_health_desc 
            }
        }
    }
    Else
    {
        Write-Verbose "Unable to find any Availability Group Information on the servers specified"
    }
    Write-Verbose "$(Get-Date): Get-AGCluster finished"
}
Function Get-AGDatabaseState
{
    <#
    .SYNOPSIS
        Script will retrieve information about every database in the Availability Group and give you its
        status.

    .DESCRIPTION
        Script will retrieve information about every database in the Availability Group and give you its
        status.  The script has been designed to accept pipeline information from Get-AGCluster
        so you don't have to specify the primary node and availability group in question (required).

    .PARAMETER AvailabilityGroup
        Name of the Availability Group you wish to see the database states.

    .INPUTS
        [PSCustomObject] from Get-AGCluster

    .OUTPUTS
        [PSCustomObject]
            AvailabilityGroup                     Name of the AG
            Name                                  Name of the database
            ReplicaServers                        Name of all of the replica servers for this database
            ReplicationState                      Replica status of each database.
                                                  [PSCustomObject]
                                                     Database                            Name of database
                                                     ReplicaServer                       Name of the replica server
                                                     SynchronizationState                Replication status
                                                     SynchronizationHealth               Health of replication
                                                     IsFailoverReady                     Database is ready for failover
                                                     IsSuspended                         Suspend state

            
    .EXAMPLE
        Import-Module PS.SQL
        Get-AGCluster -ComputerName SQL-AG-01a | Get-AGDatabaseState

        AvailabilityGroup          Name                                  ReplicaServers                              ReplicationState                                               
        -----------------          ----                                  --------------                              ----------------                                               
        SQL-AG-01-ag01             TestAGDatabase                        {SQL-AG-01A, SQL-AG-01B, SQL-AG-01C}        {@{Database=TestAGDatabase; ReplicaServer=SQL-AG-01A; Synchr...}}
        SQL-AG-01-ag01             TestAGDatabase10                      {SQL-AG-01A, SQL-AG-01B, SQL-AG-01C}        {@{Database=TestAGDatabase10; ReplicaServer=SQL-AG...}}
        SQL-AG-01-ag01             TestAGDatabase70                      {SQL-AG-01A, SQL-AG-01B, SQL-AG-01C}        {@{Database=TestAGDatabase70; ReplicaServer=D...}}

    .NOTES
        Author:             Martin Pugh
        Date:               12/16/14
      
        Changelog:
            12/16           MLP - Initial Release
            12/21           MLP - Complete rewrite to use SQL queries, gathers a lot more granular information.  Removed PrimaryReplicaServerName.
            8/16/15         MLP - Fixed for multiple AG's in input stream, now requires Get-AGCluster to run.
            2/19/16         MLP - Updated help and added to PS.SQL
            3/15/16         MLP - Added ValidateAGClusterObject and Backlog(kb) property
            3/15/16         MLP - Removed Backlog(kb) because it wasn't really what I was looking for.  Now have LogSendRate and LogSendQueueSize, which when divided gives you
                                  and estimated time it'll take to replicate.  This is much more useful. 
            5/11/16         MLP - Added PSTypeName input so no longer need ValidateAGClusterObject function
    #>

    [CmdletBinding()]
    Param (
        [Parameter(Mandatory,ValueFromPipeline)]
        [PSTypeName("SQL.AvailabilityGroup.Object")]$InputObject
    )

    BEGIN {
        Write-Verbose "$(Get-Date): Get-AGDatabaseState Started"
    }

    PROCESS {
        #Validate Cluster object
        #$InputObject | ValidateAGClusterObject

        Write-verbose "$(Get-Date): Querying $($InputObject.AvailabilityGroup)..."
        $DBs = ForEach ($DB in $InputObject.AvailabilityDatabases)
        {
            [PSCustomObject]@{
                Name = $DB
                ID = Invoke-SQLQuery -Instance $InputObject.ListenerDNSName -Database Master -MultiSubnetFailover -Query "SELECT group_database_id AS [ID] FROM sys.availability_databases_cluster WHERE database_name = '$DB'" | Select -ExpandProperty ID
            }
        }
        Write-Verbose "$(Get-Date): There are $($DBs.Count) databases in AG $AGName"
        ForEach ($DB in $DBs)
        {
            $Query = @"
SELECT rep.replica_server_name AS ReplicaServer,
    db_state.synchronization_state_desc AS SynchronizationState,
    db_state.synchronization_health_desc AS SynchronizationHealth,
    db_cluster.is_failover_ready AS IsFailoverReady,
    db_state.is_suspended AS IsSuspended,
    db_state.log_send_queue_size AS LogSendQueueSize,
    db_state.log_send_rate AS LogSendRate
FROM sys.dm_hadr_database_replica_states AS db_state 
JOIN sys.dm_hadr_database_replica_cluster_states AS db_cluster 
    ON db_state.group_database_id = db_cluster.group_database_id 
JOIN sys.availability_replicas As rep 
    ON db_state.replica_ID = rep.replica_id 
WHERE db_state.group_database_id = '$($DB.ID)' 
    AND db_state.replica_id = db_cluster.replica_id
"@
            $Date = Get-Date
            Invoke-SQLQuery -Instance $InputObject.ListenerDNSName -Database Master -MultiSubnetFailover -Query $Query | 
                Select  @{Name="AvailabilityGroup";Expression={$InputObject.AvailabilityGroup}},
                        @{Name="ListenerDNSName";Expression={$InputObject.ListenerDNSName}},
                        @{Name="Database";Expression={$DB.Name}},
                        ReplicaServer,
                        SynchronizationState,
                        SynchronizationHealth,
                        LogSendQueueSize,
                        LogSendRate,
                        @{Name="EstReplicationTime";Expression={ New-TimeSpan -Start $Date -End $Date.AddTicks(($_.LogSendQueueSize / $_.LogSendRate) * 10000000) }},
                        IsFailoverReady,
                        IsSuspended
        }

    }

    END {
        Write-Verbose "$(Get-Date): Get-AGDatabaseState finished"
    }
}

Function Get-AGReplicaState
{
    <#
    .SYNOPSIS
        Script will retrieve information about every node in the Availability Group and give you its
        replication status.

    .DESCRIPTION
        Script will retrieve information about every node in the Availability Group and give you its
        replication status.  The script has been designed to accept pipeline information from Get-AGCluster
        so you don't have to specify the availability group in question (required).

    .PARAMETER InputObject
        Availability Group information object.  Must be generated from the Get-AGCluster function.

    .INPUTS
        [PSCustomObject] from Get-AGCluster

    .OUTPUTS
        [PSCustomObject]
            AvailabilityGroup                     Name of the AG
            Name                                  Name of the Server
            Role                                  Role the server has in the AG
            AvailabilityMode                      The replication mode
            ConnectionState                       Connection state for the server
            RollupSynchronizationState            Current replication status
            
    .EXAMPLE
        Import-Module PS.SQL
        Get-AGCluster -ComputerName SQL-AG-01a | Get-AGReplicaState

        Instance             : SQL-AG-01-ag01
        Name                 : SQL-AG-01A
        Role                 : PRIMARY
        AvailabilityMode     : SYNCHRONOUS_COMMIT
        FailoverMode         : AUTOMATIC
        OperationalState     : ONLINE
        ConnectionState      : CONNECTED
        SynchronizationState : HEALTHY

        Instance             : SQL-AG-01-ag01
        Name                 : SQL-AG-01B
        Role                 : SECONDARY
        AvailabilityMode     : SYNCHRONOUS_COMMIT
        FailoverMode         : AUTOMATIC
        OperationalState     : PASSIVE
        ConnectionState      : CONNECTED
        SynchronizationState : HEALTHY

        Instance             : SQL-AG-01-ag01
        Name                 : SQL-AG-01C
        Role                 : SECONDARY
        AvailabilityMode     : ASYNCHRONOUS_COMMIT
        FailoverMode         : MANUAL
        OperationalState     : PASSIVE
        ConnectionState      : CONNECTED
        SynchronizationState : HEALTHY

    .NOTES
        Author:             Martin Pugh
        Date:               12/16/14
      
        Changelog:
            12/16           MLP - Initial Release
            12/21           MLP - Complete rewrite using SQL queries.  Removed PrimaryReplicaServerName parameter since it's no longer needed.
            2/19/16         MLP - Updated help and added to PS.SQL
            3/15/16         MLP - Added ValidateAGClusterObject function
    #>

    [CmdletBinding()]
    Param (
        [Parameter(Mandatory,ValueFromPipeline)]
        [PSTypeName("SQL.AvailabilityGroup.Object")]$InputObject
    )

    BEGIN {
        Write-Verbose "$(Get-Date): Get-AGReplicaState Started"
    }

    PROCESS {
        #Validate Cluster object
        #$InputObject | ValidateAGClusterObject

        $Query = @"
SELECT 
	Rep.replica_server_name AS Server,
	RepState.role_desc AS Role,
	Rep.availability_mode_desc AS AvailabilityMode,
	Rep.failover_mode_desc AS FailoverMode,
	OperationalState = 
		CASE operational_state_desc
			WHEN 'ONLINE' THEN 'ONLINE'
			ELSE 'PASSIVE'
		END,
	RepState.connected_state_desc AS ConnectionState,
	RepState.synchronization_health_desc AS SynchronizationState
FROM sys.availability_replicas AS Rep
JOIN sys.dm_hadr_availability_replica_states AS RepState
    ON Rep.replica_id = RepState.replica_id
WHERE Rep.group_id = '$($InputObject.AvailabilityGroupID)'
"@

        Invoke-SQLQuery -Instance $InputObject.ListenerDNSName -Database Master -MultiSubnetFailover -Query $Query | 
            Select  @{Name="AvailabilityGroup";Expression={$InputObject.AvailabilityGroup}},
                    @{Name="ListenerDNSName";Expression={$InputObject.ListenerDNSName}},
                    Server,
                    Role,
                    AvailabilityMode,
                    FailoverMode,
                    OperationalState,
                    ConnectionState,
                    SynchronizationState
    }

    END {
        Write-Verbose "$(Get-Date): Get-AGReplicaState finished"
    }
}


<#
.SYNOPSIS
    Get authentication scheme for a SQL server(s)    
.PARAMETER Instance
    Server or instance name for the SQL server
.PARAMETER Credential
    Credential needed for SQL server
.INPUTS
    None
.OUTPUTS
    None
.EXAMPLE
    Get-SQLAuthenticationScheme -Instance SQL-SVR-01

    Instance   net_transport auth_scheme
    --------   ------------- -----------
    sql-svr-01 TCP           KERBEROS

.NOTES
    Author:             Martin Pugh
    Twitter:            @thesurlyadm1n
    Spiceworks:         Martin9700
    Blog:               www.thesurlyadmin.com
      
    Changelog:
        1.0             Initial Release
        1.01            Added help and added to PS.SQL

#>
#requires -Version 3.0
Function Get-SQLAuthenticationScheme {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory)]
        [string[]]$Instance,
        [pscredential]$Credential
    )

    Invoke-SQLQuery -Instance $Instance -MultiSubnetFailover -Database Master -Query "SELECT net_transport, auth_scheme FROM sys.dm_exec_connections WHERE session_id = @@spid"
}



    
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
Function Get-SQLJobStatus {
    <#
    .SYNOPSIS
        Retrieve status of SQL jobs from designated servers
    .DESCRIPTION
        Creates a dataset of the status of jobs on the designated servers.  The query will only 
        retrieve the latest run, so this is excellent for monitoring the status of your jobs.
    
    .PARAMETER Name
        Name or names of the servers you wish to query.  Accepts single entries, arrays or piped information,
        including from Get-ADComputer.

    .INPUTS
        Names
        [Microsoft.ActiveDirectory.Management.ADAccount]
    .OUTPUTS
        PSCustomObject
            Instance            Server name (string)
            Job                 Name of the job (string)
            Last Run            Last time the job ran (datetime)
            Duration            How long it took the job to run (timespan)
            Status              Completion status (string)
            Next Run            Next time the job is scheduled to run (datetime)
    .EXAMPLE
        .\Get-SQLJobStatus.ps1 -Servers database1,database2

        Retrieve last run information for all the jobs on database1 and database2.   

    .EXAMPLE

        Get-ADComputer -Filter {Name -like "*sql*"} | .\Get-SQLJobStatus.ps1

        Retrieve the job information from all computers in Active Directory with the string "SQL" in their name.

    .NOTES
        Author:             Martin Pugh
        Twitter:            @thesurlyadm1n
        Spiceworks:         Martin9700
        Blog:               www.thesurlyadmin.com
      
        Changelog:
            1.0             Initial Release
            1.01            Removed Invoke-SQLQuery as an internal function, added to PS.SQL
    .LINK
    
    #>
    #Requires -Version 3.0
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory,ValueFromPipeline,ValueFromPipelineByPropertyName)]
        [Alias("ComputerName","Servers")]
        [string[]]$Name
    )

    BEGIN {
        Write-Verbose "$(Get-Date): Get-SQLJobStatus begins"

        #Query slightly altered from the original by: CTG76 on Spiceworks
        #Link: http://community.spiceworks.com/topic/789186-query-success-of-a-single-sql-job?page=1#entry-4300177
        $Query = @"
SELECT DISTINCT 
	S.Name AS [Job], 
	H.run_date AS [RunDate],
    H.run_time as [RunTime],
	CASE H.run_status
		WHEN 0 THEN 'Failed'
		WHEN 1 THEN 'Successful'
		WHEN 3 THEN 'Cancelled'
		WHEN 4 THEN 'In Progress'
	END AS [Status],
	H.run_duration AS [Duration],
	SCHD.next_run_date AS [NextRunDate],
	SCHD.next_run_time AS [NextRunTime]
FROM sysjobhistory H, sysjobs S, sysjobschedules SCHD
WHERE H.job_id = S.job_id and 
	S.job_id = SCHD.job_id and
	H.run_date = (SELECT MAX(H1.run_date) FROM sysjobhistory H1 WHERE H1.job_id = H.job_id) and
    H.run_time = (SELECT MAX(H1.run_time) FROM sysjobhistory H1 WHERE H1.job_id = H.job_id) and 
	enabled = 1
ORDER BY H.run_date DESC
"@
        $ServerCount = 0
    }

    PROCESS {
        Write-Verbose "$(Get-Date): Retrieving job information for:  $($Name -join ", ")"
        $ServerCount = $ServerCount + $Name.Count
        Invoke-SQLQuery -Instance $Name -Database msdb -Query $Query | Select Instance,Job,@{Name="Last Run";Expression={Get-SQLDate -Date $_.RunDate -Time $_.RunTime}},@{Name="Duration";Expression={Get-SQLTime -Time $_.Duration}},Status,@{Name="Next Run";Expression={Get-SQLDate -Date $_.NextRunDate -Time $_.NextRunTime}}
    }

    END {
        Write-Verbose "$(Get-Date): Data successfully gathered for $ServerCount servers"
        Write-Verbose "$(Get-Date): Get-SQLJobStatus finished"
    }
}
Function Invoke-SQLQuery {   
    <#
    .SYNOPSIS
        Quickly run a query against a SQL server.
    .DESCRIPTION
        Simple function to run a query against a SQL server.
    .PARAMETER Instance
        Server name and instance (if needed) of the SQL server you want to run the query against.  E.G.  SQLServer\Payroll
    .PARAMETER Database
        Name of the database the query must run against
    .PARAMETER Credential
        Supply alternative credentials
    .PARAMETER MultiSubnetFailover
        Connect to a SQL 2012 AlwaysOn Availability group.  This parameter requires the SQL2012 Native Client to be installed on
        the machine you are running this on.  MultiSubnetFailover will give your script the ability to talk to a AlwaysOn Availability
        cluster, no matter where the primary database is located.
    .PARAMETER Query
        Text of the query you wish to run.  This parameter is optional and if not specified the script will create a text file in 
        your temporary directory called Invoke-SQLQuery-Query.txt.  You can put your query text in this file and when you save and 
        exit the script will execute that query.
    .PARAMETER NoInstance
        By default Invoke-SQLQuery will add a column with the name of the instance where the data was retrieved.  Use this switch to
        suppress that behavior.
    .PARAMETER PrintToStdOut
        If your query is using the PRINT statement, instead of writing that to the verbose stream, this switch will write that output
        to StdOut.
    .PARAMETER Timeout
        Time Invoke-SQLQuery will wait for SQL Server to return data.  Default is 120 seconds.
    .PARAMETER ListDatabases
        Use this switch to get a list of all databases on the Instance you specified.
    .INPUTS
        String              Will accept the query text from pipeline
    .OUTPUTS
        System.Data.DataRow
    .EXAMPLE
        Invoke-SQLQuery -Instance faxdba101 -Database RightFax -Query "Select top 25 * from Documents where fcsfile <> ''"
        
        Runs a query against faxdba101, Rightfax database.
    .EXAMPLE
        Get-Content c:\sql\commonquery.txt | Invoke-SQLQuery -Instance faxdba101,faxdbb101,faxdba401 -Database RightFax
        
        Run a query you have stored in commonquery.txt against faxdba101, faxdbb101 and faxdba401
    .EXAMPLE
        Invoke-SQLQuery -Instance dbprod102 -ListDatabases
        
        Query dbprod102 for all databases on the SQL server
    .NOTES
        Author:             Martin Pugh
        Date:               7/11/2014
          
        Changelog:
            1.0             Initial Release
            1.1             7/11/14  - Changed $Query parameter that if none specified it will open Notepad for editing the query
            1.2             7/17/14  - Added ListDatabases switch so you can see what databases a server has
            1.3             7/18/14  - Added ability to query multiple SQL servers, improved error logging, add several more examples
                                       in help.
            1.4             10/24/14 - Added support for SQL AlwaysOn
            1.5             11/28/14 - Moved into SQL.Automation Module, fixed bug so script will properly detect when no information is returned from the SQL query
            1.51            1/28/15  - Added support for SilentlyContinue, so you can suppress the warnings if you want 
            1.6             3/5/15   - Added NoInstance switch
            1.61            10/14/15 - Added command timeout
            2.0             11/13/15 - Added ability to stream Message traffic (from PRINT command) to verbose stream.  Enhanced error output, you can now Try/Catch
                                       Invoke-SQLQuery.  Updated documentation. 
            2.01            12/23/15 - Fixed piping query into function
        Todo:
            1.              Alternate port support?
    .LINK
        https://github.com/martin9700/Invoke-SQLQuery
    #>
    [CmdletBinding(DefaultParameterSetName="query")]
    Param (
        [string[]]$Instance = $env:COMPUTERNAME,
        
        [Parameter(ParameterSetName="query",Mandatory=$true)]
        [string]$Database,
        
        [Management.Automation.PSCredential]$Credential,
        [switch]$MultiSubnetFailover,
        
        [Parameter(ParameterSetName="query",ValueFromPipeline=$true)]
        [string]$Query,

        [Parameter(ParameterSetName="query")]
        [switch]$NoInstance,

        [Parameter(ParameterSetName="query")]
        [switch]$PrintToStdOut,

        [Parameter(ParameterSetName="query")]
        [int]$Timeout = 120,

        [Parameter(ParameterSetName="list")]
        [switch]$ListDatabases
    )

    Begin {
        If ($ListDatabases)
        {   
            $Database = "Master"
            $Query = "Select Name,state_desc as [State],recovery_model_desc as [Recovery Model] From Sys.Databases"
        }        
        
        $Message = New-Object -TypeName System.Collections.ArrayList

        $ErrorHandlerScript = {
            Param(
                $Sender, 
                $Event
            )

            $Message.Add([PSCustomObject]@{
                Number = $Event.Errors.Number
                Line = $Event.Errors.LineNumber
                Message = $Event.Errors.Message
            }) | Out-Null
        }
    }

    End {
        If ($Input)
        {   
            $Query = $Input -join "`n"
        }
        If (-not $Query)
        {   
            $Path = Join-Path -Path $env:TEMP -ChildPath "Invoke-SQLQuery-Query.txt"
            Start-Process Notepad.exe -ArgumentList $Path -Wait
            $Query = Get-Content $Path
        }

        If ($Credential)
        {   
            $Security = "uid=$($Credential.UserName);pwd=$($Credential.GetNetworkCredential().Password)"
        }
        Else
        {   
            $Security = "Integrated Security=True;"
        }
        
        If ($MultiSubnetFailover)
        {   
            $MSF = "MultiSubnetFailover=yes;"
        }
        
        ForEach ($SQLServer in $Instance)
        {   
            $ConnectionString = "data source=$SQLServer,1433;Initial catalog=$Database;$Security;$MSF"
            $SqlConnection = New-Object System.Data.SqlClient.SqlConnection
            $SqlConnection.ConnectionString = $ConnectionString
            $SqlCommand = $SqlConnection.CreateCommand()
            $SqlCommand.CommandText = $Query
            $SqlCommand.CommandTimeout = $Timeout
            $Handler = [System.Data.SqlClient.SqlInfoMessageEventHandler] $ErrorHandlerScript
            $SqlConnection.add_InfoMessage($Handler)
            $SqlConnection.FireInfoMessageEventOnUserErrors = $true
            $DataAdapter = New-Object System.Data.SqlClient.SqlDataAdapter $SqlCommand
            $DataSet = New-Object System.Data.Dataset

            Try {
                $Records = $DataAdapter.Fill($DataSet)
                If ($DataSet.Tables[0])
                {   
                    If (-not $NoInstance)
                    {
                        $DataSet.Tables[0] | Add-Member -MemberType NoteProperty -Name Instance -Value $SQLServer
                    }
                    Write-Output $DataSet.Tables[0]
                }
                Else
                {   
                    Write-Verbose "Query did not return any records"
                }
            }
            Catch {
                $SqlConnection.Close()
                Write-Error $_
                Continue
            }
            $SqlConnection.Close()
        }

        If ($Message)
        {
            ForEach ($Warning in ($Message | Where Number -eq 0))
            {
                If ($PrintToStdOut)
                {
                    Write-Output $Warning.Message
                }
                Else
                {
                    Write-Verbose $Warning.Message -Verbose
                }
            }
            $Errors = @($Message | Where Number -ne 0)
            If ($Errors.Count)
            {
                ForEach ($MsgError in $Errors)
                { 
                    Write-Error "Query Error $($MsgError.Number), Line $($MsgError.Line): $($MsgError.Message)"
                }
            }
        }
    }
}
Function New-SQLBackupReport {
    <#
    .SYNOPSIS
        Get a report of all of your SQL servers and their last backup status.
    .DESCRIPTION
        This script requires Get-SQLBackupStatus.  Run that script and pipe it into New-SQLBackupReport to generate
        a HTML report of the results.
    .PARAMETER InputObject
        Object data from Get-SQLBackupStatus
    .PARAMETER Path
        Path where to save the resultant HTML file
    .INPUTS
        Get-SQLBackupStatus
    .OUTPUTS
        None
    .EXAMPLE
        Get-SQLBackupStatus -Name SQL-AG-01 | New-SQLBackupReport -Path c:\reports
    .NOTES
        Author:             Martin Pugh
        Twitter:            @thesurlyadm1n
        Spiceworks:         Martin9700
        Blog:               www.thesurlyadmin.com
      
        Changelog:
            1.0             Initial Release
            1.0.1           Fix issue #2
            1.1             Updated help and added to PS.SQL.  Removed imbedded functions and put them in the module.  
                            Split into two functions, Get-SQLBackupStatus and New-SQLBackupReport to better match up with 
                            Get-SQLJobStatus and New-SQLJobStatusReport
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true)]
        [PSCustomObject[]]$InputObject,
        
        [Parameter(Mandatory=$true)]
        [ValidateScript( { Test-Path $_ } )]
        [string]$Path
    )

    BEGIN {
        Write-Verbose "$(Get-Date): New-SQLBackupReport generating report..."

        $HTMLHeader = @"
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"  "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<style>
TABLE {border-width: 1px;border-style: solid;border-color: black;border-collapse: collapse; }
TR:Hover TD {Background-Color: #C1D5F8;}
TH {border-width: 1px;padding: 3px;border-style: solid;border-color: black;background-color: #00008B; color:white; }
TD {border-width: 1px;padding: 3px;border-style: solid;border-color: black;width: 5%; font-size:.8em; }
.odd { background-color: white; }
.even { background-color: #dddddd; }
span { font-size:.6em; }
</style>
<title>SQL Backup Report</title>
</head>
<body>
<h1 style="text-align:center;">SQL Backup Report</h1><br/>
"@
    }

    END {
        $BackupSets = @($Input)

    #Validate object
        If ($BackupSets)
        {
            $Properties = "Backup Size","Backup Status","Database","Days Since Last Backup","Last Backup","Last T-Log Backup","Recovery Model","Server"
            $ObjectProperties = $BackupSets[0] | Get-Member -MemberType Properties | Select -ExpandProperty Name
            If (Compare-Object -ReferenceObject $Properties -DifferenceObject $ObjectProperties)
            {
                Write-Error "$(Get-Date); Input object does not match object from Get-SQLJobStatus, aborting"
                Exit 999
            }
            $BackupSets = $BackupSets | Sort Server,Database
            $Failed = $BackupSets | Where "Backup Status" -eq "Failed"
            $Successful = $BackupSets | Where "Backup Status" -ne "Failed"

            $FailedHTML = If ($Failed)
            {
                Write-Output "<div style='background-color: #ff0000;color: white;font-size: 120%;text-align: center;font-weight: bold;'>Failed Backups</div>`n"
                $TableHTML = $Failed | ConvertTo-Html -Fragment | Set-GroupRowColorsByColumn -ColumnName Server -CSSEvenClass even -CSSOddClass odd
                Write-Output $TableHTML.Replace("<td>Failed</td>","<td style='color: #ff0000;'>Failed</td>")
                Write-Output "<br/>"
            }
            $TableHTML = $Successful | ConvertTo-Html -Fragment | Set-GroupRowColorsByColumn -ColumnName Server -CSSEvenClass even -CSSOddClass odd


            $HTML = @"
$HTMLHeader
$FailedHTML
<div style='background-color: green;color: white;font-size: 120%;text-align: center;font-weight: bold;'>Successful Backups</div>`n
$TableHTML
<br/>
<span>Run on: $(Get-Date)</span>
"@

            Write-Verbose "$(Get-Date): Saving report..."
            #Save New Report
            $OutputFile = Join-Path -Path $Path -ChildPath "SQLBackup-$(Get-Date -Format 'MM-dd-yyyy').html"
            $HTML | Out-File $OutputFile -Encoding ascii
        }

        Write-Verbose "$(Get-Date): New-SQLBackupReport complete"
    }
}

Function New-SQLJobStatusReport {
    <#
    .SYNOPSIS
        Leverage Get-SQLJobStatus script to produce an HTML report of SQL Job statuses.
    .DESCRIPTION
        Run Get-SQLJobStatus and pipe into New-SQLJobStatusReport to create a HTML report of job
        status.  Failed jobs will automatically be put at the top for easy triage.

    .PARAMETER InputObject
        This is the data from Get-SQLJobStatus.  Can either be piped in or run Get-SQLJobStatus as a 
        sub-expression.  

    .PARAMETER Path
        Path where you would like to save the resultant HTML report.  Report will be named SQLJobStatus.HTML.
        If path is not specified the default path will be the same folder where the script is saved.

    .INPUTS
        [PSCustomObject]
            [string]Instance
            [string]Job
            [datetime]Last Run
            [TimeSpan]Duration
            [string]Status
            [datetime]Next Run
    .OUTPUTS
        HTML report at $Path
    .EXAMPLE
        Get-SQLJobStatus -Name database1,database2 | New-SQLJobStatusReport -Path c:\path

        Get job status information from database 1 and 2 and create an HTML report.  Report will be saved
        by default in the same path as the script. 

    .EXAMPLE
        New-SQLJobStatusReport -InputObject (Get-SQLJobStatus -Name database3,database4) -Path c:\path

        Get job status information from database 3 and 4, create an HTML report and save it in c:\path

    .NOTES
        Author:             Martin Pugh
        Twitter:            @thesurlyadm1n
        Spiceworks:         Martin9700
        Blog:               www.thesurlyadmin.com
      
        Changelog:
            1.0             Initial Release
    .LINK
    
    #>
    #requires -Version 3.0
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true)]
        [PSCustomObject]$InputObject,

        [Parameter(Mandatory=$true)]
        [ValidateScript( { Test-Path $_ } )]
        [string]$Path
    )

    BEGIN {
        Write-Verbose "$(Get-Date): New-SQLJobStatusReport begins"

        $HTMLHeader = @"
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"  "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<style>
TABLE {border-width: 1px;border-style: solid;border-color: black;border-collapse: collapse; }
TR:Hover TD {Background-Color: #C1D5F8;}
TH {border-width: 1px;padding: 3px;border-style: solid;border-color: black;background-color: #00008B; color:white; }
TD {border-width: 1px;padding: 3px;border-style: solid;border-color: black;width: 5%; font-size:.8em; }
.odd { background-color: white; }
.even { background-color: #dddddd; }
span { font-size:.6em; }
</style>
<title>SQL Job Report</title>
</head>
<body>
<h1 style="text-align:center;">SQL Job Report</h1><br/>
"@

        $HTMLPath = Join-Path -Path $Path -ChildPath "SQLJobReport-$(Get-Date -Format "MM-dd-yyyy").html"
    }

    END {
        $Data = @($Input)

        #Validate object
        If ($Data)
        {
            $Properties = "Instance","Job","Last Run","Duration","Status","Next Run"
            $ObjectProperties = $Data[0] | Get-Member -MemberType Properties | Select -ExpandProperty Name
            If (Compare-Object -ReferenceObject $Properties -DifferenceObject $ObjectProperties)
            {
                Write-Error "$(Get-Date); Input object does not match object from Get-SQLJobStatus, aborting"
                Exit 999
            }

            Write-Verbose "$(Get-Date): Data successfully gathered for $(($Data | Select Instance -Unique).Count) servers"
            $Data = $Data | Sort Instance
            $Failed = $Data | Where Status -eq "Failed"
            $Successful = $Data | Where Status -ne "Failed"

            $FailedHTML = If ($Failed)
            {
                Write-Output "<div style='background-color: #ff0000;color: white;font-size: 120%;text-align: center;font-weight: bold;'>Failed Jobs</div>`n"
                $TableHTML = $Failed | ConvertTo-Html -Fragment | Set-GroupRowColorsByColumn -ColumnName Instance -CSSEvenClass even -CSSOddClass odd
                Write-Output $TableHTML.Replace("<td>Failed</td>","<td style='color: #ff0000;'>Failed</td>")
                Write-Output "<br/>"
            }

            $TableHTML = $Successful | ConvertTo-Html -Fragment | Set-GroupRowColorsByColumn -ColumnName Instance -CSSEvenClass even -CSSOddClass odd

            $HTML = @"
$HTMLHeader
$FailedHTML
<div style='background-color: green;color: white;font-size: 120%;text-align: center;font-weight: bold;'>Successful Backups</div>`n
$TableHTML
<br/>
<h5>Run on: $(Get-Date)</h5>
"@

            $HTML | Out-File $HTMLPath -Encoding ascii
        }
        Else
        {
            Write-Warning "$(Get-Date): No data input"
        }

        Write-Verbose "$(Get-Date): New-SQLJobStatusReport finished"
    }
}

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

Function Resume-AGReplication {
    <#
    .SYNOPSIS
        After a AG failover, resumes replication on databases
    .DESCRIPTION
        After a AG failover, resumes replication on databases.  Requires pipeline data from Get-AGCluster.
    .PARAMETER InputObject
        Object generated from Get-AGCluster
    .INPUTS
        Get-AGCluster
    .OUTPUTS
        None
    .EXAMPLE
        Get-AGCluster -ComputerName SQL-AG-01 | Resume-AGReplication

    .NOTES
        Author:             Martin Pugh
        Date:               1/6/2016
      
        Changelog:
            01/06/16        MLP - Initial Release

        Todo:
            1.
    #>
    Param (
        [Parameter(ValueFromPipeline)]
        [Object]$InputObject
    )

    PROCESS {
        Write-Verbose "$(Get-Date): Resuming replication of databases in [$($InputObject.AvailabilityGroup)]..."
        ForEach ($db in $InputObject.AvailabilityDatabases)
        {
            Invoke-SQLQuery -Instance $InputObject.AvailabilityReplicas -Database Master -Query "ALTER DATABASE [$db] SET HADR RESUME"
        }
    }
}
Function Set-AGClusterFailover
{
    <#
    .SYNOPSIS
        Trigger a manual failover of an AlwaysOn Availability Group

    .DESCRIPTION
        The purpose of this script is to allow you to failover to a different node in an AlwaysOn Availability Group.

        Failover to synchronous nodes does not require any extra actions and can be done anytime.

        Failover to asynchronous nodes requires the use of the -Force parameter.  Data loss is possible and the script will
        prompt you to make sure you want to do this.

        Failover to asynchronous nodes in a DR situation, when synchronous nodes and the file share witness--essentially you've
        lost quorum--can also be done with this script.  Use -Force and -FixQuorum to trigger this.  Data loss is possible and the
        script will prompt you to make sure you want to do this.

        *** WARNING ***
        Do not do this unless you absolutely must. -Force and -FixQuorum should never be used in normal operations.
        *** WARNING ***

    .PARAMETER Node
        Designate the node in the Availability Group cluster you want to failover to.

    .PARAMETER Force
        When failing over to an asynchronous node, you must use this switch to verify that you want to do this type of failover
        and that you understand data loss is possible.  This switch is also required when doing a DR failover after loss of
        quorum.

    .PARAMETER FixQuorum
        Only use in case of full DR failover and loss of quorum.  Switch instructs the script (along with the -Force parameter) 
        to force quorum to the asynchronous node and trigger a failover.

    .PARAMETER MoveClusterGroup
        Use this parameter to move the Windows Failover Cluster Group name "Cluster Group" to the specified node.  Note, this is
        not an Availability Group, but a core cluster resource.

    .EXAMPLE
        Import-Module PS.SQL
        Set-AGClusterFailover -ComputerName SQL-AG-01b

        Triggers a failover to SQL-AG-01b, no action will occur if SQL-AG-01b is already the primary.

    .EXAMPLE
        Import-Module PS.SQL
        Set-AGClusterFailover -ComputerName SQL-AG-01c -Force

        Triggers a failover to the asynchronous node, SQL-AG-01c.  

    .NOTES
        Author:             Martin Pugh
        Date:               12/16/14
      
        Changelog:
            12/14/14        MLP - Initial Release
            10/9/15         MLP - reworked to require Get-AGCluster, and to use SQL queries instead of the SQL provider
            1/6/16          MLP - Added the moving of the "Cluster Group" Windows cluster group name using Move-ClusterGroupRemote function
            2/19/16         MLP - Updated help and added to PS.SQL
            3/15/16         MLP - Added ValidateAGClusterObject function
            6/3/16          MLP - Renamed Move-RemoteClusterGroup to Move-ClusterGroupRemote
            12/22/16        MLP - 
    #>
    #requires -Version 3.0
    [CmdletBinding(DefaultParameterSetName = "cli")]
    Param (
        [Parameter(Mandatory,ValueFromPipeline,ParameterSetName="pipe")]
        [PSTypeName("SQL.AvailabilityGroup.Object")]$InputObject,

        [Parameter(Mandatory,ParameterSetName="cli")]
        [string]$ClusterName,

        [Parameter(Mandatory)]
        [Alias("ComputerName")]
        [string]$Node,

        [switch]$Force,
        [switch]$FixQuorum,
        [switch]$MoveClusterGroup
    )
    BEGIN {
        Write-Verbose "$(Get-Date): Beginning failovers to $Node..." -Verbose
        Write-Verbose "$(Get-Date):     Force: $Force"
        Write-Verbose "$(Get-Date): FixQuorum: $FixQuorum"

        #ClusterName specified so have to get the SQL.AvailabilityGroup.Object from Get-AGCluster
        If ($PsCmdlet.ParameterSetName -eq "cli")
        {
            #First try computername

            Try {
                $InputObject = Get-AGCluster -ComputerName $ClusterName -ErrorAction Stop
            }
            Catch {
                Write-Error "Unable to retrieve AG information from $ClusterName because ""$_""" -ErrorAction Stop
            }
        }
    }

    PROCESS {
        #Validate Cluster object
        #$InputObject | ValidateAGClusterObject
        ForEach ($Object in $InputObject)
        {
            $Moved = $false
            Write-Verbose "$(Get-Date): Failing over [$($Object.AvailabilityGroup)] to $Node..." -Verbose
            If ($Object.AvailabilityReplicas -contains $Node)
            {
                If ($Node -ne $Object.PrimaryReplicaServerName)
                {
                    $AGRState = $Object | Get-AGReplicaState | Where Server -eq $Node
                    Switch ($true)
                    {
                        { $AGRState.SynchronizationState -ne "Healthy" -or (-not $Object.ListenerDNSName) -and (-not $Force) } {
                            Write-Warning "$(Get-Date): Availability Group [$($Object.AvailabilityGroup)] is in an unhealthy state or does not have DNS Listener's properly configured, unable to failover until this is resolved.  If you are in a DR situation rerun this script with the -Force and -FixQuorum switches"
                            Write-Warning "$(Get-Date): HealthState: $($AGRState.SynchronizationState)"
                            Write-Warning "$(Get-Date):    Listener: $($Object.ListenerDNSName)"
                            Break
                        }
                        { $AGRState.AvailabilityMode -eq "ASYNCHRONOUS_COMMIT" -and (-not $Force) } {
                            Write-Warning "$(Get-Date): $Node is the ASynchronous node for [$($Object.AvailabilityGroup)] and cannot be failed over to without data loss.  If this is OK, use the -Force switch"
                            Break
                        }
                        { $AGRState.AvailabilityMode -eq "ASYNCHRONOUS_COMMIT" -and $Force -and (-not $FixQuorum) } {
                            If ($AGRState.SynchronizationState -ne "Healthy")
                            {
                                Write-Warning "$(Get-Date): Availability Group [$($Object.AvailabilityGroup)] is in an unhealthy state, aborting failover.  Fix the replication state, or if this is a DR situation use the -Force and -FixQuorum switches"
                            }
                            Else
                            {
                                Invoke-SQLQuery -Instance $Node -Database Master -Query "ALTER AVAILABILITY GROUP [$($Object.AvailabilityGroup)] FORCE_FAILOVER_ALLOW_DATA_LOSS"
                                Start-Sleep -Seconds 10
                                $Object | Resume-AGReplication
                                $Moved = $true
                            }
                            Break
                        }
                        { $AGRState.AvailabilityMode -eq "ASYNCHRONOUS_COMMIT" -and $Force -and $FixQuorum } {
                            Write-Warning "You have specified a DR failover to the asynchronous node. This is a drastic step and should only be performed if absolutely required."
                            $Answer = Read-Host "Are you sure you wish to proceed with a DR failover?  This action will change quorum settings, and there is a potential loss of data!`n[Y]es/[N]o (default is ""N"")"
                            If ($Answer.ToUpper() -eq "Y")
                            {
                                #Failover the cluster
                                Invoke-Command -Session $Node -ScriptBlock {
                                    Import-Module FailoverClusters
                                    Stop-ClusterNode -Name $Using:ComputerName
                                    Start-ClusterNode -Name $Using:ComputerName -FixQuorum
                                    Start-Sleep -Seconds 3

                                    #Set Node Weight
                                    (Get-ClusterNode -Name $Using:ComputerName).NodeWeight = 1
                                    ForEach ($Node in (Get-ClusterNode | Where Name -ne $Using:ComputerName))
                                    {
                                        Start-Sleep -Milliseconds 500
                                        $Node.NodeWeight = 0
                                    }
                                }
                                Invoke-SQLQuery -Instance $Node -Database Master -Query "ALTER AVAILABILITY GROUP [$($Object.AvailabilityGroup)] FORCE_FAILOVER_ALLOW_DATA_LOSS"
                                Start-Sleep -Seconds 2

                                $Object | Resume-AGReplication
                                Break
                            }
                        }
                        DEFAULT {
                            Invoke-SQLQuery -Instance $Node -Database Master -Query "ALTER AVAILABILITY GROUP [$($Object.AvailabilityGroup)] FAILOVER"
                            Start-Sleep -Seconds 10
                            #$Object | Resume-AGReplication
                            #Move-ClusterGroupRemote -Cluster $Node -ClusterGroup "Cluster Group" -Node $Node -Verbose
                            $Moved = $true
                        }
                    }
                }
                Else
                {
                    Write-Verbose "$(Get-Date): $Node is already the primary replica for [$($Object.AvailabilityGroup)]" -Verbose
                }
            }
            Else
            {
                Write-Warning "$(Get-Date): $Node is not a valid replica server for [$($Object.AvailabilityGroup)].  Skipping."
            }
        }
    }

    END {
        If ($MoveClusterGroup)
        {
            If (-not $Moved)
            {
                $Confirm = Read-Host "No Availability Groups were successfully moved, still want to move ""Cluster Group""? [y/N]"
                If ($Confirm.Substring(0,1).ToLower() -eq "y")
                {
                    $Moved = $true
                }
            }
            If ($Moved)
            {
                Try {
                    $CurrentNode = Get-Cluster $Node | Get-ClusterGroup -Name "Cluster Group"
                    If ($Node -notlike "$($CurrentNode.OwnerNode)*")
                    {
                        $null = Get-Cluster $Node | Move-ClusterGroup -Name "Cluster Group" -Node $Node
                        Start-Sleep -Seconds 15
                        Write-Verbose "$(Get-Date): ""Cluster Group"" moved to $Node" -Verbose
                    }
                }
                Catch {
                    Write-Error "Unable to move cluster group ""Cluster Group"" because ""$_""" -ErrorAction Stop
                }
            }
        }

        Write-Verbose "$(Get-Date): Failover's completed." -Verbose
    }
}
Function Set-GroupRowColorsByColumn {
    <#
    .SYNOPSIS
        Alternate HTML table colors based on the value of a column
    .PARAMETER InputObject
        The HTML you wish to work on.  Does not have to be a table fragment, will work on full HTML files.
    .PARAMETER ColumnName
        Name of the column you want to key the color changes on.  Every time the column changes value the background row color will change, so make sure you sort
    .PARAMETER CSSEvenClass
        Your HTML must have CSS with a class called TREVEN, and this defines how you want the row to look
    .PARAMETER CSSOddClass
        This defines the CSS class that opposite rows will use
    .INPUTS
        HTML
    .OUTPUTS
        HTML
    .EXAMPLE
        $Header = @"
        <style>
        TABLE {border-width: 1px;border-style: solid;border-color: black;border-collapse: collapse;}
        TH {border-width: 1px;padding: 3px;border-style: solid;border-color: black;background-color: #6495ED;}
        TD {border-width: 1px;padding: 3px;border-style: solid;border-color: black;}
        .odd  { background-color:#ffffff; }
        .even { background-color:#dddddd; }
        </style>
        "@

        Get-Process | Sort ProcessName |  ConvertTo-HTML -Head $Header | Set-GroupRowColorsByColumn -Column ProcessName -CSSEvenClass even -CSSOddClass odd | Out-File .\Processes.HTML
    .NOTES
        Author:             Martin Pugh
        Twitter:            @thesurlyadm1n
        Spiceworks:         Martin9700
        Blog:               www.thesurlyadmin.com
      
        Changelog:
            1.0             Initial Release
            1.01            Added help, added to PS.SQL Module
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory,ValueFromPipeline)]
        [string[]]$InputObject,
        [Parameter(Mandatory)]
        [string]$ColumnName,
        [string]$CSSEvenClass = "TREven",
        [string]$CSSOddClass = "TROdd"
    )
    Process {
        $NewHTML = ForEach ($Line in $InputObject)
        {
            If ($Line -like "*<th>*")
            {
                If ($Line -notlike "*$ColumnName*")
                {
                    Write-Error "Unable to locate a column named $ColumnName"
                    Exit 999
                }
                $Search = $Line | Select-String -Pattern "<th>.*?</th>" -AllMatches
                $Index = 0
                ForEach ($Column in $Search.Matches)
                {
                    If (($Column.Groups.Value -replace "<th>|</th>","") -eq $ColumnName)
                    {
                        Break
                    }
                    $Index ++
                }
            }
            If ($Line -like "*<td>*")
            {
                $Search = $Line | Select-String -Pattern "<td>.*?</td>" -AllMatches
                If ($LastColumn -ne $Search.Matches[$Index].Value)
                {
                    If ($Class -eq $CSSEvenClass)
                    {
                        $Class = $CSSOddClass
                    }
                    Else
                    {
                        $Class = $CSSEvenClass
                    }
                }
                $LastColumn = $Search.Matches[$Index].Value
                $Line = $Line.Replace("<tr>","<tr class=""$Class"">")
            }
            Write-Output $Line
        }
        Write-Output $NewHTML
    }
}

