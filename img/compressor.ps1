#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$VERSION = "1.1"


function Write-Header {
    $w = 62
    $line = "=" * $w
    Write-Host ""
    Write-Host $line -ForegroundColor Cyan
    Write-Host ("  IMAGE COMPRESSOR v{0}  |  Optimize & Resize" -f $VERSION).PadRight($w) -ForegroundColor Cyan
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

function Get-FriendlySize ([long]$Bytes) {
    if ($Bytes -ge 1GB) { return ("{0:N2} GB" -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ("{0:N2} MB" -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ("{0:N2} KB" -f ($Bytes / 1KB)) }
    return "$Bytes Bytes"
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

# ─────────────────────────────────────────────────────────────
# Main Code
# ─────────────────────────────────────────────────────────────

Write-Header

# 1. Check ImageMagick
if (-not (Test-ImageMagick)) {
    Write-Err "ImageMagick is not installed or not in PATH."
    Write-Host "  Install it via: winget install ImageMagick.ImageMagick" -ForegroundColor Yellow
    Write-Host ""
    pause
    exit 1
}

$InputPath = ""
while ($true) {
    Write-Section "Source Image"
    Write-Host "  Drag and drop an image or enter path: " -NoNewline -ForegroundColor Gray
    $InputPath = (Read-Host).Trim().Replace('"', '').Replace("'", "")

    if ($InputPath -eq "") { exit 0 }
    if (Test-Path -LiteralPath $InputPath) { break }
    
    Write-Err "File not found: $InputPath"
}

$file = Get-Item -LiteralPath $InputPath
$ext = $file.Extension.ToLower()

# 3. Show Official Image Size
Write-Info "Filename       :" $file.Name
Write-Info "Current Size   :" (Get-FriendlySize $file.Length) "Green"
Write-Info "Format         :" $ext.ToUpper()

Write-Section "Compression Settings"

# 4. Ask for Desired Size
Write-Host "  Enter desired size (e.g. 500kb, 1mb, 50%): " -NoNewline -ForegroundColor Gray
$RawSize = (Read-Host).Trim().ToLower()

if ($RawSize -eq "") {
    Write-Warn "No size entered. Using default target: 500KB"
    $TargetSize = "500kb"
}
else {
    # If user enters just a number, assume KB if > 100, else assume Quality
    if ($RawSize -match '^\d+$') {
        $val = [int]$RawSize
        if ($val -gt 100) {
            $TargetSize = "$($val)kb"
            Write-Info "Interpreted as :" "$TargetSize (Target File Size)" "Yellow"
        }
        else {
            $TargetSize = $val
            Write-Info "Interpreted as :" "$TargetSize (Quality %)" "Yellow"
        }
    }
    else {
        $TargetSize = $RawSize
    }
}

# 5. Determine Destination & Format Strategy
$Dir = $file.DirectoryName
$BaseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)

$TargetIsSizeValue = $TargetSize -match "(kb|mb|b)$"
$TargetIsPercent = $TargetSize -match '^\d+%$'

$targetBytes = 0l
if ($TargetIsSizeValue) {
    $val = [double]($TargetSize -replace '[^\d\.]', '')
    if ($TargetSize -like "*mb") { $targetBytes = $val * 1MB }
    elseif ($TargetSize -like "*kb") { $targetBytes = $val * 1KB }
    else { $targetBytes = $val }
}

$CurrentSize = $file.Length
$OutExt = $ext

Write-Section "Analyzing Strategy..."

if ($TargetIsSizeValue) {
    $ratio = $targetBytes / $CurrentSize
    
    if ($ratio -gt 0.9) {
        Write-Host "  Request is near original size. Performing lossless optimization." -ForegroundColor Gray
        $OutExt = $ext
        $Strategy = "Lossless"
    }
    elseif ($ratio -gt 0.3 -and $ext -eq ".png") {
        Write-Host "  Request is moderate. Using WebP to maintain high quality." -ForegroundColor Yellow
        $OutExt = ".webp"
        $Strategy = "WebP-High"
    }
    elseif ($ratio -gt 0.1) {
        Write-Host "  Request is standard. Using JPG with high quality." -ForegroundColor Cyan
        $OutExt = ".jpg"
        $Strategy = "JPG-High"
    }
    else {
        Write-Host "  Request is aggressive. Using JPG compression." -ForegroundColor Red
        $OutExt = ".jpg"
        $Strategy = "JPG-Low"
    }
}
else {
    $Strategy = "Standard"
}

$OutputPath = Join-Path $Dir "$BaseName-compressed$OutExt"
Write-Info "Strategy       :" $Strategy
Write-Info "Output Format  :" $OutExt.ToUpper()

# 6. Execute Compression
Write-Section "Processing..."

try {
    if ($TargetIsPercent) {
        & magick $InputPath -resize $TargetSize $OutputPath
    }
    elseif ($TargetIsSizeValue) {
        if ($Strategy -eq "Lossless") {
            # Low compression level for PNG to keep size high if requested
            if ($ext -eq ".png") {
                & magick $InputPath -define png:compression-level=1 $OutputPath
            }
            else {
                & magick $InputPath -quality 100 $OutputPath
            }
        }
        elseif ($Strategy -eq "WebP-High") {
            # WebP is better for hitting mid-range targets
            & magick $InputPath -define "webp:extent=$TargetSize" -quality 95 $OutputPath
        }
        else {
            # JPG Extents
            & magick $InputPath -define "jpeg:extent=$TargetSize" -quality 98 $OutputPath
        }
    }
    elseif ($TargetSize -match '^\d+$') {
        & magick $InputPath -quality $TargetSize $OutputPath
    }

    if (Test-Path -LiteralPath $OutputPath) {
        $newFile = Get-Item -LiteralPath $OutputPath
        Write-Host ""
        Write-Host "  [SUCCESS] Image processed successfully!" -ForegroundColor Green
        
        $newLen = $newFile.Length
        Write-Info "Requested Size :" $TargetSize.ToUpper() "Gray"
        Write-Info "Resulting Size :" (Get-FriendlySize $newLen) "Green"
        
        $savings = [math]::Round((1 - ($newLen / $CurrentSize)) * 100, 1)
        Write-Info "Reduction      :" "$savings%" "Cyan"

        if ($TargetIsSizeValue -and $newLen -lt ($targetBytes * 0.5)) {
            Write-Host ""
            Write-Warn "Result is still smaller than requested ($($TargetSize.ToUpper())). "
            Write-Host "  This happens when the image data is naturally very easy to compress." -ForegroundColor DarkGray
            Write-Host "  I have used the highest possible quality to stay as close to your target as possible." -ForegroundColor DarkGray
        }

        Write-Info "Saved path     :" $OutputPath
    }
    else {
        throw "Output file was not created."
    }

}
catch {
    Write-Err "Failed to process image: $_"
}

Write-Host ""
Write-Host "  Done." -ForegroundColor Cyan
Write-Host ""
pause
