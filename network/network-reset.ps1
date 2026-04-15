<#
.SYNOPSIS
    Advanced Network Reset Utility v1.2
.DESCRIPTION
    Performs a deep reset of the network stack, including Winsock, TCP/IP, DNS, and adapter cycling.
    Includes GUI positioning and tray notifications.
.EXAMPLE
    powershell.exe -File network-reset.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# --- Core Configuration ---
$VERSION       = "1.2"
$SCRIPT_START  = Get-Date
$ScriptDir     = $PSScriptRoot
if (-not $ScriptDir) { $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
$LogFile       = Join-Path (Split-Path -Parent $ScriptDir) "logs\netreset_log.txt"
$ResultFile    = Join-Path $ScriptDir "netreset_result.txt"
$MaxLogSizeB   = 2MB
$HeaderWidth   = 62
$LabelW        = 22

# --- UI Helpers ---
function Write-Header {
    $line = "=" * $HeaderWidth
    Write-Host ""
    Write-Host $line -ForegroundColor Cyan
    Write-Host ("  NETWORK RESET  v$VERSION  |  System Recovery" -f $VERSION).PadRight($HeaderWidth) -ForegroundColor Cyan
    Write-Host $line -ForegroundColor Cyan
    Write-Host ""
}

function Write-Section {
    param([string]$Text)
    Write-Host ""
    Write-Host "  >> $Text" -ForegroundColor DarkCyan
    Write-Host ""
}

function Write-Line {
    param([string]$Label, [string]$Value, [string]$Color = "White")
    $dots = "." * [math]::Max(1, ($LabelW - $Label.Length))
    Write-Host "  $Label$dots " -NoNewline -ForegroundColor DarkGray
    Write-Host $Value -ForegroundColor $Color
}

function Show-Loader {
    param(
        [scriptblock]$ScriptBlock,
        [object[]]$ArgumentList = @(),
        [int]$ExpectedSeconds   = 10,
        [int]$TimeoutSeconds    = 60
    )

    $barLen    = 30
    $elapsed   = [System.Diagnostics.Stopwatch]::StartNew()
    $clearLine = " " * 80

    $job = try {
        if (Get-Command Start-ThreadJob -ErrorAction SilentlyContinue) {
            Start-ThreadJob -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
        } else {
            Start-Job -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
        }
    } catch {
        Start-Job -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
    }

    $timedOut = $false
    try {
        while ($job.State -eq 'Running') {
            $secs = $elapsed.Elapsed.TotalSeconds
            if ($secs -ge $TimeoutSeconds) {
                $timedOut = $true
                Stop-Job -Job $job -ErrorAction SilentlyContinue
                break
            }
            $t    = [math]::Min($secs / [math]::Max($ExpectedSeconds, 1), 1.0)
            $fill = [int]($barLen * ($t / ($t + 0.15)) * 0.95)
            $pct  = [int](($fill / $barLen) * 100)
            $bar  = ('#' * $fill) + ('.' * ($barLen - $fill))
            $s    = [int]$secs
            Write-Host -NoNewline "`r  ${s}s  [$bar]  $pct%" -ForegroundColor Cyan
            Start-Sleep -Milliseconds 200
        }
    } finally {
        $elapsed.Stop()
    }

    Write-Host "`r$clearLine`r" -NoNewline
    if ($timedOut) {
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        return "TIMEOUT"
    }

    try {
        $result = Receive-Job -Job $job -Wait -ErrorAction SilentlyContinue
        return $result
    } finally {
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    }
}

# --- System Logic ---
function Get-WifiAdapter {
    $candidates = Get-NetAdapter | Where-Object { 
        $_.PhysicalMediaType -in @("Native 802.11", "Wireless LAN") -or 
        $_.Name -match "Wi.?Fi|Wireless|WLAN|802\.11"
    }
    return ($candidates | Sort-Object -Property { $_.Status -eq "Up" } -Descending | Select-Object -First 1)
}

function Test-Internet {
    $hosts = @("8.8.8.8", "1.1.1.1", "9.9.9.9")
    foreach ($h in $hosts) {
        $tcp = New-Object System.Net.Sockets.TcpClient
        try {
            $ar = $tcp.BeginConnect($h, 443, $null, $null)
            if ($ar.AsyncWaitHandle.WaitOne(2500)) {
                $tcp.EndConnect($ar)
                return $true
            }
        } catch {} finally { $tcp.Close(); $tcp.Dispose() }
    }
    return $false
}

# --- Main Execution ---
try {
    Write-Header
    Write-Host "  Initializing system resources..." -ForegroundColor Gray

    # 1. Position Window
    try {
        $src = @'
        using System;
        using System.Runtime.InteropServices;
        public class ConsoleWindow {
            [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
            [DllImport("user32.dll")]   public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int h2, bool r);
            [DllImport("user32.dll")]   public static extern int  GetSystemMetrics(int n);
        }
'@
        if (-not ('ConsoleWindow' -as [type])) { Add-Type -TypeDefinition $src -ErrorAction Stop }
        $hwnd = [ConsoleWindow]::GetConsoleWindow()
        if ($hwnd -ne [IntPtr]::Zero) {
            $sw = [ConsoleWindow]::GetSystemMetrics(0)
            $sh = [ConsoleWindow]::GetSystemMetrics(1)
            $ww = [int]($sw * 0.35); $wh = [int]($sh * 0.60)
            [void][ConsoleWindow]::MoveWindow($hwnd, ($sw - $ww), 0, $ww, $wh, $true)
        }
    } catch { Write-Verbose "Window positioning failed: $_" }

    # 2. Permissions Check
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) { throw "Administrator privileges required. Run as Admin." }

    # 3. Environment Setup
    if (-not (Test-Path (Split-Path $LogFile -Parent))) {
        New-Item -ItemType Directory -Path (Split-Path $LogFile -Parent) -Force | Out-Null
    }
    if ((Test-Path $LogFile) -and (Get-Item $LogFile).Length -gt $MaxLogSizeB) { Clear-Content $LogFile }

    # 4. Diagnostics
    Write-Section "Diagnostics"
    $adapter = Get-WifiAdapter
    if ($null -eq $adapter) { throw "No Wi-Fi adapter detected." }

    Write-Line "Adapter" $adapter.Name
    Write-Line "Status"  $adapter.Status $(if ($adapter.Status -eq "Up") {"Green"} else {"Yellow"})
    
    $online = Test-Internet
    Write-Line "Internet" $(if ($online) {"Online"} else {"Offline"}) $(if ($online) {"Green"} else {"Red"})

    # 5. Reset Operations
    Write-Section "Resetting Network Stack"
    
    $steps = @(
        @{ Label = "Releasing IP Lease"; Script = { ipconfig /release "$($args[0])" 2>&1 } },
        @{ Label = "Flushing DNS Cache"; Script = { Clear-DnsClientCache } },
        @{ Label = "Resetting Winsock";  Script = { netsh winsock reset 2>&1 } },
        @{ Label = "Resetting TCP/IP";  Script = { netsh int ip reset 2>&1 } },
        @{ Label = "Cycling Adapter";   Script = { 
            Disable-NetAdapter -Name "$($args[0])" -Confirm:$false
            Start-Sleep -Seconds 2
            Enable-NetAdapter -Name "$($args[0])" -Confirm:$false
        } }
    )

    foreach ($step in $steps) {
        Write-Host "  $($step.Label.PadRight(30))" -NoNewline -ForegroundColor Gray
        $res = Show-Loader -ScriptBlock $step.Script -ArgumentList $adapter.Name
        Write-Host " DONE" -ForegroundColor Green
    }

    # 6. Reconnection Logic
    Write-Section "Reconnection"
    Write-Host "  Waiting for network connectivity..." -ForegroundColor Gray
    
    $timeout = 60; $elapsed = 0; $connected = $false
    while ($elapsed -lt $timeout) {
        Start-Sleep -Seconds 1
        $elapsed++
        $current = Get-NetAdapter -Name $adapter.Name -ErrorAction SilentlyContinue
        if ($current.Status -eq "Up") {
            $handshake = Test-Internet
            if ($handshake) { $connected = $true; break }
        }
        Write-Host -NoNewline "." -ForegroundColor DarkGray
    }
    Write-Host ""

    if ($connected) {
        Write-Line "Renewing IP" "OK" "Green"
        ipconfig /renew "$($adapter.Name)" | Out-Null
    } else {
        Write-Line "Reconnection" "TIMED OUT" "Red"
    }

    # 7. Final Summary
    $FinalOnline = Test-Internet
    $Duration    = "{0:mm\:ss}" -f ((Get-Date) - $SCRIPT_START)
    
    Write-Section "Summary"
    Write-Line "Result" $(if ($FinalOnline) {"RESTORED"} else {"FAILED"}) $(if ($FinalOnline) {"Green"} else {"Red"})
    Write-Line "Elapsed" $Duration
    Write-Host ("=" * $HeaderWidth) -ForegroundColor DarkGray
    
    # 8. Logging & Notify
    $logMsg = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Result: $(if ($FinalOnline){'Success'}else{'Fail'}) | Adapter: $($adapter.Name) | Time: $Duration"
    Add-Content $LogFile $logMsg
    
    "$($adapter.Name)|Network Reset $(if ($FinalOnline){'Complete'}else{'Incomplete'})`nInternet: $(if ($FinalOnline){'Online'}else{'Check router'})" | Set-Content $ResultFile

    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    $balloon = [System.Windows.Forms.NotifyIcon]::new()
    $balloon.Icon = [System.Drawing.SystemIcons]::Information
    $balloon.Visible = $true
    $balloon.BalloonTipTitle = "Network Reset Done"
    $balloon.BalloonTipText = if ($FinalOnline) { "Connection restored." } else { "Could not verify internet. Check router." }
    $balloon.ShowBalloonTip(5000)
    
    Write-Host "`n  Closing in..." -ForegroundColor DarkGray
    for ($i=3; $i -gt 0; $i--) { Write-Host -NoNewline " $i"; Start-Sleep -Seconds 1 }
    $balloon.Dispose()

} catch {
    Write-Host "`n  [FATAL ERROR] $($_.Exception.Message)" -ForegroundColor Red
    if ($null -ne $ResultFile) { "FAIL|Error: $($_.Exception.Message)" | Set-Content $ResultFile }
    Start-Sleep -Seconds 30
}
