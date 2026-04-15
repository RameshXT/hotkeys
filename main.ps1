#Requires -Version 5.1
$ErrorActionPreference = "Continue"

$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal   = New-Object Security.Principal.WindowsPrincipal($currentUser)
$isAdmin     = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    $scriptPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
    $argList = "-NonInteractive -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
    Start-Process powershell.exe -ArgumentList $argList -Verb RunAs
    exit 0
}

Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class ConsoleWindow {
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")]   public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);
    [DllImport("user32.dll")]   public static extern int GetSystemMetrics(int nIndex);
}
"@

try {
    $hwnd       = [ConsoleWindow]::GetConsoleWindow()
    $screenW    = [ConsoleWindow]::GetSystemMetrics(0)
    $screenH    = [ConsoleWindow]::GetSystemMetrics(1)
    $winW       = [int]($screenW * 0.50)
    $winH       = [int]($screenH * 0.50)
    $posX       = [int](($screenW - $winW) / 2)
    $posY       = [int](($screenH - $winH) / 2)
    [ConsoleWindow]::MoveWindow($hwnd, $posX, $posY, $winW, $winH, $true) | Out-Null
    $bufferSize = New-Object System.Management.Automation.Host.Size(120, 9999)
    $Host.UI.RawUI.BufferSize = $bufferSize
    $windowSize = New-Object System.Management.Automation.Host.Size(80, 30)
    $Host.UI.RawUI.WindowSize = $windowSize
} catch { Write-Warning "Console window resize failed: $_" }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Show-Balloon {
    param([string]$Title, [string]$Message, [string]$Type = "Info")
    try {
        $allowedTypes = @("Info", "Warning", "Error", "None")
        if ($allowedTypes -notcontains $Type) { $Type = "Info" }
        $notify         = New-Object System.Windows.Forms.NotifyIcon
        $notify.Icon    = [System.Drawing.SystemIcons]::Application
        $notify.Visible = $true
        $tipIcon        = [System.Windows.Forms.ToolTipIcon]::$Type
        $notify.ShowBalloonTip(6000, $Title, $Message, $tipIcon)
        Start-Sleep -Milliseconds 200
        $notify.Dispose()
    } catch { Write-Warning "Balloon notification failed: $_" }
}


function Write-OK {
    param([string]$Message)
    Write-Host "  [+] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "  [!] $Message" -ForegroundColor Yellow
}

function Write-Err {
    param([string]$Message)
    Write-Host "  [x] $Message" -ForegroundColor Red
}

$TestDestination = ""

if ($PSScriptRoot -and (Test-Path $PSScriptRoot)) {
    $Source = $PSScriptRoot
} else {
    $Source = Split-Path -Parent $MyInvocation.MyCommand.Definition
}

