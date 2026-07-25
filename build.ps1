#Requires -Version 5.1
$ErrorActionPreference = "Stop"

# Paths
$RepoRoot = $PSScriptRoot
if (-not $RepoRoot) { $RepoRoot = Get-Location }

$BuildDir = Join-Path $RepoRoot "build"
$DistDir = Join-Path $RepoRoot "dist"
$Ahk2ExeZip = Join-Path $BuildDir "ahk2exe.zip"
$Ahk2ExeDir = Join-Path $BuildDir "ahk2exe"
$CompilerExe = Join-Path $Ahk2ExeDir "Ahk2Exe.exe"
$OutputFile = Join-Path $DistDir "hotkeys.exe"
$ZipRelease = Join-Path $DistDir "hotkeys.zip"

Write-Host "Creating build directories..." -ForegroundColor Cyan
if (Test-Path $BuildDir) { Remove-Item $BuildDir -Recurse -Force }
if (Test-Path $DistDir) { Remove-Item $DistDir -Recurse -Force }
New-Item -ItemType Directory -Path $BuildDir | Out-Null
New-Item -ItemType Directory -Path $DistDir | Out-Null

# 1. Detect AutoHotkey v2 Bin Path
$ahkPaths = @(
    "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe",
    "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey32.exe",
    "$env:LocalAppData\Programs\AutoHotkey\v2\AutoHotkey64.exe"
)
$ahkBin = $null
foreach ($path in $ahkPaths) {
    if (Test-Path $path) {
        $ahkBin = $path
        break
    }
}

if ($null -eq $ahkBin) {
    Write-Host "AutoHotkey v2 not found locally. Downloading portable AHK v2..." -ForegroundColor Yellow
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $ahkZip = Join-Path $BuildDir "ahk-v2.zip"
    $ahkDir = Join-Path $BuildDir "ahk-v2"
    $webClient = New-Object System.Net.WebClient
    $webClient.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
    try {
        $webClient.DownloadFile("https://www.autohotkey.com/download/ahk-v2.zip", $ahkZip)
        Expand-Archive -Path $ahkZip -DestinationPath $ahkDir -Force
        
        $ahkBin = Join-Path $ahkDir "AutoHotkey64.exe"
        if (-not (Test-Path $ahkBin)) {
            $ahkBin = Join-Path $ahkDir "AutoHotkey32.exe"
        }
    } catch {
        Write-Error "Failed to download and extract portable AHK v2: $_"
        exit 1
    }
}
Write-Host "Using AutoHotkey v2 base bin at: $ahkBin" -ForegroundColor Green

# 2. Download Ahk2Exe Compiler
Write-Host "Fetching latest compiler version from GitHub API..." -ForegroundColor Cyan
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
try {
    $apiResponse = Invoke-RestMethod -Uri "https://api.github.com/repos/AutoHotkey/Ahk2Exe/releases/latest"
    $zipAsset = $apiResponse.assets | Where-Object { $_.name -like "*.zip" } | Select-Object -First 1
    $downloadUrl = $zipAsset.browser_download_url
    Write-Host "Downloading AutoHotkey Compiler from: $downloadUrl" -ForegroundColor Green
    $webClient = New-Object System.Net.WebClient
    $webClient.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
    $webClient.DownloadFile($downloadUrl, $Ahk2ExeZip)
} catch {
    Write-Error "Failed to download compiler: $_"
    exit 1
}

Write-Host "Extracting compiler..." -ForegroundColor Cyan
Expand-Archive -Path $Ahk2ExeZip -DestinationPath $Ahk2ExeDir -Force

if (-not (Test-Path $CompilerExe)) {
    Write-Error "Ahk2Exe.exe was not found in the extracted files."
    exit 1
}

# 3. Compile hotkeys.ahk to hotkeys.exe
Write-Host "Compiling hotkeys.ahk to hotkeys.exe..." -ForegroundColor Cyan
$sourceAHK = Join-Path $RepoRoot "hotkeys.ahk"

# Compile arguments
$compileArgs = @(
    "/in", "`"$sourceAHK`"",
    "/out", "`"$OutputFile`"",
    "/bin", "`"$ahkBin`""
)

$process = Start-Process -FilePath $CompilerExe -ArgumentList $compileArgs -Wait -NoNewWindow -PassThru
if ($process.ExitCode -ne 0) {
    Write-Error "Compilation failed with exit code $($process.ExitCode)"
    exit 1
}
Write-Host "Successfully compiled to $OutputFile" -ForegroundColor Green

# 4. Copy CLI wrappers and bundle into ZIP release
Write-Host "Packaging build artifacts into ZIP..." -ForegroundColor Cyan
$PackageFolder = Join-Path $BuildDir "package"
New-Item -ItemType Directory -Path $PackageFolder | Out-Null

Copy-Item -Path $OutputFile -Destination (Join-Path $PackageFolder "hotkeys.exe")
Copy-Item -Path (Join-Path $RepoRoot "xt.bat") -Destination (Join-Path $PackageFolder "xt.bat")
Copy-Item -Path (Join-Path $RepoRoot "xt.ps1") -Destination (Join-Path $PackageFolder "xt.ps1")
Copy-Item -Path (Join-Path $RepoRoot "README.md") -Destination (Join-Path $PackageFolder "README.md")
Copy-Item -Path (Join-Path $RepoRoot "LICENSE") -Destination (Join-Path $PackageFolder "LICENSE")

Compress-Archive -Path "$PackageFolder\*" -DestinationPath $ZipRelease -Force
Write-Host "Successfully created release archive at: $ZipRelease" -ForegroundColor Green
Write-Host "SHA256 Hash of ZIP release:" -ForegroundColor Yellow
$hash = Get-FileHash -Path $ZipRelease -Algorithm SHA256
Write-Host $hash.Hash -ForegroundColor Green
