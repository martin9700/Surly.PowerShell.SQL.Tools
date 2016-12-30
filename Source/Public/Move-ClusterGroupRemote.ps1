Function Move-ClusterGroupRemote {
    <#
    .SYNOPSIS
        Move Windows Cluster default "Cluster Group" to a new node
    .DESCRIPTION
        Move the designated Windows cluster name to a new node.  Wildcards accepted for Cluster Group names
    .PARAMETER Cluster
        Cluster object name, or name of one of the nodes in the cluster
    .PARAMETER ClusterGroup
        Cluster group name, wildcards are accepted
    .PARAMETER Node
        Name of the node you want to move the cluster groups to
    .INPUTS
        None
    .OUTPUTS
        PSCustomObject
            Name,PreviousNodeOwner,OwnerNode,State,Action
    .EXAMPLE
        Move-RemoteClusterGroup -Cluster FileServer -Node fs-01b

        Move "Cluster Group" default name to fs-01b

    .EXAMPLE
        Move-RemoteClusterGroup -Cluster FileServer -ClusterGroup * -Node fs-01a

        Move all cluster groups to fs-01a

    .NOTES
        Author:             Martin Pugh
        Date:               1/5/2016
      
        Changelog:
            01/05/16        MLP - Initial Release
            2/19/16         MLP - Updated help and added to PS.SQL
            6/3/16          MLP - Script now uses Get-ClusterGroupRemote

        Todo:
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true)]
        [ValidateScript({ Test-Connection $_ -Count 1 -Quiet })]
        [string]$Cluster,

        [string[]]$ClusterGroup,

        [Parameter(Mandatory=$true)]
        [ValidateScript({ Test-Connection $_ -Count 2 -Quiet })]
        [string]$Node
    )

    Write-Verbose "$(Get-Date): Beginning Windows Cluster Failover..."
    $ClusterGroups = Get-ClusterGroupRemote -Cluster $Cluster -ClusterGroup $ClusterGroup

    ForEach ($CG in $ClusterGroups)
    {
        $NodeMove = Invoke-Command -ComputerName $CG.OwnerNode -HideComputerName -ScriptBlock {
            Import-Module FailoverClusters
            If ($Using:CG.State -ne "Online")
            {
                Write-Warning "$(Get-Date): Windows Cluster Failover: ""$($Using:CG.Name)"" is non-online state: $($Using:CG.State)"
                $ClusterMove = Get-ClusterGroup -Name $Using:CG.Name
                $Action = "None"
            }
            ElseIf ($Using:CG.OwnerNode -ne $Using:Node)
            {
                Write-Verbose "$(Get-Date): Windows Cluster Failover: Moving ""$($Using:CG.Name)"" to $($Using:Node)..."
                Try {
                    $ClusterMove = Move-ClusterGroup -Name $Using:CG.Name -Node $Using:Node -ErrorAction Stop
                    $Action = "Moved"
                }
                Catch {
                    $ClusterMove = Get-ClusterGroup -Name $Using:CG.Name
                    $Action = $Error[0]
                }
            }
            Else
            {
                Write-Verbose "$(Get-Date): Windows Cluster Failover: ""$($Using:CG.Name)"" already on $($Using:Node)"
                $ClusterMove = Get-ClusterGroup -Name $Using:CG.Name
                $Action = "None"
            }
            $ClusterMove | Add-Member -MemberType NoteProperty -Name Action -Value $Action
            Write-Output $ClusterMove
        }
        $NodeMove | Select Name,@{Name="PreviousNodeOwner";Expression={ $CG.OwnerNode }},OwnerNode,State,Action
    }
}
