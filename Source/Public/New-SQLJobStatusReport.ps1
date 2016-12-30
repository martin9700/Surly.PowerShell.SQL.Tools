Function New-SQLJobStatusReport {
    <#
    .SYNOPSIS
        Leverage Get-SQLJobStatus script to produce an HTML report of SQL Job statuses.
    .DESCRIPTION
        Run Get-SQLJobStatus and pipe into New-SQLJobStatusReport to create a HTML report of job
        status.  Failed jobs will automatically be put at the top for easy triage.

    .PARAMETER InputObject
        This is the data from Get-SQLJobStatus.  Can either be piped in or run Get-SQLJobStatus as a 
        sub-expression.  

    .PARAMETER Path
        Path where you would like to save the resultant HTML report.  Report will be named SQLJobStatus.HTML.
        If path is not specified the default path will be the same folder where the script is saved.

    .INPUTS
        [PSCustomObject]
            [string]Instance
            [string]Job
            [datetime]Last Run
            [TimeSpan]Duration
            [string]Status
            [datetime]Next Run
    .OUTPUTS
        HTML report at $Path
    .EXAMPLE
        Get-SQLJobStatus -Name database1,database2 | New-SQLJobStatusReport -Path c:\path

        Get job status information from database 1 and 2 and create an HTML report.  Report will be saved
        by default in the same path as the script. 

    .EXAMPLE
        New-SQLJobStatusReport -InputObject (Get-SQLJobStatus -Name database3,database4) -Path c:\path

        Get job status information from database 3 and 4, create an HTML report and save it in c:\path

    .NOTES
        Author:             Martin Pugh
        Twitter:            @thesurlyadm1n
        Spiceworks:         Martin9700
        Blog:               www.thesurlyadmin.com
      
        Changelog:
            1.0             Initial Release
    .LINK
    
    #>
    #requires -Version 3.0
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true)]
        [PSCustomObject]$InputObject,

        [Parameter(Mandatory=$true)]
        [ValidateScript( { Test-Path $_ } )]
        [string]$Path
    )

    BEGIN {
        Write-Verbose "$(Get-Date): New-SQLJobStatusReport begins"

        $HTMLHeader = @"
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"  "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml"><head>
<style>
TABLE {border-width: 1px;border-style: solid;border-color: black;border-collapse: collapse; }
TR:Hover TD {Background-Color: #C1D5F8;}
TH {border-width: 1px;padding: 3px;border-style: solid;border-color: black;background-color: #00008B; color:white; }
TD {border-width: 1px;padding: 3px;border-style: solid;border-color: black;width: 5%; font-size:.8em; }
.odd { background-color: white; }
.even { background-color: #dddddd; }
span { font-size:.6em; }
</style>
<title>SQL Job Report</title>
</head>
<body>
<h1 style="text-align:center;">SQL Job Report</h1><br/>
"@

        $HTMLPath = Join-Path -Path $Path -ChildPath "SQLJobReport-$(Get-Date -Format "MM-dd-yyyy").html"
    }

    END {
        $Data = @($Input)

        #Validate object
        If ($Data)
        {
            $Properties = "Instance","Job","Last Run","Duration","Status","Next Run"
            $ObjectProperties = $Data[0] | Get-Member -MemberType Properties | Select -ExpandProperty Name
            If (Compare-Object -ReferenceObject $Properties -DifferenceObject $ObjectProperties)
            {
                Write-Error "$(Get-Date); Input object does not match object from Get-SQLJobStatus, aborting"
                Exit 999
            }

            Write-Verbose "$(Get-Date): Data successfully gathered for $(($Data | Select Instance -Unique).Count) servers"
            $Data = $Data | Sort Instance
            $Failed = $Data | Where Status -eq "Failed"
            $Successful = $Data | Where Status -ne "Failed"

            $FailedHTML = If ($Failed)
            {
                Write-Output "<div style='background-color: #ff0000;color: white;font-size: 120%;text-align: center;font-weight: bold;'>Failed Jobs</div>`n"
                $TableHTML = $Failed | ConvertTo-Html -Fragment | Set-GroupRowColorsByColumn -ColumnName Instance -CSSEvenClass even -CSSOddClass odd
                Write-Output $TableHTML.Replace("<td>Failed</td>","<td style='color: #ff0000;'>Failed</td>")
                Write-Output "<br/>"
            }

            $TableHTML = $Successful | ConvertTo-Html -Fragment | Set-GroupRowColorsByColumn -ColumnName Instance -CSSEvenClass even -CSSOddClass odd

            $HTML = @"
$HTMLHeader
$FailedHTML
<div style='background-color: green;color: white;font-size: 120%;text-align: center;font-weight: bold;'>Successful Backups</div>`n
$TableHTML
<br/>
<h5>Run on: $(Get-Date)</h5>
"@

            $HTML | Out-File $HTMLPath -Encoding ascii
        }
        Else
        {
            Write-Warning "$(Get-Date): No data input"
        }

        Write-Verbose "$(Get-Date): New-SQLJobStatusReport finished"
    }
}

