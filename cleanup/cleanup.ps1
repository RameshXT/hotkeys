Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogFile     = Join-Path (Split-Path -Parent $ScriptDir) "logs\cleanup_log.txt"
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
        throw "ABORT: Environment variable `$$envVar is missing or invalid."
    }
}

$TriggerFile = Join-Path $ScriptDir "cleanup_trigger.txt"
if (Test-Path -LiteralPath $TriggerFile) {
    $TriggerLabel = "hotkey (Manual)"
    Remove-Item -LiteralPath $TriggerFile -Force -ErrorAction SilentlyContinue
} else {
    $parentName = try { (Get-Process -Id (Get-CimInstance Win32_Process -Filter "ProcessId=$PID").ParentProcessId).Name } catch { "Unknown" }
    $TriggerLabel = if ($parentName -match "^(svchost|taskeng|taskhostw)$") { "task (Auto)" } else { "shell (Manual)" }
}

function Get-FastSize {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return [long]0 }
    $sz = [long]0
    try {
        $di = New-Object System.IO.DirectoryInfo($Path)
        $fs = $di.GetFiles("*", [System.IO.SearchOption]::AllDirectories)
        foreach ($f in $fs) { $sz += $f.Length }
    } catch { }
    return $sz
}

function Format-Size {
    param([long]$Bytes)
    if ($Bytes -le 0)   { return "0 B" }
    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    return "{0:N2} KB" -f ($Bytes / 1KB)
}

function Assert-SafePath {
    param([string]$Path)
    $resolved = try { (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path.TrimEnd('\') } catch { $Path.TrimEnd('\') }
    $blocked = @("$env:SystemRoot", "$env:ProgramFiles", "${env:ProgramFiles(x86)}", "$env:SystemRoot\System32")
    foreach ($b in $blocked) {
        if ($resolved -ieq $b) { throw "SAFETY BLOCK: Protected path '$resolved'" }
    }
}

function Clean-Target {
    param([string]$Path, [string]$Label, [int]$DaysOld = 0)
    if (-not (Test-Path -LiteralPath $Path)) { $script:Results.Add("SKIP|$Label|not found"); return }
    try { Assert-SafePath $Path } catch { $script:Results.Add("BLOCK|$Label|$($_.Exception.Message)"); return }
    
    $before = Get-FastSize $Path
    try {
        if ($DaysOld -gt 0) {
            $cutoff = (Get-Date).AddDays(-$DaysOld)
            Get-ChildItem -LiteralPath $Path -Recurse -Force | Where-Object { -not $_.PSIsContainer -and $_.LastWriteTime -lt $cutoff } | Remove-Item -Force
        } else {
            Remove-Item -LiteralPath "$Path\*" -Recurse -Force
        }
    } catch { }

    $after = Get-FastSize $Path
    $freed = [math]::Max([long]0, $before - $after)
    $script:TotalFreed += $freed
    $script:Results.Add("OK|$Label|$(Format-Size $freed)")
}

Write-Host "Modern Cleanup Pipeline Initialized..." -ForegroundColor Cyan

Clean-Target $env:TEMP "User Temp"
Clean-Target "$env:LOCALAPPDATA\Temp" "LocalAppData Temp"
Clean-Target "$env:SystemRoot\Temp" "Windows Temp"

$wuService = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
if ($wuService -and $wuService.Status -eq "Stopped") {
    Clean-Target "$env:SystemRoot\SoftwareDistribution\Download" "Windows Update Cache"
} else {
    $script:Results.Add("SKIP|Windows Update Cache|service running")
}

Clean-Target "$env:SystemRoot\SoftwareDistribution\DeliveryOptimization" "Delivery Opt Cache"
Clean-Target "$env:SystemRoot\Minidump" "Crash Minidumps"
Clean-Target "$env:ProgramData\Microsoft\Windows\WER\ReportArchive" "System WER Reports"
Clean-Target "$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportArchive" "User WER Reports"
Clean-Target "$env:SystemRoot\Logs" "Windows Logs (>7d)" 7
Clean-Target "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache\Cache_Data" "Edge Browser Cache"

if (Test-Path "$env:SystemDrive\Windows.old") {
    Clean-Target "$env:SystemDrive\Windows.old" "Windows.old"
}

$EndTime  = Get-Date
$Duration = ($EndTime - $StartTime).TotalSeconds
$W        = 55
$line1    = "=" * $W
$line2    = "-" * $W
$lineBot  = [string][char]0x2570 + ([string][char]0x2500 * ($W - 2)) + [string][char]0x256F
$tagW     = 8
$labelW   = 26

$rowLines = foreach ($r in $Results) {
    $p = $r -split '\|'
    "  [$($p[0])]".PadRight($tagW) + " $($p[1])".PadRight($labelW) + " $($p[2])"
}

$LogEntry = @"
$line1
  Cleanup  $($StartTime.ToString('dd-MM-yyyy | hh.mm.ss tt'))
  Trigger  $TriggerLabel
  Runner   : $env:USERDOMAIN\$env:USERNAME
$line1
$($rowLines -join "`n")
$line2
  Total    $(Format-Size $TotalFreed)   |   $([math]::Round($Duration, 1))s
$lineBot
  End      $($EndTime.ToString('dd-MM-yyyy | hh.mm.ss tt'))
$lineBot

"@

Add-Content -LiteralPath $LogFile -Value $LogEntry -Encoding UTF8

$ResultFile = Join-Path $ScriptDir "cleanup_result.txt"
"Cleanup Success|Freed up: $(Format-Size $TotalFreed)`nLogs: Ctrl+Shift+Alt+L" | Set-Content -LiteralPath $ResultFile -Encoding UTF8

Write-Host "Cleanup Complete. Total Freed: $(Format-Size $TotalFreed)" -ForegroundColor Green
