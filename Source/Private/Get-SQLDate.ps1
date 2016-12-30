Function Get-SQLDate {
    Param (
        [int]$Date,
        [int]$Time
    )

    $RunDate = $Date.ToString()
    $RunTime = $Time.ToString().PadLeft(6,"0")
    Return Get-Date ("$($RunDate.SubString(4,2))/$($RunDate.SubString(6,2))/$($RunDate.Substring(0,4)) $($RunTime.SubString(0,2)):$($RunTime.SubString(2,2)):$($RunTime.SubString(4,2))")
}