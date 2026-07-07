#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$ScriptVersion = "3.0.0"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogFile = Join-Path (Split-Path -Parent $ScriptDir) "logs\update_log.txt"
$MaxLogSizeB = 2MB
$TriggerFile = Join-Path $ScriptDir "update_trigger.txt"
$LastRunFile = Join-Path $ScriptDir "update_lastrun.txt"
$StartTime = Get-Date
$Results = [System.Collections.Generic.List[string]]::new()
$HeaderWidth = 50
$LabelW = 22
$line = "=" * $HeaderWidth
$ExitCode = 0
$WarnCount = 0

$mutex = [System.Threading.Mutex]::new($false, "Global\WindowsUpdaterMutex")
$mutexAcquired = $false
try {
    $mutexAcquired = $mutex.WaitOne(0)
}
catch [System.Threading.AbandonedMutexException] {
    $mutexAcquired = $true
}

if (-not $mutexAcquired) {
    Write-Host "ABORT: Another instance is already running." -ForegroundColor Red
    Start-Sleep -Seconds 4
    exit 1
}

function Write-Row {
    param(
        [Parameter(Mandatory)][string] $Label,
        [Parameter(Mandatory)][string] $Value,
        [string] $Color = "White"
    )
    $dots = "." * [math]::Max(1, ($script:LabelW - $Label.Length))
    Write-Host "  $Label$dots " -NoNewline -ForegroundColor DarkGray
    Write-Host $Value -ForegroundColor $Color
}

function Add-Result {
    param(
        [Parameter(Mandatory)][string] $Tag,
        [Parameter(Mandatory)][string] $Label,
        [Parameter(Mandatory)][string] $Value
    )
    $script:Results.Add("$Tag|$Label|$Value")
    if ($Tag -eq "WARN") { $script:WarnCount++ }
}

function Format-Row {
    param([string]$Tag, [string]$Label, [string]$Value)
    $tagCol = "[$Tag]".PadRight(12)
    $labelCol = $Label.PadRight($script:LabelW)
    "  $tagCol  $labelCol  $Value"
}

