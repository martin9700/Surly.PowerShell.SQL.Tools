Function Set-GroupRowColorsByColumn {
    <#
    .SYNOPSIS
        Alternate HTML table colors based on the value of a column
    .PARAMETER InputObject
        The HTML you wish to work on.  Does not have to be a table fragment, will work on full HTML files.
    .PARAMETER ColumnName
        Name of the column you want to key the color changes on.  Every time the column changes value the background row color will change, so make sure you sort
    .PARAMETER CSSEvenClass
        Your HTML must have CSS with a class called TREVEN, and this defines how you want the row to look
    .PARAMETER CSSOddClass
        This defines the CSS class that opposite rows will use
    .INPUTS
        HTML
    .OUTPUTS
        HTML
    .EXAMPLE
        $Header = @"
        <style>
        TABLE {border-width: 1px;border-style: solid;border-color: black;border-collapse: collapse;}
        TH {border-width: 1px;padding: 3px;border-style: solid;border-color: black;background-color: #6495ED;}
        TD {border-width: 1px;padding: 3px;border-style: solid;border-color: black;}
        .odd  { background-color:#ffffff; }
        .even { background-color:#dddddd; }
        </style>
        "@

        Get-Process | Sort ProcessName |  ConvertTo-HTML -Head $Header | Set-GroupRowColorsByColumn -Column ProcessName -CSSEvenClass even -CSSOddClass odd | Out-File .\Processes.HTML
    .NOTES
        Author:             Martin Pugh
        Twitter:            @thesurlyadm1n
        Spiceworks:         Martin9700
        Blog:               www.thesurlyadmin.com
      
        Changelog:
            1.0             Initial Release
            1.01            Added help, added to PS.SQL Module
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory,ValueFromPipeline)]
        [string[]]$InputObject,
        [Parameter(Mandatory)]
        [string]$ColumnName,
        [string]$CSSEvenClass = "TREven",
        [string]$CSSOddClass = "TROdd"
    )
    Process {
        $NewHTML = ForEach ($Line in $InputObject)
        {
            If ($Line -like "*<th>*")
            {
                If ($Line -notlike "*$ColumnName*")
                {
                    Write-Error "Unable to locate a column named $ColumnName"
                    Exit 999
                }
                $Search = $Line | Select-String -Pattern "<th>.*?</th>" -AllMatches
                $Index = 0
                ForEach ($Column in $Search.Matches)
                {
                    If (($Column.Groups.Value -replace "<th>|</th>","") -eq $ColumnName)
                    {
                        Break
                    }
                    $Index ++
                }
            }
            If ($Line -like "*<td>*")
            {
                $Search = $Line | Select-String -Pattern "<td>.*?</td>" -AllMatches
                If ($LastColumn -ne $Search.Matches[$Index].Value)
                {
                    If ($Class -eq $CSSEvenClass)
                    {
                        $Class = $CSSOddClass
                    }
                    Else
                    {
                        $Class = $CSSEvenClass
                    }
                }
                $LastColumn = $Search.Matches[$Index].Value
                $Line = $Line.Replace("<tr>","<tr class=""$Class"">")
            }
            Write-Output $Line
        }
        Write-Output $NewHTML
    }
}

