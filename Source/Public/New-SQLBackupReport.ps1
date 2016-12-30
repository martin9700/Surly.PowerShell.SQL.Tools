Function New-SQLBackupReport {
    <#
    .SYNOPSIS
        Get a report of all of your SQL servers and their last backup status.
    .DESCRIPTION
        This script requires Get-SQLBackupStatus.  Run that script and pipe it into New-SQLBackupReport to generate
        a HTML report of the results.
    .PARAMETER InputObject
        Object data from Get-SQLBackupStatus
    .PARAMETER Path
        Path where to save the resultant HTML file
    .INPUTS
        Get-SQLBackupStatus
    .OUTPUTS
        None
    .EXAMPLE
        Get-SQLBackupStatus -Name SQL-AG-01 | New-SQLBackupReport -Path c:\reports
    .NOTES
        Author:             Martin Pugh
        Twitter:            @thesurlyadm1n
        Spiceworks:         Martin9700
        Blog:               www.thesurlyadmin.com
      
        Changelog:
            1.0             Initial Release
            1.0.1           Fix issue #2
            1.1             Updated help and added to PS.SQL.  Removed imbedded functions and put them in the module.  
                            Split into two functions, Get-SQLBackupStatus and New-SQLBackupReport to better match up with 
                            Get-SQLJobStatus and New-SQLJobStatusReport
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true)]
        [PSCustomObject[]]$InputObject,
        
        [Parameter(Mandatory=$true)]
        [ValidateScript( { Test-Path $_ } )]
        [string]$Path
    )

    BEGIN {
        Write-Verbose "$(Get-Date): New-SQLBackupReport generating report..."

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
<title>SQL Backup Report</title>
</head>
<body>
<h1 style="text-align:center;">SQL Backup Report</h1><br/>
"@
    }

    END {
        $BackupSets = @($Input)

    #Validate object
        If ($BackupSets)
        {
            $Properties = "Backup Size","Backup Status","Database","Days Since Last Backup","Last Backup","Last T-Log Backup","Recovery Model","Server"
            $ObjectProperties = $BackupSets[0] | Get-Member -MemberType Properties | Select -ExpandProperty Name
            If (Compare-Object -ReferenceObject $Properties -DifferenceObject $ObjectProperties)
            {
                Write-Error "$(Get-Date); Input object does not match object from Get-SQLJobStatus, aborting"
                Exit 999
            }
            $BackupSets = $BackupSets | Sort Server,Database
            $Failed = $BackupSets | Where "Backup Status" -eq "Failed"
            $Successful = $BackupSets | Where "Backup Status" -ne "Failed"

            $FailedHTML = If ($Failed)
            {
                Write-Output "<div style='background-color: #ff0000;color: white;font-size: 120%;text-align: center;font-weight: bold;'>Failed Backups</div>`n"
                $TableHTML = $Failed | ConvertTo-Html -Fragment | Set-GroupRowColorsByColumn -ColumnName Server -CSSEvenClass even -CSSOddClass odd
                Write-Output $TableHTML.Replace("<td>Failed</td>","<td style='color: #ff0000;'>Failed</td>")
                Write-Output "<br/>"
            }
            $TableHTML = $Successful | ConvertTo-Html -Fragment | Set-GroupRowColorsByColumn -ColumnName Server -CSSEvenClass even -CSSOddClass odd


            $HTML = @"
$HTMLHeader
$FailedHTML
<div style='background-color: green;color: white;font-size: 120%;text-align: center;font-weight: bold;'>Successful Backups</div>`n
$TableHTML
<br/>
<span>Run on: $(Get-Date)</span>
"@

            Write-Verbose "$(Get-Date): Saving report..."
            #Save New Report
            $OutputFile = Join-Path -Path $Path -ChildPath "SQLBackup-$(Get-Date -Format 'MM-dd-yyyy').html"
            $HTML | Out-File $OutputFile -Encoding ascii
        }

        Write-Verbose "$(Get-Date): New-SQLBackupReport complete"
    }
}