function Invoke-WithLoader {
    param(
        [Parameter(Mandatory)][scriptblock] $ScriptBlock,
        [object[]]  $ArgumentList = @(),
        [int]       $ExpectedSeconds = 120,
        [int]       $TimeoutSeconds = 600,
        [string]    $Label = ""
    )

    $barLen = 38
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $clearLine = " " * 80

    $job = $null
    try {
        if (Get-Command Start-ThreadJob -ErrorAction SilentlyContinue) {
            $job = Start-ThreadJob -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList -ErrorAction Stop
        }
    }
    catch { $job = $null }

    if ($null -eq $job) {
        try {
            $job = Start-Job -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList -ErrorAction Stop
        }
        catch {
            Write-Host "  [!] Could not start background job: $($_.Exception.Message)" -ForegroundColor Red
            return $null
        }
    }

    $timedOut = $false
    try {
        while ($job.State -eq 'Running') {
            $secs = $sw.Elapsed.TotalSeconds
            if ($secs -ge $TimeoutSeconds) {
                $timedOut = $true
                Stop-Job  -Job $job -ErrorAction SilentlyContinue
                $null = $job | Wait-Job -Timeout 5 -ErrorAction SilentlyContinue
                break
            }
            $t = [math]::Min($secs / [math]::Max($ExpectedSeconds, 1), 1.0)
            $fill = [int]($barLen * ($t / ($t + 0.15)) * 0.95)
            $pct = [int](($fill / $barLen) * 100)
            $bar = ('#' * $fill) + ('.' * ($barLen - $fill))
            $s = [int]$secs
            Write-Host -NoNewline "`r  ${s}s  [$bar]  $pct%" -ForegroundColor Cyan
            Start-Sleep -Milliseconds 250
        }
    }
    finally {
        $sw.Stop()
    }

    if ($timedOut) {
        $s = [int]$sw.Elapsed.TotalSeconds
        Write-Host -NoNewline "`r  ${s}s  [$('!' * $barLen)]  TIMEOUT" -ForegroundColor Red
        Start-Sleep -Milliseconds 400
        Write-Host "`r$clearLine`r" -NoNewline
        try { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue } catch { }
        return $null
    }

    $s = [int]$sw.Elapsed.TotalSeconds
    Write-Host -NoNewline "`r  ${s}s  [$('#' * $barLen)]  100%" -ForegroundColor Green
    Start-Sleep -Milliseconds 300
    Write-Host "`r$clearLine`r" -NoNewline

    try {
        $result = Receive-Job -Job $job -Wait -ErrorAction SilentlyContinue
        return $result
    }
    catch {
        return $null
    }
    finally {
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-WithRetry {
    param(
        [Parameter(Mandatory)][scriptblock] $ScriptBlock,
        [int]    $MaxAttempts = 3,
        [int]    $DelaySeconds = 5,
        [string] $Label = "operation"
    )
    for ($i = 1; $i -le $MaxAttempts; $i++) {
        try {
            $result = & $ScriptBlock
            return $result
        }
        catch {
            if ($i -lt $MaxAttempts) {
                Write-Host "  [!] $Label failed (attempt $i/$MaxAttempts): $($_.Exception.Message)" -ForegroundColor Yellow
                Start-Sleep -Seconds $DelaySeconds
            }
            else {
                throw
            }
        }
    }
}

function Test-InternetConnection {
    param([int]$TimeoutMs = 4000)
    $targets = @(
        @{ Host = "8.8.8.8"; Port = 443 },
        @{ Host = "1.1.1.1"; Port = 443 },
        @{ Host = "dns.google"; Port = 53 }
    )
    foreach ($t in $targets) {
        $tcp = $null
        try {
            $tcp = [System.Net.Sockets.TcpClient]::new()
            $ar = $tcp.BeginConnect($t.Host, $t.Port, $null, $null)
            if ($ar.AsyncWaitHandle.WaitOne($TimeoutMs)) {
                try { $tcp.EndConnect($ar) } catch { }
                return $true
            }
        }
        catch { }
        finally {
            if ($null -ne $tcp) { try { $tcp.Close() } catch { } }
        }
    }
    return $false
}

try {

    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
    if (-not $isAdmin) {
        Write-Host "ABORT: Must run as Administrator." -ForegroundColor Red
        Start-Sleep -Seconds 5
        throw "ABORT: Not running as Administrator."
    }

    $IsHotkeyTrigger = Test-Path -LiteralPath $TriggerFile
    if ($IsHotkeyTrigger) {
        $TriggerLabel = "Manual (Hotkey)"
        Remove-Item -LiteralPath $TriggerFile -Force -ErrorAction SilentlyContinue
    }
    else {
        $_selfProc = Get-CimInstance Win32_Process -Filter "ProcessId=$PID" -ErrorAction SilentlyContinue
        $parentName = ""
        if ($_selfProc) {
            $parentName = try {
                (Get-Process -Id $_selfProc.ParentProcessId -ErrorAction Stop).Name
            }
            catch { "" }
        }
        $TriggerLabel = switch -Regex ($parentName) {
            "^(powershell|pwsh)$" { "Manual (Shell)"; break }
            "^(svchost|taskeng|taskhostw|msdtc)$" {
                $sid = if ($_selfProc) { $_selfProc.SessionId } else { 0 }
                if ($sid -gt 0) { "Scheduled (Manual)" } else { "Scheduled (Auto)" }
                break
            }
            default { "Scheduled (Auto)" }
        }
    }

    if (-not $IsHotkeyTrigger) {
        $_today = (Get-Date).ToString('yyyy-MM-dd')
        if (Test-Path -LiteralPath $LastRunFile) {
            $_lastRun = (Get-Content -LiteralPath $LastRunFile -ErrorAction SilentlyContinue |
                Select-Object -First 1).Trim()
            if ($_lastRun -eq $_today) {
                Write-Host "SKIP: Already ran today ($_today). Exiting." -ForegroundColor Yellow
                Start-Sleep -Seconds 4
                exit 0
            }
        }

        $_logonTime = try {
            (Get-Process -Name "explorer" -ErrorAction Stop |
            Sort-Object StartTime | Select-Object -First 1).StartTime
        }
        catch { $null }

        if ($null -ne $_logonTime) {
            $_minSinceLogon = ((Get-Date) - $_logonTime).TotalMinutes
            if ($_minSinceLogon -lt 30) {
                Write-Host "SKIP: Less than 30 minutes since logon. Exiting." -ForegroundColor Yellow
                Start-Sleep -Seconds 4
                exit 0
            }
        }
    }

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
        if (-not ('ConsoleWindow' -as [type])) {
            Add-Type -TypeDefinition $src -ErrorAction Stop
        }
        $hwnd = [ConsoleWindow]::GetConsoleWindow()
        if ($hwnd -ne [IntPtr]::Zero) {
            $sw = [ConsoleWindow]::GetSystemMetrics(0)
            $sh = [ConsoleWindow]::GetSystemMetrics(1)
            $ww = [int]($sw * 0.35)
            $wh = [int]($sh * 0.60)
            [void][ConsoleWindow]::MoveWindow($hwnd, ($sw - $ww), 0, $ww, $wh, $true)
        }
    }
    catch { }

    $title = "WINDOWS UPDATER"
    $titleLine = $title.PadLeft([int](($HeaderWidth + $title.Length) / 2))
    Write-Host ""
    Write-Host $line -ForegroundColor DarkGray
    Write-Host $titleLine -ForegroundColor Cyan
    Write-Host $line -ForegroundColor DarkGray
    Write-Row "Start"   $StartTime.ToString('yyyy-MM-dd  HH:mm:ss') "White"
    Write-Row "Trigger" $TriggerLabel                                "White"
    Write-Row "Version" "v$ScriptVersion"                            "White"

    Write-Host ""
    Write-Host "[Init]" -ForegroundColor Yellow

    $psVer = "$($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor).$($PSVersionTable.PSVersion.Build)"
    Write-Row "PowerShell" "v$psVer" "DarkGray"
    Add-Result "INFO" "PowerShell" "v$psVer"

    $osInfo = try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $caption = $os.Caption -replace '\s*(Single Language|Multi Language|Home Single Language)\s*', ' '
        $caption.Trim()
    }
    catch { "Unknown" }
    Write-Row "OS" $osInfo "DarkGray"
    Add-Result "INFO" "OS" $osInfo

    $wingetVerStr = "not found"
    $wingetExe = $null
    $wingetCandidates = @(
        "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe",
        "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*\winget.exe"
    )
    foreach ($candidate in $wingetCandidates) {
        $resolved = Get-Item -Path $candidate -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($resolved) { $wingetExe = $resolved.FullName; break }
    }
    if (-not $wingetExe) {
        $wingetExe = try { (Get-Command winget -ErrorAction Stop).Source } catch { $null }
    }
    if ($wingetExe) {
        $wingetVerStr = try {
            $raw = & $wingetExe --version 2>&1
            ($raw | Out-String).Trim()
        }
        catch { "unknown" }
    }
    Write-Row "Winget" $wingetVerStr "DarkGray"
    Add-Result "INFO" "Winget" $wingetVerStr

    $envOk = $true
    foreach ($envVar in @('TEMP', 'LOCALAPPDATA', 'USERPROFILE')) {
        $val = [System.Environment]::GetEnvironmentVariable($envVar)
        if ([string]::IsNullOrWhiteSpace($val) -or $val.Length -lt 4) { $envOk = $false; break }
    }
    if (-not $envOk) {
        Write-Row "Env Vars" "MISSING" "Red"
        throw "ABORT: Required environment variable missing. Halted for safety."
    }
    Write-Row "Env Vars" "OK" "Green"

    $minFreeGB = 2
    $diskFreeGB = try {
        $drive = Get-PSDrive -Name ($env:SystemDrive.TrimEnd(':')) -ErrorAction Stop
        [math]::Round($drive.Free / 1GB, 2)
    }
    catch { -1 }

    if ($diskFreeGB -lt 0) { Write-Row "Disk Space" "UNKNOWN"                    "Yellow"; Add-Result "WARN" "Disk Space" "could not determine free space" }
    elseif ($diskFreeGB -lt $minFreeGB) { Write-Row "Disk Space" "LOW  (${diskFreeGB} GB)"    "Red"; Add-Result "WARN" "Disk Space" "${diskFreeGB}GB free - below ${minFreeGB}GB minimum" }
    else { Write-Row "Disk Space" "${diskFreeGB} GB free"       "Green"; Add-Result "INFO" "Disk Space" "${diskFreeGB}GB free" }

    $logWritable = try {
        $testFile = Join-Path $ScriptDir ".write_test_$PID"
        [System.IO.File]::WriteAllText($testFile, "test")
        Remove-Item -LiteralPath $testFile -Force -ErrorAction SilentlyContinue
        $true
    }
    catch { $false }

    if (-not $logWritable) {
        Write-Row "Log Path" "READ-ONLY" "Yellow"
        Add-Result "WARN" "Log Path" "directory not writable - log will be skipped"
        $LogFile = $null
    }
    else {
        Write-Row "Log Path" "OK" "Green"
    }

    $internetOk = $false
    for ($attempt = 1; $attempt -le 3 -and -not $internetOk; $attempt++) {
        $internetOk = Test-InternetConnection -TimeoutMs 4000
        if (-not $internetOk -and $attempt -lt 3) {
            Write-Host "  [!] Connectivity check failed (attempt $attempt/3), retrying in 5s..." -ForegroundColor Yellow
            Start-Sleep -Seconds 5
        }
    }

    if (-not $internetOk) {
        Write-Row "Internet" "FAIL" "Red"
        $msg = "ABORT: No internet connection after 3 attempts. Update cancelled."
        if ($LogFile) {
            Add-Content -LiteralPath $LogFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | $msg" `
                -Encoding UTF8 -ErrorAction SilentlyContinue
        }
        Start-Sleep -Seconds 5
        throw $msg
    }
    Write-Row "Internet" "OK" "Green"

    if ($LogFile) {
        $logItem = Get-Item -LiteralPath $LogFile -ErrorAction SilentlyContinue
        if ($logItem -and $logItem.Length -gt $MaxLogSizeB) {
            Clear-Content -LiteralPath $LogFile -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Host ""
    Write-Host "[Phase 1] Winget" -ForegroundColor Yellow
    $Phase1Start = Get-Date

    if ($null -eq $wingetExe) {
        Write-Row "Sources"  "SKIPPED" "DarkGray"
        Write-Row "Packages" "SKIPPED" "DarkGray"
        Write-Row "Time"     "n/a"     "DarkGray"
        Add-Result "SKIP" "Winget"              "not found"
        Add-Result "SKIP" "Winget Source Update" "not available"
    }
    else {
        $sourceResult = Invoke-WithLoader -ScriptBlock {
            param($exe)
            $ErrorActionPreference = "Stop"
            for ($i = 1; $i -le 2; $i++) {
                try { & $exe source update --disable-interactivity 2>&1 | Out-Null; return "done" }
                catch {
                    if ($i -lt 2) { Start-Sleep -Seconds 5 } else { return "failed:$($_.Exception.Message)" }
                }
            }
        } -ArgumentList $wingetExe -ExpectedSeconds 30 -TimeoutSeconds 120

        if ($null -eq $sourceResult) { Write-Row "Sources" "TIMED OUT" "Red"; Add-Result "FAIL" "Winget Sources" "timed out" }
        elseif ($sourceResult -match '^failed:') { Write-Row "Sources" "FAILED"    "Red"; Add-Result "FAIL" "Winget Sources" ($sourceResult -replace '^failed:', '') }
        else { Write-Row "Sources" "REFRESHED" "Green"; Add-Result "OK"   "Winget Sources" "refreshed" }

        $wingetResult = Invoke-WithLoader -ScriptBlock {
            param($exe)
            $ErrorActionPreference = "Continue"
            try {
                $upgrades = & $exe list --upgrade-available --disable-interactivity 2>&1
                $packagesToUpgrade = @()
                
                $headerLine = $upgrades | Where-Object { $_ -match '\bId\b.*\bVersion\b' } | Select-Object -First 1
                if ($headerLine) {
                    $idOffset = $headerLine.IndexOf("Id")
                    $versionOffset = $headerLine.IndexOf("Version")
                    
                    foreach ($line in $upgrades) {
                        if ($line -match '^\s*$' -or 
                            $line -match '^-+$' -or 
                            $line -match '\bId\b.*\bVersion\b' -or
                            $line -match 'upgrades? available' -or
                            $line -match 'package\(s\) have upgrades blocked') {
                            continue
                        }
                        if ($line.Length -gt $idOffset) {
                            $name = $line.Substring(0, $idOffset).Trim()
                            $idEnd = if ($line.Length -gt $versionOffset) { $versionOffset - $idOffset } else { -1 }
                            $id = if ($idEnd -gt 0) { $line.Substring($idOffset, $idEnd).Trim() } else { $line.Substring($idOffset).Trim() }
                            
                            $id = ($id -split '\s+')[0]
                            
                            if ($name -and $id -and $name -notlike "*Photoshop*" -and $id -notlike "*Photoshop*") {
                                $packagesToUpgrade += $id
                            }
                        }
                    }
                }

                $updatedCount = 0
                $failedCount = 0
                foreach ($id in $packagesToUpgrade) {
                    $raw = & $exe upgrade --id $id --silent --accept-source-agreements `
                        --accept-package-agreements --disable-interactivity --include-unknown --uninstall-previous --force 2>&1
                    $out = ($raw | Out-String)
                    if ($out -match '(?i)\bfailed\b') {
                        $failedCount++
                    } else {
                        $updatedCount++
                    }
                }
                return @{ Updated = $updatedCount; Failed = $failedCount; ExitCode = 0 }
            }
            catch {
                return @{ Updated = 0; Failed = 1; Error = $_.Exception.Message }
            }
        } -ArgumentList $wingetExe -ExpectedSeconds 180 -TimeoutSeconds 600

        if ($null -eq $wingetResult) {
            Write-Row "Packages" "TIMED OUT" "Red"
            Add-Result "FAIL" "Winget Packages" "job timed out"
        }
        else {
            $u = [int]($wingetResult.Updated)
            $f = [int]($wingetResult.Failed)
            if ($u -gt 0 -and $f -eq 0) { Write-Row "Packages" "$u updated"               "Green"; Add-Result "OK"         "Winget Packages" "$u updated" }
            elseif ($u -gt 0 -and $f -gt 0) { Write-Row "Packages" "$u updated  /  $f failed" "Yellow"; Add-Result "OK"         "Winget Packages" "$u updated, $f failed" }
            elseif ($u -eq 0 -and $f -gt 0) { Write-Row "Packages" "FAILED  ($f)"             "Red"; Add-Result "FAIL"       "Winget Packages" "$f failed" }
            else { Write-Row "Packages" "UP-TO-DATE"               "Green"; Add-Result "UP-TO-DATE" "Winget Packages" "all current" }
        }

        $p1s = [math]::Round(((Get-Date) - $Phase1Start).TotalSeconds, 1)
        Add-Result "OK" "Winget Duration" "${p1s}s"
        Write-Row "Time" "${p1s}s" "DarkGray"
    }

    Write-Host ""
    Write-Host "[Phase 2] Windows Update" -ForegroundColor Yellow
    $Phase2Start = Get-Date
    $wuReady = $false

    try {
        Invoke-WithRetry -Label "PSWindowsUpdate install" -MaxAttempts 2 -DelaySeconds 10 -ScriptBlock {
            if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate -ErrorAction SilentlyContinue)) {
                Install-Module -Name PSWindowsUpdate -MinimumVersion "2.2.0" -Repository PSGallery `
                    -Force -Scope CurrentUser -ErrorAction Stop
            }
            Import-Module PSWindowsUpdate -Force -ErrorAction Stop
        }
        $wuReady = $true
    }
    catch {
        Write-Row "Status" "MODULE UNAVAILABLE" "Red"
        Add-Result "SKIP" "Windows Update" "module unavailable: $($_.Exception.Message)"
    }

    if ($wuReady) {
        $wuResult = Invoke-WithLoader -ScriptBlock {
            $ErrorActionPreference = "Stop"
            try {
                Import-Module PSWindowsUpdate -Force -ErrorAction Stop

                $available = Get-WindowsUpdate -MicrosoftUpdate -IgnoreReboot -ErrorAction Stop
                if (-not $available -or @($available).Count -eq 0) {
                    return @{ State = "uptodate"; Count = 0; KBList = ""; TitleList = "" }
                }

                $installed = Install-WindowsUpdate -MicrosoftUpdate -IgnoreReboot -AcceptAll -ErrorAction Stop
                $unique = @($installed | Sort-Object KB -Unique)
                $kbList = ($unique | ForEach-Object { $_.KB } | Where-Object { $_ } | Select-Object -Unique) -join ", "
                $titleList = ($unique | ForEach-Object { $_.Title } | Where-Object { $_ } | Select-Object -Unique) -join ", "
                return @{ State = "installed"; Count = $unique.Count; KBList = $kbList; TitleList = $titleList }
            }
            catch {
                return @{ State = "failed"; Count = 0; KBList = $_.Exception.Message; TitleList = "" }
            }
        } -ExpectedSeconds 300 -TimeoutSeconds 1800

        if ($null -eq $wuResult) {
            Write-Row "Status" "TIMED OUT" "Red"
            Add-Result "FAIL" "Windows Update" "job timed out after 30 min"
        }
        else {
            $wuState = if ($wuResult.State) { $wuResult.State } else { "failed" }
            switch ($wuState) {
                "uptodate" { Write-Row "Status" "UP-TO-DATE"                   "Green"; Add-Result "UP-TO-DATE" "Windows Update" "no updates available" }
                "installed" { Write-Row "Status" "$($wuResult.Count) installed" "Green"; Add-Result "OK"         "Windows Update" "$($wuResult.Count) installed | KB: $($wuResult.KBList) | $($wuResult.TitleList)" }
                "failed" { Write-Row "Status" "FAILED"                       "Red"; Add-Result "FAIL"       "Windows Update" $wuResult.KBList }
            }
        }
    }

    $p2s = [math]::Round(((Get-Date) - $Phase2Start).TotalSeconds, 1)
    Add-Result "OK" "Windows Update Duration" "${p2s}s"
    Write-Row "Time" "${p2s}s" "DarkGray"

    Write-Host ""
    Write-Host "[Phase 3] Driver Update" -ForegroundColor Yellow
    $Phase3Start = Get-Date

    if ($wuReady) {
        $driverResult = Invoke-WithLoader -ScriptBlock {
            $ErrorActionPreference = "Stop"
            try {
                Import-Module PSWindowsUpdate -Force -ErrorAction Stop
                $available = Get-WindowsUpdate -UpdateType Driver -IgnoreReboot -ErrorAction Stop
                if (-not $available -or @($available).Count -eq 0) {
                    return @{ State = "uptodate"; Count = 0; List = "" }
                }
                $installed = Install-WindowsUpdate -UpdateType Driver -IgnoreReboot -AcceptAll -ErrorAction Stop
                $count = @($installed).Count
                $list = (@($installed) | ForEach-Object { $_.Title } | Where-Object { $_ }) -join ", "
                return @{ State = "installed"; Count = $count; List = $list }
            }
            catch {
                return @{ State = "failed"; Count = 0; List = $_.Exception.Message }
            }
        } -ExpectedSeconds 120 -TimeoutSeconds 900

        if ($null -eq $driverResult) {
            Write-Row "Status" "TIMED OUT" "Red"
            Add-Result "FAIL" "Driver Update" "job timed out"
        }
        else {
            $driverState = if ($driverResult.State) { $driverResult.State } else { "failed" }
            switch ($driverState) {
                "uptodate" { Write-Row "Status" "UP-TO-DATE"                       "Green"; Add-Result "UP-TO-DATE" "Driver Update" "no driver updates available" }
                "installed" { Write-Row "Status" "$($driverResult.Count) installed" "Green"; Add-Result "OK"         "Driver Update" "$($driverResult.Count) installed: $($driverResult.List)" }
                "failed" { Write-Row "Status" "FAILED"                           "Red"; Add-Result "FAIL"       "Driver Update" $driverResult.List }
            }
        }
    }
    else {
        Write-Row "Status" "SKIPPED" "DarkGray"
        Add-Result "SKIP" "Driver Update" "PSWindowsUpdate not available"
    }

    $p3s = [math]::Round(((Get-Date) - $Phase3Start).TotalSeconds, 1)
    Add-Result "OK" "Driver Duration" "${p3s}s"
    Write-Row "Time" "${p3s}s" "DarkGray"
    Write-Host ""
    Write-Host "[Phase 4] Windows Store" -ForegroundColor Yellow
    $Phase4Start = Get-Date

    $storeResult = Invoke-WithLoader -ScriptBlock {
        $ErrorActionPreference = "SilentlyContinue"
        $triggeredMethods = [System.Collections.Generic.List[string]]::new()
        
        # 1. Stop services to release locks on cache folders
        Stop-Service -Name "InstallService", "wuauserv", "bits" -Force -ErrorAction SilentlyContinue
        
        # 2. Clear Microsoft Store Local Cache
        $storeCachePath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsStore_8wekyb3d8bbwe\LocalCache"
        if (Test-Path -LiteralPath $storeCachePath) {
            Remove-Item -Path "$storeCachePath\*" -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        # 3. Clear Delivery Optimization Cache
        $doCachePath = "$env:SystemRoot\SoftwareDistribution\DeliveryOptimization"
        if (Test-Path -LiteralPath $doCachePath) {
            Remove-Item -Path "$doCachePath\*" -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        # 4. Restart services
        Start-Service -Name "bits", "wuauserv", "InstallService" -ErrorAction SilentlyContinue
        
        # 5. Re-register Microsoft Store to rebuild service/task connections
        Get-AppXPackage -AllUsers -Name Microsoft.WindowsStore | ForEach-Object {
            Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml"
        }
        
        # 6. Trigger MDM Modern App Management scan
        try {
            $ns = "root\cimv2\mdm\dmmap"
            $cls = "MDM_EnterpriseModernAppManagement_AppManagement01"
            $instance = Get-CimInstance -Namespace $ns -ClassName $cls -ErrorAction Stop
            $null = Invoke-CimMethod -InputObject $instance -MethodName "UpdateScanMethod" -ErrorAction Stop
            $triggeredMethods.Add("MDM")
        }
        catch {}
        
        # 7. Trigger wsreset to launch Store client update loop
        try {
            $proc = Start-Process "wsreset.exe" -ArgumentList "-i" -WindowStyle Hidden -PassThru -ErrorAction Stop
            if ($proc) {
                $triggeredMethods.Add("WSRESET")
            }
        }
        catch {}
        
        if ($triggeredMethods.Count -gt 0) {
            return ($triggeredMethods -join "+")
        }
        return "failed"
    } -ExpectedSeconds 60 -TimeoutSeconds 300
 
    if ($null -eq $storeResult) {
        Write-Row "Scan" "TIMED OUT" "Red"
        Add-Result "FAIL" "Windows Store" "job timed out"
    }
    else {
        switch -Wildcard ($storeResult) {
            "failed" { Write-Row "Scan" "FAILED" "Red"; Add-Result "FAIL" "Windows Store" "failed to trigger updates" }
            "failed:*" { $err = $storeResult -replace '^failed:', ''; Write-Row "Scan" "FAILED" "Red"; Add-Result "FAIL" "Windows Store" $err }
            default { Write-Row "Scan" "TRIGGERED ($storeResult)" "Green"; Add-Result "OK" "Windows Store" "scan triggered via $storeResult" }
        }
    }

    $p4s = [math]::Round(((Get-Date) - $Phase4Start).TotalSeconds, 1)
    Add-Result "OK" "Store Duration" "${p4s}s"
    Write-Row "Time" "${p4s}s" "DarkGray"

    $rebootKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
    $rebootPending = Test-Path -LiteralPath $rebootKey
    if ($rebootPending) { Add-Result "NOTICE" "Reboot" "restart required" }

    $EndTime = Get-Date
    $Duration = ($EndTime - $StartTime).TotalSeconds
    $DurationText = "$([math]::Round($Duration, 1))s"

    $failCount = @($Results | Where-Object { $_ -match '^FAIL\|' }).Count

    $overallStatus = if ($failCount -gt 0) {
        "PARTIAL"
    }
    elseif ($WarnCount -gt 0) {
        "SUCCESS  ($WarnCount WARNING$(if ($WarnCount -ne 1) { 'S' }))"
    }
    else {
        "SUCCESS"
    }

    $ExitCode = if ($failCount -gt 0) { 2 } else { 0 }

    if (-not $IsHotkeyTrigger) {
        (Get-Date).ToString('yyyy-MM-dd') | Set-Content -LiteralPath $LastRunFile -Encoding UTF8 -ErrorAction SilentlyContinue
    }

    $logRows = foreach ($r in $Results) {
        $p = $r -split '\|', 3
        Format-Row $p[0] $p[1] $p[2]
    }
    $logRowsText = $logRows -join "`n"

    $verTitle = "WINDOWS UPDATER  v$ScriptVersion"
    $verTitleLine = $verTitle.PadLeft([int](($HeaderWidth + $verTitle.Length) / 2))
    $startStr = $StartTime.ToString('yyyy-MM-dd  HH:mm:ss')
    $endStr = $EndTime.ToString('yyyy-MM-dd  HH:mm:ss')
    $startLabel = "Start".PadRight($LabelW)
    $triggerLabel = "Trigger".PadRight($LabelW)
    $statusLabel = "Status".PadRight($LabelW)
    $totalLabel = "Total".PadRight($LabelW)
    $endLabel = "End".PadRight($LabelW)

    $LogEntry = @"
$line
$verTitleLine
$line
$startLabel  $startStr
$triggerLabel  $TriggerLabel
$line
$logRowsText
$line
$statusLabel  $overallStatus
$totalLabel  $DurationText
$endLabel  $endStr
$line

"@

    if ($LogFile) {
        $logDir = Split-Path -Parent $LogFile
        if (-not (Test-Path -LiteralPath $logDir)) {
            New-Item -ItemType Directory -LiteralPath $logDir -Force | Out-Null
        }
        try {
            Add-Content -LiteralPath $LogFile -Value $LogEntry -Encoding UTF8
        }
        catch {
            Write-Host "  Log FAILED: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    Write-Host ""
    Write-Host $line -ForegroundColor DarkGray
    if ($LogFile) { Write-Row "Log" $LogFile "DarkGray" }
    $statusColor = if ($failCount -gt 0) { "Yellow" } elseif ($WarnCount -gt 0) { "Cyan" } else { "Green" }
    Write-Row "Status" $overallStatus $statusColor
    Write-Row "Total"  $DurationText  "White"
    Write-Row "End"    $endStr        "White"
    if ($rebootPending) {
        Write-Host ""
        Write-Host "  ! Reboot required to complete updates" -ForegroundColor Magenta
    }
    Write-Host $line -ForegroundColor DarkGray
    Write-Host ""

    for ($i = 3; $i -ge 1; $i--) {
        Write-Host -NoNewline "`r  Closing in ${i}s..." -ForegroundColor DarkGray
        Start-Sleep -Seconds 1
    }
    Write-Host "`r  Closing...      " -ForegroundColor DarkGray
    Write-Host ""

    $statusLine = if ($failCount -gt 0) { "Windows Updater - errors found" } else { "Windows Updater success" }
    $resultPath = Join-Path $ScriptDir "update_result.txt"
    "$statusLine|Completed in $DurationText`nLogs: Ctrl+Shift+Alt+L" |
    Set-Content -LiteralPath $resultPath -Encoding UTF8 -ErrorAction SilentlyContinue

}
finally {
    try { if ($mutexAcquired) { $mutex.ReleaseMutex() } } catch { }
    $mutex.Dispose()
}

exit $ExitCode
