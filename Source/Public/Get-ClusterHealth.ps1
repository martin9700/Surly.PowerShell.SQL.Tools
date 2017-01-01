Function Get-ClusterHealth {
    <#
    #>



        #Now let's get some information on them
    ForEach ($Cluster in $RawClusters)
    {
        Write-Verbose "$(Get-Date):Gathering cluster information from $($Cluster.Name)"
        Try {
            $ClusterObject = Get-Cluster -Name $Cluster.DNSHostName -ErrorAction Stop
            $Nodes = $ClusterObject | Get-ClusterNode
            $ClusterGroups = $ClusterObject | Get-ClusterGroup
        }
        Catch {
            [PSCustomObject]@{
                Cluster            = $Cluster.Name
                Enabled            = $Cluster.Enabled
                Nodes              = "Error Connecting"
                ClusterGroups      = $_.Exception.Message
                IsAG               = $null
                AvailabilityGroups = $null
            }
            Continue
        }

        $IsAG = $false
        Try {
            $AGs = Get-AGCluster -ComputerName $Cluster.DNSHostName -ErrorAction Stop
            $Filter = ($AGs.AvailabilityGroup) -join '|'
            $ClusterGroups = $ClusterGroups | Where Name -notmatch $Filter
            $IsAG = $true
        }
        Catch {
            If ($_.Exception.Message -like "*login failed*")
            {
                Write-Warning "Unable to query, need to configure PROD\WinFailover on the SQL server"
            }
            Else
            {
                Write-Verbose "No AG on this cluster"
            }
            $AGs = $null
        }
        [PSCustomObject]@{
            Cluster            = $Cluster.Name
            Enabled            = $Cluster.Enabled
            Nodes              = $Nodes | Select Name,State
            ClusterGroups      = $ClusterGroups | Select Name,State
            IsAG               = $IsAg
            AvailabilityGroups = $AGs | Select @{Name="Name";Expression={ $_.AvailabilityGroup }},@{Name="State";Expression={ $_.HealthState }}
        }
    }

}