#Requires -Version 5.1
#Requires -RunAsAdministrator
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$CleanupScript = Join-Path $PSScriptRoot "cleanup.ps1"
$TaskName = "WindowsCleanup"
$LoggedInUser = "$env:USERDOMAIN\$env:USERNAME"

if (-not (Test-Path -LiteralPath $CleanupScript)) {
    Write-Host "ERROR: cleanup.ps1 not found at $CleanupScript" -ForegroundColor Red
    Write-Host "Place cleanup.ps1 in the correct folder first." -ForegroundColor Yellow
    exit 1
}

if ([string]::IsNullOrWhiteSpace($env:USERNAME)) {
    Write-Host "ERROR: Could not determine the current username." -ForegroundColor Red
    exit 1
}

Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

$Action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File `"$CleanupScript`""

$Principal = New-ScheduledTaskPrincipal `
    -UserId    $LoggedInUser `
    -RunLevel  Highest `
    -LogonType Interactive

$Settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 10) `
    -MultipleInstances  IgnoreNew `
    -Priority           7

try {
    Register-ScheduledTask `
        -TaskName  $TaskName `
        -Action    $Action `
        -Principal $Principal `
        -Settings  $Settings `
        -Force `
        -ErrorAction Stop | Out-Null
}
catch {
    Write-Host "ERROR: Failed to register task '$TaskName': $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Task '$TaskName' registered successfully." -ForegroundColor Green
Write-Host "Cleanup script : $CleanupScript"           -ForegroundColor Cyan
Write-Host "Runs as        : $LoggedInUser (elevated, popup visible)" -ForegroundColor Cyan
Write-Host "Triggered by   : Ctrl+Shift+Alt+C via AHK" -ForegroundColor Cyan
Write-Host ""
Write-Host "You only need to run this registration script once." -ForegroundColor Yellow
