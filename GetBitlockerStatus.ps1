#Nathan Engelhardt

#This script checks the bitlocker status of the system drive

#It is intended for use in environments where the system drive is
#to be protected by a TPM protector and a recovery password protector

#Exit code guide:
#0 System drive is encrypted, intended protectors are in place
#3 Recovery protectors are in place, encryption is in progress
#4 Encryption has been initiated, but requires a reboot to complete hardware tests before encryption begins
#6 System drive is not encrypted, and has not intention of becoming encrypted at this time
#7 TPM Protector is missing
#8 Recovery Password Protector is missing
#11 Unable to determine bitlocker status

#In the event of errors (exit code >10), error information is output


#Ensure stop action occurs on errors so we can catch the errors
$ErrorActionPreference = "Stop"

#Get the bitlocker status. If it fails, error out
Try {$Blstatus = (Get-BitLockerVolume -MountPoint $env:SystemDrive)}
Catch {
    Write-Output "Unable to get Bitlocker Status"
    Write-Output $Error[0].Exception
    Exit 11
}

If ($Blstatus.VolumeStatus -eq "FullyEncrypted") {
    If (-not ($Blstatus.KeyProtector.KeyProtectorType -contains "TPM")) {
        Write-Output "Bitlocker is enabled, but TPM protector is not present."
        Exit 7
    }
    ElseIf (-not ($Blstatus.KeyProtector.KeyProtectorType -contains "RecoveryPassword")) {
        Write-Output "Bitlocker is enabled, but Recovery Password protector is not present."
        Exit 8
    }
    Else {
        Write-Output "Bitlocker is enabled."
        Exit 0
    }
}

If ($Blstatus.VolumeStatus -eq "EncryptionInProgress") {
    If (-not ($Blstatus.KeyProtector.KeyProtectorType -contains "TPM")) {
        Write-Output "Bitlocker is encrypting, but TPM protector is not present."
        Exit 7
    }
    ElseIf (-not ($Blstatus.KeyProtector.KeyProtectorType -contains "RecoveryPassword")) {
        Write-Output "Bitlocker is encrypting, but Recovery Password protector is not present."
        Exit 8
    }
    Else {
        Write-Output "Bitlocker is encrypting."
        Exit 3
    }
}

If ($BLStatus.VolumeStatus -eq "FullyDecrypted") {
    If (-not ($BLStatus.EncryptionMethod -eq "None")) {
        Write-Output "Warning: Encryption initiated, but not completed. Please reboot."
        Exit 4
    }
    Else {
        Write-Output "Failed: System Drive is not encrypted."
        Exit 6
    }
}