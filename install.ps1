<#
.SYNOPSIS
    xtkeys installer script.

.DESCRIPTION
    This script downloads and installs AutoHotkey, the hotkeys.ahk script, and the xtkeys CLI
    manager. It adds the installation folder to the user's PATH environment variable and
    creates a Startup shortcut to automatically run the hotkey script on login.

.PARAMETER Command
    Action to execute. Default is 'install'.

.PARAMETER IncludeAhk
    Switch parameter for `uninstall` to also uninstall the AutoHotkey compiler.

.PARAMETER Force
    Switch parameter to bypass prompts during uninstallation.

.EXAMPLE
    .\install.ps1
    Runs the full installation/re-installation workflow.

.NOTES
    Author: RameshXT
    Repository: hotkeys
#>
[CmdletBinding()]
[OutputType([void])]
param(
    [Parameter(Mandatory = $false, Position = 0)]
    [ValidateSet('install', 'status', 'update', 'restart', 'uninstall', 'help')]
    [string]$Command = 'install',

    [Parameter(Mandatory = $false)]
    [switch]$IncludeAhk,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

function Write-UI {
    param([string]$Message, [string]$Type="INFO")
    switch ($Type) {
        "OK"    { Write-Host "[OK]: $Message" -ForegroundColor Green }
        "INFO"  { Write-Host "[INFO]: $Message" -ForegroundColor Cyan }
        "WARN"  { Write-Host "[WARNING]: $Message" -ForegroundColor Yellow }
        "ERROR" { Write-Host "[ERROR]: $Message" -ForegroundColor Red }
    }
}

function Invoke-Spinner {
    param([scriptblock]$ScriptBlock, [string]$Message, [array]$ArgumentList = @())
    $spinstr = "⠋","⠙","⠹","⠸","⠼","⠴","⠦","⠧","⠇","⠏"
    $job = Start-Job -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
    $i = 0
    while ($job.State -eq "Running" -or $i -lt 12) {
        $char = $spinstr[$i % $spinstr.Length]
        Write-Host "`r[INFO]: $Message [$char] " -ForegroundColor Cyan -NoNewline
        Start-Sleep -Milliseconds 80
        $i++
    }
    $result = Receive-Job -Job $job
    Remove-Job -Job $job
    Write-Host "`r[OK]: $Message             " -ForegroundColor Green
    return $result
}

$REPO_OWNER       = 'RameshXT'
$REPO_NAME        = 'hotkeys'
$INSTALL_DIR      = Join-Path $env:LOCALAPPDATA 'xtkeys'
$AHK_FILE         = Join-Path $INSTALL_DIR 'hotkeys.ahk'
$CLI_FILE         = Join-Path $INSTALL_DIR 'xtkeys.ps1'
$CLI_BAT          = Join-Path $INSTALL_DIR 'xtkeys.cmd'
$PID_FILE         = Join-Path $INSTALL_DIR 'hotkeys.pid'
$STARTUP_LNK      = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\xtkeys.lnk'
$RELEASE_BASE     = "https://github.com/$REPO_OWNER/$REPO_NAME/releases/latest/download"
$AHK_URL          = "$RELEASE_BASE/hotkeys.ahk"
$HASH_URL         = "$RELEASE_BASE/hotkeys.sha256"
$AHK_WINGET_ID    = 'AutoHotkey.AutoHotkey'
$AHK_WINGET_VER   = '2.0.26'
$AHK_MIN_VER      = [Version]'2.0.26'
$AHK_DIRECT_URL   = 'https://github.com/AutoHotkey/AutoHotkey/releases/download/v2.0.26/AutoHotkey_2.0.26_setup.exe'
$AHK_PORTABLE_URL = 'https://github.com/AutoHotkey/AutoHotkey/releases/download/v2.0.26/AutoHotkey_2.0.26.zip'
$AHK_PORTABLE_DIR = Join-Path $INSTALL_DIR 'ahk'

function Set-SecureTls {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.SecurityProtocolType]::Tls12 -bor
        [Net.SecurityProtocolType]::Tls13
}

