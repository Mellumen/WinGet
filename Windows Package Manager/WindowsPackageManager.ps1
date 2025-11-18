<# 
.SYNOPSIS
Install winget and dependencies for System-context and other users through Intune.

.DESCRIPTION
Allows the System account to use Winget to install apps by setting up dependencies and environment variables.

.PARAMETER LogPath
Used to specify logpath for the transcript file. Default is the same folder as Intune logs.

.EXAMPLE
"%systemroot%\sysnative\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File WindowsPackageManager.ps1

.EXAMPLE
"%systemroot%\sysnative\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File WindowsPackageManager.ps1 -LogPath "C:\temp" 

   ================================
   WinGet installation via Intune (System Context)
   ================================
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $False)] [String] $LogPath
)
# --- Logging ---
$PackageName = "winget"
if (!($LogPath)) {
    # If LogPath is not set, default to the Intune log path
    $LogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\"
} 
$LogFile = "$LogPath\$PackageName-install.log"

Start-Transcript -Path $LogFile -Append -Force
Write-Host "Starting installation of $PackageName..."

# --- Configuration ---
$ProgressPreference = 'SilentlyContinue' # Improves download speed by suppressing progress bar
$VCVersion = [System.Version]"14.40.0.0" # Minimum required Visual C++ version
$TempPath = $env:TEMP
$ExitCode = 0 # 0 = OK, 1 = Error, 3010 = Restart required

# Determine architecture. 
# Note: Currently primarily optimized for x64. Changes to $Env:ProgramFiles and "SetEnvironmentVariable" would be needed for full x86/ARM support.
switch -Regex ($env:PROCESSOR_ARCHITECTURE) {
    "ARM64" { $OSArch = "arm64" }
    ".*64.*" { $OSArch = "x64" }
    default { $OSArch = "x86" }
}
Write-Host "Detected architecture: $OSArch"

# --- Functions ---
function Download-File($Url, $Destination) {
    Write-Host "Downloading $Url to $Destination..."
    try {
        Invoke-WebRequest -Uri $Url -OutFile $Destination -ErrorAction Stop
        return (Test-Path $Destination)
    } catch {
        Write-Warning "Error downloading from $($Url): $($_.Exception.Message)"
        return $false
    }
}

function Install-VisualC {
    Write-Host "Checking Visual C++ Redistributable..."
    # Check registry for existing installation meeting the version requirement
    $VCInstalled = Get-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*, HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -like "Microsoft Visual C++ 2015-2022 Redistributable*" -and [System.Version]$_.DisplayVersion -ge $VCVersion }
    
    if (-not $VCInstalled) {
        Write-Host "Installing Visual C++ Redistributable..."
        $VCUrl = "https://aka.ms/vs/17/release/VC_redist.$OSArch.exe"
        $VCInstaller = "$TempPath\VC_redist.$OSArch.exe"
        
        if (Download-File $VCUrl $VCInstaller) {
            try {
                $Process = Start-Process -FilePath $VCInstaller -ArgumentList "/quiet /norestart" -Wait -PassThru -ErrorAction Stop
                
                # Handle installer exit codes
                switch ($Process.ExitCode) {
                    0 { Write-Host "Visual C++ installed successfully." }
                    3010 { 
                        Write-Warning "Visual C++ installed, reboot required."
                        # Only set reboot code if we don't already have a hard error
                        if ($script:ExitCode -eq 0) { $script:ExitCode = 3010 } 
                    }
                    1618 { 
                        Write-Warning "Installation already in progress (1618)."
                        $script:ExitCode = 1618 
                    }
                    default { 
                        Write-Warning "Visual C++ failed with code $($Process.ExitCode)"
                        $script:ExitCode = 1 
                    }
                }
            } catch {
                Write-Warning "Error during Visual C++ installation: $($_.Exception.Message)"
                $script:ExitCode = 1
            } finally {
                Remove-Item -Path $VCInstaller -Force -ErrorAction SilentlyContinue
            }
        } else {
            Write-Warning "Could not download Visual C++ installer."
            $script:ExitCode = 1
        }
    } else {
        Write-Host "Visual C++ Redistributable is already installed."
    }
}

