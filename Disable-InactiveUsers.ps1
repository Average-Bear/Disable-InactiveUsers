<#
.SYNOPSIS
    Inactive users (over 30 days) are disabled. Stale users (over 90 days) are moved to inactive OU.

.DESCRIPTION
    Inactive users (over 30 days) are disabled. Stale users (over 90 days) are moved to inactive OU.

.DESCRIPTION
    Script assists SysAdmins with the deletion of End-User home drives and to mitigate the Human Error factor; providing the checks and balances to maintain a clean enviroment.

.NOTES
    Author: JBear 3/11/2017
    Edited: JBear 3/24/2018
#>

[Cmdletbinding(SupportsShouldProcess)]
param(

    [Parameter(DontShow)]
    [String[]]$SearchOU = @(

        "OU=01_Users, DC=ACME, DC=COM"
    ),

    [Parameter(DontShow)]
    $InactiveOU = 'OU=11_InactiveUsers, DC=ACME, DC=COM',

    [Parameter(DontShow)]
    $LogDate = (Get-Date -format yyyyMMdd),
    
    [Parameter(DontShow)]
    $LogFile = "\\ACMESHARE\IT\Reports\DisabledUsers\30DayInactive-$($logdate).csv",
    
    [Parameter(DontShow)]
    $LogFile2 = "\\ACMESHARE\IT\Reports\DisabledUsers\90DayInactive-$($logdate).csv",
    
    [Parameter(DontShow)]
    $Time  = (Get-Date).Adddays(-(30)),
    
    [Parameter(DontShow)]
    $Time2 = (Get-Date).Adddays(-(90)),

    [Parameter(DontShow)]
    $Days = @($Time, $Time2)
)

Try {

    Import-Module ActiveDirectory -ErrorAction Stop
}

Catch {

    Write-Host -ForegroundColor Yellow "`nUnable to reach Active Directory Module."
    Break
}

function GetInactive {
[Cmdletbinding(SupportsShouldProcess)]param()

    foreach($OU in $SearchOU) {
        
        foreach($D in $Days) {

            #Get all AD users with LastLogon more than 30 days
            $Inactive = Get-ADUser -SearchBase $OU -Filter {LastLogon -lt $D} -Properties LastLogon, Description, SAMAccountName | Sort Name | 
                Select Name, Enabled, Description, Lastlogon, DistinguishedName, SamAccountName
            
            
            foreach($Item in $Inactive) {

                $DateTime = [DateTime]::FromFileTime($Item.LastLogon)
                $Inactive30 = $( $DateTime -lt $Time ) | Where { $Item.Lastlogon -ne 0 }
                $Inactive90 = $( $DateTime -lt $Time2 ) | Where { $Item.Lastlogon -ne 0 }

                [PSCustomObject] @{
            
                    Name=$Item.Name
                    Enabled=$Item.Enabled
                    Description=$Item.Description
                    LastLogonValue=$Item.LastLogon
                    LastLogonDate=$DateTime
                    DistinguishedName=$Item.DistinguishedName
                    SamAccountName=$Item.SamAccountName
                    Inactive30 = $Inactive30
                    Inactive90 = $Inactive90
                }
            }
        }
    }
}

function DisableUsers {
[Cmdletbinding(SupportsShouldProcess)]param()

    $Getinactive | Select * -Unique | Export-CSV $LogFile -Append -NoTypeInformation -Force
    $GetInactive | Where { $_.Inactive90 -eq $true } | Select * -Unique | Export-CSV $LogFile2 -Append -NoTypeInformation -Force

    #Disable all accounts over 30 days
    $GetInactive.SamAccountName | Select -Unique | Disable-ADAccount

    ($GetInactive | Where {$_.Inactive90 -eq $true}).SamAccountName | Select -Unique | Get-ADUser -Filter {SamAccountName -like "*$_*"} | Move-ADObject -TargetPath $InactiveOU
}

#Call and store GetInactive function
$Getinactive = GetInactive

#Call DisableUsers function
DisableUsers
