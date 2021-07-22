Try {$BLStatus = Get-BitLockerVolume -MountPoint $env:SystemDrive}
Catch {
    Write-Output "Failed: Unable to get bitlocker status"
    Write-Output $_
    Exit 31
}
If ($BLStatus.VolumeStatus -eq "FullyEncrypted") {
    Write-Output "Success: System Drive is encrypted"
    Exit 0
}
If ($BLStatus.VolumeStatus -eq "EncryptionInProgress") {
    Write-Output "Success: System Drive encryption is in progress"
    Exit 11
}
If ($BLStatus.VolumeStatus -eq "FullyDecrypted") {
    If (-not ($BLStatus.EncryptionMethod -eq "None")) {
        Write-Output "Warning: Encryption initiated, but not completed. Please reboot."
        Exit 21
    }
    Write-Output "Failed: System Drive is not encrypted."
    Exit 32
}