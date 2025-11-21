<#
.SYNOPSIS
    Intune Remediation Script for Winget-AutoUpdate Log Copying.
.DESCRIPTION
    This script copies 'install.log' and 'updates.log' from the Winget-AutoUpdate logs folder
    to the Intune Management Extension log directory. It is designed to be run after its
    corresponding detection script has determined a copy is necessary.
.NOTES
    Exit codes:
        0 = Success (Remediation completed successfully)
        1 = Failure (An error occurred during the remediation process)
#>

# Configuration
$sourceLogDir = "C:\Program Files\Winget-AutoUpdate\Logs"
$destinationLogDir = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs"
$logFilesToCopy = @("install.log", "updates.log")
$ScriptLogFile = "Remediation-Logs.log"

# --- LOGGING FUNCTION ---
function Write-Log {
    param([string]$Message)
    $ScriptLogPath = Join-Path -Path $destinationLogDir -ChildPath $ScriptLogFile
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $FullMessage = "$timestamp - $Message"

    # Write to standard output for Intune logs and console
    Write-Output $FullMessage 

    try {
        # Check file size: If larger than 1MB, clear it to save space
        if ((Test-Path $ScriptLogPath) -and ((Get-Item $ScriptLogPath).Length -gt 1MB)) {
            Clear-Content $ScriptLogPath
            # Recursive call: Log the rotation event (file is now empty, so it won't loop)
            Write-Log "INFO: Log rotated due to size > 1MB"
        }
        # Write the timestamped message to the log file
        Add-Content -Path $ScriptLogPath -Value $FullMessage
    } catch {
        # Fallback to Write-Output if logging to file fails
        Write-Output "ERROR: Failed to write to log file '$ScriptLogPath'. Error: $($_.Exception.Message)"
        Write-Output "Original Message: $FullMessage"
    }
}

# --- Script Starts Here ---

try {
    # Ensure the destination directory exists.
    if (-not (Test-Path -Path $destinationLogDir -PathType Container)) {
        Write-Log "INFO: Creating destination directory '$destinationLogDir'."
        New-Item -Path $destinationLogDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }

    # This function copies a single log file.
    function Copy-LogFile {
        param(
            [string]$LogFileName
        )

        $sourceLogPath = Join-Path -Path $sourceLogDir -ChildPath $LogFileName
        
        # Only copy if the source file actually exists.
        if (-not (Test-Path -Path $sourceLogPath -PathType Leaf)) {
            Write-Output "INFO: Source file '$LogFileName' not found, skipping."
            return
        }

        $destinationLogPath = Join-Path -Path $destinationLogDir -ChildPath "WAU-$LogFileName"
        Write-Log "INFO: Copying '$sourceLogPath' to '$destinationLogPath'."
        Copy-Item -Path $sourceLogPath -Destination $destinationLogPath -Force -ErrorAction Stop
        Write-Log "Copied '$LogFileName' successfully."
    }

    # --- Main Logic ---
    
    # Ensure the source directory exists.
    if (-not (Test-Path -Path $sourceLogDir -PathType Container)) {
        Write-Error "ERROR: Source log directory '$sourceLogDir' does not exist. Cannot proceed."
        exit 1
    }

    # Loop through the log files and copy each one.
    # The detection script has already confirmed at least one is out of date.
    # This script simply ensures both are brought up-to-date.
    foreach ($logFile in $logFilesToCopy) {
        Copy-LogFile -LogFileName $logFile
    }

    Write-Output "SUCCESS: Remediation completed."
    Write-Log "Remediation completed. Exit code: 0 (Success)"
    exit 0
} catch {
    $errorMessage = $_.Exception.Message
    Write-Error "An unexpected error occurred during remediation: $errorMessage"
    Write-Log "Remediation failed. Exit code: 1"
    Write-Log "ERROR: $errorMessage"
    exit 1
}

