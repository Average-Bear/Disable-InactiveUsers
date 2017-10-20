<#
.SYNOPSIS
    If users are inactive (not logged in for more than 90 days) they are disabled.
    If users are stale (not logged in for more than 120 days) they are disabled and moved to the 09_Inactive OU for removal.

.DESCRIPTION
    If users are inactive (not logged in for more than 90 days) they are disabled.
    If users are stale (not logged in for more than 120 days) they are disabled and moved to the 09_Inactive OU for removal.

.NOTES
    Written by: Jbear 
    Date: 3/11/2017

    Requires Active Directory Module
    This script is meant to be set as a scheduled task and run against and OU's specified in $SearchOU. 
    Reports are output to \\NetShare\Weekly Reports\Inactive Users\*
#>
param(

    [Parameter(ValueFromPipeline=$true,HelpMessage='Enter desired OU; (i.e. "OU=Users, DC=FOO, DC=BAR, DC=COM")')]
    [String[]]$SearchOU = @(

        "OU=01_Users, DC=ACME, DC=COM"
    )
)

Try {

    Import-Module ActiveDirectory -ErrorAction Stop
}

Catch {

    Write-Host -ForegroundColor Yellow "`nUnable to load Active Directory Module is required to run this script. Please, install RSAT and configure this server properly."
    Break
}

$LogDate = Get-Date -Format yyyyMMdd
$LogFile = "\\NetShare\Weekly Reports\Inactive Users\90 Days Inactive Users - "  + $logdate + ".csv"
$LogFile2 = "\\NetShare\Weekly Reports\Inactive Users\120 Days Inactive Users - "  + $logdate + ".csv"
$Time  = (Get-Date).Adddays(-(90))
$Time2 = (Get-Date).Adddays(-(120))

foreach($OU in $SearchOU) {

    #Get all AD users with LastLogon more than 90 days
    $FindInactive = Get-ADUser -SearchBase "$OU" -Filter {LastLogon -lt $Time} -Properties LastLogon, Description, SAMAccountName  
    $FindInactive = $FindInactive | Sort SamAccountName | Select Name, Enabled, Description, @{Name="LastLogon"; Expression={[DateTime]::FromFileTime($_.LastLogon)}}, DistinguishedName, SamAccountName

    #Add SamAccountNames to $InactiveUsers90 array
    $InactiveUsers90 = $FindInactive.SamAccountName

    #If array is empty, break from script
    if($InactiveUsers90 -eq $NULL) {
    
        Break
    }

    else {
        
        #Export information to $LogFile location
        $FindInactive | Export-CSV $LogFile -Append -NoTypeInformation -Force
        
        #Disable all accounts over 90 days
        $InactiveUsers90 | Disable-ADAccount
    }

    #Get all AD users with LastLogon more than 120 days
    $MoveInactive = Get-ADUser -SearchBase "$OU" -Filter {LastLogon -lt $Time2} -Properties LastLogon, Description, SAMAccountName
    $MoveInactive = $MoveInactive | Sort SamAccountName | Select Name, Enabled, Description, @{Name="LastLogon"; Expression={[DateTime]::FromFileTime($_.LastLogon)}}, DistinguishedName, SamAccountName

    #Add SamAccountNames to $InactiveUsers120 array
    $InactiveUsers120 = $MoveInactive.SamAccountName

    if($InactiveUsers120 -eq $NULL) {
    
        Break
    }

    else {

        $MoveInactive | Export-CSV $LogFile2 -Append -NoTypeInformation -Force

        foreach ($User in $InactiveUsers120) {

            $AccountsToDelete = 'OU=Accounts_to_Delete, OU=Users, DC=ACME, DC=COM'
               
            Get-ADUser -Filter {SamAccountName -eq "$User"} | Move-ADObject -TargetPath $AccountsToDelete
        }
    }
}
