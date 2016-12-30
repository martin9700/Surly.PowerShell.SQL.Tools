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