if ($TestDestination -ne "") {
    $Destination = $TestDestination
} else {
    $Destination = Join-Path $env:USERPROFILE "sys-scripts"
}
$StartupFolder = [Environment]::GetFolderPath("Startup")
$SourceNorm    = $Source.TrimEnd('\').ToLower()
$DestNorm      = $Destination.TrimEnd('\').ToLower()

$checkFiles = @(
    (Join-Path $Destination "install.ps1"),
    (Join-Path $Destination "cleanup\cleanup.ps1"),
    (Join-Path $Destination "network\network-reset.ps1"),
    (Join-Path $Destination "update\update.ps1"),
    (Join-Path $Destination "hotkeys\hotkeys.ahk")
)

$installedCount  = ($checkFiles | Where-Object { Test-Path $_ }).Count
$alreadyInstalled = ($SourceNorm -eq $DestNorm) -or ($installedCount -eq $checkFiles.Count)

if ($alreadyInstalled) {
    Clear-Host
    Write-Host ""
    Write-Host "  sys-scripts Installer" -ForegroundColor White
    Write-Host "  ----------------------------------------" -ForegroundColor DarkGray
    Write-Host "  Installing to  $Destination" -ForegroundColor DarkGray
    Write-Host "  ----------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  [+] Already installed." -ForegroundColor Green
    Write-Host ""
    Write-Host "  ----------------------------------------" -ForegroundColor DarkGray
    Write-Host "  All done." -ForegroundColor Green
    Write-Host "  ----------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
    Show-Balloon -Title "sys-scripts Installer" -Message "Already installed. Nothing to do." -Type "Info"
    [Console]::Write("  Closing in 5...")
    for ($i = 5; $i -ge 1; $i--) {
        [Console]::SetCursorPosition(0, [Console]::CursorTop)
        [Console]::Write("  Closing in $i...  ")
        Start-Sleep -Seconds 1
    }
    [Console]::WriteLine("")
    exit 0
}

Clear-Host
Write-Host ""
Write-Host "  sys-scripts Installer" -ForegroundColor White
Write-Host "  ----------------------------------------" -ForegroundColor DarkGray
Write-Host "  Installing to  $Destination" -ForegroundColor DarkGray
Write-Host "  ----------------------------------------" -ForegroundColor DarkGray
Write-Host ""

$TotalSteps  = 5
$StepNum     = 0
$ErrorCount  = 0
$WarnCount   = 0

$StepNum++
Write-Host ""
Write-Host "  Copying files" -ForegroundColor DarkGray

try {
    $items = Get-ChildItem -Path $Source -Recurse -ErrorAction Stop
    $total = $items.Count
    $i     = 0

    foreach ($item in $items) {
        $i++
        $relPath = $item.FullName.Substring($Source.Length).TrimStart('\')
        $dest    = Join-Path $Destination $relPath

        if ($item.PSIsContainer) {
            if (-not (Test-Path $dest)) {
                New-Item -ItemType Directory -Path $dest -Force | Out-Null
            }
        } else {
            $destDir = Split-Path $dest -Parent
            if (-not (Test-Path $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }
            Copy-Item -Path $item.FullName -Destination $dest -Force -ErrorAction Stop
        }

    }

    Write-OK "Files copied ($total items)"
} catch {
    Write-Err "File copy failed : $_"
    $ErrorCount++
}

$StepNum++
Write-Host ""
Write-Host "  Preparing logs" -ForegroundColor DarkGray

try {
    $LogDir   = Join-Path $Destination "logs"
    $LogFiles = @("cleanup_log.txt", "netreset_log.txt", "update_log.txt")

    if (-not (Test-Path $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    }

    foreach ($log in $LogFiles) {
        $logPath = Join-Path $LogDir $log
        if (-not (Test-Path $logPath)) {
            New-Item -ItemType File -Path $logPath -Force | Out-Null
        }
    }
    Write-OK "Log files ready"
} catch {
    Write-Warn "Log file setup issue : $_"
    $WarnCount++
}

$StepNum++
Write-Host ""
Write-Host "  Registering tasks" -ForegroundColor DarkGray

function Register-PSTask {
    [CmdletBinding()]
    param(
        [string]$TaskName,
        [string]$ScriptPath,
        [ValidateSet("Weekly", "Daily", "AtLogon")]
        [string]$TriggerType,
        [string]$At  = "02:00",
        [ValidateSet("Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday")]
        [string]$Day = "Sunday"
    )
    try {
        if (-not (Test-Path $ScriptPath)) {
            Write-Warn "Script not found, skipping task '$TaskName' : $ScriptPath"
            return "WARN"
        }

        $action   = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NonInteractive -ExecutionPolicy Bypass -File `"$ScriptPath`""

        if ($TriggerType -eq "Weekly") {
            $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $Day -At $At
        } elseif ($TriggerType -eq "Daily") {
            $trigger = New-ScheduledTaskTrigger -Daily -At $At
        } else {
            $trigger = New-ScheduledTaskTrigger -AtLogOn
        }

        $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 1) -StartWhenAvailable -MultipleInstances IgnoreNew

        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -RunLevel Highest -Force -ErrorAction Stop | Out-Null
        Write-OK "Task registered : $TaskName"
        return "OK"
    } catch {
        Write-Err "Task failed : $TaskName - $_"
        return "FAIL"
    }
}

$t1 = Register-PSTask -TaskName "UserCleanup"  -ScriptPath (Join-Path $Destination "cleanup\cleanup.ps1")         -TriggerType "Weekly"  -At "02:00" -Day "Sunday"
$t2 = Register-PSTask -TaskName "UserNetReset" -ScriptPath (Join-Path $Destination "network\network-reset.ps1")   -TriggerType "AtLogon"
$t3 = Register-PSTask -TaskName "UserUpdate"   -ScriptPath (Join-Path $Destination "update\update.ps1")           -TriggerType "Weekly"  -At "03:00" -Day "Monday"

if ($t1 -eq "FAIL" -or $t2 -eq "FAIL" -or $t3 -eq "FAIL") { $ErrorCount++ }
if ($t1 -eq "WARN" -or $t2 -eq "WARN" -or $t3 -eq "WARN") { $WarnCount++ }

$StepNum++
Write-Host ""
Write-Host "  Startup hotkey" -ForegroundColor DarkGray

try {
    $ahkSource = Join-Path $Destination "hotkeys\hotkeys.ahk"
    $ahkTarget = Join-Path $StartupFolder "hotkeys.ahk"

    if (Test-Path $ahkSource) {
        Copy-Item -Path $ahkSource -Destination $ahkTarget -Force -ErrorAction Stop

        $ahkPaths = @(
            "$env:ProgramFiles\AutoHotkey\AutoHotkey.exe",
            "${env:ProgramFiles(x86)}\AutoHotkey\AutoHotkey.exe",
            "$env:LocalAppData\Programs\AutoHotkey\AutoHotkey.exe"
        )
        $ahkFound = $ahkPaths | Where-Object { Test-Path $_ }

        if ($ahkFound.Count -gt 0) {
            Write-OK "Hotkey placed in startup"
        } else {
            Write-Warn "Hotkey placed but AutoHotkey is not installed"
            $WarnCount++
        }
    } else {
        Write-Warn "hotkeys.ahk not found, skipping"
        $WarnCount++
    }
} catch {
    Write-Err "Startup hotkey failed : $_"
    $ErrorCount++
}

$StepNum++

Write-Host ""
Write-Host "  ----------------------------------------" -ForegroundColor DarkGray

if ($ErrorCount -eq 0 -and $WarnCount -eq 0) {
    Write-Host "  All done." -ForegroundColor Green
    $balloonType = "Info"
    $balloonMsg  = "Installation complete."
} elseif ($ErrorCount -eq 0) {
    Write-Host "  Done with $WarnCount warning(s)." -ForegroundColor Yellow
    $balloonType = "Warning"
    $balloonMsg  = "Installed with $WarnCount warning(s)."
} else {
    Write-Host "  Failed. $ErrorCount error(s)." -ForegroundColor Red
    $balloonType = "Error"
    $balloonMsg  = "$ErrorCount error(s) during install."
}

Write-Host "  ----------------------------------------" -ForegroundColor DarkGray
Write-Host ""

Show-Balloon -Title "sys-scripts Installer" -Message $balloonMsg -Type $balloonType

[Console]::Write("  Closing in 5...")
for ($i = 5; $i -ge 1; $i--) {
    [Console]::SetCursorPosition(0, [Console]::CursorTop)
    [Console]::Write("  Closing in $i...  ")
    Start-Sleep -Seconds 1
}
[Console]::WriteLine("")
exit 0
