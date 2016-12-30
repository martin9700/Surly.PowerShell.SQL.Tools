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
            12/22/16        MLP - Fixed "Cluster Group" move final time, no more need of Get/Move-ClusterGroupRemote.  
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
