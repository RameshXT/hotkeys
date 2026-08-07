<#
.SYNOPSIS
    build.ps1 — Release build script for xtkeys / hotkeys
    Produces all artifacts needed for the GitHub Release.

.OUTPUTS
    dist/hotkeys.ahk       <- the script users download
    dist/hotkeys.sha256    <- SHA-256 hash for integrity verification
    dist/xtkeys.ps1        <- installer/CLI (so irm .../xtkeys.ps1 | iex always works)
    dist/hotkeys.zip       <- zip bundle (hotkeys.ahk + xtkeys.ps1)
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ROOT     = $PSScriptRoot
$DIST     = Join-Path $ROOT 'dist'
$AHK_SRC  = Join-Path $ROOT 'hotkeys.ahk'
$CLI_SRC  = Join-Path $ROOT 'xtkeys.ps1'

# ==============================================================================
# Validate source files
# ==============================================================================

if (-not (Test-Path $AHK_SRC)) { throw "Missing source: $AHK_SRC" }
if (-not (Test-Path $CLI_SRC)) { throw "Missing source: $CLI_SRC" }

Write-Host ''
Write-Host '  Building release artifacts...' -ForegroundColor Cyan
Write-Host ''

# ==============================================================================
# Clean and create dist/
# ==============================================================================

if (Test-Path $DIST) {
    Remove-Item $DIST -Recurse -Force
}
New-Item -ItemType Directory -Path $DIST -Force | Out-Null
Write-Host '  -> dist/ cleaned and ready.' -ForegroundColor DarkGray

# ==============================================================================
# Copy hotkeys.ahk
# ==============================================================================

$AHK_DEST = Join-Path $DIST 'hotkeys.ahk'
Copy-Item $AHK_SRC $AHK_DEST -Force
Write-Host '  OK dist/hotkeys.ahk' -ForegroundColor Green

# ==============================================================================
# Generate SHA-256 checksum  (format: HASH  hotkeys.ahk)
# ==============================================================================

$hash     = (Get-FileHash -Path $AHK_DEST -Algorithm SHA256).Hash.ToUpper()
$hashLine = "$hash  hotkeys.ahk"
$HASH_DEST = Join-Path $DIST 'hotkeys.sha256'
[System.IO.File]::WriteAllText($HASH_DEST, $hashLine, [System.Text.Encoding]::ASCII)
Write-Host "  OK dist/hotkeys.sha256  ($hash)" -ForegroundColor Green

# ==============================================================================
# Copy xtkeys.ps1 (so the raw GitHub URL always serves the latest installer)
# ==============================================================================

$CLI_DEST = Join-Path $DIST 'xtkeys.ps1'
Copy-Item $CLI_SRC $CLI_DEST -Force
Write-Host '  OK dist/xtkeys.ps1' -ForegroundColor Green

# ==============================================================================
# Create hotkeys.zip  (bundle: hotkeys.ahk + xtkeys.ps1)
# ==============================================================================

$ZIP_DEST = Join-Path $DIST 'hotkeys.zip'
Compress-Archive -Path $AHK_DEST, $CLI_DEST -DestinationPath $ZIP_DEST -Force
Write-Host '  OK dist/hotkeys.zip' -ForegroundColor Green

# ==============================================================================
# Summary
# ==============================================================================

Write-Host ''
Write-Host '  Release artifacts ready in dist/:' -ForegroundColor White
Get-ChildItem $DIST | ForEach-Object {
    $size = [math]::Round($_.Length / 1KB, 1)
    Write-Host "    $($_.Name.PadRight(22)) $size KB" -ForegroundColor Cyan
}
Write-Host ''
