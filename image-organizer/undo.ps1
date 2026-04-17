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
function Resolve-NormalizedPath {
    param([Parameter(Mandatory)][string]$Path)

    $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    return $resolved.TrimEnd('\')
}

function Test-IsChildPath {
    param(
        [Parameter(Mandatory)][string]$ParentPath,
        [Parameter(Mandatory)][string]$ChildPath
    )

    $parent = $ParentPath.TrimEnd('\')
    $child = $ChildPath.TrimEnd('\')

    if ($child.Length -lt $parent.Length) {
        return $false
    }

    return $child.StartsWith($parent, [System.StringComparison]::OrdinalIgnoreCase) -and
    ($child.Length -eq $parent.Length -or $child[$parent.Length] -eq '\')
}

function Test-OrganizerLogRow {
    param(
        [Parameter(Mandatory)]$Row,
        [Parameter(Mandatory)][bool]$IsMove,
        [Parameter(Mandatory)][string]$DestinationRoot
    )

    if ([string]::IsNullOrWhiteSpace($Row.Action) -or
        [string]::IsNullOrWhiteSpace($Row.DestinationPath) -or
        [string]::IsNullOrWhiteSpace($Row.FileName)) {
        return $false
    }

    if (-not (Test-IsChildPath -ParentPath $DestinationRoot -ChildPath $Row.DestinationPath)) {
        return $false
    }

    if ($IsMove) {
        foreach ($propertyName in @('SourcePath', 'CreationTime', 'LastWriteTime', 'LastAccessTime')) {
            if ([string]::IsNullOrWhiteSpace($Row.$propertyName)) {
                return $false
            }
        }
    }

    return $true
}

$w = 62
$divider = "=" * $w
$line = "=" * $w

Write-Host ""
Write-Host $line -ForegroundColor Cyan
Write-Host "  IMAGE ORGANIZER  |  Undo".PadRight($w) -ForegroundColor Cyan
Write-Host $line -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path -LiteralPath $Log)) {
    Write-Host "  [ERROR] Log file not found: $Log" -ForegroundColor Red
    exit 1
}

$rows = @(Import-Csv -LiteralPath $Log -ErrorAction Stop)

if ($rows.Count -eq 0) {
    Write-Host "  [WARN]  Log file is empty. Nothing to undo." -ForegroundColor Yellow
    exit
}

if (-not ($rows[0].PSObject.Properties.Name -contains 'Action') -or
    -not ($rows[0].PSObject.Properties.Name -contains 'DestinationPath')) {
    Write-Host "  [ERROR] Log file format is invalid or not an organizer log: $Log" -ForegroundColor Red
    exit 1
}

$opType = $rows[0].Action.ToUpper()
$isMove = ($opType -eq "MOVE")
$total = $rows.Count

$LogDir = Split-Path -Parent $Log
$DestinationRoot = Split-Path -Parent $LogDir
$LogTimestamp = [System.IO.Path]::GetFileNameWithoutExtension($Log) -replace '^undo_', ''
$HtmlReportPath = Join-Path $LogDir "report_$LogTimestamp.html"
$DestinationRootResolved = Resolve-NormalizedPath -Path $DestinationRoot

Write-Info "Log file   :" $Log
Write-Info "Entries    :" $total
Write-Host ""

if ($isMove) {
    Write-Host "  What will happen:" -ForegroundColor Gray
    Write-Host "    $total file(s) will be moved back to their original locations." -ForegroundColor White
    Write-Host "    Original timestamps (created, modified, accessed) will be restored exactly." -ForegroundColor Green
    Write-Host "    Empty destination folders will be removed automatically." -ForegroundColor DarkGray
    Write-Host "    Organizer logs for this run will be deleted." -ForegroundColor DarkGray
}
else {
    Write-Host "  What will happen:" -ForegroundColor Gray
    Write-Host "    $total file(s) will be permanently deleted from the destination." -ForegroundColor White
    Write-Host "    Your original source files are NOT affected." -ForegroundColor Green
    Write-Host "    Empty destination folders will be removed automatically." -ForegroundColor DarkGray
    Write-Host "    Organizer logs for this run will be deleted." -ForegroundColor DarkGray
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
$deleted = 0
$skipped = 0
$errored = 0
$counter = 0
$padWidth = ([string]$total).Length

foreach ($row in $rows) {

    $counter++
    $progress = "[{0,$padWidth}/{1}]" -f $counter, $total

    if (-not (Test-OrganizerLogRow -Row $row -IsMove $isMove -DestinationRoot $DestinationRootResolved)) {
        Write-Host "  $progress " -NoNewline -ForegroundColor DarkGray
        Write-Host " ERROR    " -NoNewline -ForegroundColor Red
        Write-Host " invalid or unsafe log entry detected" -ForegroundColor DarkGray
        $errored++
        continue
    }

    if ($isMove) {
        $destPath = $row.DestinationPath
        $sourcePath = $row.SourcePath
        $fileName = $row.FileName

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

            $f = Get-Item -LiteralPath $sourcePath
            $f.CreationTime = [datetime]::Parse($row.CreationTime)
            $f.LastWriteTime = [datetime]::Parse($row.LastWriteTime)
            $f.LastAccessTime = [datetime]::Parse($row.LastAccessTime)

            Write-Host " RESTORED " -NoNewline -ForegroundColor Green
            Write-Host " $fileName" -ForegroundColor DarkGray
            $restored++

        }
        catch {
            Write-Host " ERROR    " -NoNewline -ForegroundColor Red
            Write-Host " $fileName -- $_" -ForegroundColor DarkGray
            $errored++
        }

    }
    else {
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

            Write-Host " DELETED  " -NoNewline -ForegroundColor Red
            Write-Host " $fileName" -ForegroundColor DarkGray
            $deleted++

        }
        catch {
            Write-Host " ERROR    " -NoNewline -ForegroundColor Red
            Write-Host " $fileName -- $_" -ForegroundColor DarkGray
            $errored++
        }
    }
}

$foldersRemoved = 0

if (Test-Path -LiteralPath $DestinationRoot) {
    $dirsToCheck = @(Get-ChildItem -LiteralPath $DestinationRoot -Directory -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notlike "*\_organizer_logs*" } |
        Sort-Object FullName -Descending)

    foreach ($dir in $dirsToCheck) {
        if (Test-Path -LiteralPath $dir.FullName) {
            $children = @(Get-ChildItem -LiteralPath $dir.FullName -Force -ErrorAction SilentlyContinue)
            if ($children.Count -eq 0) {
                try {
                    Remove-Item -LiteralPath $dir.FullName -Force -ErrorAction Stop
                    $foldersRemoved++
                }
                catch { }
            }
        }
    }
}

