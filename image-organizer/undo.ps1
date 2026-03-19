#Requires -Version 5.1

param(
    [Parameter(Mandatory = $true)]
    [string]$Log
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Info ([string]$Label, [string]$Value, [string]$Color = "White") {
    Write-Host ("  {0,-16}" -f $Label) -NoNewline -ForegroundColor Gray
    Write-Host $Value -ForegroundColor $Color
}

$w       = 62
$divider = "=" * $w
$line    = "=" * $w

Write-Host ""
Write-Host $line -ForegroundColor Cyan
Write-Host "  IMAGE ORGANIZER  |  Undo".PadRight($w) -ForegroundColor Cyan
Write-Host $line -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path -LiteralPath $Log)) {
    Write-Host "  [ERROR] Log file not found: $Log" -ForegroundColor Red
    exit 1
}

$rows = Import-Csv -LiteralPath $Log

if ($rows.Count -eq 0) {
    Write-Host "  [WARN]  Log file is empty. Nothing to undo." -ForegroundColor Yellow
    exit
}

$opType = $rows[0].Action.ToUpper()
$isMove = ($opType -eq "MOVE")
$total  = $rows.Count

Write-Info "Log file   :" $Log
Write-Info "Entries    :" $total
Write-Host ""

if ($isMove) {
    Write-Host "  What will happen:" -ForegroundColor Gray
    Write-Host "    $total file(s) will be moved back to their original locations." -ForegroundColor White
    Write-Host "    Original timestamps (created, modified, accessed) will be restored exactly." -ForegroundColor DarkGray
    Write-Host "    Empty destination folders left behind will NOT be removed." -ForegroundColor DarkGray
} else {
    Write-Host "  What will happen:" -ForegroundColor Gray
    Write-Host "    $total file(s) will be permanently deleted from the destination." -ForegroundColor Yellow
    Write-Host "    Your original source files are NOT affected." -ForegroundColor DarkGray
    Write-Host "    Empty destination folders will be removed automatically." -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "  Proceed? [Y/N] : " -NoNewline -ForegroundColor Gray
$confirm = (Read-Host).Trim().ToUpper()

if ($confirm -ne "Y") {
    Write-Host ""
    Write-Host "  Cancelled. Nothing was changed." -ForegroundColor DarkGray
    Write-Host ""
    exit
}

Write-Host ""

$restored = 0
$deleted  = 0
$skipped  = 0
$errored  = 0
$counter  = 0
$padWidth = ([string]$total).Length

foreach ($row in $rows) {

    $counter++
    $progress = "[{0,$padWidth}/{1}]" -f $counter, $total

    if ($isMove) {
        $destPath   = $row.DestinationPath
        $sourcePath = $row.SourcePath
        $fileName   = $row.FileName

        Write-Host "  $progress " -NoNewline -ForegroundColor DarkGray

        if (-not (Test-Path -LiteralPath $destPath)) {
            Write-Host " SKIPPED  " -NoNewline -ForegroundColor DarkGray
            Write-Host " $fileName -- not found at destination (already moved?)" -ForegroundColor DarkGray
            $skipped++
            continue
        }

        if (Test-Path -LiteralPath $sourcePath) {
            Write-Host " SKIPPED  " -NoNewline -ForegroundColor DarkGray
            Write-Host " $fileName -- file already exists at original location" -ForegroundColor DarkGray
            $skipped++
            continue
        }

        try {
            $sourceDir = [System.IO.Path]::GetDirectoryName($sourcePath)
            if (-not (Test-Path -LiteralPath $sourceDir)) {
                New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
            }

            Move-Item -LiteralPath $destPath -Destination $sourcePath -Force

            # Restore all three timestamps exactly
            $f                = Get-Item -LiteralPath $sourcePath
            $f.CreationTime   = [datetime]::Parse($row.CreationTime)
            $f.LastWriteTime  = [datetime]::Parse($row.LastWriteTime)
            $f.LastAccessTime = [datetime]::Parse($row.LastAccessTime)

            Write-Host " RESTORED " -NoNewline -ForegroundColor Green
            Write-Host " $fileName" -ForegroundColor DarkGray
            $restored++

        } catch {
            Write-Host " ERROR    " -NoNewline -ForegroundColor Red
            Write-Host " $fileName -- $_" -ForegroundColor DarkGray
            $errored++
        }

    } else {
        $destPath = $row.DestinationPath
        $fileName = $row.FileName

        Write-Host "  $progress " -NoNewline -ForegroundColor DarkGray

        if (-not (Test-Path -LiteralPath $destPath)) {
            Write-Host " SKIPPED  " -NoNewline -ForegroundColor DarkGray
            Write-Host " $fileName -- not found (already deleted?)" -ForegroundColor DarkGray
            $skipped++
            continue
        }

        try {
            Remove-Item -LiteralPath $destPath -Force

            $parentDir = [System.IO.Path]::GetDirectoryName($destPath)
            if ((Test-Path -LiteralPath $parentDir) -and
                (@(Get-ChildItem -LiteralPath $parentDir -Force).Count -eq 0)) {
                Remove-Item -LiteralPath $parentDir -Force -ErrorAction SilentlyContinue
            }

            Write-Host " DELETED  " -NoNewline -ForegroundColor Red
            Write-Host " $fileName" -ForegroundColor DarkGray
            $deleted++

        } catch {
            Write-Host " ERROR    " -NoNewline -ForegroundColor Red
            Write-Host " $fileName -- $_" -ForegroundColor DarkGray
            $errored++
        }
    }
}

Write-Host ""
Write-Host $divider -ForegroundColor DarkGray
Write-Host "  UNDO SUMMARY" -ForegroundColor Cyan
Write-Host $divider -ForegroundColor DarkGray

if ($isMove) {
    Write-Info "Restored   :" $restored  "Green"
} else {
    Write-Info "Deleted    :" $deleted   "Red"
}

Write-Info "Skipped    :" $skipped  "DarkGray"
Write-Info "Errors     :" $errored  $(if ($errored -gt 0){"Red"} else {"White"})
Write-Host $divider -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Done." -ForegroundColor Cyan
Write-Host ""
