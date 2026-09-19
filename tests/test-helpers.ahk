#Requires AutoHotkey v2.0.26

#Include "..\src\config.ahk"
#Include "..\src\logging.ahk"
#Include "..\src\helpers.ahk"
#Include "..\src\app-resolver.ahk"

passed := 0
failed := 0

AssertEqual(actual, expected, testName) {
    global passed, failed
    if (actual == expected) {
        passed++
        FileAppend("[PASS] " . testName . "`n", "*", "UTF-8")
    } else {
        failed++
        FileAppend("[FAIL] " . testName . " | Expected: '" . String(expected) . "', Got: '" . String(actual) . "'`n", "*", "UTF-8")
    }
}

AssertEqual(ConvertToWSLPath("C:\Users\Test\File.txt"), "/mnt/c/Users/Test/File.txt", "WSL Drive Path Conversion")
AssertEqual(ConvertToWSLPath(""), "", "WSL Empty Path")
AssertEqual(ConvertToWSLPath("\\wsl.localhost\Ubuntu\home\user\project"), "/home/user/project", "WSL UNC Path Conversion")
AssertEqual(GetEnvInt("NON_EXISTENT_VAR_12345", 999), 999, "GetEnvInt Default Value Fallback")
AssertEqual(GetEnvString("NON_EXISTENT_VAR_12345", "default_val"), "default_val", "GetEnvString Default Value Fallback")
AssertEqual(AppResolver.ExpandEnvVars("%ProgramFiles%"), A_ProgramFiles, "AppResolver ExpandEnvVars %ProgramFiles%")

FileAppend("`n====================`nTests Passed: " . passed . " | Failed: " . failed . "`n====================`n", "*", "UTF-8")
ExitApp(failed > 0 ? 1 : 0)
