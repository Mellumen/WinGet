# ================================
# WinGet uninstall via Intune (System Context)
# ================================

$PackageName = "WindowsPackageManager"
$LogRoot = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
$LogPath = "$LogRoot\$PackageName-uninstall.log"

# Sørg for at log-mappen finnes
New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null

Start-Transcript -Path $LogPath -Force
Write-Output "Starter avinstallasjon av $PackageName..."

$ExitCode = 0

try {
    # Fjern for eksisterende brukere
    Write-Output "Fjerner AppX-pakken Microsoft.DesktopAppInstaller..."
    Remove-AppPackage -Package "Microsoft.DesktopAppInstaller" -AllUsers -ErrorAction Stop

    # Fjern provisioned for nye brukere
    Write-Output "Fjerner provisioned AppX-pakken..."
    Remove-AppxProvisionedPackage -Online -PackageName "Microsoft.DesktopAppInstaller" -ErrorAction Stop

    Write-Output "Avinstallasjon fullført."
} catch {
    Write-Warning "Feil under avinstallasjon: $($_.Exception.Message)"
    $ExitCode = 1
}

Stop-Transcript
Exit $ExitCode
