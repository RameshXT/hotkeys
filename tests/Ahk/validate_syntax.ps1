#Requires -Version 5.1
<#
.SYNOPSIS
    Validates AutoHotkey v2 script syntax across modular files and bundled distributions.
#>
[CmdletBinding()]
param(
    [string]$AhkPath = ""
)

if (-not $AhkPath) {
    $possiblePaths = @(
        "$env:LOCALAPPDATA\xtkeys\ahk\AutoHotkey64.exe",
        "$env:LOCALAPPDATA\xtkeys\ahk\AutoHotkey32.exe",
        "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe",
        'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe',
        'C:\Program Files\AutoHotkey\v2\AutoHotkey32.exe',
        'C:\Program Files\AutoHotkey\AutoHotkey64.exe',
        'C:\Program Files\AutoHotkey\AutoHotkey.exe'
    )
    $f64 = Get-Command 'AutoHotkey64.exe' -ErrorAction SilentlyContinue
    if ($f64) { $possiblePaths += $f64.Source }
    $f32 = Get-Command 'AutoHotkey.exe' -ErrorAction SilentlyContinue
    if ($f32) { $possiblePaths += $f32.Source }

    foreach ($p in ($possiblePaths | Select-Object -Unique)) {
        if ($p -and (Test-Path $p)) {
            $AhkPath = $p
            break
        }
    }
}

if (-not $AhkPath -or -not (Test-Path $AhkPath)) {
    Write-Warning "AutoHotkey v2 executable not found. Skipping live runtime validation."
    exit 0
}

Write-Host "Validating AutoHotkey scripts with: $AhkPath" -ForegroundColor Cyan

$root = Resolve-Path "$PSScriptRoot\..\.."
$entryPoint = "$root\src\main.ahk"

if (Test-Path $entryPoint) {
    Write-Host "Validating $entryPoint..." -ForegroundColor Gray
    $process = Start-Process -FilePath $AhkPath -ArgumentList "/validate `"$entryPoint`"" -NoNewWindow -PassThru -Wait
    if ($process.ExitCode -ne 0) {
        Write-Error "AHK syntax validation failed on $entryPoint with exit code $($process.ExitCode)"
        exit $process.ExitCode
    }
    Write-Host "  OK: $entryPoint passed syntax check." -ForegroundColor Green
}

$bundled = "$root\hotkeys.ahk"
if (Test-Path $bundled) {
    Write-Host "Validating $bundled..." -ForegroundColor Gray
    $process = Start-Process -FilePath $AhkPath -ArgumentList "/validate `"$bundled`"" -NoNewWindow -PassThru -Wait
    if ($process.ExitCode -ne 0) {
        Write-Error "AHK syntax validation failed on $bundled with exit code $($process.ExitCode)"
        exit $process.ExitCode
    }
    Write-Host "  OK: $bundled passed syntax check." -ForegroundColor Green
}

Write-Host "All AutoHotkey validation checks completed successfully." -ForegroundColor Green
exit 0
