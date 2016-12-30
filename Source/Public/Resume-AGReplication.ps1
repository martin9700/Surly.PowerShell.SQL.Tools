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