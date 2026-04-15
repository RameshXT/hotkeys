<#
.SYNOPSIS
    Premium Network Reset Utility v1.3
.DESCRIPTION
    Minimal, structured network stack recovery with a modern aesthetic.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

# --- Configuration ---
$VERSION       = "1.3"
$SCRIPT_START  = Get-Date
$ScriptDir     = $PSScriptRoot
if (-not $ScriptDir) { $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
$LogFile       = Join-Path (Split-Path -Parent $ScriptDir) "logs\netreset_log.txt"
$ResultFile    = Join-Path $ScriptDir "netreset_result.txt"
$MaxLogSizeB   = 2MB
$ColWidth      = 40

# --- Aesthetic Helpers ---
function Write-Header {
    Write-Host ""
    Write-Host "  NETWORK RESET" -ForegroundColor Cyan -NoNewline
    Write-Host " v$VERSION" -ForegroundColor DarkGray
    Write-Host "  " + ("-" * 30) -ForegroundColor DarkGray
    Write-Host ""
}

function Write-Section {
    param([string]$Text)
    Write-Host "`n  $($Text.ToUpper())" -ForegroundColor White
}

function Write-Status {
    param([string]$Label, [string]$Status, [string]$Color = "White")
    $dots = "." * ($ColWidth - $Label.Length)
    Write-Host "  $Label" -NoNewline -ForegroundColor Gray
    Write-Host $dots -NoNewline -ForegroundColor DarkGray
    Write-Host " [ " -NoNewline -ForegroundColor DarkGray
    Write-Host $Status -NoNewline -ForegroundColor $Color
    Write-Host " ]" -ForegroundColor DarkGray
}

function Invoke-WithStatus {
    param(
        [string]$Label,
        [scriptblock]$Script,
        [object[]]$Args = @()
    )
    
    $dots = "." * ($ColWidth - $Label.Length)
    Write-Host "  $Label" -NoNewline -ForegroundColor Gray
    Write-Host $dots -NoNewline -ForegroundColor DarkGray
    Write-Host " [ " -NoNewline -ForegroundColor DarkGray
    Write-Host "...." -NoNewline -ForegroundColor Cyan
    Write-Host " ]" -NoNewline -ForegroundColor DarkGray

    $job = Start-Job -ScriptBlock $Script -ArgumentList $Args
    $spinner = @('|', '/', '-', '\')
    $i = 0
    
    while ($job.State -eq 'Running') {
        Write-Host -NoNewline "`b`b`b`b`b" 
        Write-Host -NoNewline " $($spinner[$i % 4])  " -ForegroundColor Cyan
        $i++
        Start-Sleep -Milliseconds 150
    }
    
    $result = Receive-Job -Job $job -Wait
    Remove-Job $job
    
    Write-Host -NoNewline "`b`b`b`b`b"
    Write-Host " OK " -ForegroundColor Green
    Write-Host " ]" -ForegroundColor DarkGray -NoNewline
    Write-Host ""
}

# --- Core Logic ---
try {
    # 1. Initialization
    $hwnd = $null
    try {
        $src = @'
        using System;
        using System.Runtime.InteropServices;
        public class Win {
            [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
            [DllImport("user32.dll")]   public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int h2, bool r);
            [DllImport("user32.dll")]   public static extern int  GetSystemMetrics(int n);
        }
'@
        if (-not ('Win' -as [type])) { Add-Type -TypeDefinition $src }
        $hwnd = [Win]::GetConsoleWindow()
        if ($hwnd -ne [IntPtr]::Zero) {
            $sw = [Win]::GetSystemMetrics(0); $sh = [Win]::GetSystemMetrics(1)
            $ww = [int]($sw * 0.30); $wh = [int]($sh * 0.50)
            [void][Win]::MoveWindow($hwnd, ($sw - $ww), 0, $ww, $wh, $true)
        }
    } catch {}

    Write-Header
    
    # 2. Checks
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Admin privileges required."
    }

    $adapter = Get-NetAdapter | Where-Object { $_.PhysicalMediaType -match '802.11|Wireless' -or $_.Name -match 'Wi-Fi|Wireless' } | Sort-Object Status -Descending | Select-Object -First 1
    if (-not $adapter) { throw "No Wi-Fi adapter found." }

    Write-Section "Diagnostics"
    Write-Status "Adapter" $adapter.Name "Cyan"
    Write-Status "Current Status" $adapter.Status $(if ($adapter.Status -eq 'Up'){'Green'}else{'Yellow'})

    # 3. Actions
    Write-Section "Recovery Actions"
    Invoke-WithStatus "Releasing IP lease"   { ipconfig /release "$($args[0])" 2>&1 } $adapter.Name
    Invoke-WithStatus "Flushing DNS cache"   { Clear-DnsClientCache }
    Invoke-WithStatus "Resetting Winsock"    { netsh winsock reset 2>&1 }
    Invoke-WithStatus "Resetting IP stack"   { netsh int ip reset 2>&1 }
    Invoke-WithStatus "Cycling Hardware"     { 
        Disable-NetAdapter -Name "$($args[0])" -Confirm:$false
        Start-Sleep -Seconds 1
        Enable-NetAdapter -Name "$($args[0])" -Confirm:$false
    } $adapter.Name

    # 4. Reconnection
    Write-Section "Network Handshake"
    Write-Host "  Waiting for connectivity" -NoNewline -ForegroundColor Gray
    $timeout = 45; $elapsed = 0; $connected = $false
    while ($elapsed -lt $timeout) {
        Write-Host -NoNewline "." -ForegroundColor DarkGray
        $elapsed++; Start-Sleep -Seconds 1
        if ((Get-NetAdapter -Name $adapter.Name).Status -eq 'Up') {
            $handshake = try { $t = [System.Net.Sockets.TcpClient]::new(); $ar = $t.BeginConnect("8.8.8.8", 443, $null, $null); $ok = $ar.AsyncWaitHandle.WaitOne(2000); $t.Close(); $ok } catch { $false }
            if ($handshake) { $connected = $true; break }
        }
    }
    Write-Host ""
    if ($connected) { 
        Invoke-WithStatus "Renewing IP lease" { ipconfig /renew "$($args[0])" 2>&1 } $adapter.Name
    } else {
        Write-Status "Connection" "TIMED OUT" "Red"
    }

    # 5. Summary
    $FinalOnline = try { $t = [System.Net.Sockets.TcpClient]::new(); $ar = $t.BeginConnect("1.1.1.1", 443, $null, $null); $ok = $ar.AsyncWaitHandle.WaitOne(2000); $t.Close(); $ok } catch { $false }
    $Duration = "{0:mm\:ss}" -f ((Get-Date) - $SCRIPT_START)

    Write-Section "Summary"
    Write-Status "Final Result" $(if ($FinalOnline){'RESTORED'}else{'CHECK ROUTER'}) $(if ($FinalOnline){'Green'}else{'Red'})
    Write-Status "Time Elapsed" $Duration "Gray"

    # Finish
    if ($FinalOnline) { 
        "$($adapter.Name)|Network Reset Success`nInternet is online." | Set-Content $ResultFile 
    } else {
        "$($adapter.Name)|Network Reset Partial`nConnection not verified." | Set-Content $ResultFile
    }

    Write-Host "`n  Done. Closing..." -ForegroundColor DarkGray
    Start-Sleep -Seconds 3

} catch {
    Write-Host "`n  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
    if ($null -ne $ResultFile) { "ERROR|$($_.Exception.Message)" | Set-Content $ResultFile }
    Start-Sleep -Seconds 20
}
