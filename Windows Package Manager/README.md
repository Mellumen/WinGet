<img width="720" height="720" alt="WindowsPackageManager_SYSTEM" src="https://github.com/user-attachments/assets/c7669f3c-6e77-41ed-87f6-58ad134553f4" />

# WinGet Installer for Microsoft Intune (System Context)
This PowerShell script automates the robust installation, configuration, and repair of the **Windows Package Manager (WinGet)** via Microsoft Intune running in the **System Context**.

WinGet is primarily designed to run in a user context. Running it as `NT AUTHORITY\SYSTEM` (which Intune does by default) often results in missing dependencies, pathing issues, and execution failures. This script solves those problems by installing all necessary dependencies, configuring environment variables, and performing a self-repair using PowerShell 7.

## Features

* **Full Dependency Handling:** Checks for and installs:
  * Visual C++ Redistributable (2015-2022).
  * UWP Dependencies (`Microsoft.UI.Xaml.2.8` and `Microsoft.VCLibs.140.00`).
* **WinGet Installation:** Downloads and installs the latest `Microsoft.DesktopAppInstaller` (.msixbundle) directly from the official GitHub repository.
* **System Context Fix:** Dynamically updates the `PATH` environment variable so `winget.exe` can be called directly by the System account without full paths.
* **Self-Healing:** Installs **PowerShell 7** and uses the `Microsoft.WinGet.Client` module to run `Repair-WinGetPackageManager`, ensuring sources are correctly configured.
* **Logging:** Generates transcript logs in the standard Intune log directory, or custome path with parameter.

## Acknowledgments & Credits

This solution is built upon the hard work and research of the community. Special thanks to:

* **fanuelsen (Horten kommune)** for the foundational work in the `Install-Winget-System.ps1` script: https://github.com/Hortenkommune/hackcon2025/tree/main/winget-scripts
* **Scloud** for the comprehensive logic regarding WindowsPackageManager installation scripts.
  * Source: [How to deploy Winget with Intune](https://scloud.work/how-to-winget-intune/)
* **Nialljen** for crucial insights on executing Windows Package Manager in the System Context.
  * Source: [Running Windows Package Manager (WinGet) in the System Context](https://nialljen.wordpress.com/2023/05/14/running-windows-package-manager-winget-in-the-system-context/)

## Prerequisites

* **Microsoft Intune** tenant.
* **Windows 10/11** devices (x64/x86/ARM64).
* The script must be packaged as a `.intunewin` file using the [Microsoft Win32 Content Prep Tool](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool).

## Intune Deployment Settings

Create a new **Win32 App** in Intune using the following settings:

### 1. Program

* **Install command:**
  ```powershell
  %SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File WindowsPackageManager.ps1
  ```

* **Uninstall command:**
  ```powershell
  %SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File uninstallWindowsPackageManager.ps1
  ```

* **Install behavior:** System

* **Device restart behavior:** App install may force a device restart (The script returns Exit Code `3010` if Environment Variables are modified).

### 2. Requirements

* **Operating system architecture:** 64-bit
* **Minimum operating system:** Windows 10 20H2 or later.

### 3. Detection Rule

#### DetectWindowsPackageManager.ps1

This script verifies that the Windows Package Manager (Winget) is not only present but also **executable** within the System context.
Unlike standard file presence checks or registry version checks, this script attempts to **execute** `winget.exe` with the `-v` (version) flag. This ensures that not only is the binary present, but all required dependencies (like VCLibs and UI.Xaml) are correctly loaded and the environment path is configured.

**Key Features:**
* **Execution Validation:** Attempts to run `winget.exe --version` to ensure all dependencies (e.g., VCLibs) are correctly loaded and the package is fully provisioned for the System user.
* **Version Compliance:** Parses the output version and compares it against a defined minimum requirement (default: `1.7.11132`).
* **Robust Error Handling & Logging:** Captures non-zero exit codes to detect execution failures (e.g., missing prerequisites) and writes detailed diagnostics to `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\Detect-WinGet.log` if non-compliant.

**Exit Codes:**
* `0`: Compliant (Winget runs successfully and meets version requirements).
* `1`: Non-Compliant (Triggers the remediation/install script).

## Logging

Logs are written to the standard Intune Management Extension log folder for easy collection via the Intune portal ("Collect diagnostics").

* **Log Path:** `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\winget-install.log`

## Important Notes

* **Exit Code 3010:** The script may return exit code `3010` (Soft Reboot). This is intentional. While `winget` might work immediately for some processes, a reboot ensures the updated `PATH` environment variable is recognized by all system processes.
* **Network:** Ensure the target devices can reach `api.github.com`, `aka.ms`, and `github.com` to download the required installers.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
