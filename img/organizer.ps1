#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$HardSource = ""
$HardDestination = ""
$HardAction = ""
$HardRecurse = ""
$HardDryRun = ""

$FolderFormat = "1"
$OnConflict = "R"

$VERSION = "2.1"
$SCRIPT_START = Get-Date
$LOG_TIMESTAMP = $SCRIPT_START.ToString("yyyyMMdd_HHmmss")

$SupportedImages = @('.jpg', '.jpeg', '.png', '.heic', '.raw', '.bmp', '.tiff', '.tif', '.webp', '.gif', '.cr2', '.nef', '.arw', '.dng')
$SupportedVideos = @('.mp4', '.mov', '.avi', '.mkv', '.m4v', '.wmv', '.3gp', '.flv', '.mpg', '.mpeg')
$SupportedAll = $SupportedImages + $SupportedVideos

function Write-Header {
    $w = 62
    $line = "=" * $w
    Write-Host ""
    Write-Host $line -ForegroundColor Cyan
    Write-Host ("  IMAGE ORGANIZER  v{0}  |  Organize by Date" -f $VERSION).PadRight($w) -ForegroundColor Cyan
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

function Read-Choice {
    param([string]$Question, [string[]]$Valid, [string]$Default = "")
    $wordMap = @{
        "MOVE" = "M"; "COPY" = "C"
        "YES" = "Y"; "NO" = "N"
    }
    do {
        $hint = if ($Default) { " [$($Valid -join '/'), default=$Default]" } else { " [$($Valid -join '/')]" }
        Write-Host "  $Question$hint : " -NoNewline -ForegroundColor Gray
        $answer = (Read-Host).Trim()
        if ($answer -eq "" -and $Default -ne "") { $answer = $Default }
        $upper = $answer.ToUpper()
        if ($wordMap.ContainsKey($upper)) { $answer = $wordMap[$upper] }
    } while ($answer.ToUpper() -notin ($Valid | ForEach-Object { $_.ToUpper() }))
    return $answer.ToUpper()
}

function Get-FileMD5 {
    param ([string]$FilePath)
    try {
        $md5 = [System.Security.Cryptography.MD5]::Create()
        $stream = [System.IO.File]::OpenRead($FilePath)
        try {
            $hashBytes = $md5.ComputeHash($stream)
            return [BitConverter]::ToString($hashBytes).Replace("-", "").ToLower()
        }
        finally { $stream.Close(); $md5.Dispose() }
    }
    catch { return $null }
}

function Get-ExifDateTaken {
    param ([string]$FilePath)

    $ext = [System.IO.Path]::GetExtension($FilePath).ToLower()

    if ($ext -in @('.jpg', '.jpeg', '.png', '.bmp', '.gif', '.tiff', '.tif')) {
        try {
            Add-Type -AssemblyName System.Drawing
            $image = [System.Drawing.Image]::FromFile($FilePath)
            try {
                $prop = $image.GetPropertyItem(36867)
                $dateString = [System.Text.Encoding]::ASCII.GetString($prop.Value).TrimEnd([char]0)
                if ($dateString -match '^(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})$') {
                    return [datetime]"$($Matches[1])-$($Matches[2])-$($Matches[3]) $($Matches[4]):$($Matches[5]):$($Matches[6])"
                }
            }
            catch { }
            finally { $image.Dispose() }
        }
        catch { }
    }

    $name = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
    $patterns = @(
        '(?<y>\d{4})(?<m>\d{2})(?<d>\d{2})[_\-](?<H>\d{2})(?<M>\d{2})(?<S>\d{2})',
        '(?<y>\d{4})[_\-](?<m>\d{2})[_\-](?<d>\d{2})',
        '(?<y>\d{4})(?<m>\d{2})(?<d>\d{2})'
    )
    foreach ($pat in $patterns) {
        if ($name -match $pat) {
            try {
                $y = [int]$Matches['y']; $mo = [int]$Matches['m']; $day = [int]$Matches['d']
                $H = if ($Matches['H']) { [int]$Matches['H'] } else { 0 }
                $Mi = if ($Matches['M']) { [int]$Matches['M'] } else { 0 }
                $S = if ($Matches['S']) { [int]$Matches['S'] } else { 0 }
                if ($mo -in 1..12 -and $day -in 1..31) {
                    return [datetime]::new($y, $mo, $day, $H, $Mi, $S)
                }
            }
            catch { }
        }
    }

    return $null
}

function Get-FileDate {
    param ([System.IO.FileInfo]$File)
    $exif = Get-ExifDateTaken -FilePath $File.FullName
    if ($null -ne $exif) { return @{ Date = $exif; Source = "EXIF" } }
    $earliest = if ($File.CreationTime -lt $File.LastWriteTime) { $File.CreationTime } else { $File.LastWriteTime }
    return @{ Date = $earliest; Source = "FILE" }
}

function Get-SubFolder {
    param ([datetime]$Date, [string]$Format)
    switch ($Format) {
        "1" { return $Date.ToString("yyyy") + "\" + $Date.ToString("MM-MMMM") }
        "2" { return $Date.ToString("yyyy") + "\" + $Date.ToString("MM") }
        "3" { return $Date.ToString("yyyy") + "\" + $Date.ToString("MMM") }
        default { return $Date.ToString("yyyy") + "\" + $Date.ToString("MM-MMMM") }
    }
}

function Get-UniqueDestPath {
    param ([string]$DestDir, [string]$FileName)
    $base = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    $ext = [System.IO.Path]::GetExtension($FileName)
    $candidate = Join-Path $DestDir $FileName
    $i = 1
    while (Test-Path -LiteralPath $candidate) {
        $candidate = Join-Path $DestDir ("{0}_{1:D3}{2}" -f $base, $i, $ext)
        $i++
        if ($i -gt 9999) { throw "Cannot find unique name for $FileName" }
    }
    return $candidate
}

function Invoke-Organize {
    param(
        [string] $Source,
        [string] $Destination,
        [bool]   $DoMove,
        [bool]   $DoRecurse,
        [bool]   $DryRun,
        [string] $FolderFormat,
        [string] $OnConflict,
        [string] $UndoLogPath,
        [string] $HtmlReportPath
    )

    $Verb = if ($DoMove) { "Moved" } else { "Copied" }

    Write-Section "Scanning source..."
    $gcArgs = @{ LiteralPath = $Source; File = $true }
    if ($DoRecurse) { $gcArgs['Recurse'] = $true }
    $allFiles = @(Get-ChildItem @gcArgs -ErrorAction SilentlyContinue |
        Where-Object { $script:SupportedAll -contains $_.Extension.ToLower() })
    $total = $allFiles.Count

    if ($total -eq 0) { Write-Warn "No supported media files found in: $Source"; return $null }
    Write-Info "Files found    :" "$total file(s) to process"

    $UndoEntries = [System.Collections.Generic.List[PSCustomObject]]::new()
    $processed = 0; $skipped = 0; $replaced = 0; $renamed = 0; $errored = 0; $counter = 0
    $padWidth = ([string]$total).Length
    $destHashCache = [System.Collections.Generic.HashSet[string]]::new()

    if (-not $DryRun -and $null -ne $UndoLogPath) {
        if ($DoMove) {
            "Action,SourcePath,DestinationPath,FileName,CreationTime,LastWriteTime,LastAccessTime" |
            Out-File -FilePath $UndoLogPath -Encoding UTF8
        }
        else {
            "Action,SourcePath,DestinationPath,FileName" |
            Out-File -FilePath $UndoLogPath -Encoding UTF8
        }
    }

    Write-Section "Processing files..."

    foreach ($file in $allFiles) {
        $counter++
        $progress = "[{0,$padWidth}/{1}]" -f $counter, $total

        $dateInfo = Get-FileDate -File $file
        $dateTaken = $dateInfo.Date
        $dateSource = $dateInfo.Source
        $subFolder = Get-SubFolder -Date $dateTaken -Format $FolderFormat
        $destDir = Join-Path -Path $Destination -ChildPath $subFolder

        if (-not $DryRun -and -not (Test-Path -LiteralPath $destDir)) {
            try { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
            catch {
                Write-Host "  $progress " -NoNewline -ForegroundColor DarkGray
                Write-Host " ERROR    " -NoNewline -ForegroundColor Red
                Write-Host " $($file.Name) -- Cannot create folder: $_" -ForegroundColor DarkGray
                $errored++; continue
            }
        }

        $destFile = Join-Path -Path $destDir -ChildPath $file.Name
        $sourceHash = $null
        $status = $null
        $finalDest = $destFile
        $skipFile = $false

        if (Test-Path -LiteralPath $destFile) {
            $sourceHash = Get-FileMD5 -FilePath $file.FullName
            $existHash = Get-FileMD5 -FilePath $destFile

            if ($null -ne $sourceHash -and $sourceHash -eq $existHash) {
                $status = "SKIPPED"; $skipFile = $true; $skipped++
            }
            else {
                switch ($OnConflict) {
                    "S" { $status = "SKIPPED"; $skipFile = $true; $skipped++ }
                    "R" {
                        if ($file.Length -gt (Get-Item -LiteralPath $destFile).Length) {
                            if (-not $DryRun) { Remove-Item -LiteralPath $destFile -Force }
                            $status = "REPLACED"; $replaced++
                        }
                        else {
                            $status = "SKIPPED"; $skipFile = $true; $skipped++
                        }
                    }
                    "N" {
                        $finalDest = Get-UniqueDestPath -DestDir $destDir -FileName $file.Name
                        $status = "RENAMED"; $renamed++
                    }
                }
            }
        }

        if (-not $skipFile -and $null -eq $sourceHash) {
            $sourceHash = Get-FileMD5 -FilePath $file.FullName
        }
        if (-not $skipFile -and $null -ne $sourceHash -and $destHashCache.Contains($sourceHash)) {
            $status = "SKIPPED"; $skipFile = $true; $skipped++
        }

        if (-not $skipFile) {
            try {
                if (-not $DryRun) {
                    if ($DoMove) {
                        $ctm = $file.CreationTime
                        $lwt = $file.LastWriteTime
                        $lat = $file.LastAccessTime

                        Move-Item -LiteralPath $file.FullName -Destination $finalDest -Force

                        $moved = Get-Item -LiteralPath $finalDest
                        $moved.CreationTime = $ctm
                        $moved.LastWriteTime = $lwt
                        $moved.LastAccessTime = $lat

                        $undoLine = "MOVE,{0},{1},{2},{3},{4},{5}" -f `
                            $file.FullName, $finalDest, $file.Name,
                        $ctm.ToString("o"), $lwt.ToString("o"), $lat.ToString("o")
                    }
                    else {
                        Copy-Item -LiteralPath $file.FullName -Destination $finalDest -Force

                        $undoLine = "COPY,{0},{1},{2}" -f `
                            $file.FullName, $finalDest, $file.Name
                    }
                    if ($null -ne $UndoLogPath) { $undoLine | Out-File -FilePath $UndoLogPath -Append -Encoding UTF8 }
                }

                if ($null -eq $status) { $status = if ($DryRun) { "WILL $($Verb.ToUpper())" } else { $Verb.ToUpper() } }
                $processed++
                if ($null -ne $sourceHash) { $destHashCache.Add($sourceHash) | Out-Null }

                $UndoEntries.Add([PSCustomObject]@{
                        Action      = if ($DoMove) { "MOVE" } else { "COPY" }
                        Source      = $file.FullName
                        Destination = $finalDest
                        FileName    = $file.Name
                        Date        = $dateTaken.ToString("yyyy-MM-dd HH:mm:ss")
                    })

            }
            catch {
                Write-Host "  $progress " -NoNewline -ForegroundColor DarkGray
                Write-Host " ERROR    " -NoNewline -ForegroundColor Red
                Write-Host " $($file.Name) -- $_" -ForegroundColor DarkGray
                $status = "ERROR"; $errored++; continue
            }
        }

        Write-Host "  $progress " -NoNewline -ForegroundColor DarkGray
        switch ($status) {
            "WILL MOVED" { Write-Host " WILL MOVE" -NoNewline -ForegroundColor Cyan }
            "WILL COPIED" { Write-Host " WILL COPY" -NoNewline -ForegroundColor Cyan }
            "MOVED" { Write-Host " MOVED    " -NoNewline -ForegroundColor Green }
            "COPIED" { Write-Host " COPIED   " -NoNewline -ForegroundColor Green }
            "REPLACED" { Write-Host " REPLACED " -NoNewline -ForegroundColor Yellow }
            "RENAMED" { Write-Host " RENAMED  " -NoNewline -ForegroundColor Cyan }
            "SKIPPED" { Write-Host " SKIPPED  " -NoNewline -ForegroundColor DarkGray }
            "ERROR" { Write-Host " ERROR    " -NoNewline -ForegroundColor Red }
            default { Write-Host " $status  " -NoNewline -ForegroundColor Gray }
        }
        Write-Host " $(if ($dateSource -eq 'EXIF'){'[EXIF]'} else {'[FILE]'}) " -NoNewline -ForegroundColor DarkGray
        Write-Host $file.Name -NoNewline -ForegroundColor White
        Write-Host "  ->  "   -NoNewline -ForegroundColor DarkGray
        if ($status -eq "RENAMED") {
            Write-Host "$subFolder\$([System.IO.Path]::GetFileName($finalDest))" -ForegroundColor DarkCyan
        }
        else {
            Write-Host $subFolder -ForegroundColor DarkCyan
        }
    }

    $elapsed = (Get-Date) - $SCRIPT_START
    $elapsedStr = "{0:mm\:ss}" -f $elapsed
    $divider = "=" * 62

    Write-Host ""
    Write-Host $divider -ForegroundColor DarkGray
    Write-Host "  SUMMARY$(if ($DryRun){' (TEST RUN -- nothing was changed)'})" -ForegroundColor Cyan
    Write-Host $divider -ForegroundColor DarkGray
    Write-Info "Total found    :" $total
    $summaryVerb = if ($DryRun) { "Will $Verb" } else { $Verb }
    Write-Info "$($summaryVerb.PadRight(12)) :" $processed
    Write-Info "Replaced       :" $replaced "Yellow"
    Write-Info "Renamed        :" $renamed  "Cyan"
    Write-Info "Skipped        :" $skipped  "DarkGray"
    Write-Info "Errors         :" $errored  $(if ($errored -gt 0) { "Red" } else { "White" })
    Write-Info "Elapsed        :" $elapsedStr
    Write-Host $divider -ForegroundColor DarkGray

    if (-not $DryRun -and $null -ne $HtmlReportPath) {
        $htmlRows = ($UndoEntries | ForEach-Object {
                $rc = if ($_.Action -eq "MOVE") { "moved" } else { "copied" }
                "<tr class='$rc'><td>$($_.FileName)</td><td>$($_.Action)</td><td>$($_.Date)</td><td>$($_.Source)</td><td>$($_.Destination)</td></tr>"
            }) -join "`n"

        $undoCmd = ".\undo.ps1 -Log `"$UndoLogPath`""
        $undoDesc = if ($DoMove) { "Moves all files back to their original locations and restores timestamps exactly." } `
            else { "Deletes all copied files from the destination. Your source files are not affected." }

        @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Image Organizer Report</title>
<style>
  * { box-sizing:border-box; margin:0; padding:0; }
  body { font-family:'Segoe UI',sans-serif; background:#0f1117; color:#cdd6f4; padding:2rem; }
  h1 { font-size:1.6rem; color:#89dceb; margin-bottom:0.3rem; }
  .meta { color:#6c7086; font-size:0.85rem; margin-bottom:2rem; }
  .stats { display:flex; gap:1rem; flex-wrap:wrap; margin-bottom:2rem; }
  .stat { background:#1e1e2e; border:1px solid #313244; border-radius:8px; padding:1rem 1.5rem; min-width:120px; }
  .stat .n { font-size:2rem; font-weight:700; }
  .stat .l { font-size:0.75rem; color:#6c7086; text-transform:uppercase; letter-spacing:0.05em; }
  .n.yellow { color:#f9e2af; } .n.cyan { color:#89dceb; }
  .n.red { color:#f38ba8; } .n.gray { color:#6c7086; }
  h2 { font-size:1rem; color:#89b4fa; margin:1.5rem 0 0.5rem; }
  table { width:100%; border-collapse:collapse; font-size:0.82rem; }
  th { background:#1e1e2e; color:#89b4fa; text-align:left; padding:0.5rem 0.75rem; border-bottom:1px solid #313244; }
  td { padding:0.4rem 0.75rem; border-bottom:1px solid #1e1e2e; word-break:break-all; }
  tr:hover td { background:#1e1e2e; }
  tr.moved td:nth-child(2) { color:#a6e3a1; }
  tr.copied td:nth-child(2) { color:#89dceb; }
  .undo-box { background:#1e1e2e; border:1px solid #313244; border-radius:8px; padding:1.2rem 1.5rem; margin-bottom:2rem; }
  .undo-box .undo-title { font-size:0.75rem; color:#6c7086; text-transform:uppercase; letter-spacing:0.08em; margin-bottom:0.4rem; }
  .undo-box .undo-desc  { font-size:0.82rem; color:#6c7086; margin-bottom:1rem; }
  .undo-cmd-row { display:flex; align-items:center; gap:0.75rem; }
  .undo-cmd { font-family:'Cascadia Code','Consolas',monospace; font-size:0.88rem; color:#89dceb;
              background:#0f1117; border:1px solid #313244; border-radius:5px;
              padding:0.55rem 1rem; flex:1; user-select:all; }
  .copy-btn { background:#313244; color:#cdd6f4; border:none; border-radius:5px;
              padding:0.55rem 1.1rem; font-size:0.82rem; cursor:pointer; white-space:nowrap;
              transition:background 0.15s; }
  .copy-btn:hover { background:#45475a; }
  .copy-btn.copied { background:#a6e3a1; color:#1e1e2e; }
</style>
</head>
<body>
<h1>&#128247; Image Organizer Report</h1>
<p class="meta">$($SCRIPT_START.ToString("yyyy-MM-dd HH:mm:ss")) &bull; Elapsed: $elapsedStr &bull; v$VERSION</p>
<div class="stats">
  <div class="stat"><div class="n gray">$total</div><div class="l">Found</div></div>
  <div class="stat"><div class="n">$processed</div><div class="l">$Verb</div></div>
  <div class="stat"><div class="n yellow">$replaced</div><div class="l">Replaced</div></div>
  <div class="stat"><div class="n cyan">$renamed</div><div class="l">Renamed</div></div>
  <div class="stat"><div class="n gray">$skipped</div><div class="l">Skipped</div></div>
  <div class="stat"><div class="n red">$errored</div><div class="l">Errors</div></div>
</div>
<div class="undo-box">
  <div class="undo-title">&#8635; Undo this run</div>
  <div class="undo-desc">$undoDesc</div>
  <div class="undo-cmd-row">
    <div class="undo-cmd" id="undoCmd">$undoCmd</div>
    <button class="copy-btn" onclick="copyUndo()">Copy</button>
  </div>
</div>
<h2>File Log</h2>
<table>
<thead><tr><th>File</th><th>Action</th><th>Date Taken</th><th>Source</th><th>Destination</th></tr></thead>
<tbody>$htmlRows</tbody>
</table>
<script>
  function copyUndo() {
    var cmd = document.getElementById('undoCmd').innerText;
    navigator.clipboard.writeText(cmd).then(function() {
      var btn = document.querySelector('.copy-btn');
      btn.textContent = 'Copied!';
      btn.classList.add('copied');
      setTimeout(function() { btn.textContent = 'Copy'; btn.classList.remove('copied'); }, 2000);
    });
  }
</script>
</body>
</html>
"@ | Out-File -FilePath $HtmlReportPath -Encoding UTF8
    }

    return @{ Processed = $processed; Skipped = $skipped; Errored = $errored; Total = $total }
}

Write-Header

Write-Section "Configuration"

if ($HardSource -ne "") {
    $Source = $HardSource
    Write-Info "Source         :" $Source
}
else {
    Write-Host "  Enter Source path : " -NoNewline -ForegroundColor Gray
    $Source = (Read-Host).Trim()
}
if (-not (Test-Path -LiteralPath $Source)) { Write-Err "Source path does not exist: $Source"; exit 1 }

if ($HardDestination -ne "") {
    $Destination = $HardDestination
    Write-Info "Destination    :" $Destination
}
else {
    Write-Host "  Enter Destination path : " -NoNewline -ForegroundColor Gray
    $Destination = (Read-Host).Trim()
}

$srcFull = (Resolve-Path -LiteralPath $Source).Path.TrimEnd('\')
$dstFull = if (Test-Path -LiteralPath $Destination) { (Resolve-Path -LiteralPath $Destination).Path.TrimEnd('\') } else { $Destination.TrimEnd('\') }
if ($srcFull -ieq $dstFull) { Write-Err "Source and Destination cannot be the same path."; exit 1 }

if ($HardAction -ne "") {
    $Action = $HardAction.ToUpper()
}
else {
    $Action = Read-Choice "Move or Copy?" @("M", "C")
}
if ($Action -notin @("M", "C")) { Write-Err "Invalid action '$Action'"; exit 1 }
$DoMove = ($Action -eq "M")
$Verb = if ($DoMove) { "Moved" } else { "Copied" }

if ($HardRecurse -ne "") {
    $RecurseInput = $HardRecurse.ToUpper()
}
else {
    $subDirs = @(Get-ChildItem -LiteralPath $Source -Directory -ErrorAction SilentlyContinue)
    if ($subDirs.Count -gt 0) {
        Write-Host "  Subfolders found:" -ForegroundColor Gray
        $subDirs | Select-Object -First 10 | ForEach-Object { Write-Host "    - $($_.Name)" -ForegroundColor DarkGray }
        if ($subDirs.Count -gt 10) { Write-Host "    ... and $($subDirs.Count - 10) more" -ForegroundColor DarkGray }
    }
    $RecurseInput = Read-Choice "Include subfolders?" @("Y", "N")
}
if ($RecurseInput -notin @("Y", "N")) { Write-Err "Invalid choice '$RecurseInput'"; exit 1 }
$DoRecurse = ($RecurseInput -eq "Y")

if ($HardDryRun -ne "") {
    $DryRunInput = $HardDryRun.ToUpper()
}
else {
    Write-Host ""
    Write-Host "  Test run? (shows what will happen without touching any files)" -ForegroundColor Gray
    $DryRunInput = Read-Choice "Proceed" @("Y", "N") "N"
}
$DryRun = ($DryRunInput -eq "Y")

Write-Host ""
Write-Info "Action         :" $(if ($DoMove) { "Move" } else { "Copy" })
Write-Info "Subfolders     :" $(if ($DoRecurse) { "Yes" } else { "No" })
if ($DryRun) { Write-Info "Mode           :" "TEST RUN - nothing will be changed" "Yellow" }

$LogDir = Join-Path $Destination "_organizer_logs"
$UndoLogPath = Join-Path $LogDir "undo_$LOG_TIMESTAMP.csv"
$HtmlReportPath = Join-Path $LogDir "report_$LOG_TIMESTAMP.html"

if (-not $DryRun) {
    if (-not (Test-Path -LiteralPath $LogDir)) {
        try {
            New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
        }
        catch {
            Write-Warn "Cannot create log directory '$LogDir': $($_.Exception.Message). Logs will be skipped."
            $UndoLogPath = $null
            $HtmlReportPath = $null
        }
    }
}

$result = Invoke-Organize `
    -Source         $Source `
    -Destination    $Destination `
    -DoMove         $DoMove `
    -DoRecurse      $DoRecurse `
    -DryRun         $DryRun `
    -FolderFormat   $FolderFormat `
    -OnConflict     $OnConflict `
    -UndoLogPath    $UndoLogPath `
    -HtmlReportPath $HtmlReportPath

$cancelled = $false

if ($DryRun -and $null -ne $result) {
    Write-Host ""
    Write-Host "  This was a test run. No files were touched." -ForegroundColor Yellow
    Write-Host ""
    $go = Read-Choice "Ready to run the real $($Verb.ToLower()) now?" @("Y", "N") "N"

    if ($go -eq "Y") {
        Write-Host ""
        Write-Host "  Starting real run..." -ForegroundColor Cyan

        if (-not (Test-Path -LiteralPath $LogDir)) {
            try {
                New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
            }
            catch {
                Write-Warn "Cannot create log directory: $($_.Exception.Message). Logs will be skipped."
                $UndoLogPath = $null
                $HtmlReportPath = $null
            }
        }

        $result = Invoke-Organize `
            -Source         $Source `
            -Destination    $Destination `
            -DoMove         $DoMove `
            -DoRecurse      $DoRecurse `
            -DryRun         $false `
            -FolderFormat   $FolderFormat `
            -OnConflict     $OnConflict `
            -UndoLogPath    $UndoLogPath `
            -HtmlReportPath $HtmlReportPath

        if ($null -ne $UndoLogPath -and (Test-Path -LiteralPath $UndoLogPath)) {
            $undoDesc = if ($DoMove) { "move all files back to their original locations" } `
                else { "delete all copied files from destination" }
            Write-Host ""
            Write-Host "  Report saved : $HtmlReportPath" -ForegroundColor DarkGray
            Write-Host ""
            Write-Host "  To undo ($undoDesc):" -ForegroundColor Gray
            Write-Host "  .\undo.ps1 -Log `"$UndoLogPath`"" -ForegroundColor Cyan
        }
    }
    else {
        $cancelled = $true
        $result = $null
        Write-Host ""
        Write-Host "  Cancelled. No files were changed." -ForegroundColor DarkGray
    }

}
elseif (-not $DryRun -and $null -ne $result) {
    if ($null -ne $UndoLogPath -and (Test-Path -LiteralPath $UndoLogPath)) {
        $undoDesc = if ($DoMove) { "move all files back to their original locations" } `
            else { "delete all copied files from destination" }
        Write-Host ""
        Write-Host "  Report saved : $HtmlReportPath" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  To undo ($undoDesc):" -ForegroundColor Gray
        Write-Host "  .\undo.ps1 -Log `"$UndoLogPath`"" -ForegroundColor Cyan
    }
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
        $balloon.BalloonTipTitle = "Image Organizer"
        $balloon.BalloonTipText = "Cancelled. No files were changed."
        $balloon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
        $balloon.ShowBalloonTip(4000)
        Start-Sleep -Milliseconds 4500
    }
    elseif ($null -ne $result) {
        $balloon.BalloonTipTitle = "Image Organizer Done"
        $balloon.BalloonTipText = "$($result.Processed) $Verb, $($result.Skipped) skipped, $($result.Errored) error(s)"
        $balloon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
        $balloon.ShowBalloonTip(4000)
        Start-Sleep -Milliseconds 4500
    }
    $balloon.Dispose()
}
catch { }