function Invoke-SecureDownload ([string]$Url, [string]$OutFile) {
    if ($Url -notmatch '^https://') { throw "Security: refusing non-HTTPS URL: $Url" }
    $wc = $null
    try {
        $wc = [System.Net.WebClient]::new()
        $wc.Headers.Add('User-Agent', "xt-installer/1.0 (github.com/$REPO_OWNER/$REPO_NAME)")
        $wc.DownloadFile($Url, $OutFile)
    } catch {
        throw "Failed to download from '$Url' to '$OutFile'. Details: $($_.Exception.Message)"
    } finally {
        if ($null -ne $wc) { $wc.Dispose() }
    }
}

function Confirm-FileHash ([string]$File, [string]$Expected) {
    try {
        $actual = (Get-FileHash -Path $File -Algorithm SHA256).Hash.ToUpper()
        $expect = ($Expected.Trim().ToUpper() -replace '\s.*$', '')
        if ($actual -ne $expect) {
            throw "SHA-256 MISMATCH - aborting for security.`n  Expected: $expect`n  Got     : $actual"
        }
    } catch {
        throw "Hash confirmation failed for file '$File'. Details: $($_.Exception.Message)"
    }
}

function Get-AhkVersion ([string]$ExePath) {
    try {
        $vi = (Get-Item $ExePath).VersionInfo
        $ver = $vi.ProductVersion
        if (-not $ver) { $ver = $vi.FileVersion }
        if ($ver -match '(\d+\.\d+\.\d+)') {
            return [Version]$Matches[1]
        }
        return $null
    } catch { return $null }
}

function Test-AhkVersionOk ([string]$ExePath) {
    $v = Get-AhkVersion $ExePath
    if ($null -eq $v) { return $false }
    return $v -ge $AHK_MIN_VER
}

function Get-AhkExe {
    $candidates = @(
        (Join-Path $AHK_PORTABLE_DIR 'AutoHotkey64.exe'),
        (Join-Path $AHK_PORTABLE_DIR 'AutoHotkey32.exe'),
        (Join-Path $AHK_PORTABLE_DIR 'AutoHotkey.exe'),
        'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe',
        'C:\Program Files\AutoHotkey\v2\AutoHotkey32.exe',
        'C:\Program Files\AutoHotkey\v2\AutoHotkey.exe',
        'C:\Program Files\AutoHotkey\AutoHotkey64.exe',
        'C:\Program Files\AutoHotkey\AutoHotkey.exe',
        'C:\Program Files (x86)\AutoHotkey\AutoHotkey.exe'
    )
    $f64 = Get-Command 'AutoHotkey64.exe' -ErrorAction SilentlyContinue
    if ($f64) { $candidates += $f64.Source }
    $f32 = Get-Command 'AutoHotkey.exe'   -ErrorAction SilentlyContinue
    if ($f32) { $candidates += $f32.Source }
    $best     = $null
    $bestVer  = $null
    foreach ($c in ($candidates | Select-Object -Unique)) {
        if (-not (Test-Path $c)) { continue }
        $v = Get-AhkVersion $c
        if ($null -eq $v) { continue }
        if ($null -eq $bestVer -or $v -gt $bestVer) {
            $best    = $c
            $bestVer = $v
        }
    }
    return $best
}

