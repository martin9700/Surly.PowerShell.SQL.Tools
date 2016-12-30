Function ValidateAGClusterObject {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true)]
        [object[]]$InputObject
    )

    BEGIN {
        $ValidatePropertySet = "AvailabilityGroup","AvailabilityDatabases","ListenerDNSName","AvailabilityGroupID"
        Write-Verbose "$(Get-Date): Validating object..."
    }

    PROCESS {
        ForEach ($AGObject in $InputObject)
        {
            $Properties = $AGObject | Get-Member -MemberType NoteProperty | Select -ExpandProperty Name
            If (@(Compare-Object -ReferenceObject $ValidatePropertySet -DifferenceObject $Properties | Where SideIndicator -eq "<=").Count)
            {
                Write-Error "Input object did not contain required properties, you must use Get-AGCluster to pipe into this function"
                Exit 999
            }
        }
    }
}