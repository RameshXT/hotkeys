#Requires -Version 5.1
#Requires -RunAsAdministrator
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$VERSION       = "1.0"
$SCRIPT_START  = Get-Date

function Write-Header {
    $w    = 62
    $line = "=" * $w
    Write-Host ""
    Write-Host $line -ForegroundColor Cyan
    Write-Host ("  NETWORK RESET  v{0}  |  Fast Network Recovery" -f $VERSION).PadRight($w) -ForegroundColor Cyan
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

function Get-WifiAdapter {
    $adapters = @(Get-NetAdapter | Where-Object {
        $_.Status -in @("Up","Disabled") -and
        $_.PhysicalMediaType -in @("Native 802.11","Wireless LAN")
    })

    if ($adapters.Count -eq 0) {
        $adapters = @(Get-NetAdapter | Where-Object {
            $_.Status -in @("Up","Disabled") -and
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
    $hosts = @("8.8.8.8","1.1.1.1","9.9.9.9")
    foreach ($h in $hosts) {
        if (Test-Connection -ComputerName $h -Count 1 -Quiet -ErrorAction SilentlyContinue) {
            return $true
        }
    }
    return $false
}

Write-Header

Write-Section "Diagnostics"

$adapter = Get-WifiAdapter
if ($null -eq $adapter) {
    Write-Host "  [ERROR] No Wi-Fi adapter found." -ForegroundColor Red
    exit 1
}

Write-Info "Adapter        :" $adapter.Name
Write-Info "Status         :" $adapter.Status $(if ($adapter.Status -eq "Up") {"Green"} else {"Yellow"})

$preGateway = Test-Gateway
$preInternet = Test-Internet

Write-Info "Gateway        :" $(if ($preGateway.Gateway) { $preGateway.Gateway } else { "None" }) $(if ($preGateway.Reachable) {"Green"} else {"Red"})
Write-Info "Internet       :" $(if ($preInternet) {"Reachable"} else {"Unreachable"}) $(if ($preInternet) {"Green"} else {"Red"})

Write-Section "Resetting..."

Write-Step "Releasing IP lease          " { ipconfig /release *"$($adapter.Name)"* 2>&1 }
Write-Step "Flushing DNS cache          " { Clear-DnsClientCache }
Write-Step "Resetting Winsock           " { netsh winsock reset 2>&1 }
Write-Step "Resetting TCP/IP stack      " { netsh int ip reset 2>&1 }
Write-Step "Resetting IPv6 stack        " { netsh int ipv6 reset 2>&1 }
Write-Step "Disabling adapter           " { Disable-NetAdapter -Name $adapter.Name -Confirm:$false }

Start-Sleep -Seconds 2

Write-Step "Enabling adapter            " { Enable-NetAdapter -Name $adapter.Name -Confirm:$false }

Write-Host ""
Write-Host "  Waiting for adapter to reconnect..." -ForegroundColor DarkGray

$timeout  = 20
$interval = 1
$elapsed  = 0
$connected = $false

while ($elapsed -lt $timeout) {
    Start-Sleep -Seconds $interval
    $elapsed += $interval
    $current = Get-NetAdapter -Name $adapter.Name -ErrorAction SilentlyContinue
    if ($current -and $current.Status -eq "Up") { $connected = $true; break }
    Write-Host "  ." -NoNewline -ForegroundColor DarkGray
}
Write-Host ""

if (-not $connected) {
    Write-Host "  [WARN] Adapter did not come back up within $timeout seconds." -ForegroundColor Yellow
} else {
    Write-Step "Renewing IP lease           " { ipconfig /renew *"$($adapter.Name)"* 2>&1 }
    Write-Step "Registering DNS             " { Register-DnsClient }
}

Write-Section "Post-reset check"

Start-Sleep -Seconds 2

$postGateway  = Test-Gateway
$postInternet = Test-Internet

Write-Info "Gateway        :" $(if ($postGateway.Gateway) { $postGateway.Gateway } else { "None" }) $(if ($postGateway.Reachable) {"Green"} else {"Red"})
Write-Info "Internet       :" $(if ($postInternet) {"Reachable"} else {"Unreachable"}) $(if ($postInternet) {"Green"} else {"Red"})

$elapsed    = (Get-Date) - $SCRIPT_START
$elapsedStr = "{0:mm\:ss}" -f $elapsed
$divider    = "=" * 62

Write-Host ""
Write-Host $divider -ForegroundColor DarkGray
Write-Host "  SUMMARY" -ForegroundColor Cyan
Write-Host $divider -ForegroundColor DarkGray
Write-Info "Adapter        :" $adapter.Name
Write-Info "Elapsed        :" $elapsedStr
Write-Info "Result         :" $(if ($postInternet) {"Network restored"} else {"Still no internet - try restarting router"}) $(if ($postInternet) {"Green"} else {"Yellow"})
Write-Host $divider -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Done." -ForegroundColor Cyan
Write-Host ""

Add-Type -AssemblyName System.Windows.Forms
$balloon                 = New-Object System.Windows.Forms.NotifyIcon
$balloon.Icon            = [System.Drawing.SystemIcons]::Information
$balloon.BalloonTipTitle = "Network Reset Done"
$balloon.BalloonTipText  = if ($postInternet) { "Internet restored." } else { "Still no internet. Try restarting router." }
$balloon.Visible         = $true
$balloon.ShowBalloonTip(5000)
Start-Sleep -Milliseconds 5500
$balloon.Dispose()