function Install-UWPDependencies {
    # Winget dependencies
    Write-Host "Installing UWP dependencies..."
    $Packages = @(
        @{ Name = "Microsoft.VCLibs.140.00.UWPDesktop"; Url = "https://aka.ms/Microsoft.VCLibs.$OSArch.14.00.Desktop.appx" }
        @{ Name = "Microsoft.UI.Xaml.2.8"; Url = "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.$OSArch.appx" }
    )
    
    foreach ($Package in $Packages) {
        # Check if package is provisioned
        if (-not (Get-AppxPackage -Name $Package.Name -AllUsers)) {
            Write-Host "Installing $($Package.Name)..."
            $AppxFile = "$TempPath\$($Package.Name).appx"
            if (Download-File $Package.Url $AppxFile) {
                try {
                    # Use Add-AppxProvisionedPackage to ensure it is available for the System account and future users
                    Add-AppxProvisionedPackage -Online -PackagePath $AppxFile -SkipLicense | Out-Null
                    Write-Host "$($Package.Name) installed."
                } catch {
                    Write-Warning "Error installing $($Package.Name): $($_.Exception.Message)"
                    $script:ExitCode = 1
                } finally {
                    Remove-Item -Path $AppxFile -Force -ErrorAction SilentlyContinue
                }
            } else {
                Write-Warning "Could not download $($Package.Name)."
                $script:ExitCode = 1
            }
        } else {
            Write-Host "$($Package.Name) is already installed."
        }
    }
}

function Install-PowerShell7 {
    Write-Host "Checking PowerShell 7..."
    $pwshExecutable = "$Env:ProgramFiles\PowerShell\7\pwsh.exe"
    
    if (Test-Path $pwshExecutable) {
        Write-Host "PowerShell 7 is already installed."
        return $pwshExecutable
    }
    # Fetch latest release info from GitHub API
    $githubApiUrl = 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest'
    $release = Invoke-RestMethod -Uri $githubApiUrl
    # Filter for MSI installer and correct architecture
    $asset = $release.assets | Where-Object { $_.name -like "*msi*" -and $_.name -like "*$OSArch*" }
    $filename = "$TempPath\$($asset.name)"
    
    if (Download-File $asset.browser_download_url $filename) {
        Write-Host "Installing PowerShell 7..."
        $Process = Start-Process msiexec.exe -Wait -ArgumentList "/I $filename /qn" -PassThru
        if ($Process.ExitCode -ne 0) {
            Write-Warning "PowerShell 7 installation failed."
            $script:ExitCode = 1
            return $null
        }
        Write-Host "PowerShell 7 installed."
        return $pwshExecutable
    }
    return $null
}

