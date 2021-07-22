$ErrorActionPreference = "Stop"

Try {$Blstatus = (Get-BitLockerVolume -MountPoint $env:SystemDrive)}
Catch {
    Write-Output "Unable to get Bitlocker Status"
    Write-Output $Error[0].Exception
    Exit 11
}

If ($Blstatus.KeyProtector.KeyProtectorType -contains "TPM") {
    Write-Output "TPM protector already present."
    Exit 1
}

Try {Add-BitLockerKeyProtector -MountPoint $env:SystemDrive -TpmProtector}
Catch {
    Write-Output "Unable to add TPM Protector"
    Write-Output $Error[0].Exception
    Exit 12
}

Write-Output "TPM Protectors added."
Exit 0