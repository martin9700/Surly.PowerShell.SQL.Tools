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
