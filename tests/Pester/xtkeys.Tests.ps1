Describe "Repository Structure and Integrity" {
    BeforeAll {
        $RepoRoot = Resolve-Path "$PSScriptRoot\..\.."
        $XtkeysScript = "$RepoRoot\xtkeys.ps1"
        $InstallScript = "$RepoRoot\install.ps1"
        $DefaultConfig = "$RepoRoot\config\default.config.json"
    }

    It "Should contain default configuration schema" {
        if (-not (Test-Path $DefaultConfig)) { throw "Default config not found at $DefaultConfig" }
    }

    It "Should have a valid JSON config file" {
        $json = Get-Content -Raw $DefaultConfig | ConvertFrom-Json
        if ($null -eq $json.general -or $json.general.doublePressDelayMs -ne 400) { throw "Invalid default config JSON" }
    }

    It "Should contain modular src architecture" {
        $required = @(
            "$RepoRoot\src\main.ahk",
            "$RepoRoot\src\core\Config.ahk",
            "$RepoRoot\src\core\Logger.ahk",
            "$RepoRoot\src\core\ErrorHandler.ahk",
            "$RepoRoot\src\core\ToolTip.ahk",
            "$RepoRoot\src\core\Watchdog.ahk",
            "$RepoRoot\src\interop\Win32.ahk",
            "$RepoRoot\src\interop\Explorer.ahk",
            "$RepoRoot\src\interop\AudioEndpoint.ahk",
            "$RepoRoot\src\managers\AppResolver.ahk",
            "$RepoRoot\src\managers\GestureManager.ahk",
            "$RepoRoot\src\managers\WindowManager.ahk",
            "$RepoRoot\src\actions\AppActions.ahk",
            "$RepoRoot\src\actions\AudioActions.ahk",
            "$RepoRoot\src\actions\UtilityActions.ahk",
            "$RepoRoot\src\bindings\Hotkeys.ahk"
        )
        foreach ($file in $required) {
            if (-not (Test-Path $file)) { throw "Missing required module: $file" }
        }
    }

    It "Should have valid PowerShell syntax in CLI scripts" {
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($XtkeysScript, [ref]$null, [ref]$errors)
        if ($errors.Count -gt 0) { throw "Syntax error in ${XtkeysScript}: $($errors | Out-String)" }

        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($InstallScript, [ref]$null, [ref]$errors)
        if ($errors.Count -gt 0) { throw "Syntax error in ${InstallScript}: $($errors | Out-String)" }
    }

    It "Should pass AutoHotkey v2 syntax validation" {
        $valScript = "$RepoRoot\tests\Ahk\validate_syntax.ps1"
        if (Test-Path $valScript) {
            $null = & $valScript
            if ($LASTEXITCODE -ne 0) { throw "AHK syntax validation failed with exit code $LASTEXITCODE" }
        }
    }
}
