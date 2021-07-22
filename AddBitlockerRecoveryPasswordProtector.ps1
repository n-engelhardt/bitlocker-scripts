#Nathan Engelhardt

#This script verifies there's a Recovery Password protector on the system drive
#If there is not, it adds one.

#Exit code guide:
#0 - Succesfully added recovery password protector
#1 - Recovery password protector already present
#11 - Unable to obtain bitlocker status
#12 - Unable to add recovery password protector

#In the event of errors (exit code >10), error information is output


#In the event of errors (exit code >10), error information is output

#If there's an error, stop so we can catch it
$ErrorActionPreference = "Stop"

#Attempt to determine the status. Error out if failure.
Try {$Blstatus = (Get-BitLockerVolume -MountPoint $env:SystemDrive)}
Catch {
    Write-Output "Unable to get Bitlocker Status"
    Write-Output $Error[0].Exception
    Exit 11
}

#If there's already a recovery password, quit. We don't want more than one.
If ($Blstatus.KeyProtector.KeyProtectorType -contains "RecoveryPassword") {
    Write-Output "Recovery password already present."
    Exit 1
}


#If we got this far, that means there's not a recovery password. Try to add one.
#If we fail to add one, error out.
Try {Add-BitLockerKeyProtector -MountPoint $env:SystemDrive -RecoveryPasswordProtector}
Catch {
    Write-Output "Unable to add Recovery Password Protector"
    Write-Output $Error[0].Exception
    Exit 12
}


#If we got this far, we succesfully added the recovery password.
#Let people know we succeeded, then exit 0
Write-Output "Recovery password added."
Exit 0