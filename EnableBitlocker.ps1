#This script is intended to be a one-click way to enable bitlocker on the system drive of
#a computer using the TPM and a recovery password. If the computer is joined to a local
#AD domain, it will only enable if the recovery password is succesfully backed up to AD.



#Exit Code Legend

#0: Enabled, Success
#11: Encryption already in progress
#12: Encryption already completed
#13: Unable to get computer info.
#   Ensure you're using an in-support version of Windows 10.
#14: Computer role invalid, or computer not a workstation
#   This script isn't intended for workstations.

#21: Unable to get bitlocker status using Get-BitlockerVolume
#22: Encryption intiated, but not completed.
#   Device likely needs rebooting to complete hardware check before beginning encryption. May also require manual review.
#23: Unable to verify connection to domain. Please verify connection to the domain, reboot, and try again.

#32: Unable to obtain status of key protectors
#33: Unable to obtain status of TPM protector

#41: Unable to remove existing key protector

#51: Unable to add Password Protector
#52: Unable to move exiting Recovery Key directory

#61: Unable to enable Bitlocker
#63: Unable to back up key to AD


#83: Unable to roll back password recovery protector.


#Set log locations
$LogDir = ($env:SystemDrive + "\BitlockerScriptLogs\")
$DatedLogDir = ($LogDir + (Get-Date -Format "yyyy-MM-dd") + "\")

#If the log directory doesn't exist, make it
If (-not (Get-Item $DatedLogDir -ErrorAction SilentlyContinue)) {
    New-Item -Path $DatedLogDir -ItemType "directory"
}


#Start a log in the dated log directory, with a name of the current time
Start-Transcript -Path ($DatedLogDir + (Get-Date -Format "HH-mm-ss") + ".log")

#Stop if we encounter an error so we can catch the error
$ErrorActionPreference = "Stop"

#Try to get the computer info. This will fail if using an old version of Windows 10
#I don't intend to change this behavior. You should be using an in-support version of Windows 10.
Try {$ComputerInfo = Get-ComputerInfo}
Catch {
    Write-Output "Unable to get computer info"
    Write-Output $PSItem
    Exit 13
}

#If this isn't a workstation, quit. This script is for workstations.
If (-not (($ComputerInfo.CsDomainRole -eq "MemberWorkstation") -or ($ComputerInfo.CsDomainRole -eq "StandaloneWorkstation"))) {
    Write-Output "Error 14: Computer role invalid, or computer not a workstation"
    Exit 14
}
Else {
    #If it is a workstation, determine if it's domain-joined or not.
    $ComputerRole = ($ComputerInfo.CsDomainRole)
    $ComputerDomain = ($ComputerInfo.CsDomain)
    If ($ComputerRole -eq "StandaloneWorkstation") {$DomainJoined = $false}
    If ($ComputerRole -eq "MemberWorkstation") {$DomainJoined = $true}
}


#To save me some typing, the system drive is now $MP for MountPoint
$MP = $env:SystemDrive

#Get the volume status so we can make sure it's ready.
Try {$BLStatus = (Get-BitLockerVolume -MountPoint $MP)}
Catch {
    Write-Output "Unable to get Bitlocker status. Exiting"
    Write-Output $PSItem
    Exit 21
}

#Quit if it's already encrypted or in progress
#There's only 3 statuses, EncryptionInProgress, FullyEncrypted, or FullyDecrypted

#If "EncryptionInProgress" then bitlocker was enabled succesfully, and it's working on encrypting the drive.
If ($BLStatus.VolumeStatus -eq "EncryptionInProgress") {
    Write-Output "Encryption is already in Progress. Exiting"
    Write-Output $PSItem
    Exit 11
}

#If "FullyEncrypted" then it's already encrypted. We don't need to do it again.
If ($BLStatus.VolumeStatus -eq "FullyEncrypted") {
    Write-Output "Encryption already completed. Exiting."
    Write-Output $PSItem
    Exit 12
}

#If it's neither of those two, then it's FullyDecrypted
#If it's FullyDecrypted, but has an encryption method, that means
#that it's ready to begin encryption, but needs to reboot to run hardware tests.

If (-not ($BLStatus.EncryptionMethod -eq "None")) {
    Write-Output "Encryption intiated, but not completed. Device may need rebooting. May also require manual review. Exiting."
    Write-Output $PSItem
    Exit 22
}

#This is the part where we start to make sure the TPM is ready. If it's not, this won't work.
#Try to get the TPM info. If it doesn't work, get out.
Try {$TPMInfo = (Get-Tpm)}
Catch {
    Write-Output "Unable to get TPM info"
    Write-Output $PSItem
    Exit 24
}

#If the TPM isn't ready, this won't work. Error out.
If (-not $TPMInfo.TpmReady) {
    Write-Output "TPM not ready. Exiting"
    Exit 25
}


#Next we need to take care of some work specifically for domain-joined computers.
If ($DomainJoined) {

    Write-Output "Computer is joined to a domain. Proceeding with domain-joined bitlocker implementation."

    Write-Output "Testing connection to domain..."

    #because I'm lazy
    $domain = $ComputerDomain
    
    #Make sure we're connected to the domain by pinging a DC and running Test-ComputerSecureChannel
    #If we can't connect to the domain, we won't be able to back up the recovery password
    If (-not ((Test-ComputerSecureChannel) -and ((Test-NetConnection $domain).PingSucceeded))) {
        Write-Output "Connection to domain failed. Attempting to repair..."
        
        #If we can't connect to the domain, try 20 times to repair the connection with Test-ComputerSecureChannel -Repair
        #20 is arbitrary, idgaf
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
}
Else {
        Write-Output "Computer is not domain joined. Proceeding with standalone bitlocker implementation."
}

#Just to be sure, we'll double check bitlocker hasn't already been set up.
If (($BLStatus.VolumeStatus -eq "FullyDecrypted") -and ($BLStatus.EncryptionMethod -eq "None")) {
    Write-Output "Beginning encryption process..."

    #Check if there are already key protectors we need to get rid of. They can exist even if bitlocker isn't on.
    Write-Output "Checking for presence of other key protectors..."
    Try {$KeyProtectors = ((Get-BitLockerVolume -MountPoint $MP).KeyProtector)}
    Catch {
        Write-Output "Unable to obtain status of key protectors. Error 32. Exiting."
        Write-Output $PSItem
        Exit 32
    }

    #Remove exisiting key protectors. We don't want them interfering.
    If ($KeyProtectors) {
        Write-Output "Existing Key Protectors found. Removing..."
        foreach ($KP in $KeyProtectors) {
            Write-Output ("Removing Key protector: " + [String]$KP.KeyProtectorType + " | " + [String]$KP.KeyProtectorID)
            Try {Remove-BitLockerKeyProtector -MountPoint $MP -KeyProtectorId $KP.KeyProtectorId}
            Catch {
                Write-Output ("Unable to remove existing Key protector: " + [String]$KP.KeyProtectorType + " | " + [String]$KP.KeyProtectorID +" | Error 41. Exiting")
                Write-Output $PSItem
                Exit 41
            }
        }
    }

    #Add the recovery password protector.
    Write-Output "Adding Recovery Password Protector..."

    Try {Add-BitLockerKeyProtector -RecoveryPasswordProtector -MountPoint $MP}
    Catch {
        Write-Output "Failed to add Recovery Password protector."
        Exit 51
    }

    #If it's domain joined, we need to back up the Recovery Password to AD. If we can't back it up to AD, remove the protectors we added and error out.
    If ($DomainJoined) {
        Write-Output "Retrieving recovery password from system..."

        Try {$RecoveryPasswords = (((Get-BitLockerVolume -MountPoint $MP).KeyProtector) | Where-Object {$PSItem.KeyProtectorType -eq "RecoveryPassword"})}
        Catch {
            Write-Output "Could not retrieve Recovery Password. Error 62. Exiting."
            Write-Output $PSItem
            Exit 62
        }

        Write-Output "Backing up recovery password to AD..."

        Foreach ($pass in $RecoveryPasswords) {
            Try {Backup-BitLockerKeyProtector -KeyProtectorId $pass.KeyProtectorID -MountPoint $MP}
            Catch {
                Write-Output "Unable to backup key to AD."
                Write-Output $PSItem
                Write-Output "Rolling back Recovery Password protector..."
                Try {Remove-BitLockerKeyProtector -MountPoint $MP -KeyProtectorId $pass.KeyProtectorID}
                Catch {
                    Write-Output "Unable to roll back. MANUAL INTERVENTION REQUIRED. Error 83. Exiting."
                    Write-Output $PSItem
                    Exit 83
                }
                Exit 63
            }
        }
    }

    #If we got past all that alright, we're ready to enable bitlocker using the TPM and our existing recovery password.
    #Do that. If it doesn't work, clean up the key protectors and quit.
    Write-Output "Enabling Bitlocker with TPM"
    Try {Enable-BitLocker -MountPoint $MP -EncryptionMethod XtsAes256 -TpmProtector}
    Catch {
        Write-Output "Unable to enable bitlocker. Error 61. Exiting."
        Write-Output $PSItem

        Write-Output "Rolling back Recovery Password protector..."
        foreach ($pass in $RecoveryPasswords) {
            Try {Remove-BitLockerKeyProtector -MountPoint $MP -KeyProtectorId $pass.KeyProtectorID}
            Catch {
                Write-Output "Unable to roll back. MANUAL INTERVENTION REQUIRED. Error 83. Exiting."
                Write-Output $PSItem
                Exit 83
            }
        }
        Exit 61
    }

    #If we got this far, we've succeeded.
    Write-Output "Succesfully enabled bitlocker. Restart to finish."
    Exit 0
}