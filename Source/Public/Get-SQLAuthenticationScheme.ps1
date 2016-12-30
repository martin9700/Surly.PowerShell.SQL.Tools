<#
.SYNOPSIS
    Get authentication scheme for a SQL server(s)    
.PARAMETER Instance
    Server or instance name for the SQL server
.PARAMETER Credential
    Credential needed for SQL server
.INPUTS
    None
.OUTPUTS
    None
.EXAMPLE
    Get-SQLAuthenticationScheme -Instance SQL-SVR-01

    Instance   net_transport auth_scheme
    --------   ------------- -----------
    sql-svr-01 TCP           KERBEROS

.NOTES
    Author:             Martin Pugh
    Twitter:            @thesurlyadm1n
    Spiceworks:         Martin9700
    Blog:               www.thesurlyadmin.com
      
    Changelog:
        1.0             Initial Release
        1.01            Added help and added to PS.SQL

#>
#requires -Version 3.0
Function Get-SQLAuthenticationScheme {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory)]
        [string[]]$Instance,
        [pscredential]$Credential
    )

    Invoke-SQLQuery -Instance $Instance -MultiSubnetFailover -Database Master -Query "SELECT net_transport, auth_scheme FROM sys.dm_exec_connections WHERE session_id = @@spid"
}



    