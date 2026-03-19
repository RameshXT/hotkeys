Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir    = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogFile      = Join-Path $ScriptDir "update_log.txt"
$MaxLogSizeB  = 2MB
$TriggerFile  = Join-Path $ScriptDir "update_trigger.txt"
$ResultFile   = Join-Path $ScriptDir "update_result.txt"
$StartTime    = Get-Date
$Results      = [System.Collections.Generic.List[string]]::new()
$W            = 50
$line         = "=" * $W

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
    if (-not ([System.Management.Automation.PSTypeName]'ConsoleWindow').Type) {
        Add-Type -TypeDefinition $src -ErrorAction Stop
    }
    $sw = [ConsoleWindow]::GetSystemMetrics(0)
    $sh = [ConsoleWindow]::GetSystemMetrics(1)
    $ww = [int]($sw * 0.35)
    $wh = [int]($sh * 0.60)
    [void][ConsoleWindow]::MoveWindow([ConsoleWindow]::GetConsoleWindow(), ($sw - $ww), 0, $ww, $wh, $true)
} catch { }

if (Test-Path -LiteralPath $TriggerFile) {
    $TriggerLabel = "Manual (Hotkey)"
    Remove-Item -LiteralPath $TriggerFile -Force -ErrorAction SilentlyContinue
} else {
    $parentName = try {
        $ppid = (Get-CimInstance Win32_Process -Filter "ProcessId=$PID" -ErrorAction Stop).ParentProcessId
        (Get-Process -Id $ppid -ErrorAction Stop).Name
    } catch { "" }

    $TriggerLabel = switch -Regex ($parentName) {
        "^(powershell|pwsh)$"                 { "Manual (Shell)" }
        "^(svchost|taskeng|taskhostw|msdtc)$" {
            $sid = try {
                (Get-CimInstance Win32_Process -Filter "ProcessId=$PID" -ErrorAction Stop).SessionId
            } catch { 0 }
            if ($sid -gt 0) { "Scheduled (Manual)" } else { "Scheduled (Auto)" }
        }
        default { "Manual (Shell)" }
    }
}

function Write-Line {
    param([string]$Label, [string]$Value, [string]$Color = "White")
    $totalW = 28
    $dots   = "." * [math]::Max(1, $totalW - $Label.Length)
    Write-Host "  $Label$dots " -NoNewline -ForegroundColor DarkGray
    Write-Host $Value -ForegroundColor $Color
}

function Add-Result {
    param([string]$Tag, [string]$Label, [string]$Value)
    $script:Results.Add("$Tag|$Label|$Value")
}

function Format-LogRow {
    param([string]$Tag, [string]$Label, [string]$Value)
    "  " + "[$Tag]".PadRight(14) + $Label.PadRight(26) + $Value
}

function Format-PopupRow {
    param([string]$Tag, [string]$Label, [string]$Value)
    $tagStr = "[$Tag]"
    $tab    = if ($tagStr.Length -lt 12) { "`t`t" } else { "`t" }
    "  $tagStr$tab$Label`t$Value"
}

function Show-Loader {
    param(
        [scriptblock]$ScriptBlock,
        [object[]]$ArgumentList = @()
    )

    $barLen     = 38
    $elapsed    = [System.Diagnostics.Stopwatch]::StartNew()
    $job        = Start-Job -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
    $smoothFill = 0.0
    $prevCpu    = 0.0
    $clearLine  = " " * 80

    try {
        while ($job.State -eq 'Running') {
            $secs   = [int]$elapsed.Elapsed.TotalSeconds

            $cpuNow = try {
                $procs = Get-Process -Name "powershell","pwsh","winget","wuauclt","TiWorker" -ErrorAction SilentlyContinue
                if ($procs) { ($procs | Measure-Object -Property CPU -Sum).Sum } else { $prevCpu }
            } catch { $prevCpu }

            $delta      = [math]::Max(0, $cpuNow - $prevCpu)
            $prevCpu    = $cpuNow
            $smoothFill = [math]::Min($smoothFill + [math]::Min($delta * 0.8, 3.0), $barLen - 1)
            $minFill    = [math]::Min($secs / 3.0, $barLen - 1)
            $fill       = [int][math]::Max($smoothFill, $minFill)
            $pct        = [int](($fill / $barLen) * 100)
            $bar        = ('#' * $fill) + ('.' * ($barLen - $fill))

            Write-Host -NoNewline "`r  ${secs}s  [$bar]  $pct%" -ForegroundColor Cyan
            Start-Sleep -Milliseconds 250
        }
    } finally {
        $elapsed.Stop()
    }

    $secs = [int]$elapsed.Elapsed.TotalSeconds
    Write-Host -NoNewline "`r  ${secs}s  [$('#' * $barLen)]  100%" -ForegroundColor Green
    Start-Sleep -Milliseconds 300

    Write-Host "`r$clearLine`r" -NoNewline

    $result = Receive-Job -Job $job -Wait -ErrorAction SilentlyContinue
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    return $result
}

