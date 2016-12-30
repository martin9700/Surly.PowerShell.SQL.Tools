Function Get-Size {
    Param (
        [float]$Size
    )

    If ($Size -ge 1000000000)
    {
        Write-Output ("{0:N2} GB" -f ($Size / 1gb))
    }
    ElseIf ($Size -gt 0)
    {
        Write-Output ("{0:N2} MB" -f ($Size / 1mb))
    }
    Else
    {
        Write-Output $null
    }
}