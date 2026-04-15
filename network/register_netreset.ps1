<#
.SYNOPSIS
    Registers the Network Reset script as a high-privilege scheduled task.
.DESCRIPTION
    Handles task registration, principal setup, and settings configuration. 
    Can be run multiple times to update the task definition.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$TaskName       = "NetworkReset"
$NetResetScript = Join-Path $PSScriptRoot "network-reset.ps1"
$LoggedInUser   = "$env:USERDOMAIN\$env:USERNAME"

Write-Host ""
Write-Host "  NETWORK TASK REGISTRATION" -ForegroundColor Cyan
Write-Host "  ------------------------------------" -ForegroundColor DarkGray

if (-not (Test-Path $NetResetScript)) {
    Write-Host "  [ERROR] Script not found: $NetResetScript" -ForegroundColor Red
    exit 1
}

try {
    Write-Host "  Unregistering old task (if exists)..." -ForegroundColor Gray
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

    Write-Host "  Configuring task action..." -ForegroundColor Gray
    $Action = New-ScheduledTaskAction `
        -Execute "powershell.exe" `
        -Argument "-NoProfile -WindowStyle Normal -ExecutionPolicy Bypass -File `"$NetResetScript`""

    Write-Host "  Configuring principal ($LoggedInUser)..." -ForegroundColor Gray
    $Principal = New-ScheduledTaskPrincipal `
        -UserId    $LoggedInUser `
        -RunLevel  Highest `
        -LogonType Interactive

    Write-Host "  Configuring settings..." -ForegroundColor Gray
    $Settings = New-ScheduledTaskSettingsSet `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 10) `
        -MultipleInstances  IgnoreNew `
        -Priority           5 `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries

    Write-Host "  Registering with Task Scheduler..." -ForegroundColor Gray
    Register-ScheduledTask `
        -TaskName  $TaskName `
        -Action    $Action `
        -Principal $Principal `
        -Settings  $Settings `
        -Force | Out-Null

    Write-Host "  [SUCCESS] Task '$TaskName' registered." -ForegroundColor Green
    Write-Host ""
    Write-Host "  Details:" -ForegroundColor Gray
    Write-Host "  - Script: $NetResetScript"
    Write-Host "  - User  : $LoggedInUser"
    Write-Host "  - Mode  : Elevated, Visible Window"
    Write-Host ""
    
} catch {
    Write-Host "  [FATAL ERROR] Failed to register task: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
