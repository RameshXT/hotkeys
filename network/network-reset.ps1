#Requires -Version 5.1

# --- Functions ---
function Write-Header {
    param($version)
    $w    = 62
    $line = "=" * $w
    Write-Host ""
    Write-Host $line -ForegroundColor Cyan
    Write-Host ("  NETWORK RESET  v{0}  |  Fast Network Recovery" -f $version).PadRight($w) -ForegroundColor Cyan
    Write-Host $line -ForegroundColor Cyan
    Write-Host ""
}

function Write-Section ([string]$Text) {
    Write-Host ""
    Write-Host "  >> $Text" -ForegroundColor DarkCyan
    Write-Host ""
}

function Write-Info ([string]$Label, [string]$Value, [string]$Color = "White") {
    Write-Host ("  {0,-22}" -f $Label) -NoNewline -ForegroundColor Gray
    Write-Host $Value -ForegroundColor $Color
}

function Write-Step ([string]$Label, [scriptblock]$Action) {
    Write-Host ("  {0,-38}" -f $Label) -NoNewline -ForegroundColor Gray
    try {
        & $Action | Out-Null
        Write-Host " OK" -ForegroundColor Green
    } catch {
        Write-Host " FAILED  $_" -ForegroundColor Red
    }
}

function Ensure-ParentDirectory {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    $parentPath = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parentPath) -and -not (Test-Path -LiteralPath $parentPath)) {
        New-Item -ItemType Directory -LiteralPath $parentPath -Force | Out-Null
    }
}

function Ensure-WindowsFormsLoaded {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
}

function Ensure-SystemDrawingLoaded {
    Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
}

function Get-WifiAdapter {
    $adapters = @(Get-NetAdapter | Where-Object {
        $_.Status -in @("Up","Disabled","Disconnected") -and
        $_.PhysicalMediaType -in @("Native 802.11","Wireless LAN")
    })
    if ($adapters.Count -eq 0) {
        $adapters = @(Get-NetAdapter | Where-Object {
            $_.Status -in @("Up","Disabled","Disconnected") -and
            $_.Name -match "Wi.?Fi|Wireless|WLAN|802\.11"
        })
    }
    if ($adapters.Count -eq 0) { return $null }
    return ($adapters | Sort-Object -Property { $_.Status -eq "Up" } -Descending | Select-Object -First 1)
}

function Test-Gateway {
    $gateways = @(Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
        Where-Object { $_.NextHop -ne "0.0.0.0" } |
        Select-Object -ExpandProperty NextHop)
    foreach ($gw in $gateways) {
        if (Test-Connection -ComputerName $gw -Count 1 -Quiet -ErrorAction SilentlyContinue) {
            return @{ Reachable = $true; Gateway = $gw }
        }
    }
    return @{ Reachable = $false; Gateway = ($gateways | Select-Object -First 1) }
}

function Test-Internet {
    $hosts = @("8.8.8.8", "1.1.1.1", "9.9.9.9")
    foreach ($h in $hosts) {
        $tcp = $null
        $asyncResult = $null
        try {
            $tcp = [System.Net.Sockets.TcpClient]::new()
            $asyncResult = $tcp.BeginConnect($h, 443, $null, $null)
            $ok = $asyncResult.AsyncWaitHandle.WaitOne(3000)
            if ($ok) { try { $tcp.EndConnect($asyncResult) } catch {} }
            if ($ok) { return $true }
        } catch {}
        finally {
            if ($null -ne $asyncResult) { try { $asyncResult.AsyncWaitHandle.Close() } catch {} }
            if ($null -ne $tcp) { try { $tcp.Close(); $tcp.Dispose() } catch {} }
        }
    }
    return $false
}

