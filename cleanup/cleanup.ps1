Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogFile     = Join-Path $ScriptDir "cleanup_log.txt"
$MaxLogSizeB = 2MB
$StartTime   = Get-Date
$TotalFreed  = [long]0
$Results     = [System.Collections.Generic.List[string]]::new()

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
                Where-Object { -not $_.PSIsContainer } |
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
    $resolved = try { (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path } catch { $Path }
    $blocked = @(
        "$env:SystemRoot",
        "$env:SystemRoot\System32",
        "$env:SystemRoot\SysWOW64",
        "$env:ProgramFiles",
        "${env:ProgramFiles(x86)}",
        "C:\\Users\\rames",
        "C:\", "D:\", "E:\"
    )
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
                Where-Object { -not $_.PSIsContainer -and $_.LastWriteTime -lt $cutoff } |
                ForEach-Object {
                    try { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop } catch {}
                }
            Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.PSIsContainer } |
                Sort-Object FullName -Descending |
                ForEach-Object {
                    try {
                        if ((Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue |
                             Measure-Object).Count -eq 0) {
                            Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                        }
                    } catch {}
                }
        } else {
            Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue |
                ForEach-Object {
                    try { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop } catch {}
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

if ((Test-Path -LiteralPath $LogFile) -and (Get-Item -LiteralPath $LogFile).Length -gt $MaxLogSizeB) {
    $archive = $LogFile -replace '\.txt$', "_archive_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
    Move-Item -LiteralPath $LogFile -Destination $archive -Force -ErrorAction SilentlyContinue
}

Clean-Folder $env:TEMP "User Temp"

Clean-Folder "C:\Windows\Temp" "Windows Temp"

$wuService    = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
$wuWasRunning = $wuService -and $wuService.Status -eq "Running"

if ($wuWasRunning) {
    $Results.Add("SKIP|Windows Update Cache|service running")
} else {
    try {
        Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Clean-Folder "C:\Windows\SoftwareDistribution\Download" "Windows Update Cache"
    } finally {
        Start-Service -Name wuauserv -ErrorAction SilentlyContinue
    }
}

Clean-Folder "C:\Windows\Prefetch" "Prefetch"
Clean-Folder "C:\Windows\Logs" "Windows Logs (>7d)" 7
Clean-Folder "C:\ProgramData\Microsoft\Windows\WER\ReportArchive"    "WER Report Archive"
Clean-Folder "C:\ProgramData\Microsoft\Windows\WER\ReportQueue"      "WER Report Queue"
Clean-Folder "$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportArchive" "WER User Archive"
Clean-Folder "$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportQueue"   "WER User Queue"

Clean-Folder "C:\Windows\Minidump"                                    "Crash Minidumps"
if (Test-Path -LiteralPath "C:\Windows\MEMORY.DMP") {
    try {
        $sz = (Get-Item -LiteralPath "C:\Windows\MEMORY.DMP").Length
        Remove-Item -LiteralPath "C:\Windows\MEMORY.DMP" -Force -ErrorAction Stop
        $script:TotalFreed += $sz
        $Results.Add("OK|Crash Memory Dump|$(Format-Size $sz)")
    } catch {
        $Results.Add("FAIL|Crash Memory Dump|$($_.Exception.Message)")
    }
} else {
    $Results.Add("SKIP|Crash Memory Dump|not found")
}
Clean-Folder "C:\Windows\Installer\`$PatchCache`$"                   "Installer Patch Cache"
Clean-Folder "$env:APPDATA\Microsoft\Windows\Recent"                  "Recent Files"

$thumbPath = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
if (Test-Path -LiteralPath $thumbPath) {
    $thumbFreed = [long]0
    Get-ChildItem -LiteralPath $thumbPath -Filter "thumbcache_*.db" -Force -ErrorAction SilentlyContinue |
        ForEach-Object {
            try {
                $sz = $_.Length
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                $thumbFreed += $sz
            } catch {}
        }
    $script:TotalFreed += $thumbFreed
    $Results.Add("OK|Thumbnail Cache|$(Format-Size $thumbFreed)")
} else {
    $Results.Add("SKIP|Thumbnail Cache|not found")
}

try {
    Clear-DnsClientCache -ErrorAction Stop
    $Results.Add("OK|DNS Cache|flushed")
} catch {
    $Results.Add("FAIL|DNS Cache|$($_.Exception.Message)")
}

try {
    if (-not ([System.Management.Automation.PSTypeName]'MemUtil').Type) {
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
            NtSetSystemInformation(0x60, buf, 4);
        } finally {
            Marshal.FreeHGlobal(buf);
        }
    }
}
'@
        Add-Type -TypeDefinition $MemCode -ErrorAction Stop
    }
    [MemUtil]::ClearStandbyList()
    $Results.Add("OK|Memory Standby List|cleared")
} catch {
    $Results.Add("FAIL|Memory Standby List|$($_.Exception.Message)")
}

$EndTime  = Get-Date
$Duration = ($EndTime - $StartTime).TotalSeconds

$W        = 55
$line1    = "=" * $W
$line2    = "-" * $W
$lineBot  = [char]0x2570 + ([string][char]0x2500 * ($W - 1)) + [char]0x256F

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
$line1
$($rowLines -join "`n")
$line2
$totalRow
$lineBot
$endRow
$lineBot

"@

Add-Content -LiteralPath $LogFile -Value $LogEntry -Encoding UTF8

$ResultFile = Join-Path $ScriptDir "cleanup_result.txt"

$OkLines   = ($Results | Where-Object { $_ -match '^OK\|' }            | ForEach-Object { $p = $_ -split '\|',3; Format-Row $p[0] $p[1] $p[2] }) -join "`n"
$SkipLines = ($Results | Where-Object { $_ -match '^SKIP\|' }          | ForEach-Object { $p = $_ -split '\|',3; Format-Row $p[0] $p[1] $p[2] }) -join "`n"
$FailLines = ($Results | Where-Object { $_ -match '^FAIL\||^BLOCK\|' } | ForEach-Object { $p = $_ -split '\|',3; Format-Row $p[0] $p[1] $p[2] }) -join "`n"

$MsgBody  = "$line1`n$headerRow`n$triggerRow`n$line1`n"
if ($OkLines)   { $MsgBody += "$OkLines`n" }
if ($SkipLines) { $MsgBody += "$SkipLines`n" }
if ($FailLines) { $MsgBody += "$FailLines`n" }
$MsgBody += "$line2`n$totalRow`n$lineBot`n$endRow`n$lineBot"

Set-Content -LiteralPath $ResultFile -Value $MsgBody -Encoding UTF8

Start-Sleep -Seconds 3
if (Test-Path -LiteralPath $ResultFile) {
    $content = Get-Content -LiteralPath $ResultFile -Raw -Encoding UTF8
    Remove-Item -LiteralPath $ResultFile -Force -ErrorAction SilentlyContinue
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show($content, "Cleanup Done", "OK", [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
}
