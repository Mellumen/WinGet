
<#
.SYNOPSIS
    Intune Detection Script for WinGet (System Context Verification)
.DESCRIPTION
    Verifies that Winget is present AND executable in the System context, exit immediately without logging.
    Otherwise, perform detailed checks with logging.

    Since Winget relies on VCLibs and specific provisioning, checking file version 
    metadata is not enough. We must execute it.
.NOTES
    Exit codes:
        0 = Compliant (Winget runs successfully and meets version requirements)
        1 = Non-compliant (Any failure (missing file, execution error, old version))
#>

# --- CONFIGURATION ---
# Desired version of Winget
$DesiredVersion = "1.7.11132"
$LogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\Detect-WinGet.log"

# --- LOGGING FUNCTION ---
#Change Write-host to write-log to log for debugging.
function Write-Log {
    param([string]$Message)
    try {
        # Ensure log directory exists
        $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Add-Content -Path $LogPath -Value "$timestamp - $Message"
    } catch {
        # Fallback to Write-Host if logging fails (visible in Intune agent logs?)
        Write-Host "Log Error: $Message"
    }
}

# --- CHECK VERSION ---
# Locate Winget executable dynamically
# We look in WindowsApps. Use the last one found (usually highest version/alphabetical)
$winget_exe = Resolve-Path "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_*__8wekyb3d8bbwe\winget.exe" -ErrorAction SilentlyContinue
if ($winget_exe.Count -gt 1) { $winget_exe = $winget_exe[-1].Path }

if ($winget_exe) {
    try {
        # Test Execution (The Critical Step)
        # We try to run it. If dependencies (VCLibs) are missing, this will likely fail or return empty.
        $wingetVersionOutput = & $winget_exe -v
        if ($wingetVersionOutput) {

            # Check Version
            # Output format is usually just "v1.12.xxxx" so trim it to "1.12.xxxx"
            $InstalledVersion = $wingetVersionOutput.Replace("v", "").Trim()
            if ([version]$InstalledVersion -ge [version]$DesiredVersion) {
                Write-Host "Compliant: WinGet version is sufficient."
                exit 0  # Success, no logging
            } else {
                Write-Log "Non-Compliant: Installed WinGet version is lower than required."
                Write-Log "Installed: $InstalledVersion | Required: $DesiredVersion"
            }
        } else {
            Write-Log "Non-Compliant: winget.exe exists but failed to run -v. Possible missing dependencies."
        }
    } catch {
        Write-Log "Non-Compliant: Error running winget.exe: $($_.Exception.Message)"
    }
    Write-Log "Non-Compliant: winget.exe found at: $winget_exe"
} else {
    Write-Log "Non-Compliant: winget.exe not found."
}
exit 1  # Failure / Non-compliant