if (Test-Path -LiteralPath $Log) {
    try { Remove-Item -LiteralPath $Log -Force -ErrorAction SilentlyContinue } catch { }
}
if (Test-Path -LiteralPath $HtmlReportPath) {
    try { Remove-Item -LiteralPath $HtmlReportPath -Force -ErrorAction SilentlyContinue } catch { }
}
if (Test-Path -LiteralPath $LogDir) {
    $remaining = @(Get-ChildItem -LiteralPath $LogDir -Force -ErrorAction SilentlyContinue)
    if ($remaining.Count -eq 0) {
        try { Remove-Item -LiteralPath $LogDir -Force -ErrorAction SilentlyContinue } catch { }
    }
}

Write-Host ""
Write-Host $divider -ForegroundColor DarkGray
Write-Host "  UNDO SUMMARY" -ForegroundColor Cyan
Write-Host $divider -ForegroundColor DarkGray

if ($isMove) {
    Write-Info "Restored   :" $restored       "Green"
}
else {
    Write-Info "Deleted    :" $deleted        "Red"
}

Write-Info "Skipped    :" $skipped           "DarkGray"
Write-Info "Errors     :" $errored           $(if ($errored -gt 0) { "Red" } else { "White" })
Write-Info "Folders rm :" $foldersRemoved    "DarkGray"
Write-Host $divider -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Done." -ForegroundColor Cyan
Write-Host ""