Write-Host ""
Write-Host $line -ForegroundColor DarkGray
Write-Host ("WINDOWS UPDATER".PadLeft([int](($W + "WINDOWS UPDATER".Length) / 2))) -ForegroundColor Cyan
Write-Host $line -ForegroundColor DarkGray
Write-Host "Start   : $($StartTime.ToString('yyyy-MM-dd | hh:mm:ss tt'))" -ForegroundColor White
Write-Host "Trigger : $TriggerLabel" -ForegroundColor White

Write-Host ""
Write-Host "[Init]" -ForegroundColor Yellow

Write-Host "  Validating environment" -NoNewline -ForegroundColor DarkGray
Write-Host "........ " -NoNewline -ForegroundColor DarkGray
foreach ($envVar in @('TEMP', 'LOCALAPPDATA', 'USERPROFILE')) {
    $val = [System.Environment]::GetEnvironmentVariable($envVar)
    if ([string]::IsNullOrWhiteSpace($val) -or $val.Length -lt 4) {
        Write-Host "FAIL" -ForegroundColor Red
        throw "ABORT: `$$envVar is missing or invalid. Halted for safety."
    }
}
Write-Host "OK" -ForegroundColor Green

Write-Host "  Checking internet" -NoNewline -ForegroundColor DarkGray
Write-Host "............. " -NoNewline -ForegroundColor DarkGray
$internetOk = try {
    $ping  = [System.Net.NetworkInformation.Ping]::new()
    $reply = $ping.Send("8.8.8.8", 3000)
    $reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success
} catch { $false }

if (-not $internetOk) {
    Write-Host "FAIL" -ForegroundColor Red
    $msg = "ABORT: No internet connection. Update cancelled."
    Add-Content -LiteralPath $LogFile -Value "$(Get-Date -Format 'yyyy-MM-dd | hh:mm:ss tt') | $msg" -Encoding UTF8 -ErrorAction SilentlyContinue
    Set-Content -LiteralPath $ResultFile -Value $msg -Encoding UTF8 -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5
    exit 1
}
Write-Host "OK" -ForegroundColor Green

try {
    if ((Test-Path -LiteralPath $LogFile) -and (Get-Item -LiteralPath $LogFile).Length -gt $MaxLogSizeB) {
        $archive = $LogFile -replace '\.txt$', "_archive_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
        Move-Item -LiteralPath $LogFile -Destination $archive -Force -ErrorAction Stop
    }
} catch { }

Write-Host ""
Write-Host "[Phase 1] Winget" -ForegroundColor Yellow
$Phase1Start = Get-Date

$wingetExe = $null
$wingetCandidates = @(
    "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe",
    "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*\winget.exe"
)
foreach ($candidate in $wingetCandidates) {
    $resolved = Get-Item -Path $candidate -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($resolved) { $wingetExe = $resolved.FullName; break }
}
if (-not $wingetExe) {
    $wingetExe = try { (Get-Command winget -ErrorAction Stop).Source } catch { $null }
}

if ($null -eq $wingetExe) {
    Write-Line "Sources refreshed" "SKIPPED" "DarkGray"
    Write-Line "Packages" "SKIPPED" "DarkGray"
    Add-Result "SKIP" "Winget" "not found"
    Add-Result "SKIP" "Winget Source Update" "not available"
} else {
    $null = Show-Loader {
        param($exe)
        & $exe source update 2>&1 | Out-Null
        return "done"
    } -ArgumentList $wingetExe
    Add-Result "OK" "Winget Source Update" "refreshed"
    Write-Line "Sources refreshed" "DONE" "Green"

    $wingetResult = Show-Loader {
        param($exe)
        $raw          = & $exe upgrade --all --silent --accept-source-agreements --accept-package-agreements 2>&1
        $out          = $raw -join "`n"
        $updatedCount = ([regex]::Matches($out, '(?m)^\s*\S+.*\s+\S+\s+->\s+\S+\s*$')).Count
        $failedCount  = ([regex]::Matches($out, 'failed', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)).Count
        return @{ Updated = $updatedCount; Failed = $failedCount }
    } -ArgumentList $wingetExe

    $u = if ($wingetResult -and $null -ne $wingetResult.Updated) { [int]$wingetResult.Updated } else { 0 }
    $f = if ($wingetResult -and $null -ne $wingetResult.Failed)  { [int]$wingetResult.Failed  } else { 0 }

    if      ($u -gt 0 -and $f -eq 0) { Write-Line "Packages" "$u UPDATED"           "Green";  Add-Result "OK"         "Winget" "$u updated" }
    elseif  ($u -gt 0 -and $f -gt 0) { Write-Line "Packages" "$u UPDATED $f FAILED" "Yellow"; Add-Result "OK"         "Winget" "$u updated, $f failed" }
    elseif  ($u -eq 0 -and $f -gt 0) { Write-Line "Packages" "FAILED ($f)"          "Red";    Add-Result "FAIL"       "Winget" "$f failed" }
    else                              { Write-Line "Packages" "UP-TO-DATE"            "Green";  Add-Result "UP-TO-DATE" "Winget" "all current" }
}

