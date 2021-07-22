#Nathan Engelhardt

#This script verifies there's a TPM protector on the system drive
#If there is not, it adds one.

#Exit code guide:
#0 - Succesfully added TPM protector
#1 - TPM protector already present
#11 - Unable to obtain bitlocker status
#12 - Unable to add TPM protector

#In the event of errors (exit code >10), error information is output

#If there's an error, stop so we can catch it.
$ErrorActionPreference = "Stop"


#Check the current status. If we can't get the status, error out.
Try {$Blstatus = (Get-BitLockerVolume -MountPoint $env:SystemDrive)}
Catch {
    Write-Output "Unable to get Bitlocker Status"
    Write-Output $Error[0].Exception
    Exit 11
}


#If there's already a TPM protector, error out. We don't want to try
#to have more than one of those.
If ($Blstatus.KeyProtector.KeyProtectorType -contains "TPM") {
    Write-Output "TPM protector already present."
    Exit 1
}


#If we got this far, there's not TPM protector. Add one.
#If we fail to add one, error out.
Try {Add-BitLockerKeyProtector -MountPoint $env:SystemDrive -TpmProtector}
Catch {
    Write-Output "Unable to add TPM Protector"
    Write-Output $Error[0].Exception
    Exit 12
}

#If we got this far, we succesfully added a TPM protector.
#Let the folks at home know and exit 0.
Write-Output "TPM Protectors added."
Exit 0