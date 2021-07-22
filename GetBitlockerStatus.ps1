$ErrorActionPreference = "Stop"

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