# --- Execution ---
try {
    # Define vars inside try/catch for safety
    $VERSION      = "1.1"
    $SCRIPT_START = Get-Date
    $ScriptDir    = $PSScriptRoot
    if (-not $ScriptDir) { $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
    $LogFile      = Join-Path (Split-Path -Parent $ScriptDir) "logs\netreset_log.txt"
    $ResultFile   = Join-Path $ScriptDir "netreset_result.txt"
    $MaxLogSizeB  = 2MB
    
    Write-Header $VERSION
    Write-Host "  Initializing..." -ForegroundColor Gray

    # Window Positioning
    try {
        $src = @'
        using System;
        using System.Runtime.InteropServices;
        public class ConsoleWindow {
            [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
            [DllImport("user32.dll")]   public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int h2, bool r);
            [DllImport("user32.dll")]   public static extern bool ShowWindow(IntPtr h, int n);
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
    } catch { }

    # Privilege Check
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Administrator privileges required. Please check Task Scheduler settings."
    }

    # Preparation
    Ensure-ParentDirectory -Path $LogFile
    if ((Test-Path -LiteralPath $LogFile) -and (Get-Item -LiteralPath $LogFile).Length -gt $MaxLogSizeB) {
        Clear-Content -LiteralPath $LogFile -Force -ErrorAction SilentlyContinue
    }

    Write-Section "Diagnostics"
    $adapter = Get-WifiAdapter
    if ($null -eq $adapter) { throw "No Wi-Fi adapter found." }

    Write-Info "Adapter        :" $adapter.Name
    Write-Info "Status         :" $adapter.Status $(if ($adapter.Status -eq "Up") {"Green"} else {"Yellow"})

    $preGateway = Test-Gateway
    $preInternet = Test-Internet

    Write-Info "Gateway        :" $(if ($preGateway.Gateway) { $preGateway.Gateway } else { "None" }) $(if ($preGateway.Reachable) {"Green"} else {"Red"})
    Write-Info "Internet       :" $(if ($preInternet) {"Reachable"} else {"Unreachable"}) $(if ($preInternet) {"Green"} else {"Red"})

    Write-Section "Resetting..."
    Write-Step "Releasing IP lease          " { ipconfig /release "$($adapter.Name)" 2>&1 }
    Write-Step "Flushing DNS cache          " { Clear-DnsClientCache }
    Write-Step "Resetting Winsock           " { netsh winsock reset 2>&1 }
    Write-Step "Resetting TCP/IP stack      " { netsh int ip reset 2>&1 }
    Write-Step "Resetting IPv6 stack        " { netsh int ipv6 reset 2>&1 }
    Write-Step "Disabling adapter           " { Disable-NetAdapter -Name $adapter.Name -Confirm:$false }

    Start-Sleep -Seconds 2
    Write-Step "Enabling adapter            " { Enable-NetAdapter -Name $adapter.Name -Confirm:$false }

    Write-Host ""
    Write-Host "  Waiting for adapter to reconnect..." -ForegroundColor DarkGray
    $timeout = 60; $interval = 1; $elapsed = 0; $connected = $false
    while ($elapsed -lt $timeout) {
        Start-Sleep -Seconds $interval
        $elapsed += $interval
        $current = Get-NetAdapter -Name $adapter.Name -ErrorAction SilentlyContinue
        if ($current -and $current.Status -eq "Up") { $connected = $true; break }
        Write-Host "  ." -NoNewline -ForegroundColor DarkGray
    }
    Write-Host ""

    if (-not $connected) {
        Write-Host "  [WARN] Reconnection timed out." -ForegroundColor Yellow
    } else {
        Write-Step "Renewing IP lease           " { ipconfig /renew "$($adapter.Name)" 2>&1 }
        Write-Step "Registering DNS             " { Register-DnsClient }
    }

    Write-Section "Post-reset check"
    Start-Sleep -Seconds 2
    $postGateway = Test-Gateway
    $postInternet = Test-Internet

    Write-Info "Gateway        :" $(if ($postGateway.Gateway) { $postGateway.Gateway } else { "None" }) $(if ($postGateway.Reachable) {"Green"} else {"Red"})
    Write-Info "Internet       :" $(if ($postInternet) {"Reachable"} else {"Unreachable"}) $(if ($postInternet) {"Green"} else {"Red"})

    $elapsed = (Get-Date) - $SCRIPT_START
    $elapsedStr = "{0:mm\:ss}" -f $elapsed
    $divider = "=" * 62

    Write-Host ""
    Write-Host $divider -ForegroundColor DarkGray
    Write-Host "  SUMMARY" -ForegroundColor Cyan
    Write-Host $divider -ForegroundColor DarkGray
    Write-Info "Adapter        :" $adapter.Name
    Write-Info "Elapsed        :" $elapsedStr
    Write-Info "Result         :" $(if ($postInternet) {"Network restored"} else {"Try restarting router"}) $(if ($postInternet) {"Green"} else {"Yellow"})
    Write-Host $divider -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Done." -ForegroundColor Cyan
    for ($i = 5; $i -ge 1; $i--) { Write-Host -NoNewline "`r  Closing in ${i}s..." -ForegroundColor DarkGray; Start-Sleep -Seconds 1 }
    Write-Host ""

    # Logging & Notification
    try {
        $logEntry = @"
$divider
  NETWORK RESET  v$VERSION  |  $($SCRIPT_START.ToString('dd-MM-yyyy | hh.mm.ss tt'))
$divider
  Adapter : $($adapter.Name)
  Result  : $(if ($postInternet) { "Success" } else { "Failed" })
  Elapsed : $elapsedStr
$divider

"@
        Add-Content -LiteralPath $LogFile -Value $logEntry -Encoding UTF8
        
        $resultTitle = if ($postInternet) { "Network Reset Success" } else { "Network Reset Done" }
        $resultBody  = if ($postInternet) { "Internet restored." } else { "Still no internet." }
        "$resultTitle|$resultBody" | Set-Content -LiteralPath $ResultFile -Encoding UTF8
        
        Ensure-WindowsFormsLoaded
        Ensure-SystemDrawingLoaded
        $balloon = [System.Windows.Forms.NotifyIcon]::new()
        $balloon.Icon = [System.Drawing.SystemIcons]::Information
        $balloon.BalloonTipTitle = "Network Reset"
        $balloon.BalloonTipText = $resultBody
        $balloon.Visible = $true
        $balloon.ShowBalloonTip(5000)
        Start-Sleep -Milliseconds 5500
        $balloon.Dispose()
    } catch {}

} catch {
    Write-Host ""
    Write-Host "  FATAL ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  Script halted. Waiting 30s..." -ForegroundColor Gray
    if ($null -ne $ResultFile) {
        "Network Reset Error|$($_.Exception.Message)" | Set-Content -LiteralPath $ResultFile -Encoding UTF8 -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 30
}
