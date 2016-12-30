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

