<#
    .SYNOPSIS
        Intune Detection Script for Winget-AutoUpdate (WAU)
    .DESCRIPTION
        Verifies the presence of WAU using 'winget list' in System context.

        This script is optimized for robustness by:
        1. Locating winget.exe dynamically in the WindowsApps folder.
        2. Using 'winget list' instead of 'export' to avoid JSON parsing errors and
           heavy source synchronization.
        3. Implementing '--disable-interactivity' and '2>$null' to prevent hangs and
           ignore transient source update errors common in System context.
   .NOTES
        Exit codes:
            0 = Detected (WAU is installed and visible to WinGet)
            1 = Not Detected (WAU is missing or WinGet is unable to list local packages)

        Version: 1.1 (Improved for reliability on edge-case clients)
#>
$AppToDetect = "Romanitho.Winget-AutoUpdate"

# 1. Finn winget.exe dynamisk (samme logikk som WinGet-deteksjon)
$winget_exe = Resolve-Path "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_*__8wekyb3d8bbwe\winget.exe" -ErrorAction SilentlyContinue
if ($winget_exe.Count -gt 1) { $winget_exe = $winget_exe[-1].Path }
if (-not $winget_exe) { $winget_exe = "winget.exe" }

# 2. Sjekk med 'winget list' (mye mer robust enn 'export')
# --disable-interactivity: Hindrer heng i SYSTEM-kontekst
# 2>$null: Ignorerer støy fra kilde-feil (sources)
# --no-upgrade: (Valgfritt) Sier til winget at den ikke trenger å sjekke etter nye versjoner nå
$wingetList = & $winget_exe list -e --id $AppToDetect --accept-source-agreements --disable-interactivity 2>$null

if ($wingetList -match $AppToDetect) {
    Write-Host "Detected via WinGet List"
    exit 0
}



exit 1