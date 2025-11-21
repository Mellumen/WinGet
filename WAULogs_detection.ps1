<#
.SYNOPSIS
    Intune Detection Script for Winget-AutoUpdate Log Monitoring.
.DESCRIPTION
    This script checks if 'install.log' or 'updates.log' from Winget-AutoUpdate are newer than their copied versions
    in the Intune Management Extension log directory.
    It is intended to be used as a detection script in an Intune Proactive Remediation.
.NOTES
    Exit codes:
        0 = Compliant (Both log files are up-to-date, no action needed)
        1 = Non-compliant (One or both log files need to be copied, remediation is required)
#>

# Configuration
$sourceLogDir = "C:\Program Files\Winget-AutoUpdate\Logs"
$destinationLogDir = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
$logFilesToCheck = @("install.log", "updates.log")
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
    # This function checks if a single log file needs to be copied.
    # Returns $true if remediation is needed, $false otherwise.
    function Test-LogNeedsRemediation {
        param(
            [string]$LogFileName
        )

        $sourceLogPath = Join-Path -Path $sourceLogDir -ChildPath $LogFileName
        $destinationLogPath = Join-Path -Path $destinationLogDir -ChildPath "WAU-$LogFileName"

        # If the source log file doesn't exist, no action is needed for it.
        if (-not (Test-Path -Path $sourceLogPath -PathType Leaf)) {
            Write-Log "INFO: Source log '$LogFileName' not found. No action needed for this file."
            return $false
        }

        # If the destination log file doesn't exist, remediation is required.
        if (-not (Test-Path -Path $destinationLogPath -PathType Leaf)) {
            Write-Log "INFO: Destination log for '$LogFileName' not found. Remediation is required."
            return $true
        }

        # Get the modification times of both files.
        $sourceWriteTime = (Get-Item -Path $sourceLogPath).LastWriteTime
        $destinationWriteTime = (Get-Item -Path $destinationLogPath).LastWriteTime

        # Compare the last write time of the source log with the destination log.
        if ($sourceWriteTime -gt $destinationWriteTime) {
            Write-Log "INFO: Source log '$LogFileName' is newer than its destination. Remediation is required."
            return $true
        }

        # Log is up to date.
        return $false
    }

    # --- Main Logic ---

    # Check if the source log directory exists. If not, no action is needed.
    if (-not (Test-Path -Path $sourceLogDir -PathType Container)) {
        Write-Log "INFO: Source log directory '$sourceLogDir' not found. No action needed."
        exit 0
    }

    # Loop through the log files and check if any of them need remediation.
    foreach ($logFile in $logFilesToCheck) {
        if (Test-LogNeedsRemediation -LogFileName $logFile) {
            Write-Log "INFO: Remediation required for at least one log file."
            exit 1
        }
    }

    # If the loop completes without exiting, all logs are up-to-date (or no logs in source).
    Write-Log "INFO: All log files are up-to-date. No action needed."
    Write-Log "Detection completed. Exit code: 0 (Compliant)"
    exit 0
} catch {
    $errorMessage = $_.Exception.Message
    Write-Error "An unexpected error occurred: $errorMessage"
    Write-Log "ERROR: An unexpected error occurred: $errorMessage" # Log to file as well
    exit 1 # Exit with an error code to indicate failure.
}
