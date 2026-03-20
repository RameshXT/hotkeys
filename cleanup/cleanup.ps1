Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogFile     = Join-Path (Split-Path -Parent $ScriptDir) "logs\cleanup_log.txt"
$MaxLogSizeB = 2MB
$StartTime   = Get-Date
$TotalFreed  = [long]0
$Results     = [System.Collections.Generic.List[string]]::new()

$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "ABORT: Script must be run as Administrator."
}

foreach ($envVar in @('TEMP', 'LOCALAPPDATA', 'USERPROFILE')) {
    $val = [System.Environment]::GetEnvironmentVariable($envVar)
    if ([string]::IsNullOrWhiteSpace($val) -or $val.Length -lt 4) {
        throw "ABORT: Environment variable `$$envVar is missing or invalid ('$val'). Script stopped for safety."
    }
}

$AuditInfo = "  Runner  : $env:USERDOMAIN\$env:USERNAME  |  Host: $env:COMPUTERNAME  |  Script: $PSCommandPath"

$TriggerFile = Join-Path $ScriptDir "cleanup_trigger.txt"

if (Test-Path -LiteralPath $TriggerFile) {
    $TriggerLabel = "hotkey (Manual)"
    Remove-Item -LiteralPath $TriggerFile -Force -ErrorAction SilentlyContinue
} else {
    $parentName = try {
        (Get-Process -Id (Get-CimInstance Win32_Process -Filter "ProcessId=$PID" -ErrorAction Stop).ParentProcessId -ErrorAction Stop).Name
    } catch { "" }

    if ($parentName -match "^(powershell|pwsh)$") {
        $TriggerLabel = "shell (Manual)"
    } elseif ($parentName -match "^(svchost|taskeng|taskhostw|msdtc)$") {
        $sessionId = try {
            (Get-CimInstance Win32_Process -Filter "ProcessId=$PID" -ErrorAction Stop).SessionId
        } catch { 0 }
        $TriggerLabel = if ($sessionId -gt 0) { "task (Manual)" } else { "task (Auto)" }
    } else {
        $TriggerLabel = "shell (Manual)"
    }
}

function Get-FolderSize {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return [long]0 }
    try {
        $sum = (Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue |
                Where-Object { $null -ne $_ -and -not $_.PSIsContainer } |
                Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        return [long]$(if ($null -eq $sum) { 0 } else { $sum })
    } catch { return [long]0 }
}

