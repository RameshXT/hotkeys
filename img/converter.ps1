#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$HardPath = ""
$HardKeepSource = ""
$HardDryRun = ""
$HardQuality = ""

$VERSION = "1.0"
$SCRIPT_START = Get-Date

$SupportedFormats = @('.jpg', '.jpeg', '.png', '.bmp', '.tiff', '.tif', '.gif', '.heic', '.raw', '.cr2', '.nef', '.arw', '.dng', '.webp')
$DefaultQuality = 85

function Write-Header {
    $w = 62
    $line = "=" * $w
    Write-Host ""
    Write-Host $line -ForegroundColor Cyan
    Write-Host ("  IMAGE CONVERTER  v{0}  |  Convert to WebP" -f $VERSION).PadRight($w) -ForegroundColor Cyan
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

function Test-ImageMagick {
    try {
        $null = & magick --version 2>&1
        return $true
    }
    catch {
        return $false
    }
}

function Invoke-ConvertFolder {
    param(
        [string] $FolderPath,
        [bool]   $KeepSource,
        [int]    $Quality,
        [bool]   $DryRun
    )

    $files = @(Get-ChildItem -LiteralPath $FolderPath -File -ErrorAction SilentlyContinue |
        Where-Object { $script:SupportedFormats -contains $_.Extension.ToLower() } |
        Sort-Object Name)

    if ($files.Count -eq 0) { return @{ Converted = 0; Skipped = 0; Errored = 0; Deleted = 0; Total = 0 } }

    $converted = 0; $skipped = 0; $errored = 0; $deleted = 0; $counter = 0

    foreach ($file in $files) {
        $counter++
        $progress = "[{0}/{1}]" -f $counter, $files.Count
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        $newName = "$baseName.webp"
        $newPath = Join-Path $FolderPath $newName

        Write-Host "  $progress " -NoNewline -ForegroundColor DarkGray

        # Already a webp — skip
        if ($file.Extension.ToLower() -eq '.webp') {
            Write-Host " SKIPPED  " -NoNewline -ForegroundColor DarkGray
            Write-Host " $($file.Name)  (already WebP)" -ForegroundColor DarkGray
            $skipped++
            continue
        }

        # Output already exists
        if (Test-Path -LiteralPath $newPath) {
            Write-Host " SKIPPED  " -NoNewline -ForegroundColor Yellow
            Write-Host " $($file.Name)  ->  $newName  (output already exists)" -ForegroundColor Yellow
            $skipped++
            continue
        }

        if ($DryRun) {
            $action = if ($KeepSource) { "KEEP original" } else { "DELETE original" }
            Write-Host " WOULD CONVERT " -NoNewline -ForegroundColor Cyan
            Write-Host " $($file.Name)  ->  $newName  [$action]" -ForegroundColor DarkGray
            $converted++
            continue
        }

        try {
            $magickArgs = @($file.FullName, "-quality", $Quality, $newPath)
            $proc = Start-Process -FilePath "magick" -ArgumentList $magickArgs `
                -NoNewWindow -Wait -PassThru -RedirectStandardError "$env:TEMP\magick_err.txt"

            if ($proc.ExitCode -ne 0) {
                $errMsg = if (Test-Path "$env:TEMP\magick_err.txt") { Get-Content "$env:TEMP\magick_err.txt" -Raw } else { "unknown error" }
                throw $errMsg.Trim()
            }

            if (-not $KeepSource) {
                Remove-Item -LiteralPath $file.FullName -Force
                $deleted++
            }

            Write-Host " CONVERTED" -NoNewline -ForegroundColor Green
            Write-Host " $($file.Name)  ->  $newName" -ForegroundColor DarkGray
            $converted++

        }
        catch {
            if (Test-Path -LiteralPath $newPath) {
                try { Remove-Item -LiteralPath $newPath -Force } catch { }
            }
            Write-Host " ERROR    " -NoNewline -ForegroundColor Red
            Write-Host " $($file.Name)  --  $_" -ForegroundColor DarkGray
            $errored++
        }
    }

    return @{ Converted = $converted; Skipped = $skipped; Errored = $errored; Deleted = $deleted; Total = $files.Count }
}

function Invoke-Convert {
    param(
        [string] $TargetPath,
        [bool]   $KeepSource,
        [int]    $Quality,
        [bool]   $DryRun
    )

    $totalConverted = 0
    $totalSkipped = 0
    $totalErrored = 0
    $totalDeleted = 0
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
            Where-Object { $script:SupportedFormats -contains $_.Extension.ToLower() }).Count
        if ($imgCount -eq 0) { continue }

        $foldersFound++
        $relPath = if ($folder -ieq $TargetPath) { "(root)" } else { $folder.Substring($TargetPath.Length).TrimStart('\') }

        Write-Host ""
        Write-Host "  Folder : $relPath  ($imgCount image(s))" -ForegroundColor DarkCyan
        Write-Host ""

        $result = Invoke-ConvertFolder -FolderPath $folder -KeepSource $KeepSource -Quality $Quality -DryRun $DryRun
        $totalConverted += $result.Converted
        $totalSkipped += $result.Skipped
        $totalErrored += $result.Errored
        $totalDeleted += $result.Deleted
        $totalFiles += $result.Total
    }

    if ($foldersFound -eq 0) {
        Write-Warn "No supported image files found in: $TargetPath"
        return $null
    }

    return @{ Converted = $totalConverted; Skipped = $totalSkipped; Errored = $totalErrored; Deleted = $totalDeleted; Total = $totalFiles; Folders = $foldersFound }
}

# ── Entry Point ──────────────────────────────────────────────

Write-Header

# ── Check ImageMagick ────────────────────────────────────────
if (-not (Test-ImageMagick)) {
    Write-Host "  [ERROR] ImageMagick is not installed or not in PATH." -ForegroundColor Red
    Write-Host ""
    Write-Host "  Install it from  : https://imagemagick.org/script/download.php#windows" -ForegroundColor Yellow
    Write-Host "  Or via winget    : winget install ImageMagick.ImageMagick" -ForegroundColor Yellow
    Write-Host "  Or via choco     : choco install imagemagick" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

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

if ($HardQuality -ne "") {
    $Quality = [int]$HardQuality
}
else {
    Write-Host "  WebP quality 1-100 [default=$DefaultQuality] : " -NoNewline -ForegroundColor Gray
    $qualInput = (Read-Host).Trim()
    $Quality = if ($qualInput -match '^\d+$' -and [int]$qualInput -in 1..100) { [int]$qualInput } else { $DefaultQuality }
}

if ($HardKeepSource -ne "") {
    $KeepInput = $HardKeepSource.ToUpper()
}
else {
    $KeepInput = Prompt-Choice "Keep original files after conversion?" @("Y", "N") "Y"
}
$KeepSource = ($KeepInput -eq "Y")

if ($HardDryRun -ne "") {
    $DryRunInput = $HardDryRun.ToUpper()
}
else {
    Write-Host ""
    Write-Host "  Test run? (shows what will happen without converting any files)" -ForegroundColor Gray
    $DryRunInput = Prompt-Choice "Proceed" @("Y", "N") "N"
}
$DryRun = ($DryRunInput -eq "Y")

Write-Host ""
Write-Info "Path           :" $TargetPath
Write-Info "Quality        :" "$Quality / 100"
Write-Info "Subfolders     :" "Yes (recursive)"
Write-Info "Keep originals :" $(if ($KeepSource) { "Yes" } else { "No - originals will be deleted" }) $(if ($KeepSource) { "White" } else { "Yellow" })
if ($DryRun) { Write-Info "Mode           :" "TEST RUN - nothing will be changed" "Yellow" }

$result = Invoke-Convert -TargetPath $TargetPath -KeepSource $KeepSource -Quality $Quality -DryRun $DryRun

$cancelled = $false

if ($DryRun -and $null -ne $result) {
    Write-Host ""
    Write-Host "  This was a test run. No files were converted." -ForegroundColor Yellow
    Write-Host ""
    $go = Prompt-Choice "Ready to run the real conversion now?" @("Y", "N") "N"

    if ($go -eq "Y") {
        Write-Host ""
        Write-Host "  Starting real run..." -ForegroundColor Cyan
        $result = Invoke-Convert -TargetPath $TargetPath -KeepSource $KeepSource -Quality $Quality -DryRun $false
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
    Write-Info "Folders        :" $result.Folders                                                       "White"
    Write-Info "Total images   :" $result.Total                                                         "White"
    Write-Info "Converted      :" $result.Converted                                                     "Green"
    Write-Info "Skipped        :" $result.Skipped                                                       "DarkGray"
    Write-Info "Errors         :" $result.Errored          $(if ($result.Errored -gt 0) { "Red" } else { "White" })
    if (-not $KeepSource) {
        Write-Info "Originals del. :" $result.Deleted                                                       "DarkGray"
    }
    Write-Info "Time taken     :" ("{0:N1}s" -f $elapsed)                                               "DarkGray"
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
        $balloon.BalloonTipTitle = "Image Converter"
        $balloon.BalloonTipText = "Cancelled. No files were changed."
        $balloon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
        $balloon.ShowBalloonTip(4000)
        Start-Sleep -Milliseconds 4500
    }
    elseif ($null -ne $result) {
        $balloon.BalloonTipTitle = "Image Converter Done"
        $balloon.BalloonTipText = "$($result.Converted) converted, $($result.Skipped) skipped, $($result.Errored) error(s)"
        $balloon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
        $balloon.ShowBalloonTip(4000)
        Start-Sleep -Milliseconds 4500
    }
    $balloon.Dispose()
}
catch { }
