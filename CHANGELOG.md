# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Smart Unzip**: Automatically detects if a ZIP archive has a single top-level directory to prevent duplicate nested folders (`ZipHasRootFolder`).
- **Modular Architecture**: Split monolithic script into maintainable modules under `src/` (`config.ahk`, `helpers.ahk`, `app-resolver.ahk`, `audio.ahk`, `watchdog.ahk`, `logging.ahk`).
- **Unit Test Suite**: Added `tests/test-helpers.ahk` covering path conversions, env parsing, and macro expansions.
- **Resilient Logging**: Added OutputDebug stream broadcasting and fallback logging to `%TEMP%` when primary log directory is locked.
- **Modern CLI & Installer UI**: Animated Braille spinner (`Invoke-Spinner`) and standardized tag formatting (`Write-UI`) across `install.ps1` and `xtkeys.ps1`.

### Changed
- **Extraction Security**: Removed PowerShell string command generation in `ExtractSelectedZip`, switching to native `tar.exe` and in-process `Shell.Application` COM extraction.
- **Trailing Slash Quoting**: Fixed Win32 command line quote escaping when passing paths with trailing slashes to external programs.

### Fixed
- Fixed silent log write swallowing by introducing comprehensive catch handlers and tray error notifications.
- Fixed character encoding mojibake in PowerShell console output by enforcing UTF-8 code point definitions.
