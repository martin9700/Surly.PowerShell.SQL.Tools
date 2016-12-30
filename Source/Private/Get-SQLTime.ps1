Function Get-SQLTime {
    Param (
        [int]$Time
    )

    $Duration = $Time.ToString().PadLeft(6,"0")
    Return New-TimeSpan -Hours $Duration.SubString(0,2) -Minutes $Duration.SubString(2,2) -Seconds $Duration.SubString(4,2)
}