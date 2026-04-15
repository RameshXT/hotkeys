#Requires -Version 5.1
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$HardSource        = ""
$HardDestination   = ""
$HardAction        = ""
$HardRecurse       = ""
$HardDryRun        = ""

$FolderFormat      = "1"
$OnConflict        = "R"

$VERSION           = "2.1"
$SCRIPT_START      = Get-Date
$LOG_TIMESTAMP     = $SCRIPT_START.ToString("yyyyMMdd_HHmmss")

$SupportedImages   = @('.jpg','.jpeg','.png','.heic','.raw','.bmp','.tiff','.tif','.webp','.gif','.cr2','.nef','.arw','.dng')
$SupportedVideos   = @('.mp4','.mov','.avi','.mkv','.m4v','.wmv','.3gp','.flv','.mpg','.mpeg')
$SupportedAll      = $SupportedImages + $SupportedVideos
$script:SystemDrawingLoaded = $false

function Write-Header {
    $w    = 62
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

function Ensure-SystemDrawingLoaded {
    if (-not $script:SystemDrawingLoaded) {
        Add-Type -AssemblyName System.Drawing
        $script:SystemDrawingLoaded = $true
    }
}

function ConvertTo-HtmlText {
    param([AllowNull()][string]$Text)
    return [System.Net.WebUtility]::HtmlEncode($Text)
}

function Write-UndoRecord {
    param(
        [Parameter(Mandatory)][string]$UndoLogPath,
        [Parameter(Mandatory)][pscustomobject]$Record
    )

    $csvArgs = @{
        LiteralPath       = $UndoLogPath
        NoTypeInformation = $true
        Encoding          = 'UTF8'
    }
    if (Test-Path -LiteralPath $UndoLogPath) {
        $csvArgs['Append'] = $true
    }

    $Record | Export-Csv @csvArgs
}

function Prompt-Choice {
    param([string]$Question, [string[]]$Valid, [string]$Default = "")
    $wordMap = @{
        "MOVE" = "M"; "COPY" = "C"
        "YES"  = "Y"; "NO"   = "N"
    }
    do {
        $hint   = if ($Default) { " [$($Valid -join '/'), default=$Default]" } else { " [$($Valid -join '/')]" }
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
        $md5    = [System.Security.Cryptography.MD5]::Create()
        $stream = [System.IO.File]::OpenRead($FilePath)
        try {
            $hashBytes = $md5.ComputeHash($stream)
            return [BitConverter]::ToString($hashBytes).Replace("-","").ToLower()
        } finally { $stream.Close(); $md5.Dispose() }
    } catch { return $null }
}

function Get-ExifDateTaken {
    param ([string]$FilePath)

    $ext = [System.IO.Path]::GetExtension($FilePath).ToLower()

    if ($ext -in @('.jpg','.jpeg','.png','.bmp','.gif','.tiff','.tif')) {
        try {
            Ensure-SystemDrawingLoaded
            $image = [System.Drawing.Image]::FromFile($FilePath)
            try {
                $prop       = $image.GetPropertyItem(36867)
                $dateString = [System.Text.Encoding]::ASCII.GetString($prop.Value).TrimEnd([char]0)
                if ($dateString -match '^(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})$') {
                    return [datetime]"$($Matches[1])-$($Matches[2])-$($Matches[3]) $($Matches[4]):$($Matches[5]):$($Matches[6])"
                }
            } catch { }
            finally { $image.Dispose() }
        } catch { }
    }

    $name     = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
    $patterns = @(
        '(?<y>\d{4})(?<m>\d{2})(?<d>\d{2})[_\-](?<H>\d{2})(?<M>\d{2})(?<S>\d{2})',
        '(?<y>\d{4})[_\-](?<m>\d{2})[_\-](?<d>\d{2})',
        '(?<y>\d{4})(?<m>\d{2})(?<d>\d{2})'
    )
    foreach ($pat in $patterns) {
        if ($name -match $pat) {
            try {
                $y  = [int]$Matches['y']; $mo = [int]$Matches['m']; $day = [int]$Matches['d']
                $H  = if ($Matches['H']) { [int]$Matches['H'] } else { 0 }
                $Mi = if ($Matches['M']) { [int]$Matches['M'] } else { 0 }
                $S  = if ($Matches['S']) { [int]$Matches['S'] } else { 0 }
                if ($mo -in 1..12 -and $day -in 1..31) {
                    return [datetime]::new($y, $mo, $day, $H, $Mi, $S)
                }
            } catch { }
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
        "1"     { return $Date.ToString("yyyy") + "\" + $Date.ToString("MM-MMMM") }
        "2"     { return $Date.ToString("yyyy") + "\" + $Date.ToString("MM") }
        "3"     { return $Date.ToString("yyyy") + "\" + $Date.ToString("MMM") }
        default { return $Date.ToString("yyyy") + "\" + $Date.ToString("MM-MMMM") }
    }
}

function Get-UniqueDestPath {
    param ([string]$DestDir, [string]$FileName)
    $base      = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    $ext       = [System.IO.Path]::GetExtension($FileName)
    $candidate = Join-Path $DestDir $FileName
    $i         = 1
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

    $UndoEntries   = [System.Collections.Generic.List[PSCustomObject]]::new()
    $processed     = 0; $skipped = 0; $replaced = 0; $renamed = 0; $errored = 0; $counter = 0
    $padWidth      = ([string]$total).Length
    $destHashCache = [System.Collections.Generic.HashSet[string]]::new()

    Write-Section "Processing files..."

    foreach ($file in $allFiles) {
        $counter++
        $progress = "[{0,$padWidth}/{1}]" -f $counter, $total

        $dateInfo   = Get-FileDate -File $file
        $dateTaken  = $dateInfo.Date
        $dateSource = $dateInfo.Source
        $subFolder  = Get-SubFolder -Date $dateTaken -Format $FolderFormat
        $destDir    = Join-Path -Path $Destination -ChildPath $subFolder

        if (-not $DryRun -and -not (Test-Path -LiteralPath $destDir)) {
            try { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
            catch {
                Write-Host "  $progress " -NoNewline -ForegroundColor DarkGray
                Write-Host " ERROR    " -NoNewline -ForegroundColor Red
                Write-Host " $($file.Name) -- Cannot create folder: $_" -ForegroundColor DarkGray
                $errored++; continue
            }
        }

        $destFile   = Join-Path -Path $destDir -ChildPath $file.Name
        $sourceHash = $null
        $status     = $null
        $finalDest  = $destFile
        $skipFile   = $false

        if (Test-Path -LiteralPath $destFile) {
            $sourceHash = Get-FileMD5 -FilePath $file.FullName
            $existHash  = Get-FileMD5 -FilePath $destFile

            if ($null -ne $sourceHash -and $sourceHash -eq $existHash) {
                $status = "SKIPPED"; $skipFile = $true; $skipped++
            } else {
                switch ($OnConflict) {
                    "S" { $status = "SKIPPED"; $skipFile = $true; $skipped++ }
                    "R" {
                        if ($file.Length -gt (Get-Item -LiteralPath $destFile).Length) {
                            if (-not $DryRun) { Remove-Item -LiteralPath $destFile -Force }
                            $status = "REPLACED"; $replaced++
                        } else {
                            $status = "SKIPPED"; $skipFile = $true; $skipped++
                        }
                    }
                    "N" {
                        $finalDest = Get-UniqueDestPath -DestDir $destDir -FileName $file.Name
                        $status    = "RENAMED"; $renamed++
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

                        $moved                = Get-Item -LiteralPath $finalDest
                        $moved.CreationTime   = $ctm
                        $moved.LastWriteTime  = $lwt
                        $moved.LastAccessTime = $lat
                    } else {
                        Copy-Item -LiteralPath $file.FullName -Destination $finalDest -Force
                    }
                    if ($null -ne $UndoLogPath) {
                        $undoRecord = [PSCustomObject]@{
                            Action         = if ($DoMove) { "MOVE" } else { "COPY" }
                            SourcePath     = $file.FullName
                            DestinationPath= $finalDest
                            FileName       = $file.Name
                            CreationTime   = if ($DoMove) { $ctm.ToString("o") } else { $null }
                            LastWriteTime  = if ($DoMove) { $lwt.ToString("o") } else { $null }
                            LastAccessTime = if ($DoMove) { $lat.ToString("o") } else { $null }
                        }
                        Write-UndoRecord -UndoLogPath $UndoLogPath -Record $undoRecord
                    }
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

            } catch {
                Write-Host "  $progress " -NoNewline -ForegroundColor DarkGray
                Write-Host " ERROR    " -NoNewline -ForegroundColor Red
                Write-Host " $($file.Name) -- $_" -ForegroundColor DarkGray
                $status = "ERROR"; $errored++; continue
            }
        }

        Write-Host "  $progress " -NoNewline -ForegroundColor DarkGray
        switch ($status) {
            "WILL MOVED"  { Write-Host " WILL MOVE" -NoNewline -ForegroundColor Cyan }
            "WILL COPIED" { Write-Host " WILL COPY" -NoNewline -ForegroundColor Cyan }
            "MOVED"    { Write-Host " MOVED    " -NoNewline -ForegroundColor Green }
            "COPIED"   { Write-Host " COPIED   " -NoNewline -ForegroundColor Green }
            "REPLACED" { Write-Host " REPLACED " -NoNewline -ForegroundColor Yellow }
            "RENAMED"  { Write-Host " RENAMED  " -NoNewline -ForegroundColor Cyan }
            "SKIPPED"  { Write-Host " SKIPPED  " -NoNewline -ForegroundColor DarkGray }
            "ERROR"    { Write-Host " ERROR    " -NoNewline -ForegroundColor Red }
            default    { Write-Host " $status  " -NoNewline -ForegroundColor Gray }
        }
        Write-Host " $(if ($dateSource -eq 'EXIF'){'[EXIF]'} else {'[FILE]'}) " -NoNewline -ForegroundColor DarkGray
        Write-Host $file.Name -NoNewline -ForegroundColor White
        Write-Host "  ->  "   -NoNewline -ForegroundColor DarkGray
        if ($status -eq "RENAMED") {
            Write-Host "$subFolder\$([System.IO.Path]::GetFileName($finalDest))" -ForegroundColor DarkCyan
        } else {
            Write-Host $subFolder -ForegroundColor DarkCyan
        }
    }

    $elapsed    = (Get-Date) - $SCRIPT_START
    $elapsedStr = "{0:mm\:ss}" -f $elapsed
    $divider    = "=" * 62

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
    Write-Info "Errors         :" $errored  $(if ($errored -gt 0){"Red"} else {"White"})
    Write-Info "Elapsed        :" $elapsedStr
    Write-Host $divider -ForegroundColor DarkGray

    if (-not $DryRun -and $null -ne $HtmlReportPath) {
        $htmlRows = ($UndoEntries | ForEach-Object {
            $rc = if ($_.Action -eq "MOVE") { "moved" } else { "copied" }
            "<tr class='$rc'><td>$(ConvertTo-HtmlText $_.FileName)</td><td>$(ConvertTo-HtmlText $_.Action)</td><td>$(ConvertTo-HtmlText $_.Date)</td><td>$(ConvertTo-HtmlText $_.Source)</td><td>$(ConvertTo-HtmlText $_.Destination)</td></tr>"
        }) -join "`n"

        $undoCmd     = ".\undo.ps1 -Log `"$UndoLogPath`""
        $undoDesc    = if ($DoMove) { "Moves all files back to their original locations and restores timestamps exactly." } `
                                    else { "Deletes all copied files from the destination. Your source files are not affected." }
        $runSummary  = if ($DoMove) {
            "Files were moved from $Source to $Destination and organized into date-based folders."
        } else {
            "Files were copied from $Source to $Destination and organized into date-based folders."
        }

        @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Image Organizer Report</title>
<style>
  :root {
    --bg: #e9edf2;
    --bg-deep: #dfe5eb;
    --surface: rgba(255,255,255,0.34);
    --surface-strong: rgba(255,255,255,0.52);
    --text: #152033;
    --muted: #61708a;
    --line: rgba(21,32,51,0.12);
    --accent: #0f766e;
    --warn: #a16207;
    --danger: #b42318;
    --credit: #EF233C;
    color-scheme: light dark;

  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    font-family: 'Segoe UI', 'Helvetica Neue', sans-serif;
    color: var(--text);
    background:
      radial-gradient(circle at top left, rgba(255,255,255,0.65) 0, transparent 34%),
      radial-gradient(circle at bottom right, rgba(15,118,110,0.06) 0, transparent 24%),
      linear-gradient(180deg, var(--bg) 0%, var(--bg-deep) 100%);
    padding: 32px 20px 48px;
    position: relative;
  }
  body::before {
    content: "";
    position: fixed;
    inset: 0;
    pointer-events: none;
    opacity: 0.14;
    background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='160' height='160' viewBox='0 0 160 160'%3E%3Cg fill='%23000000' fill-opacity='0.18'%3E%3Ccircle cx='16' cy='18' r='1'/%3E%3Ccircle cx='58' cy='40' r='1'/%3E%3Ccircle cx='96' cy='24' r='1'/%3E%3Ccircle cx='134' cy='54' r='1'/%3E%3Ccircle cx='126' cy='118' r='1'/%3E%3Ccircle cx='64' cy='122' r='1'/%3E%3Ccircle cx='24' cy='102' r='1'/%3E%3C/g%3E%3C/svg%3E");
  }
  .wrap {
    max-width: 1220px;
    margin: 0 auto;
    position: relative;
    z-index: 1;
  }
  .hero {
    padding: 8px 0 28px;
    margin-bottom: 26px;
    border-bottom: 1px solid var(--line);
  }
  .eyebrow {
    font-size: 12px;
    text-transform: uppercase;
    letter-spacing: 0.14em;
    color: var(--accent);
    margin-bottom: 10px;
    font-weight: 700;
  }
  h1 {
    font-size: clamp(28px, 4vw, 40px);
    line-height: 1.05;
    margin-bottom: 10px;
    font-weight: 700;
  }
  .meta {
    color: var(--muted);
    font-size: 14px;
    line-height: 1.6;
  }
  .summary-note {
    margin-top: 14px;
    max-width: 820px;
    color: var(--muted);
    font-size: 15px;
    line-height: 1.7;
  }
  .stats {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
    gap: 14px;
    margin: 24px 0 0;
  }
  .stat {
    background: linear-gradient(180deg, var(--surface-strong) 0%, var(--surface) 100%);
    border: 1px solid var(--line);
    border-radius: 0;
    padding: 18px 18px 16px;
    box-shadow: none;
  }
  .stat .n {
    font-size: 32px;
    line-height: 1;
    font-weight: 700;
    margin-bottom: 8px;
  }
  .stat .l {
    font-size: 12px;
    color: var(--muted);
    text-transform: uppercase;
    letter-spacing: 0.08em;
  }
  .n.yellow { color: var(--warn); }
  .n.cyan { color: var(--accent); }
  .n.red { color: var(--danger); }
  .n.gray { color: var(--muted); }
  .section {
    margin-bottom: 28px;
  }
  h2 {
    font-size: 18px;
    margin-bottom: 14px;
    font-weight: 650;
  }
  .undo-shell {
    padding: 20px 0 22px;
    border-top: 1px solid var(--line);
    border-bottom: 1px solid var(--line);
  }
  .undo-desc {
    color: var(--muted);
    font-size: 14px;
    line-height: 1.6;
    margin-bottom: 16px;
  }
  .undo-cmd-row {
    display: flex;
    align-items: stretch;
    gap: 12px;
    flex-wrap: wrap;
  }
  .undo-cmd {
    flex: 1 1 520px;
    min-height: 52px;
    display: flex;
    align-items: center;
    padding: 14px 16px;
    border-radius: 0;
    border: 1px solid var(--line);
    background: rgba(255,255,255,0.34);
    color: #124e49;
    font-family: 'Cascadia Code', 'Consolas', monospace;
    font-size: 13px;
    user-select: all;
    word-break: break-all;
  }
  .copy-btn {
    border: none;
    border-radius: 0;
    background: var(--accent);
    color: #ffffff;
    padding: 0 20px;
    min-height: 52px;
    font-size: 14px;
    font-weight: 600;
    cursor: pointer;
    transition: background 0.15s ease, opacity 0.15s ease;
  }
  .copy-btn:hover { background: #0d6a63; opacity: 0.98; }
  .copy-btn.copied { background: #1f9d73; }
  .table-wrap {
    overflow: auto;
    border-top: 1px solid var(--line);
    border-bottom: 1px solid var(--line);
    background: transparent;
  }
  table {
    width: 100%;
    border-collapse: collapse;
    font-size: 13px;
  }
  th {
    position: sticky;
    top: 0;
    background: rgba(233,237,242,0.96);
    color: var(--muted);
    text-align: left;
    padding: 14px 16px;
    border-bottom: 1px solid var(--line);
    text-transform: uppercase;
    letter-spacing: 0.06em;
    font-size: 11px;
    font-weight: 700;
  }
  td {
    padding: 13px 16px;
    border-bottom: 1px solid #e8edf4;
    vertical-align: top;
    word-break: break-word;
  }
  tr:last-child td { border-bottom: none; }
  tr.moved td:nth-child(2),
  tr.copied td:nth-child(2) {
    font-weight: 700;
    color: var(--accent);
  }
  .credit {
    margin-top: 34px;
    padding-top: 18px;
    border-top: 1px solid var(--line);
    font-size: 13px;
    color: var(--muted);
  }
  .credit a {
    color: var(--credit);
    text-decoration: none;
    font-weight: 700;
  }
  @media (max-width: 760px) {
    body { padding: 18px 12px 32px; }
    .undo-cmd-row { flex-direction: column; }
    .copy-btn { width: 100%; }
    th, td { padding: 11px 12px; }
  }
</style>
</head>
<body>
<div class="wrap">
  <section class="hero">
    <div class="eyebrow">Image Organizer Report</div>
    <h1>Run Summary</h1>
    <p class="meta">$($SCRIPT_START.ToString("yyyy-MM-dd HH:mm:ss")) &bull; Elapsed: $elapsedStr &bull; v$VERSION</p>
    <p class="summary-note">$(ConvertTo-HtmlText $runSummary)</p>
    <div class="stats">
      <div class="stat"><div class="n gray">$total</div><div class="l">Found</div></div>
      <div class="stat"><div class="n">$processed</div><div class="l">$Verb</div></div>
      <div class="stat"><div class="n yellow">$replaced</div><div class="l">Replaced</div></div>
      <div class="stat"><div class="n cyan">$renamed</div><div class="l">Renamed</div></div>
      <div class="stat"><div class="n gray">$skipped</div><div class="l">Skipped</div></div>
      <div class="stat"><div class="n red">$errored</div><div class="l">Errors</div></div>
    </div>
  </section>
  <section class="section">
    <h2>Undo This Run</h2>
    <div class="undo-shell">
      <div class="undo-desc">$(ConvertTo-HtmlText $undoDesc)</div>
      <div class="undo-cmd-row">
        <div class="undo-cmd" id="undoCmd">$(ConvertTo-HtmlText $undoCmd)</div>
        <button class="copy-btn" onclick="copyUndo()">Copy</button>
      </div>
    </div>
  </section>
  <section class="section">
    <h2>File Log</h2>
    <div class="table-wrap">
      <table>
      <thead><tr><th>File</th><th>Action</th><th>Date Taken</th><th>Source</th><th>Destination</th></tr></thead>
      <tbody>$htmlRows</tbody>
      </table>
    </div>
  </section>
  <footer class="credit">
    Designed & developed by
    <a href="https://rameshxt.pages.dev/" target="_blank" rel="noopener noreferrer">Ramesh XT</a>
  </footer>
  </div>
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
} else {
    Write-Host "  Enter Source path : " -NoNewline -ForegroundColor Gray
    $Source = (Read-Host).Trim()
}
if (-not (Test-Path -LiteralPath $Source)) { Write-Err "Source path does not exist: $Source"; exit 1 }

if ($HardDestination -ne "") {
    $Destination = $HardDestination
    Write-Info "Destination    :" $Destination
} else {
    Write-Host "  Enter Destination path : " -NoNewline -ForegroundColor Gray
    $Destination = (Read-Host).Trim()
}

$srcFull = (Resolve-Path -LiteralPath $Source).Path.TrimEnd('\')
$dstFull = if (Test-Path -LiteralPath $Destination) { (Resolve-Path -LiteralPath $Destination).Path.TrimEnd('\') } else { $Destination.TrimEnd('\') }
if ($srcFull -ieq $dstFull) { Write-Err "Source and Destination cannot be the same path."; exit 1 }

if ($HardAction -ne "") {
    $Action = $HardAction.ToUpper()
} else {
    $Action = Prompt-Choice "Move or Copy?" @("M","C")
}
if ($Action -notin @("M","C")) { Write-Err "Invalid action '$Action'"; exit 1 }
$DoMove = ($Action -eq "M")
$Verb   = if ($DoMove) { "Moved" } else { "Copied" }

if ($HardRecurse -ne "") {
    $RecurseInput = $HardRecurse.ToUpper()
} else {
    $subDirs = @(Get-ChildItem -LiteralPath $Source -Directory -ErrorAction SilentlyContinue)
    if ($subDirs.Count -gt 0) {
        Write-Host "  Subfolders found:" -ForegroundColor Gray
        $subDirs | Select-Object -First 10 | ForEach-Object { Write-Host "    - $($_.Name)" -ForegroundColor DarkGray }
        if ($subDirs.Count -gt 10) { Write-Host "    ... and $($subDirs.Count - 10) more" -ForegroundColor DarkGray }
    }
    $RecurseInput = Prompt-Choice "Include subfolders?" @("Y","N")
}
if ($RecurseInput -notin @("Y","N")) { Write-Err "Invalid choice '$RecurseInput'"; exit 1 }
$DoRecurse = ($RecurseInput -eq "Y")

if ($HardDryRun -ne "") {
    $DryRunInput = $HardDryRun.ToUpper()
} else {
    Write-Host ""
    Write-Host "  Test run? (shows what will happen without touching any files)" -ForegroundColor Gray
    $DryRunInput = Prompt-Choice "Proceed" @("Y","N") "N"
}
$DryRun = ($DryRunInput -eq "Y")

Write-Host ""
Write-Info "Action         :" $(if ($DoMove){"Move"} else {"Copy"})
Write-Info "Subfolders     :" $(if ($DoRecurse){"Yes"} else {"No"})
if ($DryRun) { Write-Info "Mode           :" "TEST RUN - nothing will be changed" "Yellow" }

$LogDir         = Join-Path $Destination "_organizer_logs"
$UndoLogPath    = Join-Path $LogDir "undo_$LOG_TIMESTAMP.csv"
$HtmlReportPath = Join-Path $LogDir "report_$LOG_TIMESTAMP.html"

if (-not $DryRun) {
    if (-not (Test-Path -LiteralPath $LogDir)) {
        try {
            New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
        } catch {
            Write-Warn "Cannot create log directory '$LogDir': $($_.Exception.Message). Logs will be skipped."
            $UndoLogPath    = $null
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
    $go = Prompt-Choice "Ready to run the real $($Verb.ToLower()) now?" @("Y","N") "N"

    if ($go -eq "Y") {
        Write-Host ""
        Write-Host "  Starting real run..." -ForegroundColor Cyan

        if (-not (Test-Path -LiteralPath $LogDir)) {
            try {
                New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
            } catch {
                Write-Warn "Cannot create log directory: $($_.Exception.Message). Logs will be skipped."
                $UndoLogPath    = $null
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
    } else {
        $cancelled = $true
        $result    = $null
        Write-Host ""
        Write-Host "  Cancelled. No files were changed." -ForegroundColor DarkGray
    }

} elseif (-not $DryRun -and $null -ne $result) {
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
    $balloon         = [System.Windows.Forms.NotifyIcon]::new()
    $balloon.Icon    = [System.Drawing.SystemIcons]::Information
    $balloon.Visible = $true
    if ($cancelled) {
        $balloon.BalloonTipTitle = "Image Organizer"
        $balloon.BalloonTipText  = "Cancelled. No files were changed."
        $balloon.BalloonTipIcon  = [System.Windows.Forms.ToolTipIcon]::Info
        $balloon.ShowBalloonTip(4000)
        Start-Sleep -Milliseconds 4500
    } elseif ($null -ne $result) {
        $balloon.BalloonTipTitle = "Image Organizer Done"
        $balloon.BalloonTipText  = "$($result.Processed) $Verb, $($result.Skipped) skipped, $($result.Errored) error(s)"
        $balloon.BalloonTipIcon  = [System.Windows.Forms.ToolTipIcon]::Info
        $balloon.ShowBalloonTip(4000)
        Start-Sleep -Milliseconds 4500
    }
    $balloon.Dispose()
} catch { }
