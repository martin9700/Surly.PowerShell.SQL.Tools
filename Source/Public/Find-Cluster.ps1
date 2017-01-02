Function Find-Cluster {
    <#
    #>
    [CmdletBinding()]
    Param (
        [string]$Name = "*",

        [string[]]$Exclude,

        [switch]$ExcludeDisabled
    )
    $Excludes = $Exclude -join "|"

    #Locate the raw clusters
    $RawClusters = Get-ADComputer -Filter { servicePrincipalName -like "*MSServerCluster/*" } -Properties servicePrincipalName | Where Name -like $Name | Select Name,DNSHostName,Enabled
    $Count = 0
    ForEach ($Cluster in $RawClusters)
    {
        If ($Exclude -and $Cluster.Name -match $Excludes)
        {
            Continue
        }
        If ($ExcludeDisabled -and $Cluster.Enabled -eq $false)
        {
            Continue
        }
        $Cluster | Add-Member -MemberType NoteProperty -Name "PSTypeName" -Value "FailoverCluster.Name"

        Write-Output $Cluster
        $Count ++
    }
    Write-Verbose "Found $Count Windows Clusters"
}
