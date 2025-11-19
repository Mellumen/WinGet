<#
.SYNOPSIS
    Generates a custom Intune detection script based on a Winget ID.
.DESCRIPTION
    This script prompts for a Winget ID, searches for the application name,
    and generates a .ps1 detection script with the specified ID injected
    into the $AppToDetect variable. Saves the file at script root.
.NOTES
    Filename: make-IntuneDetectionScript.ps1

.PARAMETER WingetId
    Can be used if automated from another script or if ran from terminal.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$WingetId
)


#-----------------------------------------------------------------------
# FUNCTION: Get-WingetCmd
# DESCRIPTION: Locates the winget.exe executable
#-----------------------------------------------------------------------
Function Get-WingetCmd {
    $WingetCmd = $null
    
    # Try to find winget in Admin context
    try {
        # Get Admin Context Winget Location
        $WingetInfo = (Get-Item "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_8wekyb3d8bbwe\winget.exe").VersionInfo | Sort-Object -Property FileVersionRaw
        # If multiple versions, pick most recent one
        $WingetCmd = $WingetInfo[-1].FileName
    } catch {
        # Try to find winget in User context
        if (Test-Path "$env:LocalAppData\Microsoft\WindowsApps\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\winget.exe") {
            $WingetCmd = "$env:LocalAppData\Microsoft\WindowsApps\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\winget.exe"
        }
    }

    if ([string]::IsNullOrWhiteSpace($WingetCmd)) {
        Write-Warning "Could not find winget.exe. Ensure the App Installer is installed."
    }

    return $WingetCmd
}


#-----------------------------------------------------------------------
# MAIN SCRIPT
#-----------------------------------------------------------------------

#****Find Winget
$wingetExe = Get-WingetCmd
if (-not $wingetExe) {
    Write-Error "Could not find winget.exe. Exiting."
    return
}

#****Prompt for Winget ID
if ([string]::IsNullOrWhiteSpace($WingetId)) {
    $WingetId = Read-Host -Prompt "Enter the Winget ID for the application (e.g., 'Mozilla.Firefox')"
}
if ([string]::IsNullOrWhiteSpace($WingetId)) {
    Write-Error "No Winget ID provided. Exiting."
    return
}

#****Search for App Name using Winget ID
Write-Host "Searching for '$WingetId' using winget..."
try {
    # Run winget search and capture results
    $searchResultLines = & "$wingetExe" search --id $WingetId --exact --accept-source-agreements
    
    # Find the data line that actually contains the ID (avoids partial matches confusing the logic)
    $escapedId = [Regex]::Escape($WingetId)
    $dataLine = $searchResultLines | Where-Object { $_ -match $escapedId }

    
    if (-not $dataLine) {
        Write-Error "No application found with ID '$WingetId'. Verify the ID and try again. Exiting."
        return
    }
    
    # Extract the name. The name is the first column, before the Winget ID.
    $IdIndex = $dataLine.IndexOf($WingetId)
    
    if ($IdIndex -gt 0) {
        # Get all text from start (0) to the index of the ID, and remove extra characters/whitespace
        $AppName = $dataLine.Substring(0, $IdIndex) -replace '[\\/:*?"<>|\s]', ''
    } else {
        # Fallback if IndexOf fails for some reason
        Write-Warning "Could not determine exact ID string index, using the whole line..."
        $AppName = $dataLine
    }
    
    if ([string]::IsNullOrWhiteSpace($AppName)) {
        Write-Error "Could not parse app name from '$dataLine'. Exiting."
        return
    }
    Write-Host "Found app name: $AppName"
} catch {
    Write-Error "An error occurred while running winget search: $_"
    return
}

#****Define filename and path for the new script
# Remove invalid filename characters from the app name
$CleanAppName = $AppName -replace '[\\/:*?"<>|]', ''
$OutputScriptPath = Join-Path -Path $PSScriptRoot -ChildPath "Detect-${CleanAppName}.ps1"

#****Define the script template (Here-String)
# NOTE: @"..." is an expanding here-string.
# The $WingetId variable will be injected.
# All other '$' characters (like `$env`, `$WingetCmd`, `$_`) must be escaped
# with a backtick (`) so they are written literally to the file.
$ScriptTemplate = @"
#Change app to detect [Application ID]
`$AppToDetect = "$WingetId"


<# FUNCTIONS #>

Function Get-WingetCmd {

    `$WingetCmd = `$null
    
    #Get WinGet Path
    try {
        #Get Admin Context Winget Location
        `$WingetInfo = (Get-Item "`$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_8wekyb3d8bbwe\winget.exe").VersionInfo | Sort-Object -Property FileVersionRaw
        #If multiple versions, pick most recent one
        `$WingetCmd = `$WingetInfo[-1].FileName
    }
    catch {
        #Get User context Winget Location
        if (Test-Path "`$env:LocalAppData\Microsoft\WindowsApps\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\winget.exe") {
            `$WingetCmd = "`$env:LocalAppData\Microsoft\WindowsApps\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\winget.exe"
        }
    }
    
    return `$WingetCmd
}

<# MAIN #>

#Get WinGet Location Function
`$winget = Get-WingetCmd

#Set json export file
`$JsonFile = "`$env:TEMP\InstalledApps.json"

#Get installed apps and version in json file
& `$Winget export -o `$JsonFile --accept-source-agreements | Out-Null

#Get json content
`$Json = Get-Content `$JsonFile -Raw | ConvertFrom-Json

#Get apps and version in hashtable
`$Packages = `$Json.Sources.Packages

#Remove json file
Remove-Item `$JsonFile -Force

# Search for specific app and version
`$Apps = `$Packages | Where-Object { `$_`.PackageIdentifier -eq `$AppToDetect }

if (`$Apps) {
    Write-Output "Detected!"
    exit 0
} else {
    exit 1
}
"@

#****Save the new script file
try {
    Set-Content -Path $OutputScriptPath -Value $ScriptTemplate -Encoding UTF8
    Write-Host "`nSuccess! Generated script file:"
    Write-Host $OutputScriptPath -ForegroundColor Green
} catch {
    Write-Error "Could not write file to '$OutputScriptPath'. Error: $_"
}