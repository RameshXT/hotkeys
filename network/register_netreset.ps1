#Requires -RunAsAdministrator

$NetResetScript = "C:\Users\rames\sys-scripts\network\network-reset.ps1"
$TaskName       = "NetworkReset"
$LoggedInUser   = "$env:USERDOMAIN\$env:USERNAME"

if (-not (Test-Path -LiteralPath $NetResetScript)) {
    Write-Host "ERROR: network-reset.ps1 not found at $NetResetScript" -ForegroundColor Red
    Write-Host "Place network-reset.ps1 in the correct folder first." -ForegroundColor Yellow
    exit 1
}

Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

$Action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$NetResetScript`""

$Principal = New-ScheduledTaskPrincipal `
    -UserId    $LoggedInUser `
    -RunLevel  Highest `
    -LogonType Interactive

$Settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5) `
    -MultipleInstances  IgnoreNew `
    -Priority           5

Register-ScheduledTask `
    -TaskName  $TaskName `
    -Action    $Action `
    -Principal $Principal `
    -Settings  $Settings `
    -Force | Out-Null

Write-Host ""
Write-Host "Task '$TaskName' registered successfully." -ForegroundColor Green
Write-Host "Network reset script : $NetResetScript"           -ForegroundColor Cyan
Write-Host "Runs as              : $LoggedInUser (elevated, no UAC prompt)" -ForegroundColor Cyan
Write-Host "Triggered by         : Ctrl+Shift+Alt+N via AHK" -ForegroundColor Cyan
Write-Host ""
Write-Host "You only need to run this registration script once." -ForegroundColor Yellow