$p1s = [math]::Round(((Get-Date) - $Phase1Start).TotalSeconds, 1)
Add-Result "OK" "Winget Duration" "${p1s}s"
Write-Line "Time" "${p1s}s" "DarkGray"

Write-Host ""
Write-Host "[Phase 2] Windows Update" -ForegroundColor Yellow
$Phase2Start = Get-Date
$wuReady     = $false

try {
    if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate -ErrorAction SilentlyContinue)) {
        Install-Module -Name PSWindowsUpdate -Force -Scope CurrentUser -ErrorAction Stop
    }
    Import-Module PSWindowsUpdate -Force -ErrorAction Stop
    $wuReady = $true
} catch {
    Write-Line "Status" "MODULE UNAVAILABLE" "Red"
    Add-Result "SKIP" "Windows Update" "module unavailable"
}

if ($wuReady) {
    $wuResult = Show-Loader {
        try {
            Import-Module PSWindowsUpdate -Force -ErrorAction Stop
            $available = Get-WindowsUpdate -IgnoreReboot -ErrorAction Stop
            if (-not $available -or $available.Count -eq 0) {
                return @{ State = "uptodate"; Count = 0; KBList = "" }
            }
            $installed = Install-WindowsUpdate -IgnoreReboot -AcceptAll -ErrorAction Stop
            $count     = @($installed).Count
            $kbList    = (@($installed) | ForEach-Object { $_.KB } | Where-Object { $_ }) -join ", "
            return @{ State = "installed"; Count = $count; KBList = $kbList }
        } catch {
            return @{ State = "failed"; Count = 0; KBList = $_.Exception.Message }
        }
    }

    $wuState = if ($wuResult -and $wuResult.State) { $wuResult.State } else { "failed" }
    switch ($wuState) {
        "uptodate"  { Write-Line "Status" "UP-TO-DATE"                     "Green"; Add-Result "UP-TO-DATE" "Windows Update" "no updates available" }
        "installed" { Write-Line "Status" "$($wuResult.Count) INSTALLED"   "Green"; Add-Result "OK"         "Windows Update" "$($wuResult.Count) installed: $($wuResult.KBList)" }
        "failed"    { Write-Line "Status" "FAILED"                         "Red";   Add-Result "FAIL"       "Windows Update" $wuResult.KBList }
    }
}

$p2s = [math]::Round(((Get-Date) - $Phase2Start).TotalSeconds, 1)
Add-Result "OK" "Windows Update Duration" "${p2s}s"
Write-Line "Time" "${p2s}s" "DarkGray"

Write-Host ""
Write-Host "[Phase 3] Windows Store" -ForegroundColor Yellow
$Phase3Start = Get-Date

$storeResult = Show-Loader {
    try {
        $ns       = "root\cimv2\mdm\dmmap"
        $cls      = "MDM_EnterpriseModernAppManagement_AppManagement01"
        $instance = Get-CimInstance -Namespace $ns -ClassName $cls -ErrorAction Stop
        $null     = Invoke-CimMethod -InputObject $instance -MethodName "UpdateScanMethod" -ErrorAction Stop
        return "mdm"
    } catch {
        try {
            $proc = Start-Process "wsreset.exe" -ArgumentList "-i" -WindowStyle Hidden -PassThru -ErrorAction Stop
            if ($proc) { return "wsreset" }
            return "failed"
        } catch {
            return "failed:$($_.Exception.Message)"
        }
    }
}

switch -Wildcard ($storeResult) {
    "mdm"      { Write-Line "Scan" "TRIGGERED (MDM)"     "Green"; Add-Result "OK"   "Windows Store" "scan triggered via MDM" }
    "wsreset"  { Write-Line "Scan" "TRIGGERED (WSRESET)" "Green"; Add-Result "OK"   "Windows Store" "scan triggered via WSReset" }
    "failed:*" { $err = $storeResult -replace '^failed:',''; Write-Line "Scan" "FAILED" "Red"; Add-Result "FAIL" "Windows Store" $err }
    default    { Write-Line "Scan" "FAILED"               "Red";  Add-Result "FAIL" "Windows Store" "unknown error" }
}