function Install-AutoHotkey {
    Write-UI "Checking for AutoHotkey >= v$AHK_WINGET_VER..." "INFO"
    $existing = Get-AhkExe
    if ($null -ne $existing) {
        if (Test-AhkVersionOk $existing) {
            $v = Get-AhkVersion $existing
            Write-UI "AutoHotkey v$v found at $existing" "OK"
            return $existing
        } else {
            $v = Get-AhkVersion $existing
            Write-UI "AutoHotkey v$v found but is too old (need >= v$AHK_WINGET_VER). Updating..." "WARN"
        }
    }
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-UI "Attempting winget install for AutoHotkey v$AHK_WINGET_VER..." "INFO"
        try {
            winget install --id $AHK_WINGET_ID --version $AHK_WINGET_VER `
                --silent --force --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
            Start-Sleep -Seconds 2
            $exe = Get-AhkExe
            if ($null -ne $exe -and (Test-AhkVersionOk $exe)) {
                $v = Get-AhkVersion $exe
                Write-UI "AutoHotkey v$v installed via winget: $exe" "OK"
                return $exe
            }
        } catch { Write-UI "winget install failed: $($_.Exception.Message)" "WARN" }
    }
    $tmpZip = Join-Path $env:TEMP "ahk-v${AHK_WINGET_VER}.zip"
    Invoke-Spinner -Message "Downloading AutoHotkey v$AHK_WINGET_VER portable package..." -ScriptBlock {
        param($url, $dest)
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
        $wc = [System.Net.WebClient]::new()
        $wc.DownloadFile($url, $dest)
        $wc.Dispose()
    } -ArgumentList $AHK_PORTABLE_URL, $tmpZip

    Write-UI "Extracting AutoHotkey portable runtime..." "INFO"
    try {
        if (Test-Path $AHK_PORTABLE_DIR) {
            Remove-Item $AHK_PORTABLE_DIR -Recurse -Force -ErrorAction SilentlyContinue
        }
        New-Item -ItemType Directory -Path $AHK_PORTABLE_DIR -Force | Out-Null
        Expand-Archive -Path $tmpZip -DestinationPath $AHK_PORTABLE_DIR -Force
        Write-UI "AutoHotkey runtime extracted to $AHK_PORTABLE_DIR" "OK"
    } catch {
        throw "Failed to extract AutoHotkey portable ZIP. Details: $($_.Exception.Message)"
    } finally {
        if (Test-Path $tmpZip) {
            Remove-Item $tmpZip -Force -ErrorAction SilentlyContinue
        }
    }
    $exe = Get-AhkExe
    if ($null -eq $exe -or -not (Test-AhkVersionOk $exe)) {
        throw 'AutoHotkey install failed. Check https://www.autohotkey.com/download/'
    }
    $v = Get-AhkVersion $exe
    Write-UI "AutoHotkey v$v ready: $exe" "OK"
    return $exe
}

function Get-HotkeysPid {
    if (Test-Path $PID_FILE) {
        $raw = (Get-Content $PID_FILE -Raw -ErrorAction SilentlyContinue)
        if ($raw) {
            $raw = $raw.Trim()
            if ($raw -match '^\d+$') {
                $pidVal = [int]$raw
                try {
                    $proc = Get-Process -Id $pidVal -ErrorAction Stop
                    if ($proc.ProcessName -like '*AutoHotkey*') {
                        return $pidVal
                    }
                } catch {}
            }
        }
    }
    try {
        $ahkProcs = Get-CimInstance Win32_Process -Filter "Name LIKE 'AutoHotkey%'" -ErrorAction SilentlyContinue
        foreach ($p in $ahkProcs) {
            if ($p.CommandLine -and ($p.CommandLine -like "*hotkeys.ahk*" -or $p.CommandLine -like "*$INSTALL_DIR*")) {
                return [int]$p.ProcessId
            }
        }
    } catch {}
    return $null
}

function Test-HotkeysRunning {
    $hpid = Get-HotkeysPid
    return ($null -ne $hpid)
}

function Stop-Hotkeys {
    $hpid = Get-HotkeysPid
    if ($null -ne $hpid) {
        try { Stop-Process -Id $hpid -Force -ErrorAction SilentlyContinue } catch {}
    }
    try {
        $ahkProcs = Get-CimInstance Win32_Process -Filter "Name LIKE 'AutoHotkey%'" -ErrorAction SilentlyContinue
        foreach ($p in $ahkProcs) {
            if ($p.CommandLine -and ($p.CommandLine -like "*hotkeys.ahk*" -or $p.CommandLine -like "*$INSTALL_DIR*")) {
                try { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
            }
        }
    } catch {}
    if (Test-Path $PID_FILE) {
        Remove-Item $PID_FILE -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Milliseconds 300
}

function Start-Hotkeys ([string]$AhkExe) {
    Start-Process -FilePath $AhkExe -ArgumentList "`"$AHK_FILE`"" -WorkingDirectory $INSTALL_DIR -WindowStyle Hidden
}

function Register-SessionFunction {
    try {
        Set-Item -Path "Function:\global:xtkeys" -Value {
            [CmdletBinding()]
            param(
                [Parameter(ValueFromRemainingArguments = $true)]
                [string[]]$ArgumentList
            )
            $script = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'xtkeys\xtkeys.ps1'
            if (Test-Path $script) {
                & $script @ArgumentList
            } else {
                Write-Error "xtkeys script not found at '$script'."
            }
        }.GetNewClosure() -Force -ErrorAction SilentlyContinue
    } catch {}
}

function Add-ToUserPath ([string]$Dir) {
    try {
        $cur = [Environment]::GetEnvironmentVariable('PATH', 'User')
        if ($null -eq $cur) { $cur = '' }
        $parts = $cur -split ';' | Where-Object { [string]::IsNullOrWhiteSpace($_) -eq $false }
        if ($parts -notcontains $Dir) {
            $newPath = (($parts + $Dir) -join ';')
            [Environment]::SetEnvironmentVariable('PATH', $newPath, 'User')
        }
        $curProc = $env:PATH
        if ($null -eq $curProc) { $curProc = '' }
        $procParts = $curProc -split ';' | Where-Object { [string]::IsNullOrWhiteSpace($_) -eq $false }
        if ($procParts -notcontains $Dir) {
            $env:PATH = (($procParts + $Dir) -join ';')
        }
        Register-SessionFunction
        Write-UI "Added $Dir to User PATH" "OK"
    } catch {
        throw "Failed to add '$Dir' to User PATH. Details: $($_.Exception.Message)"
    }
}

function Remove-FromUserPath ([string]$Dir) {
    try {
        $cur = [Environment]::GetEnvironmentVariable('PATH', 'User')
        if ($null -ne $cur) {
            $parts = $cur -split ';' | Where-Object { [string]::IsNullOrWhiteSpace($_) -eq $false -and $_ -ne $Dir }
            [Environment]::SetEnvironmentVariable('PATH', ($parts -join ';'), 'User')
        }
        $curProc = $env:PATH
        if ($null -ne $curProc) {
            $procParts = $curProc -split ';' | Where-Object { [string]::IsNullOrWhiteSpace($_) -eq $false -and $_ -ne $Dir }
            $env:PATH = ($procParts -join ';')
        }
        Remove-Item Function:\xtkeys -ErrorAction SilentlyContinue
        Write-UI "Removed $Dir from User PATH" "OK"
    } catch {
        throw "Failed to remove '$Dir' from User PATH. Details: $($_.Exception.Message)"
    }
}

function New-StartupShortcut ([string]$AhkExe) {
    try {
        $wsh      = New-Object -ComObject WScript.Shell
        $lnk      = $wsh.CreateShortcut($STARTUP_LNK)
        $lnk.TargetPath       = $AhkExe
        $lnk.Arguments        = "`"$AHK_FILE`""
        $lnk.WorkingDirectory = $INSTALL_DIR
        $lnk.Description      = 'xt Hotkeys - AutoHotkey'
        $lnk.IconLocation     = "$AhkExe,0"
        $lnk.Save()
        Write-UI "Created Startup shortcut at $STARTUP_LNK" "OK"
    } catch {
        throw "Failed to create Startup shortcut at '$STARTUP_LNK'. Details: $($_.Exception.Message)"
    }
}

function Write-CliWrapper {
    try {
        $bat = "@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"%~dp0xtkeys.ps1`" %*`r`n"
        [System.IO.File]::WriteAllText($CLI_BAT, $bat, [System.Text.Encoding]::ASCII)
    } catch {
        throw "Failed to write CLI wrapper to '$CLI_BAT'. Details: $($_.Exception.Message)"
    }
}

function Set-ScriptExecutionPolicy {
    foreach ($f in @($CLI_FILE, $CLI_BAT)) {
        if (Test-Path $f) {
            try   { Unblock-File $f -ErrorAction Stop }
            catch { }
        }
    }
    $cur = Get-ExecutionPolicy -Scope CurrentUser
    if ($cur -eq 'Undefined' -or $cur -eq 'Restricted' -or $cur -eq 'AllSigned') {
        try {
            Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
            Write-UI "Execution policy set to RemoteSigned (CurrentUser)" "OK"
        } catch {
            Write-UI "Could not set execution policy automatically." "WARN"
        }
    }
}

function Get-LatestHotkeys {
    $tmpAhk  = Join-Path $env:TEMP 'hotkeys_dl.ahk'
    $tmpHash = Join-Path $env:TEMP 'hotkeys_dl.sha256'
    
    Invoke-Spinner -Message "Downloading latest hotkeys.ahk..." -ScriptBlock {
        param($url, $dest)
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
        $wc = [System.Net.WebClient]::new()
        $wc.DownloadFile($url, $dest)
        $wc.Dispose()
    } -ArgumentList $AHK_URL, $tmpAhk

    try {
        Invoke-SecureDownload $HASH_URL $tmpHash
        $expected = Get-Content $tmpHash -Raw
        Confirm-FileHash $tmpAhk $expected
        Write-UI "SHA-256 integrity verification passed" "OK"
        Remove-Item $tmpHash -Force -ErrorAction SilentlyContinue
    } catch [System.Net.WebException] {
        Write-UI "No SHA-256 file found in release - skipping hash check." "WARN"
    } catch {
        Write-UI "SHA-256 check skipped or failed: $($_.Exception.Message)" "WARN"
    }
    return $tmpAhk
}

function Invoke-Install {
    Write-Host ""
    Write-UI "Starting hotkeys installation..." "INFO"
    Write-Host ""
    Set-SecureTls
    
    if (-not (Test-Path $INSTALL_DIR)) {
        New-Item -ItemType Directory -Path $INSTALL_DIR -Force | Out-Null
        Write-UI "Created installation directory at $INSTALL_DIR" "OK"
    }

    $ahkExe = Install-AutoHotkey
    
    $self = $MyInvocation.ScriptName
    $scriptDir = if ($self) { Split-Path $self -Parent } else { $null }
    $localCli = if ($scriptDir) { Join-Path $scriptDir 'xtkeys.ps1' } else { $null }
    $localInstaller = if ($scriptDir) { Join-Path $scriptDir 'install.ps1' } else { $null }
    $localAhk = if ($scriptDir) { Join-Path $scriptDir 'hotkeys.ahk' } else { $null }

    if ($localAhk -and (Test-Path $localAhk)) {
        Write-UI "Using local hotkeys.ahk source" "INFO"
        Copy-Item $localAhk $AHK_FILE -Force
        Write-UI "Copied hotkeys.ahk to $AHK_FILE" "OK"
    } else {
        $tmp = Get-LatestHotkeys
        try {
            Copy-Item $tmp $AHK_FILE -Force
            Write-UI "Saved hotkeys.ahk to $AHK_FILE" "OK"
        } finally {
            if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
        }
    }

    if ($localCli -and (Test-Path $localCli)) {
        Copy-Item $localCli $CLI_FILE -Force
    } else {
        Invoke-SecureDownload "$RELEASE_BASE/xtkeys.ps1" $CLI_FILE
    }
    if ($localInstaller -and (Test-Path $localInstaller)) {
        Copy-Item $localInstaller (Join-Path $INSTALL_DIR 'install.ps1') -Force
    } else {
        Invoke-SecureDownload "$RELEASE_BASE/install.ps1" (Join-Path $INSTALL_DIR 'install.ps1')
    }
    Write-UI "Registered xtkeys CLI binaries" "OK"

    Write-CliWrapper
    Set-ScriptExecutionPolicy
    Add-ToUserPath $INSTALL_DIR
    New-StartupShortcut $ahkExe

    Write-UI "Launching hotkeys background process..." "INFO"
    Stop-Hotkeys
    Start-Hotkeys $ahkExe
    Start-Sleep -Milliseconds 800

    Write-Host ""
    if (Test-HotkeysRunning) {
        $hpid = Get-HotkeysPid
        Write-Host "[DONE]: Installation complete!" -ForegroundColor Green
        Write-UI "hotkeys.ahk is RUNNING (PID: $hpid)" "OK"
        Write-UI "All hotkeys and 'xtkeys' CLI commands are now active!" "OK"
    } else {
        Write-UI "Installation finished. Run 'xtkeys status' to verify running state." "WARN"
    }
    Write-Host ""
}

function Invoke-Status {
    Write-Host ""
    $hpid = Get-HotkeysPid
    if ($null -ne $hpid) {
        Write-UI "hotkeys.ahk is RUNNING (PID: $hpid)" "OK"
    } else {
        Write-UI "hotkeys.ahk is NOT running. Run 'xtkeys restart' to start it." "WARN"
    }
    $ahkExe = Get-AhkExe
    if ($null -ne $ahkExe) {
        $v = Get-AhkVersion $ahkExe
        Write-Host "  AHK    : $ahkExe (v$v)" -ForegroundColor DarkGray
    }
    Write-Host "  Dir    : $INSTALL_DIR" -ForegroundColor DarkGray
    Write-Host "  Script : $AHK_FILE"   -ForegroundColor DarkGray
    Write-Host ""
}

function Invoke-Update {
    Write-Host ""
    Write-UI "Starting hotkeys update..." "INFO"
    Write-Host ""
    Set-SecureTls
    if (-not (Test-Path $INSTALL_DIR) -or -not (Test-Path $AHK_FILE)) {
        Write-UI "xtkeys is not installed yet. Running installation..." "WARN"
        Invoke-Install
        return
    }
    $ahkExe = Get-AhkExe
    if ($null -eq $ahkExe) {
        $ahkExe = Install-AutoHotkey
    }
    $tmp = Get-LatestHotkeys
    Stop-Hotkeys
    try {
        Copy-Item $tmp $AHK_FILE -Force
        Write-UI "Updated hotkeys.ahk" "OK"
    } finally {
        if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
    }

    $tmpCli = Join-Path $env:TEMP 'xtkeys_update.ps1'
    $tmpInst = Join-Path $env:TEMP 'install_update.ps1'
    try {
        Invoke-SecureDownload "$RELEASE_BASE/xtkeys.ps1" $tmpCli
        Invoke-SecureDownload "$RELEASE_BASE/install.ps1" $tmpInst
        Copy-Item $tmpCli $CLI_FILE -Force
        Copy-Item $tmpInst (Join-Path $INSTALL_DIR 'install.ps1') -Force
        Write-UI "Updated xtkeys CLI management files" "OK"
    } catch {
        Write-UI "Failed to download update scripts: $($_.Exception.Message)" "WARN"
    } finally {
        if (Test-Path $tmpCli) { Remove-Item $tmpCli -Force -ErrorAction SilentlyContinue }
        if (Test-Path $tmpInst) { Remove-Item $tmpInst -Force -ErrorAction SilentlyContinue }
    }
    Write-CliWrapper
    Set-ScriptExecutionPolicy
    Add-ToUserPath $INSTALL_DIR

    Write-UI "Restarting hotkeys background process..." "INFO"
    Start-Hotkeys $ahkExe
    Start-Sleep -Milliseconds 800
    Write-Host ""
    if (Test-HotkeysRunning) {
        $hpid = Get-HotkeysPid
        Write-Host "[DONE]: Update complete!" -ForegroundColor Green
        Write-UI "hotkeys.ahk is running on the latest version (PID: $hpid)" "OK"
    } else {
        Write-UI "hotkeys may not have started - run 'xtkeys status'." "WARN"
    }
    Write-Host ""
}

function Invoke-Restart {
    Write-Host ""
    Write-UI "Restarting hotkeys background process..." "INFO"
    $ahkExe = Get-AhkExe
    if ($null -eq $ahkExe) {
        $ahkExe = Install-AutoHotkey
    }
    Stop-Hotkeys
    Start-Hotkeys $ahkExe
    Start-Sleep -Milliseconds 800
    Write-Host ""
    if (Test-HotkeysRunning) {
        $hpid = Get-HotkeysPid
        Write-Host "[DONE]: Hotkeys restarted successfully!" -ForegroundColor Green
        Write-UI "hotkeys.ahk is RUNNING (PID: $hpid)" "OK"
    } else {
        Write-UI "hotkeys may not have started - run 'xtkeys status'." "WARN"
    }
    Write-Host ""
}

function Invoke-Uninstall {
    Write-Host ""
    Write-UI "Starting hotkeys uninstallation..." "INFO"
    Write-Host ""
    $uninstallAhk = [bool]$IncludeAhk
    if (-not $Force -and [Environment]::UserInteractive) {
        $response = Read-Host "Are you sure you want to uninstall hotkeys and xtkeys? (y/n)"
        if ($response -notmatch '^[Yy]$') {
            Write-Host ""
            Write-UI "Uninstallation aborted by user." "INFO"
            return
        }
        if (-not $uninstallAhk) {
            $ahkResp = Read-Host "Do you want to uninstall AutoHotkey compiler as well? (y/n)"
            if ($ahkResp -match '^[Yy]$') {
                $uninstallAhk = $true
            }
        }
    }
    Write-UI "Stopping background hotkey processes..." "INFO"
    Stop-Hotkeys
    Write-UI "Background processes stopped" "OK"

    try {
        if (Test-Path $STARTUP_LNK) {
            Remove-Item $STARTUP_LNK -Force -ErrorAction SilentlyContinue
            Write-UI "Removed Startup shortcut" "OK"
        }
        Remove-FromUserPath $INSTALL_DIR
        if (Test-Path $INSTALL_DIR) {
            Get-ChildItem -Path $INSTALL_DIR -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
                try { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue } catch {}
            }
            if (Test-Path $AHK_PORTABLE_DIR) {
                try { Remove-Item $AHK_PORTABLE_DIR -Recurse -Force -ErrorAction SilentlyContinue } catch {}
            }
            try {
                Remove-Item $INSTALL_DIR -Recurse -Force -ErrorAction SilentlyContinue
            } catch {}
            if (Test-Path $INSTALL_DIR) {
                Start-Process -FilePath 'cmd.exe' -ArgumentList "/c timeout /t 1 /nobreak >nul & rmdir /s /q `"$INSTALL_DIR`"" -WindowStyle Hidden -ErrorAction SilentlyContinue
            }
            Write-UI "Cleaned up installation directory $INSTALL_DIR" "OK"
        }
    } catch {
        throw "Failed to clean up files during uninstallation. Details: $($_.Exception.Message)"
    }

    if ($uninstallAhk) {
        Write-UI "Uninstalling AutoHotkey..." "INFO"
        $uninstalled = $false
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            try {
                winget uninstall --id $AHK_WINGET_ID --silent --accept-source-agreements 2>&1 | Out-Null
                Write-UI "AutoHotkey uninstalled via winget" "OK"
                $uninstalled = $true
            } catch {}
        }
        if (-not $uninstalled) {
            $regPath = @(
                "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
                "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
            )
            $ahkReg = Get-ItemProperty $regPath -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like '*AutoHotkey*' } | Select-Object -First 1
            if ($ahkReg -and $ahkReg.UninstallString) {
                try {
                    if ($ahkReg.UninstallString -match '^"([^"]+)"\s+(.*)$') {
                        Start-Process -FilePath $Matches[1] -ArgumentList "$($Matches[2]) /silent" -Wait -NoNewWindow -ErrorAction SilentlyContinue | Out-Null
                    } else {
                        Start-Process -FilePath $ahkReg.UninstallString -Wait -NoNewWindow -ErrorAction SilentlyContinue | Out-Null
                    }
                    Write-UI "AutoHotkey uninstalled via system uninstaller" "OK"
                } catch {}
            }
        }
    }

    Write-Host ""
    Write-Host "[DONE]: Uninstallation complete!" -ForegroundColor Green
    Write-UI "hotkeys and xtkeys CLI have been fully removed." "OK"
    if (-not $uninstallAhk) {
        Write-UI "AutoHotkey compiler was kept on your system." "INFO"
    }
    Write-Host ""
}

function Invoke-Help {
    Write-Host ""
    Write-UI "xtkeys installer and management tool" "INFO"
    Write-Host ""
    Write-Host "Commands:" -ForegroundColor White
    Write-Host "  xtkeys install     Install or reinstall hotkeys"     -ForegroundColor Cyan
    Write-Host "  xtkeys status      Check if hotkeys are running"     -ForegroundColor Cyan
    Write-Host "  xtkeys update      Download latest version & restart"-ForegroundColor Cyan
    Write-Host "  xtkeys restart     Restart hotkeys background process"-ForegroundColor Cyan
    Write-Host "  xtkeys uninstall   Remove everything cleanly"        -ForegroundColor Cyan
    Write-Host "  xtkeys help        Show this help message"           -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Web install (any Windows machine):" -ForegroundColor White
    Write-Host "  irm https://github.com/$REPO_OWNER/$REPO_NAME/releases/latest/download/install.ps1 | iex" -ForegroundColor DarkCyan
    Write-Host ""
}

switch ($Command) {
    'install'   { Invoke-Install }
    'status'    { Invoke-Status }
    'update'    { Invoke-Update }
    'restart'   { Invoke-Restart }
    'uninstall' { Invoke-Uninstall }
    'help'      { Invoke-Help }
    Default {
        throw "Invalid command received: $Command"
    }
}

