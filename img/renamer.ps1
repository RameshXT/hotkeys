#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$HardPath = ""
$HardPrefix = ""
$HardDryRun = ""

$VERSION = "1.0"
$SCRIPT_START = Get-Date

$SupportedImages = @('.jpg', '.jpeg', '.png', '.heic', '.raw', '.bmp', '.tiff', '.tif', '.webp', '.gif', '.cr2', '.nef', '.arw', '.dng')

function Write-Header {
    $w = 62
    $line = "=" * $w
    Write-Host ""
    Write-Host $line -ForegroundColor Cyan
    Write-Host ("  IMAGE RENAMER  v{0}  |  Sequential Rename" -f $VERSION).PadRight($w) -ForegroundColor Cyan
    Write-Host $line -ForegroundColor Cyan
    Write-Host ""
}

function Write-Section ([string]$Text) {
    Write-Host ""
    Write-Host "  >> $Text" -ForegroundColor DarkCyan
    Write-Host ""
}

function Write-Info ([string]$Label, [string]$Value, [string]$Color = "White") {
    Write-Host ("  {0,-18}" -f $Label) -NoNewline -ForegroundColor Gray
    Write-Host $Value -ForegroundColor $Color
}

function Write-Warn ([string]$Msg) { Write-Host "  [WARN]  $Msg" -ForegroundColor Yellow }
function Write-Err  ([string]$Msg) { Write-Host "  [ERROR] $Msg" -ForegroundColor Red }

function Prompt-Choice {
    param([string]$Question, [string[]]$Valid, [string]$Default = "")
    do {
        $hint = if ($Default) { " [$($Valid -join '/'), default=$Default]" } else { " [$($Valid -join '/')]" }
        Write-Host "  $Question$hint : " -NoNewline -ForegroundColor Gray
        $answer = (Read-Host).Trim()
        if ($answer -eq "" -and $Default -ne "") { $answer = $Default }
    } while ($answer.ToUpper() -notin ($Valid | ForEach-Object { $_.ToUpper() }))
    return $answer.ToUpper()
}

function Invoke-RenameFolder {
    param(
        [string] $FolderPath,
        [string] $Prefix,
        [bool]   $DryRun
    )

    $files = @(Get-ChildItem -LiteralPath $FolderPath -File -ErrorAction SilentlyContinue |
        Where-Object { $script:SupportedImages -contains $_.Extension.ToLower() } |
        Sort-Object Name)

    if ($files.Count -eq 0) { return @{ Renamed = 0; Skipped = 0; Errored = 0; Total = 0 } }

    $padWidth = ([string]$files.Count).Length
    if ($padWidth -lt 2) { $padWidth = 2 }

    $renamed = 0; $skipped = 0; $errored = 0; $counter = 0

    foreach ($file in $files) {
        $counter++
        $progress = "[{0}/{1}]" -f $counter, $files.Count
        $ext = $file.Extension.ToLower()
        $newName = "{0}{1}{2}" -f $Prefix, ($counter.ToString("D$padWidth")), $ext
        $newPath = Join-Path $FolderPath $newName

        Write-Host "  $progress " -NoNewline -ForegroundColor DarkGray

        if ($file.Name -eq $newName) {
            Write-Host " SKIPPED  " -NoNewline -ForegroundColor DarkGray
            Write-Host " $($file.Name)  (already named correctly)" -ForegroundColor DarkGray
            $skipped++
            continue
        }

        if ((Test-Path -LiteralPath $newPath) -and ($newPath -ine $file.FullName)) {
            Write-Host " SKIPPED  " -NoNewline -ForegroundColor Yellow
            Write-Host " $($file.Name)  -> $newName  (target name already exists)" -ForegroundColor Yellow
            $skipped++
            continue
        }

        if ($DryRun) {
            Write-Host " WOULD RENAME " -NoNewline -ForegroundColor Cyan
            Write-Host " $($file.Name)  ->  $newName" -ForegroundColor DarkGray
            $renamed++
            continue
        }

        try {
            Rename-Item -LiteralPath $file.FullName -NewName $newName -Force
            Write-Host " RENAMED  " -NoNewline -ForegroundColor Green
            Write-Host " $($file.Name)  ->  $newName" -ForegroundColor DarkGray
            $renamed++
        }
        catch {
            Write-Host " ERROR    " -NoNewline -ForegroundColor Red
            Write-Host " $($file.Name)  --  $_" -ForegroundColor DarkGray
            $errored++
        }
    }

    return @{ Renamed = $renamed; Skipped = $skipped; Errored = $errored; Total = $files.Count }
}