function Install-WingetMSIX {
    Write-Host "Checking WinGet..."
    # Look for existing Winget executable. 
    # Note: The path changes based on version, hence the wildcard search.
    $winget_exe = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_*__8wekyb3d8bbwe\winget.exe" 
    if ($winget_exe.count -gt 1) { 
        # If multiple versions found, pick the last one (usually newest)
        $winget_exe = $winget_exe[-1].Path 
    } 
     
    Write-Host "Checking/Installing WinGet (MSIX package)..." 
    if ($winget_exe) { 
        Write-Host "Found existing WinGet at $($winget_exe.Path)." 
    } else {
        # If not installed, download and install Winget
        Write-Host "Installing WinGet MSIX..."
        $LatestInfo = Invoke-RestMethod -Uri 'https://api.github.com/repos/microsoft/winget-cli/releases/latest'
        $WingetDownloadUrl = ($LatestInfo.assets | Where-Object { $_.name -like "*.msixbundle" }).browser_download_url
        $WingetInstaller = "$TempPath\Microsoft.DesktopAppInstaller.msixbundle"
        
        if (Download-File $WingetDownloadUrl $WingetInstaller) {
            try {
                Add-AppxProvisionedPackage -Online -PackagePath $WingetInstaller -SkipLicense -ErrorAction Stop | Out-Null
                Write-Host "WinGet installed."
            } catch {
                Write-Warning "Error installing WinGet MSIX: $($_.Exception.Message)"
                $script:ExitCode = 1
            } finally {
                Remove-Item -Path $WingetInstaller -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

function SetEnvironmentVariable {
    Write-Host "Setting Winget Environment Variable for User (including VCLibs.140)..."
    # **** Define paths to add ***
    $basePath = "C:\Program Files\WindowsApps"
    $pathsToAdd = @()

    # Find VCLibs folder dynamically (version number in folder name changes)
    $vcLibsDir = (Resolve-Path "$basePath\Microsoft.VCLibs.140.00.UWPDesktop_*_x64__8wekyb3d8bbwe" | Sort-Object -Property Path | Select-Object -Last 1)
    if ($vcLibsDir) {
        Write-Host "Found VCLibs: $($vcLibsDir.Path)"
        $pathsToAdd += $vcLibsDir.Path
    } else {
        Write-Warning "Did not find VCLibs folder."
    }
    # Find Winget/DesktopAppInstaller folder dynamically
    $wingetDir = (Resolve-Path "$basePath\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe" | Sort-Object -Property Path | Select-Object -Last 1)
    if ($wingetDir) {
        Write-Host "Found Winget: $($wingetDir.Path)"
        $pathsToAdd += $wingetDir.Path
    } else {
        Write-Warning "Did not find Winget folder (Microsoft.DesktopAppInstaller)."
    }
    # Abort if no paths were found
    if ($pathsToAdd.Count -eq 0) {
        Write-Error "Found none of the folders to add to PATH. Aborting variable update."
        return
    }
    # ***** Get "User" path variable and split it
    # Note: We modify the "User" path even when running as System to ensure Winget works in System context.
    $currentUserPathString = [Environment]::GetEnvironmentVariable("PATH", "User")
    
    # Remove empty entries and ensure uniqueness
    $pathEntries = $currentUserPathString.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries) | Select-Object -Unique

    # ***** Iterate through paths and check if they exist
    $pathWasModified = $false 
    foreach ($path in $pathsToAdd) {
        if ($pathEntries -notcontains $path) {
            Write-Host "  Adding: $path"
            $pathEntries += $path
            $pathWasModified = $true
        } else {
            Write-Host "  Already exists (skipping): $path"
        }
    }

    # ****** Set the new variable if changed
    if ($pathWasModified) {
        $newPathString = $pathEntries -join ';'
    
        [Environment]::SetEnvironmentVariable("PATH", $newPathString, "User")
    
        Write-Host "SUCCESS: The SYSTEM account's User PATH has been updated."
        Write-Warning "You must restart PowerShell (or the PC) for changes to take effect in new processes."
    
        # Update this *specific* process's $env:PATH to allow immediate usage (e.g., for repair functions)
        $env:PATH = $newPathString + ";" + $env:PATH
        
        # Trigger a soft reboot code if changes were made
        $script:ExitCode = 3010 
    } else {
        Write-Host "No changes necessary. User PATH is already correct."
    }
}


function Repair-With-PowerShellModule($pwshExecutable) {
    if (-not $pwshExecutable) {
        Write-Warning "Cannot run Winget repair, PowerShell 7 is missing."
        return
    }

    Write-Host "Running WinGet repair using PowerShell 7 module..."
    # We execute this inside a new PowerShell 7 process because the Microsoft.WinGet.Client module
    # often requires PWSH 7 features and clean module loading.
    try {
        & $pwshExecutable -Command {
            try {
                # Check if NuGet provider exists, bootstrap if necessary
                if (-not (Get-PackageProvider NuGet -ErrorAction Ignore)) {
                    Write-Host "Installing NuGet provider..."
                    Find-PackageProvider -Name NuGet -ForceBootstrap -IncludeDependencies
                }

                # Install or update the winget module
                Write-Host "Installing/updating microsoft.winget.client module..."
                Install-Module microsoft.winget.client -Force -AllowClobber -Scope AllUsers

                # Import and run repair
                Import-Module microsoft.winget.client -Force
                Write-Host "Running Repair-WinGetPackageManager..."
                Repair-WinGetPackageManager

                Write-Host "Repair completed."
                exit 0 # Tell parent process it went well
            } catch {
                Write-Warning "Error during repair with PowerShell 7: $($_.Exception.Message)"
                exit 1 # Tell parent process it failed
            }
        }
        # Check exit code from the external pwsh.exe process
        if ($LASTEXITCODE -ne 0) {
            throw "Repair script block failed with exit code $LASTEXITCODE."
        }
    } catch {
        Write-Warning "Could not start/finish PowerShell 7 for repair: $($_.Exception.Message)"
        $script:ExitCode = 1 
    }
}

# --- Main Execution ---
Write-Host "=== Starting main execution ==="
$pwshPath = ""

Install-VisualC
Install-UWPDependencies
Install-WingetMSIX
SetEnvironmentVariable
$pwshPath = Install-PowerShell7
Repair-With-PowerShellModule -pwshExecutable $pwshPath

# --- Final Status ---
if ($ExitCode -eq 0) {
    Write-Host "Installation finished without critical errors."
} elseif ($ExitCode -eq 3010) {
    Write-Warning "Installation finished, but requires reboot (Exit Code: 3010)."
} else {
    Write-Error "Installation finished, but with errors (Exit Code: $ExitCode)."
}

Stop-Transcript
Exit $ExitCode