$p3s = [math]::Round(((Get-Date) - $Phase3Start).TotalSeconds, 1)
Add-Result "OK" "Store Duration" "${p3s}s"
Write-Line "Time" "${p3s}s" "DarkGray"

$rebootKey     = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
$rebootPending = Test-Path -LiteralPath $rebootKey
if ($rebootPending) {
    Add-Result "NOTICE" "Reboot Pending" "restart required"
}

$EndTime      = Get-Date
$Duration     = ($EndTime - $StartTime).TotalSeconds
$DurationText = "$([math]::Round($Duration, 1))s"

$failCount     = @($Results | Where-Object { $_ -match '^FAIL\|' }).Count
$overallStatus = if ($failCount -gt 0) { "PARTIAL" } else { "SUCCESS" }

$logRows = foreach ($r in $Results) {
    $p = $r -split '\|', 3
    Format-LogRow $p[0] $p[1] $p[2]
}

$LogEntry = @"
$line
$("WINDOWS UPDATER".PadLeft([int](($W + "WINDOWS UPDATER".Length) / 2)))
$line
Start   : $($StartTime.ToString('yyyy-MM-dd | hh:mm:ss tt'))
Trigger : $TriggerLabel
$line
$($logRows -join "`n")
$line
Status  : $overallStatus
Total   : $DurationText
End     : $($EndTime.ToString('yyyy-MM-dd | hh:mm:ss tt'))
$line

"@

try {
    Add-Content -LiteralPath $LogFile -Value $LogEntry -Encoding UTF8
} catch {
    Write-Host "  Log FAILED: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Line "Log" $LogFile "DarkGray"
Write-Host ""
$statusColor = if ($overallStatus -eq "SUCCESS") { "Green" } else { "Yellow" }
Write-Host "Status: $overallStatus" -ForegroundColor $statusColor
Write-Host "Total : $DurationText" -ForegroundColor White
Write-Host "End   : $($EndTime.ToString('yyyy-MM-dd | hh:mm:ss tt'))" -ForegroundColor White
if ($rebootPending) {
    Write-Host ""
    Write-Host "NOTICE: Reboot required to complete updates" -ForegroundColor Magenta
}
Write-Host $line -ForegroundColor DarkGray
Write-Host ""

for ($i = 5; $i -ge 1; $i--) {
    Write-Host -NoNewline "`r  Closing in $i...  " -ForegroundColor DarkGray
    Start-Sleep -Seconds 1
}
Write-Host "`r  Closing...        " -ForegroundColor DarkGray
Write-Host ""

$popupRows = foreach ($r in $Results) {
    $p = $r -split '\|', 3
    Format-PopupRow $p[0] $p[1] $p[2]
}

$MsgBody  = "Update`t$($StartTime.ToString('yyyy-MM-dd | hh:mm tt'))`n"
$MsgBody += "Trigger`t$TriggerLabel`n`n"
$MsgBody += ($popupRows -join "`n")
$MsgBody += "`n`nTotal`t$DurationText"

Set-Content -LiteralPath $ResultFile -Value $MsgBody -Encoding UTF8 -ErrorAction SilentlyContinue

Add-Type -AssemblyName System.Windows.Forms

$content = try {
    if (Test-Path -LiteralPath $ResultFile) {
        $c = Get-Content -LiteralPath $ResultFile -Raw -Encoding UTF8
        Remove-Item -LiteralPath $ResultFile -Force -ErrorAction SilentlyContinue
        $c
    } else { $MsgBody }
} catch { $MsgBody }

try {
    $hwnd = [ConsoleWindow]::GetConsoleWindow()
    Add-Type -Name WinUser -Namespace Win -MemberDefinition '[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);' -ErrorAction SilentlyContinue
    [Win.WinUser]::ShowWindow($hwnd, 0) | Out-Null
} catch { }

[System.Windows.Forms.MessageBox]::Show($content, "Update Done", "OK", [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null

$openLog = [System.Windows.Forms.MessageBox]::Show(
    "Wanna check the log file?",
    "Update Log",
    [System.Windows.Forms.MessageBoxButtons]::YesNo,
    [System.Windows.Forms.MessageBoxIcon]::Question
)
if ($openLog -eq [System.Windows.Forms.DialogResult]::Yes) {
    if (Test-Path -LiteralPath $LogFile) {
        Start-Process notepad.exe -ArgumentList $LogFile
    } else {
        [System.Windows.Forms.MessageBox]::Show("Log file not found:`n$LogFile", "Error", "OK", [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
    }
}

exit 0
