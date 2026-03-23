#Requires -RunAsAdministrator

$UpdateScript = Join-Path $PSScriptRoot "update.ps1"
$TaskName      = "WindowsUpdater"
$LoggedInUser  = "$env:USERDOMAIN\$env:USERNAME"

if (-not (Test-Path -LiteralPath $UpdateScript)) {
    Write-Host "ERROR: update.ps1 not found at $UpdateScript" -ForegroundColor Red
    Write-Host "Place update.ps1 in your user profile folder first." -ForegroundColor Yellow
    exit 1
}

Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

$Action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -WindowStyle Normal -ExecutionPolicy RemoteSigned -File `"$UpdateScript`""

$Principal = New-ScheduledTaskPrincipal `
    -UserId    $LoggedInUser `
    -RunLevel  Highest `
    -LogonType Interactive

$Trigger = New-ScheduledTaskTrigger -AtLogOn -User $LoggedInUser
$Trigger.Delay = "PT30M"

$Settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit      (New-TimeSpan -Minutes 90) `
    -MultipleInstances       IgnoreNew `
    -Priority                7 `
    -RunOnlyIfNetworkAvailable

try {
    Register-ScheduledTask `
        -TaskName  $TaskName `
        -Action    $Action `
        -Principal $Principal `
        -Trigger   $Trigger `
        -Settings  $Settings `
        -Force `
        -ErrorAction Stop | Out-Null
} catch {
    Write-Host "ERROR: Failed to register task '$TaskName': $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Task '$TaskName' registered successfully."          -ForegroundColor Green
Write-Host "Update script  : $UpdateScript"                    -ForegroundColor Cyan
Write-Host "Runs as        : $LoggedInUser (elevated, popup visible)" -ForegroundColor Cyan
Write-Host "Triggered by   : At logon + 20 min delay, or Ctrl+Shift+Alt+W via AHK" -ForegroundColor Cyan
Write-Host ""
Write-Host "You only need to run this registration script once." -ForegroundColor Yellow
