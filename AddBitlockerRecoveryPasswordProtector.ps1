$ErrorActionPreference = "Stop"

Try {$Blstatus = (Get-BitLockerVolume -MountPoint $env:SystemDrive)}
Catch {
    Write-Output "Unable to get Bitlocker Status"
    Write-Output $Error[0].Exception
    Exit 11
}

If ($Blstatus.KeyProtector.KeyProtectorType -contains "RecoveryPassword") {
    Write-Output "Recovery password already present."
    Exit 1
}

Try {Add-BitLockerKeyProtector -MountPoint $env:SystemDrive -RecoveryPasswordProtector}
Catch {
    Write-Output "Unable to add Recovery Password Protector"
    Write-Output $Error[0].Exception
    Exit 12
}

Write-Output "Recover password added."
Exit 0