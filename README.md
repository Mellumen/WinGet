# Winget-AutoUpdate Strategy

Instead of packaging every single application installer manually, this environment uses a dependency chain that enables a "Fire and Forget" mechanism for app deployment and updates.

## Layer 1: The Foundation (System Context Enabler)
* **Component:** `WindowsPackageManager.ps1`
* **Role:** Prepares the OS to run `winget.exe` as the **SYSTEM** account.
* **Intune Assignment:** Assigned as **Required** to all devices.

## Layer 2: The Engine (Winget-AutoUpdate)
* **Component:** [Winget-AutoUpdate (WAU)](https://github.com/Romanitho/Winget-AutoUpdate) by Romanitho.
* **Role:** Handles the actual installation and daily updating of apps.
* **Configuration:** WAU is configured via Intune ADMX Policies. See documentation here: [WAU Policies](https://github.com/Romanitho/Winget-AutoUpdate/tree/main/Sources/Policies).
* **Install Command (Win32 App):**
    The `.intunewin` package is built using `winget-install.ps1` and the `functions` folder (sourced from `Romanitho/Winget-AutoUpdate/Sources`).
	
    **Command:**
    `"%systemroot%\sysnative\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File ".\winget-install.ps1" -AppIDs Romanitho.Winget-AutoUpdate`
  
* **Dependency:** Depends on **Layer 1** (Windows Package Manager).

## Layer 3: The Applications (7-Zip, etc.)
* **Component:** Lightweight "Dummy" Win32 Apps.
* **Role:** Triggers WAU to install a specific App ID from the WinGet repository.
* **Dependency:** Depends on **Layer 2** (Winget-AutoUpdate).
* **Install Command Example:**
  `"%systemroot%\sysnative\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%ProgramFiles%\Winget-AutoUpdate\Winget-Install.ps1" -AppIDs 7zip.7zip`
## Benefits of this Approach

1. **Zero Packaging Maintenance:** You don't need to download `.exe` or `.msi` files and repackage them every time an app updates.
2. **Automatic Updates:** WAU runs a scheduled task daily that checks and updates all installed apps automatically.
3. **System Context:** Everything runs silently in the background as System, with no user interaction required.
4. **Clean Dependency Chain:**
    * If you assign **7-Zip** to a user...
    * Intune sees it needs **WAU** -> Installs WAU.
    * Intune sees WAU needs **WinGet** -> Installs WinGet System.
    * Finally, 7-Zip is installed.

## How to add a new App (e.g., Notepad++)

1. Find the App ID: `winget search Notepad++` -> ID: `Notepad++.Notepad++`
2. Use a dummy `.intunewin` file (can contain an empty text file).
3. Create a Win32 App in Intune:
    * **Install Command:**
        `...\powershell.exe" ... -File "%ProgramFiles%\Winget-AutoUpdate\Winget-Install.ps1" -AppIDs Notepad++.Notepad++`
    * **Uninstall Command:**
        `...\powershell.exe" ... -File "%ProgramFiles%\Winget-AutoUpdate\Winget-Install.ps1" -AppIDs Notepad++.Notepad++ -Uninstall`
    * **Detection Rule:** Custome script [Winget-AutoUpdate (WAU) Detect](https://github.com/Romanitho/Winget-AutoUpdate/blob/main/Sources/Tools/Detection/winget-detect.ps1)
        * The script `make-IntuneDetectionScript.ps1` creates a detect script based on this detect script and the winget app id as the only input.
    * **Dependencies:** Add **Winget-AutoUpdate** as a dependency.

## Log File Management for Winget-AutoUpdate
This process uses an Intune Proactive Remediations script to collect WAU logs.

* **Detection Script:** `WAULogs_detection.ps1`
    * **Role:** Monitors `install.log` and `updates.log` from Winget-AutoUpdate.
	* It checks if the source logs are newer than the copies in the Intune Management Extension (IME) logs directory.
	* If a log is newer or a copy is missing, it exits with code 1, triggering the remediation script.

* **Remediation Script:** `WAULogs_remediation.ps1`
    * **Role:** Copies the latest WAU log files to the IME logs directory.
    * **Details:** Renames the files with a `WAU-` prefix for easy identification (e.g., `WAU-install.log`).

* **Goal:** To ensure Intune centrally collects the latest WAU logs for monitoring and troubleshooting.
