#Exit Code Legend

#0: Enabled, Success
#11: Encryption in Progress
#12: Already Encrypted
#13: Unable to get computer info
#14: Computer role invalid, or computer not a workstation

#21: Unable to get bitlocker status
#22: Encryption intiated, but not completed. Device may need rebooting. May also require manual review.
#23: Unable to verify connection to domain. Please verify connection to the domain, reboot, and try again.

#32: Unable to obtain status of key protectors
#33: Unable to obtain status of TPM protector

#41: Unable to remove existing key protector

#51: Unable to add Password Protector
#52: Unable to move exiting Recovery Key directory

#61: Unable to enable Bitlocker
#63: Unable to back up key to AD


#83: Unable to roll back password recovery protector.

$LogDir = ($env:SystemDrive + "\BitlockerScriptLogs\")

$DatedLogDir = ($LogDir + (Get-Date -Format "yyyy-MM-dd") + "\")

If (-not (Get-Item $DatedLogDir -ErrorAction SilentlyContinue)) {
    New-Item -Path $DatedLogDir -ItemType "directory"
}

Start-Transcript -Path ($DatedLogDir + (Get-Date -Format "HH-mm-ss") + ".log")

$ErrorActionPreference = "Stop"

Try {$ComputerInfo = Get-ComputerInfo}
Catch {
    Write-Output "Unable to get computer info"
    Write-Output $_
    Exit 13
}

If (-not (($ComputerInfo.CsDomainRole -eq "MemberWorkstation") -or ($ComputerInfo.CsDomainRole -eq "StandaloneWorkstation"))) {
    Write-Output "Error 14: Computer role invalid, or computer not a workstation"
    Exit 14
}
Else {
    $ComputerRole = ($ComputerInfo.CsDomainRole)
    $ComputerDomain = ($ComputerInfo.CsDomain)
    If ($ComputerRole -eq "StandaloneWorkstation") {$DomainJoined = $false}
    If ($ComputerRole -eq "MemberWorkstation") {$DomainJoined = $true}
}

$MP = $env:SystemDrive

#Get the volume status
Try {$BLStatus = (Get-BitLockerVolume -MountPoint $MP)}
Catch {
    Write-Output "Unable to get Bitlocker status. Exiting"
    Write-Output $_
    Exit 21
}

#If Volume is already encrypted, or in progress, output as such

If ($BLStatus.VolumeStatus -eq "EncryptionInProgress") {
    Write-Output "Encryption is already in Progress. Exiting"
    Write-Output $_
    Exit 11
}

If ($BLStatus.VolumeStatus -eq "FullyEncrypted") {
    Write-Output "Encryption already completed. Exiting."
    Write-Output $_
    Exit 12
}

If (-not ($BLStatus.EncryptionMethod -eq "None")) {
    Write-Output "Encryption intiated, but not completed. Device may need rebooting. May also require manual review. Exiting."
    Write-Output $_
    Exit 22
}

Try {$TPMInfo = (Get-Tpm)}
Catch {
    Write-Output "Unable to get TPM info"
    Write-Output $PSItem
    Exit 24
}

If (-not $TPMInfo.TpmReady) {
    Write-Output "TPM not ready. Exiting"
    Exit 25
}

If ($DomainJoined) {

    Write-Output "Computer is joined to a domain. Proceeding with domain-joined bitlocker enablement."

    Write-Output "Testing connection to domain..."

    $domain = $ComputerDomain


    If (-not ((Test-ComputerSecureChannel) -and ((Test-NetConnection $domain).PingSucceeded))) {
        Write-Output "Connection to domain failed. Attempting to repair..."
        $i = 0
        $s = $false
        While ((!($s)) -and ($i -le 20)) {
            $Error.Clear()
            Try {Test-ComputerSecureChannel -Repair}
            Catch {$i++}
            if (!($Error)) {
                $s = ((Test-NetConnection -ComputerName $domain).PingSucceeded)
            }
        }
        if (-not $s) {
            Write-Output "Failed to repair connection to domain. Exiting. Error 23."
            Exit 23
        }
        Write-Output "Succesfully repaired connection to domain. Continuing..."
    }

    If ($BLStatus.VolumeStatus -eq "FullyDecrypted") {
        Write-Output "Beginning encryption process..."

        #Check if there are key protectors
        Write-Output "Checking for presence of other key protectors..."
        Try {$KeyProtectors = ((Get-BitLockerVolume -MountPoint $MP).KeyProtector)}
        Catch {
            Write-Output "Unable to obtain status of key protectors. Error 32. Exiting."
            Write-Output $_
            Exit 32
        }

        #Remove exisiting key protectors
        If ($KeyProtectors) {
            Write-Output "Existing Key Protectors found. Removing..."
            foreach ($KP in $KeyProtectors) {
                Write-Output ("Removing Key protector: " + [String]$KP.KeyProtectorType + " | " + [String]$KP.KeyProtectorID)
                Try {Remove-BitLockerKeyProtector -MountPoint $MP -KeyProtectorId $KP.KeyProtectorId}
                Catch {
                    Write-Output ("Unable to remove existing Key protector: " + [String]$KP.KeyProtectorType + " | " + [String]$KP.KeyProtectorID +" | Error 41. Exiting")
                    Write-Output $_
                    Exit 41
                }
            }
        }

        Write-Output "Adding Recovery Password Protector..."

        Try {Add-BitLockerKeyProtector -RecoveryPasswordProtector -MountPoint $MP}
        Catch {
            Write-Output "Failed to add Recovery Password protector."
            Exit 51
        }

        Write-Output "Retrieving recovery password..."

        Try {$RecoveryPasswords = (((Get-BitLockerVolume -MountPoint $MP).KeyProtector) | Where-Object {$_.KeyProtectorType -eq "RecoveryPassword"})}
        Catch {
            Write-Output "Could not retrieve Recovery Password. Error 62. Exiting."
            Write-Output $_
        }

        Write-Output "Backing up recovery password to AD..."

        Foreach ($pass in $RecoveryPasswords) {
            Try {Backup-BitLockerKeyProtector -KeyProtectorId $pass.KeyProtectorID -MountPoint $MP}
            Catch {
                Write-Output "Unable to backup key to AD."
                Write-Output $_
                Write-Output "Rolling back Recovery Password protector..."
                Try {Remove-BitLockerKeyProtector -MountPoint $MP -KeyProtectorId $pass.KeyProtectorID}
                Catch {
                    Write-Output "Unable to roll back. MANUAL INTERVENTION REQUIRED. Error 83. Exiting."
                    Write-Output $_
                    Exit 83
                }
                Exit 63
            }
        }


        Write-Output "Enabling Bitlocker with TPM"
        Try {Enable-BitLocker -MountPoint $MP -EncryptionMethod XtsAes256 -TpmProtector}
        Catch {
            Write-Output "Unable to enable bitlocker. Error 61. Exiting."
            Write-Output $_

            Write-Output "Rolling back Recovery Password protector..."
            foreach ($pass in $RecoveryPasswords) {
                Try {Remove-BitLockerKeyProtector -MountPoint $MP -KeyProtectorId $pass.KeyProtectorID}
                Catch {
                    Write-Output "Unable to roll back. MANUAL INTERVENTION REQUIRED. Error 83. Exiting."
                    Write-Output $_
                    Exit 83
                }
            }
            Exit 61
        }
        Write-Output "Succesfully enabled bitlocker. Restart to finish."
        Exit 0
    }
}

If (-not $DomainJoined) {

    Write-Output "Computer is not domain joined. Proceeding with standalone bitlocker enablement."

    If ($BLStatus.VolumeStatus -eq "FullyDecrypted") {
        Write-Output "Beginning encryption process..."

        #Check if there are key protectors
        Write-Output "Checking for presence of other key protectors..."
        Try {$KeyProtectors = ((Get-BitLockerVolume -MountPoint $MP).KeyProtector)}
        Catch {
            Write-Output "Unable to obtain status of key protectors. Error 32. Exiting."
            Write-Output $_
            Exit 32
        }

        #Remove exisiting key protectors
        If ($KeyProtectors) {
            Write-Output "Existing Key Protectors found. Removing..."
            foreach ($KP in $KeyProtectors) {
                Write-Output ("Removing Key protector: " + [String]$KP.KeyProtectorType + " | " + [String]$KP.KeyProtectorID)
                Try {Remove-BitLockerKeyProtector -MountPoint $MP -KeyProtectorId $KP.KeyProtectorId}
                Catch {
                    Write-Output ("Unable to remove existing Key protector: " + [String]$KP.KeyProtectorType + " | " + [String]$KP.KeyProtectorID +" | Error 41. Exiting")
                    Write-Output $_
                    Exit 41
                }
            }
        }

        Write-Output "Adding Recovery Password Protector..."

        Try {Add-BitLockerKeyProtector -RecoveryPasswordProtector -MountPoint $MP}
        Catch {
            Write-Output "Failed to add Recovery Password protector."
            Exit 51
        }

        Write-Output "Enabling Bitlocker with TPM"
        Try {Enable-BitLocker -MountPoint $MP -EncryptionMethod XtsAes256 -TpmProtector}
        Catch {
            Write-Output "Unable to enable bitlocker. Error 61. Exiting."
            Write-Output $_

            Write-Output "Rolling back Recovery Password protector..."
            foreach ($pass in $RecoveryPasswords) {
                Try {Remove-BitLockerKeyProtector -MountPoint $MP -KeyProtectorId $pass.KeyProtectorID}
                Catch {
                    Write-Output "Unable to roll back. MANUAL INTERVENTION REQUIRED. Error 83. Exiting."
                    Write-Output $_
                    Exit 83
                }
            }
            Exit 61
        }
        Write-Output "Succesfully enabled bitlocker. Restart to finish."
        Exit 0
    }
}