function Format-Size {
    param([long]$Bytes)
    if ($Bytes -le 0)        { return "0 B" }
    if ($Bytes -ge 1GB)      { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB)      { return "{0:N2} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB)      { return "{0:N2} KB" -f ($Bytes / 1KB) }
    return "$Bytes B"
}

function Assert-SafePath {
    param([string]$Path)
    $resolved = try { (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path.TrimEnd('\') } catch { $Path.TrimEnd('\') }
    $usersRoot = Join-Path $env:SystemDrive "Users"
    $fixedDriveRoots = [System.IO.DriveInfo]::GetDrives() |
        Where-Object { $_.DriveType -eq 'Fixed' } |
        ForEach-Object { $_.RootDirectory.FullName.TrimEnd('\') }
    $blocked = (@(
        "$env:SystemRoot",
        "$env:SystemRoot\System32",
        "$env:SystemRoot\SysWOW64",
        "$env:ProgramFiles",
        "${env:ProgramFiles(x86)}",
        $usersRoot,
        $env:SystemDrive
    ) + $fixedDriveRoots) | ForEach-Object { $_.TrimEnd('\') }
    foreach ($b in $blocked) {
        if ($resolved -ieq $b) {
            throw "SAFETY BLOCK: Refusing to clean protected path '$resolved'"
        }
    }
}

function Clean-Folder {
    param(
        [string]$Path,
        [string]$Label,
        [int]$DaysOld = 0
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $script:Results.Add("SKIP|$Label|empty path")
        return
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        $script:Results.Add("SKIP|$Label|not found")
        return
    }

    try { Assert-SafePath $Path } catch {
        $script:Results.Add("BLOCK|$Label|$($_.Exception.Message)")
        return
    }

    $before = Get-FolderSize $Path

    try {
        if ($DaysOld -gt 0) {
            $cutoff = (Get-Date).AddDays(-$DaysOld)
            Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue |
                Where-Object { $null -ne $_ -and -not $_.PSIsContainer -and $_.LastWriteTime -lt $cutoff } |
                ForEach-Object {
                    $itemPath = $_.FullName
                    try { Remove-Item -LiteralPath $itemPath -Force -ErrorAction Stop } catch {
                        $script:Results.Add("WARN|$Label|delete failed: $itemPath - $($_.Exception.Message)")
                    }
                }
            Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue |
                Where-Object { $null -ne $_ -and $_.PSIsContainer } |
                Sort-Object FullName -Descending |
                ForEach-Object {
                    $itemPath = $_.FullName
                    try {
                        if ((Get-ChildItem -LiteralPath $itemPath -Force -ErrorAction SilentlyContinue |
                             Measure-Object).Count -eq 0) {
                            Remove-Item -LiteralPath $itemPath -Force -ErrorAction Stop
                        }
                    } catch {
                        $script:Results.Add("WARN|$Label|delete failed: $itemPath - $($_.Exception.Message)")
                    }
                }
        } else {
            Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue |
                Where-Object { $null -ne $_ } |
                ForEach-Object {
                    $itemPath = $_.FullName
                    try { Remove-Item -LiteralPath $itemPath -Recurse -Force -ErrorAction Stop } catch {
                        $script:Results.Add("WARN|$Label|delete failed: $itemPath - $($_.Exception.Message)")
                    }
                }
        }
    } catch {
        $script:Results.Add("FAIL|$Label|$($_.Exception.Message)")
        return
    }

    $after  = Get-FolderSize $Path
    $freed  = [math]::Max([long]0, $before - $after)
    $script:TotalFreed += $freed
    $script:Results.Add("OK|$Label|$(Format-Size $freed)")
}

$logDir = Split-Path -Parent $LogFile
if (-not (Test-Path -LiteralPath $logDir)) {
    New-Item -ItemType Directory -LiteralPath $logDir -Force | Out-Null
}

if ((Test-Path -LiteralPath $LogFile) -and (Get-Item -LiteralPath $LogFile).Length -gt $MaxLogSizeB) {
    Clear-Content -LiteralPath $LogFile -Force -ErrorAction SilentlyContinue
}

Write-Host "[TRACE] START: User Temp"
Clean-Folder $env:TEMP "User Temp"

Write-Host "[TRACE] START: LocalAppData Temp"
Clean-Folder "$env:LOCALAPPDATA\Temp" "LocalAppData Temp"

Write-Host "[TRACE] START: Windows Temp"
Clean-Folder "C:\Windows\Temp" "Windows Temp"

Write-Host "[TRACE] START: Windows Update Cache block"
$wuService    = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
$wuWasRunning = $wuService -and $wuService.Status -eq "Running"

if ($wuWasRunning) {
    $script:Results.Add("SKIP|Windows Update Cache|service running")
} else {
    try {
        if ($wuService -and $wuService.Status -ne "Stopped") {
            Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
            $stopTimeout = 10
            $stopElapsed = 0
            do {
                Start-Sleep -Seconds 1
                $stopElapsed++
                $wuService.Refresh()
            } until ($wuService.Status -eq 'Stopped' -or $stopElapsed -ge $stopTimeout)
            if ($wuService.Status -ne 'Stopped') {
                throw "wuauserv did not stop within $stopTimeout seconds - aborting cache clean to prevent corruption."
            }
        }
        Clean-Folder "C:\Windows\SoftwareDistribution\Download" "Windows Update Cache"
    } finally {
        if ($wuService) {
            Start-Service -Name wuauserv -ErrorAction SilentlyContinue
        }
    }
}

Write-Host "[TRACE] START: Delivery Optimization Cache"
Clean-Folder "C:\Windows\SoftwareDistribution\DeliveryOptimization" "Delivery Optimization Cache"

Write-Host "[TRACE] START: Prefetch"
Clean-Folder "C:\Windows\Prefetch" "Prefetch"

Write-Host "[TRACE] START: Windows Logs"
Clean-Folder "C:\Windows\Logs" "Windows Logs (>7d)" 7

Write-Host "[TRACE] START: WER blocks"
Clean-Folder "C:\ProgramData\Microsoft\Windows\WER\ReportArchive"    "WER Report Archive"
Clean-Folder "C:\ProgramData\Microsoft\Windows\WER\ReportQueue"      "WER Report Queue"
Clean-Folder "$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportArchive" "WER User Archive"
Clean-Folder "$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportQueue"   "WER User Queue"

Write-Host "[TRACE] START: Crash dumps"
Clean-Folder "C:\Windows\Minidump" "Crash Minidumps"
if (Test-Path -LiteralPath "C:\Windows\MEMORY.DMP") {
    try {
        $sz = (Get-Item -LiteralPath "C:\Windows\MEMORY.DMP").Length
        Remove-Item -LiteralPath "C:\Windows\MEMORY.DMP" -Force -ErrorAction Stop
        $script:TotalFreed += $sz
        $script:Results.Add("OK|Crash Memory Dump|$(Format-Size $sz)")
    } catch {
        $script:Results.Add("FAIL|Crash Memory Dump|$($_.Exception.Message)")
    }
} else {
    $script:Results.Add("SKIP|Crash Memory Dump|not found")
}

Write-Host "[TRACE] START: Installer Patch Cache"
Clean-Folder "C:\Windows\Installer\`$PatchCache`$" "Installer Patch Cache"

Write-Host "[TRACE] START: Recent Files"
Clean-Folder "$env:APPDATA\Microsoft\Windows\Recent" "Recent Files"

Write-Host "[TRACE] START: Edge Browser Cache"
Clean-Folder "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache\Cache_Data" "Edge Browser Cache"

Write-Host "[TRACE] START: Windows.old"
if (Test-Path -LiteralPath "C:\Windows.old") {
    try {
        $woldBefore = Get-FolderSize "C:\Windows.old"
        Get-ChildItem -LiteralPath "C:\Windows.old" -Force -ErrorAction SilentlyContinue |
            Where-Object { $null -ne $_ } |
            ForEach-Object {
                $itemPath = $_.FullName
                try { Remove-Item -LiteralPath $itemPath -Recurse -Force -ErrorAction Stop } catch {
                    $script:Results.Add("WARN|Windows.old|delete failed: $itemPath - $($_.Exception.Message)")
                }
            }
        $woldAfter = Get-FolderSize "C:\Windows.old"
        $woldFreed = [math]::Max([long]0, $woldBefore - $woldAfter)
        $script:TotalFreed += $woldFreed
        try { Remove-Item -LiteralPath "C:\Windows.old" -Recurse -Force -ErrorAction SilentlyContinue } catch {}
        $script:Results.Add("OK|Windows.old|$(Format-Size $woldFreed)")
    } catch {
        $script:Results.Add("FAIL|Windows.old|$($_.Exception.Message)")
    }
} else {
    $script:Results.Add("SKIP|Windows.old|not found")
}

Write-Host "[TRACE] START: Event Logs"
$evtLogs    = Get-WinEvent -ListLog "*" -ErrorAction SilentlyContinue
$cutoffEvt  = (Get-Date).AddDays(-7)
$evtCleared = 0
$evtFailed  = 0
if ($evtLogs) {
    foreach ($log in $evtLogs) {
        if ($log.RecordCount -gt 0 -and $log.LastWriteTime -lt $cutoffEvt) {
            try {
                [System.Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession.ClearLog($log.LogName)
                $evtCleared++
            } catch {
                $evtFailed++
            }
        }
    }
    $script:Results.Add("OK|Event Logs (>7d)|cleared $evtCleared log(s)$(if ($evtFailed -gt 0) { ", $evtFailed failed" })")
} else {
    $script:Results.Add("SKIP|Event Logs (>7d)|no logs found")
}

Write-Host "[TRACE] START: Thumbnail Cache"
$thumbPath = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
if (Test-Path -LiteralPath $thumbPath) {
    $thumbFreed = [long]0
    Get-ChildItem -LiteralPath $thumbPath -Filter "thumbcache_*.db" -Force -ErrorAction SilentlyContinue |
        Where-Object { $null -ne $_ } |
        ForEach-Object {
            $itemPath = $_.FullName
            $itemSize = $_.Length
            try {
                Remove-Item -LiteralPath $itemPath -Force -ErrorAction Stop
                $thumbFreed += $itemSize
            } catch {}
        }
    $script:TotalFreed += $thumbFreed
    $script:Results.Add("OK|Thumbnail Cache|$(Format-Size $thumbFreed)")
} else {
    $script:Results.Add("SKIP|Thumbnail Cache|not found")
}

Write-Host "[TRACE] START: DNS Cache"
try {
    Clear-DnsClientCache -ErrorAction Stop
    $script:Results.Add("OK|DNS Cache|flushed")
} catch {
    $script:Results.Add("FAIL|DNS Cache|$($_.Exception.Message)")
}

Write-Host "[TRACE] START: Memory Standby List"
try {
    if (-not ('MemUtil' -as [type])) {
        $MemCode = @'
using System;
using System.Runtime.InteropServices;
public class MemUtil {
    [DllImport("ntdll.dll")]
    public static extern int NtSetSystemInformation(int InfoClass, IntPtr Info, int Length);
    public static void ClearStandbyList() {
        IntPtr buf = Marshal.AllocHGlobal(4);
        try {
            Marshal.WriteInt32(buf, 4);
            int status = NtSetSystemInformation(0x50, buf, 4);
            if (status != 0) {
                throw new Exception(string.Format("NtSetSystemInformation failed with NTSTATUS 0x{0:X8}", status));
            }
        } finally {
            Marshal.FreeHGlobal(buf);
        }
    }
}
'@
        Add-Type -TypeDefinition $MemCode -ErrorAction Stop
    }
    [MemUtil]::ClearStandbyList()
    $script:Results.Add("OK|Memory Standby List|cleared")
} catch {
    $script:Results.Add("WARN|Memory Standby List|$($_.Exception.Message)")
}

$EndTime  = Get-Date
$Duration = ($EndTime - $StartTime).TotalSeconds

$W        = 55
$line1    = "=" * $W
$line2    = "-" * $W
$lineBot  = [string][char]0x2570 + ([string][char]0x2500 * ($W - 2)) + [string][char]0x256F

$tagW     = 8
$labelW   = 26
$valueW   = 16

function Format-Row {
    param([string]$Tag, [string]$Label, [string]$Value)
    $tagStr   = "[$Tag]".PadRight($tagW)
    $labelStr = $Label.PadRight($labelW)
    "  $tagStr $labelStr $Value"
}

$rowLines = foreach ($r in $Results) {
    $parts = $r -split '\|', 3
    $tag   = $parts[0]; $lbl = $parts[1]; $val = $parts[2]
    Format-Row $tag $lbl $val
}

$FreedText    = Format-Size $TotalFreed
$DurationText = "$([math]::Round($Duration, 1))s"
$totalRow     = "  Total    $FreedText   |   $DurationText"
$endRow       = "  End      $($EndTime.ToString('dd-MM-yyyy | hh.mm.ss tt'))"
$headerRow    = "  Cleanup  $($StartTime.ToString('dd-MM-yyyy | hh.mm.ss tt'))"
$triggerRow   = "  Trigger  $TriggerLabel"

$LogEntry = @"
$line1
$headerRow
$triggerRow
$AuditInfo
$line1
$($rowLines -join "`n")
$line2
$totalRow
$lineBot
$endRow
$lineBot

"@

Add-Content -LiteralPath $LogFile -Value $LogEntry -Encoding UTF8

$hasFail    = @($Results | Where-Object { $_ -match '^FAIL\||^BLOCK\|' }).Count -gt 0
$statusLine = if ($hasFail) { "Windows Cleanup - errors found" } else { "Windows Cleanup success" }
$ResultFile = Join-Path $ScriptDir "cleanup_result.txt"

"$statusLine|Freed up: $FreedText`nLogs: Ctrl+Shift+Alt+L" | Set-Content -LiteralPath $ResultFile -Encoding UTF8

Write-Host "[TRACE] Script completed successfully"
