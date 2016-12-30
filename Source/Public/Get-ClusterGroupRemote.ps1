Function Get-ClusterGroupRemote {
    <#
    .SYNOPSIS
        Get cluster group status for remote clusters
    .DESCRIPTION
        Get-ClusterGroup lacks remoting so you have to use Invoke-Command to get cluster group
        status remotely.  This script fixes that.  Requires remoting.
    .PARAMETER Cluster
        Name of the cluster, or a single node in the cluster
    .PARAMETER ClusterGroup
        Name of the cluster group you wish to get status for.  Defaults to all cluster groups.
    .PARAMETER Credential
        Alternative credential for PowerShell remoting
    .INPUTS
        None
    .OUTPUTS
        Object[]
    .EXAMPLE
        Get-ClusterGroupRemote -Cluster Test-Cluster -ClusterGroup "Cluster Group"

    .EXAMPLE
        Get-ClusterGroupRemote -Cluster Test-Cluster -ClusterGroup "Cluster Group","DFSShare"

    .EXAMPLE
        Get-ClusterGroupRemote -Cluster Test-Cluster -Credential test\surlyadmin

    .NOTES
        Author:             Martin Pugh
        Twitter:            @thesurlyadm1n
        Spiceworks:         Martin9700
        Blog:               www.thesurlyadmin.com
      
        Changelog:
            06/03/16        MLP - Initial Release
            06/03/16        MLP - Added credential
            06/15/16        MLP - Added support for Windows 2008 R2 clusters.  Will probably work with straight 2008 too.
    .LINK
        https://github.com/martin9700/Surly.PowerShell.SQL.Tools
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [ValidateScript({ Test-Connection $_ -Count 1 -Quiet })]
        [string[]]$Cluster,
        [string[]]$ClusterGroup = "*",
        [PSCredential]$Credential
    )

    Begin {
        $DefaultProperties = "Cluster","Name","OwnerNode","State"
    }

    Process {
        ForEach ($Cl in $Cluster)
        {
            $InvokeSplat = @{
                ComputerName = $Cl
                HideComputerName = $true
            }
            If ($Credential)
            {
                $InvokeSplat.Add("Credential",$Credential)
            }
            $Result = Invoke-Command @InvokeSplat -ScriptBlock {
                Import-Module FailoverClusters
                $ClusterSplat = @{}
                If ($Using:ClusterGroup -ne "*")
                {
                    $ClusterSplat.Add("Name",$Using:ClusterGroup)
                }
                Get-ClusterGroup @ClusterSplat
            }
            $Result | Add-Member MemberSet PSStandardMembers ([System.Management.Automation.PSMemberInfo[]]@(New-Object System.Management.Automation.PSPropertySet("DefaultDisplayPropertySet",[string[]]$DefaultProperties))) -PassThru
        }
    }
}
