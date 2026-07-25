#Requires -Version 5.1
$ErrorActionPreference = "Stop"

# Self-elevate for commands that require Admin privileges
$cmd = if ($args.Count -gt 0) { $args[0].ToLower() } else { "" }
if ($cmd -in @("install", "update", "uninstall")) {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        $scriptPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
        $passedArgs = $args | ForEach-Object { "`"$_`"" }
        $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" $passedArgs"
        try {
            Start-Process powershell.exe -ArgumentList $argList -Verb RunAs
        } catch {
            Write-Error "This command requires Administrator privileges."
        }
        exit 0
    }
}

# CLI Paths
$InstallDir = Join-Path $env:LOCALAPPDATA "xt"
$StartupFolder = [Environment]::GetFolderPath("Startup")
$ShortcutPath = Join-Path $StartupFolder "hotkeys.lnk"

# Find source directory (where this script is located)
if ($PSScriptRoot -and (Test-Path $PSScriptRoot)) {
    $SourceDir = $PSScriptRoot
} else {
    $SourceDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
}

# Helper output functions
function Write-OK ($Msg) { Write-Host "  [+] $Msg" -ForegroundColor Green }
function Write-Warn ($Msg) { Write-Host "  [!] $Msg" -ForegroundColor Yellow }
function Write-Err ($Msg) { Write-Host "  [x] $Msg" -ForegroundColor Red }
function Write-Info ($Msg) { Write-Host "  [-] $Msg" -ForegroundColor Cyan }

# Check for AutoHotkey installation
function Get-AHKPath {
    $ahkPaths = @(
        "$env:ProgramFiles\AutoHotkey\AutoHotkey.exe",
        "${env:ProgramFiles(x86)}\AutoHotkey\AutoHotkey.exe",
        "$env:LocalAppData\Programs\AutoHotkey\AutoHotkey.exe",
        "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe",
        "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe"
    )
    foreach ($path in $ahkPaths) {
        if (Test-Path $path) { return $path }
    }
    return $null
}

# Check if script is running
function Get-RunningAHK {
    $pidFile = Join-Path $InstallDir "hotkeys.pid"
    if (Test-Path $pidFile) {
        try {
            $id = Get-Content $pidFile -ErrorAction Stop
            $p = Get-Process -Id [int]$id -ErrorAction Stop
            if ($p.ProcessName -like "AutoHotkey*") {
                return $p
            }
        } catch {}
    }
    return $null
}

# 1. INSTALL COMMAND
function Invoke-Install ($Target, $Yes) {
    Write-Host "`n  Installing Hotkeys..." -ForegroundColor White
    Write-Host "  ----------------------------------------" -ForegroundColor DarkGray

    # Verify AutoHotkey is installed
    $ahk = Get-AHKPath
    if ($null -eq $ahk) {
        Write-Warn "AutoHotkey v2 is not detected on your system."
        Write-Info "Please install AutoHotkey v2: https://www.autohotkey.com/"
        if (-not $Yes) {
            $choice = Read-Host "  Do you want to continue anyway? (y/N)"
            if ($choice.ToLower() -ne "y") { exit 1 }
        }
    } else {
        Write-OK "AutoHotkey found at: $ahk"
    }

    # Create destination directory
    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
        Write-OK "Created directory: $InstallDir"
    }

    # Copy files
    try {
        Copy-Item -Path (Join-Path $SourceDir "hotkeys.ahk") -Destination (Join-Path $InstallDir "hotkeys.ahk") -Force
        Copy-Item -Path (Join-Path $SourceDir "xt.bat") -Destination (Join-Path $InstallDir "xt.bat") -Force
        Copy-Item -Path (Join-Path $SourceDir "xt.ps1") -Destination (Join-Path $InstallDir "xt.ps1") -Force
        Write-OK "Copied script and CLI files to $InstallDir"
    } catch {
        Write-Err "Failed to copy files: $_"
        exit 1
    }

    # Create Startup Shortcut
    try {
        $WshShell = New-Object -ComObject WScript.Shell
        $Shortcut = $WshShell.CreateShortcut($ShortcutPath)
        $Shortcut.TargetPath = Join-Path $InstallDir "hotkeys.ahk"
        $Shortcut.WorkingDirectory = $InstallDir
        $Shortcut.Save()

        # Force "Run as Administrator" on the shortcut (set 0x20 flag at byte 21)
        $bytes = [System.IO.File]::ReadAllBytes($ShortcutPath)
        $bytes[21] = $bytes[21] -bor 0x20
        [System.IO.File]::WriteAllBytes($ShortcutPath, $bytes)

        Write-OK "Autostart shortcut created (Admin flag enabled)"
    } catch {
        Write-Err "Failed to create startup shortcut: $_"
        exit 1
    }

    # Add directory to PATH
    try {
        $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
        $dirs = $currentPath -split ";"
        $normalizedInstall = $InstallDir.TrimEnd('\').ToLower()
        $alreadyInPath = $false
        foreach ($d in $dirs) {
            if ($d.TrimEnd('\').ToLower() -eq $normalizedInstall) {
                $alreadyInPath = $true
                break
            }
        }
        if (-not $alreadyInPath) {
            $newPath = $currentPath + ";" + $InstallDir
            [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
            Write-OK "Added $InstallDir to user PATH (Restart terminal to apply)"
        } else {
            Write-OK "$InstallDir is already in user PATH"
        }
    } catch {
        Write-Warn "Failed to update PATH environment variable: $_"
    }

    # Start AHK script
    try {
        $p = Get-RunningAHK
        if ($null -ne $p) {
            Write-Info "Restarting running instance..."
            $p | Stop-Process -Force
            Start-Sleep -Milliseconds 500
        }
        $targetAHKScript = Join-Path $InstallDir "hotkeys.ahk"
        $ahkExe = Get-AHKPath
        if ($null -ne $ahkExe) {
            Start-Process -FilePath $ahkExe -ArgumentList "`"$targetAHKScript`"" -WorkingDirectory $InstallDir
        } else {
            Start-Process -FilePath $targetAHKScript -WorkingDirectory $InstallDir
        }
        Write-OK "Launched hotkeys.ahk"
    } catch {
        Write-Err "Failed to start hotkeys.ahk: $_"
    }

    Write-Host "  ----------------------------------------" -ForegroundColor DarkGray
    Write-Host "  Installation completed successfully!`n" -ForegroundColor Green
}

# 2. UPDATE COMMAND
function Invoke-Update ($Target) {
    Write-Host "`n  Updating Hotkeys..." -ForegroundColor White
    Write-Host "  ----------------------------------------" -ForegroundColor DarkGray

    if (-not (Test-Path $InstallDir)) {
        Write-Err "Installation directory not found. Please run 'xt install' first."
        exit 1
    }

    # If run inside git repo, sync from repo. Otherwise, try pulling git changes
    $gitDir = Join-Path $SourceDir ".git"
    if (Test-Path $gitDir) {
        Write-Info "Repository detected. Copying latest local changes..."
        try {
            # Stop active script
            $p = Get-RunningAHK
            if ($null -ne $p) {
                $p | Stop-Process -Force
                Start-Sleep -Milliseconds 500
            }

            # Copy updated files
            Copy-Item -Path (Join-Path $SourceDir "hotkeys.ahk") -Destination (Join-Path $InstallDir "hotkeys.ahk") -Force
            Copy-Item -Path (Join-Path $SourceDir "xt.bat") -Destination (Join-Path $InstallDir "xt.bat") -Force
            Copy-Item -Path (Join-Path $SourceDir "xt.ps1") -Destination (Join-Path $InstallDir "xt.ps1") -Force
            Write-OK "Updated files in $InstallDir"

            # Restart script
            $targetAHKScript = Join-Path $InstallDir "hotkeys.ahk"
            $ahkExe = Get-AHKPath
            if ($null -ne $ahkExe) {
                Start-Process -FilePath $ahkExe -ArgumentList "`"$targetAHKScript`"" -WorkingDirectory $InstallDir
            } else {
                Start-Process -FilePath $targetAHKScript -WorkingDirectory $InstallDir
            }
            Write-OK "Restarted hotkeys.ahk"
        } catch {
            Write-Err "Failed to apply update: $_"
            exit 1
        }
    } else {
        Write-Warn "Not running inside a git repository. Cannot pull updates."
    }

    Write-Host "  ----------------------------------------" -ForegroundColor DarkGray
    Write-Host "  Update completed successfully!`n" -ForegroundColor Green
}

# 3. STATUS COMMAND
function Get-Status {
    Write-Host "`n  sys-scripts Status:" -ForegroundColor White
    Write-Host "  ----------------------------------------" -ForegroundColor DarkGray
    
    $p = Get-RunningAHK
    if ($null -ne $p) {
        Write-Host "  Hotkeys:    " -NoNewline
        Write-Host "Running (PID: $($p.Id))" -ForegroundColor Green
    } else {
        Write-Host "  Hotkeys:    " -NoNewline
        Write-Host "Stopped" -ForegroundColor Red
    }

    Write-Host "  InstallDir: " -NoNewline
    if (Test-Path $InstallDir) {
        Write-Host $InstallDir -ForegroundColor Green
    } else {
        Write-Host "Not Installed" -ForegroundColor Red
    }

    Write-Host "  Shortcut:   " -NoNewline
    if (Test-Path $ShortcutPath) {
        Write-Host "Active in Startup" -ForegroundColor Green
    } else {
        Write-Host "Missing" -ForegroundColor Red
    }

    Write-Host "  ----------------------------------------`n" -ForegroundColor DarkGray
}

# 4. UNINSTALL COMMAND
function Invoke-Uninstall ($Target) {
    Write-Host "`n  Uninstalling Hotkeys..." -ForegroundColor White
    Write-Host "  ----------------------------------------" -ForegroundColor DarkGray

    # Terminate script
    $p = Get-RunningAHK
    if ($null -ne $p) {
        $p | Stop-Process -Force
        Write-OK "Stopped active hotkeys instance"
    }

    # Delete Startup shortcut
    if (Test-Path $ShortcutPath) {
        Remove-Item -Path $ShortcutPath -Force
        Write-OK "Removed Startup shortcut"
    }

    # Remove PATH environment variable
    try {
        $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
        $dirs = $currentPath -split ";"
        $normalizedInstall = $InstallDir.TrimEnd('\').ToLower()
        
        $newDirs = @()
        foreach ($d in $dirs) {
            if ($d.TrimEnd('\').ToLower() -ne $normalizedInstall -and $d -ne "") {
                $newDirs += $d
            }
        }
        $newPath = $newDirs -join ";"
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        Write-OK "Removed $InstallDir from PATH"
    } catch {
        Write-Warn "Failed to update PATH environment variable: $_"
    }

    # Clean up installation directory
    if (Test-Path $InstallDir) {
        try {
            Remove-Item -Path $InstallDir -Recurse -Force
            Write-OK "Deleted installation folder: $InstallDir"
        } catch {
            Write-Warn "Failed to completely delete installation directory (some files might be locked): $_"
        }
    }

    Write-Host "  ----------------------------------------" -ForegroundColor DarkGray
    Write-Host "  Uninstall completed successfully!`n" -ForegroundColor Green
}

# CLI Argument Router
if ($args.Count -eq 0) {
    Write-Host "`n  'xt' Hotkey CLI Tool" -ForegroundColor White
    Write-Host "  Usage: xt [install | update | status | uninstall] [hotkeys] [-y]" -ForegroundColor DarkGray
    Write-Host "  Commands:" -ForegroundColor DarkGray
    Write-Host "    install     Installs hotkeys and adds command to PATH"
    Write-Host "    update      Updates files and restarts the script"
    Write-Host "    status      Checks active script status"
    Write-Host "    uninstall   Removes all shortcuts, files, and PATH configuration`n"
    exit 0
}

$cmd = $args[0].ToLower()
$target = "hotkeys"
$yes = $false

foreach ($arg in $args[1..($args.Count-1)]) {
    if ($arg.ToLower() -eq "-y") { $yes = $true }
    elseif ($arg.ToLower() -eq "hotkeys") { $target = "hotkeys" }
}

switch ($cmd) {
    "install"   { Invoke-Install $target $yes }
    "update"    { Invoke-Update $target }
    "status"    { Get-Status }
    "uninstall" { Invoke-Uninstall $target }
    default     { Write-Err "Unknown command: $cmd" }
}