function Invoke-Rename {
    param(
        [string] $TargetPath,
        [string] $Prefix,
        [bool]   $DryRun
    )

    $totalRenamed = 0
    $totalSkipped = 0
    $totalErrored = 0
    $totalFiles = 0
    $foldersFound = 0

    $folders = [System.Collections.Generic.List[string]]::new()
    $folders.Add($TargetPath)
    $subFolders = @(Get-ChildItem -LiteralPath $TargetPath -Directory -Recurse -ErrorAction SilentlyContinue |
        Sort-Object FullName)
    foreach ($d in $subFolders) { $folders.Add($d.FullName) }

    Write-Section "Scanning for images..."

    foreach ($folder in $folders) {
        $imgCount = @(Get-ChildItem -LiteralPath $folder -File -ErrorAction SilentlyContinue |
            Where-Object { $script:SupportedImages -contains $_.Extension.ToLower() }).Count
        if ($imgCount -eq 0) { continue }

        $foldersFound++
        $relPath = if ($folder -ieq $TargetPath) { "(root)" } else { $folder.Substring($TargetPath.Length).TrimStart('\') }

        Write-Host ""
        Write-Host "  Folder : $relPath  ($imgCount image(s))" -ForegroundColor DarkCyan
        Write-Host ""

        $result = Invoke-RenameFolder -FolderPath $folder -Prefix $Prefix -DryRun $DryRun
        $totalRenamed += $result.Renamed
        $totalSkipped += $result.Skipped
        $totalErrored += $result.Errored
        $totalFiles += $result.Total
    }

    if ($foldersFound -eq 0) {
        Write-Warn "No supported image files found in: $TargetPath"
        return $null
    }

    return @{ Renamed = $totalRenamed; Skipped = $totalSkipped; Errored = $totalErrored; Total = $totalFiles; Folders = $foldersFound }
}

# ── Entry Point ──────────────────────────────────────────────

Write-Header

Write-Section "Configuration"

if ($HardPath -ne "") {
    $TargetPath = $HardPath
    Write-Info "Path           :" $TargetPath
}
else {
    Write-Host "  Enter target path : " -NoNewline -ForegroundColor Gray
    $TargetPath = (Read-Host).Trim()
}
if (-not (Test-Path -LiteralPath $TargetPath)) { Write-Err "Path does not exist: $TargetPath"; exit 1 }

if ($HardPrefix -ne "") {
    $Prefix = $HardPrefix
}
else {
    Write-Host "  Prefix (leave blank for none, e.g. IMG_) : " -NoNewline -ForegroundColor Gray
    $Prefix = (Read-Host).Trim()
}

if ($HardDryRun -ne "") {
    $DryRunInput = $HardDryRun.ToUpper()
}
else {
    Write-Host ""
    Write-Host "  Test run? (shows what will happen without renaming any files)" -ForegroundColor Gray
    $DryRunInput = Prompt-Choice "Proceed" @("Y", "N") "N"
}
$DryRun = ($DryRunInput -eq "Y")

Write-Host ""
Write-Info "Path           :" $TargetPath
Write-Info "Prefix         :" $(if ($Prefix) { $Prefix } else { "(none)" })
Write-Info "Subfolders     :" "Yes (per-folder sequence)"
if ($DryRun) { Write-Info "Mode           :" "TEST RUN - nothing will be changed" "Yellow" }

$result = Invoke-Rename -TargetPath $TargetPath -Prefix $Prefix -DryRun $DryRun

$cancelled = $false

if ($DryRun -and $null -ne $result) {
    Write-Host ""
    Write-Host "  This was a test run. No files were renamed." -ForegroundColor Yellow
    Write-Host ""
    $go = Prompt-Choice "Ready to run the real rename now?" @("Y", "N") "N"

    if ($go -eq "Y") {
        Write-Host ""
        Write-Host "  Starting real run..." -ForegroundColor Cyan
        $result = Invoke-Rename -TargetPath $TargetPath -Prefix $Prefix -DryRun $false
    }
    else {
        $cancelled = $true
        $result = $null
        Write-Host ""
        Write-Host "  Cancelled. No files were changed." -ForegroundColor DarkGray
    }
}

if ($null -ne $result) {
    $elapsed = ((Get-Date) - $SCRIPT_START).TotalSeconds

    Write-Host ""
    $w = 62
    Write-Host ("=" * $w) -ForegroundColor DarkGray
    Write-Host "  SUMMARY" -ForegroundColor Cyan
    Write-Host ("=" * $w) -ForegroundColor DarkGray
    Write-Info "Folders        :" $result.Folders         "White"
    Write-Info "Total images   :" $result.Total           "White"
    Write-Info "Renamed        :" $result.Renamed         "Green"
    Write-Info "Skipped        :" $result.Skipped         "DarkGray"
    Write-Info "Errors         :" $result.Errored         $(if ($result.Errored -gt 0) { "Red" } else { "White" })
    Write-Info "Time taken     :" ("{0:N1}s" -f $elapsed) "DarkGray"
    Write-Host ("=" * $w) -ForegroundColor DarkGray
}

Write-Host ""
Write-Host $(if ($cancelled) { "  Cancelled." } else { "  Done." }) -ForegroundColor $(if ($cancelled) { "DarkGray" } else { "Cyan" })
Write-Host ""

try {
    Add-Type -AssemblyName System.Windows.Forms
    $balloon = [System.Windows.Forms.NotifyIcon]::new()
    $balloon.Icon = [System.Drawing.SystemIcons]::Information
    $balloon.Visible = $true
    if ($cancelled) {
        $balloon.BalloonTipTitle = "Image Renamer"
        $balloon.BalloonTipText = "Cancelled. No files were changed."
        $balloon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
        $balloon.ShowBalloonTip(4000)
        Start-Sleep -Milliseconds 4500
    }
    elseif ($null -ne $result) {
        $balloon.BalloonTipTitle = "Image Renamer Done"
        $balloon.BalloonTipText = "$($result.Renamed) renamed, $($result.Skipped) skipped, $($result.Errored) error(s)"
        $balloon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
        $balloon.ShowBalloonTip(4000)
        Start-Sleep -Milliseconds 4500
    }
    $balloon.Dispose()
}
catch { }
