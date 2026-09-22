Describe "Repository Structure and Integrity" {
    $RepoRoot = Resolve-Path "$PSScriptRoot\..\.."
    $XtkeysScript = "$RepoRoot\xtkeys.ps1"
    $InstallScript = "$RepoRoot\install.ps1"
    $DefaultConfig = "$RepoRoot\config\default.config.json"

    It "Should contain default configuration schema" {
        (Test-Path $DefaultConfig) | Should Be $true
    }

    It "Should have a valid JSON config file" {
        $json = Get-Content -Raw $DefaultConfig | ConvertFrom-Json
        $json.general | Should Not Be $null
        $json.general.doublePressDelayMs | Should Be 400
    }

    It "Should contain modular src architecture" {
        (Test-Path "$RepoRoot\src\main.ahk") | Should Be $true
        (Test-Path "$RepoRoot\src\core\Config.ahk") | Should Be $true
        (Test-Path "$RepoRoot\src\core\Logger.ahk") | Should Be $true
        (Test-Path "$RepoRoot\src\core\ErrorHandler.ahk") | Should Be $true
        (Test-Path "$RepoRoot\src\core\ToolTip.ahk") | Should Be $true
        (Test-Path "$RepoRoot\src\core\Watchdog.ahk") | Should Be $true
        (Test-Path "$RepoRoot\src\interop\Win32.ahk") | Should Be $true
        (Test-Path "$RepoRoot\src\interop\Explorer.ahk") | Should Be $true
        (Test-Path "$RepoRoot\src\interop\AudioEndpoint.ahk") | Should Be $true
        (Test-Path "$RepoRoot\src\managers\AppResolver.ahk") | Should Be $true
        (Test-Path "$RepoRoot\src\managers\GestureManager.ahk") | Should Be $true
        (Test-Path "$RepoRoot\src\managers\WindowManager.ahk") | Should Be $true
        (Test-Path "$RepoRoot\src\actions\AppActions.ahk") | Should Be $true
        (Test-Path "$RepoRoot\src\actions\AudioActions.ahk") | Should Be $true
        (Test-Path "$RepoRoot\src\actions\UtilityActions.ahk") | Should Be $true
        (Test-Path "$RepoRoot\src\bindings\Hotkeys.ahk") | Should Be $true
    }

    It "Should have valid PowerShell syntax in CLI scripts" {
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($XtkeysScript, [ref]$null, [ref]$errors)
        $errors.Count | Should Be 0

        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($InstallScript, [ref]$null, [ref]$errors)
        $errors.Count | Should Be 0
    }

    It "Should pass AutoHotkey v2 syntax validation" {
        $valScript = "$RepoRoot\tests\Ahk\validate_syntax.ps1"
        if (Test-Path $valScript) {
            $null = & $valScript
            $LASTEXITCODE | Should Be 0
        }
    }
}
