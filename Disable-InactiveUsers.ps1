<#
.SYNOPSIS
    Inactive users (over 35 days) are disabled. Stale users (over 90 days) are moved to inactive OU.

.DESCRIPTION
    Script assists SysAdmins with the deletion of End-User home drives and to mitigate the Human Error factor; providing the checks and balances to maintain a clean enviroment.

.NOTES
    Author: JBear 3/11/2017
    Edited: JBear 6/22/2018
#>

[Cmdletbinding(SupportsShouldProcess)]
param(

    [Parameter(DontShow)]
    [String[]]$SearchOU = @(

        "OU=RR, OU=Users, DC=ACME, DC=COM",
        "OU=WC, OU=Users, DC=ACME, DC=COM",
        "OU=YS, OU=Users, DC=ACME, DC=COM",
        "OU=ZT, OU=Users, DC=ACME, DC=COM"
    ),

    [Parameter(DontShow)]
    $InactiveOU = 'OU=Disabled Accounts, DC=ACME, DC=COM',

    [Parameter(DontShow)]
    $LogDate = (Get-Date -Format yyyyMMdd),
    
    [Parameter(DontShow)]
    $LogFile = "\\ServerShare01\WeeklyReports\DisabledUsers\35DaysInactive-$($logdate).csv",
    
    [Parameter(DontShow)]
    $LogFile2 = "\\ServerShare01\WeeklyReports\DisabledUsers\90DaysInactive-$($logdate).csv",
    
    [Parameter(DontShow)]
    $Time  = (Get-Date).Adddays(-(35)),
    
    [Parameter(DontShow)]
    $Time2 = (Get-Date).Adddays(-(90))
)

Try {

    Import-Module ActiveDirectory -ErrorAction Stop
}

Catch {

    Write-Host -ForegroundColor Yellow "`nUnable to reach Active Directory Module."
    Break
}

$DCs = (Get-ADComputer -SearchBase "OU=Domain Controllers, DC=ACME, DC=COM" -Filter *).Name

function GetInactive {
[Cmdletbinding(SupportsShouldProcess)]
param()

    $LastLogon = foreach($DC in $DCs) {

        foreach($OU in $SearchOU) {

            #Get all AD users with LastLogon more than 35 days
            Get-ADUser -Server $DC -SearchBase $OU -Filter { LastLogon -lt $Time } -Properties LastLogon, Description, SAMAccountName, WhenCreated | Sort Name
        }
    }

    $Inactive = $(

        $Users = ($LastLogon | Select SamAccountName -Unique | Sort SamAccountName).SamAccountName
    
        foreach($User in $Users) {
    
            ($LastLogon | Where { $_.SamAccountName -Match $User } | Sort LastLogon -Descending)[0]
        }
    )

    foreach($Item in $Inactive) {

        $DateTime = [DateTime]::FromFileTime($Item.LastLogon)
        $Inactive35 = $( $DateTime -lt $Time ) | Where { $Item.Lastlogon -ne 0 }
        $Inactive90 = $( $DateTime -lt $Time2 ) | Where { $Item.Lastlogon -ne 0 }

        [PSCustomObject] @{
            
            Name=$Item.Name
            SamAccountName = $Item.SamAccountName
            WhenCreated = $Item.WhenCreated
            Enabled = $Item.Enabled
            Description = $Item.Description
            LastLogonValue = [String]$Item.LastLogon
            LastLogonDate = $DateTime
            DistinguishedName = $Item.DistinguishedName
            Inactive35 = $Inactive35
            Inactive90 = $Inactive90
        }
    }
}

function DisableUsers {
[Cmdletbinding(SupportsShouldProcess)]
param()
    
    $Getinactive | Where { $_.WhenCreated -lt $Time } | Select * -Unique | Export-CSV $LogFile -Append -NoTypeInformation -Force
    $GetInactive | Where { $_.Inactive90 -eq $true -and $_.WhenCreated -lt $Time } | Select * -Unique | Export-CSV $LogFile2 -Append -NoTypeInformation -Force

    #Disable all accounts over 35 days
    ($GetInactive | Where { $_.WhenCreated -lt $Time }).SamAccountName | Select -Unique | Disable-ADAccount

    $Users = ($GetInactive | Where {$_.Inactive90 -eq $true -and $_.WhenCreated -lt $Time}).SamAccountName | Select -Unique
    
    foreach($User in $Users) {
    
        Get-ADUser $User | Move-ADObject -TargetPath $InactiveOU
    }
}

#Call and store GetInactive function
$Getinactive = GetInactive

#Call DisableUsers function
DisableUsers
