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


