#Requires AutoHotkey v2.0.26
#SingleInstance Force
#Warn
Persistent()
SendMode "Input"
SetWorkingDir A_ScriptDir

; --- Module Inclusions ---
#Include "core\Config.ahk"
#Include "core\Logger.ahk"
#Include "core\ToolTip.ahk"
#Include "core\ErrorHandler.ahk"
#Include "core\Watchdog.ahk"

#Include "interop\Win32.ahk"
#Include "interop\Explorer.ahk"
#Include "interop\AudioEndpoint.ahk"

#Include "managers\AppResolver.ahk"
#Include "managers\GestureManager.ahk"
#Include "managers\WindowManager.ahk"

#Include "actions\AppActions.ahk"
#Include "actions\AudioActions.ahk"
#Include "actions\UtilityActions.ahk"

; --- Initialization ---
Config.Init()
ErrorHandler.Init()
AudioEndpoint.Init()

; --- Process PID Registration ---
try {
    pidDir := EnvGet("LOCALAPPDATA") ? (EnvGet("LOCALAPPDATA") . "\Programs\xtkeys") : A_ScriptDir
    if !DirExist(pidDir)
        DirCreate(pidDir)
    f := FileOpen(pidDir . "\hotkeys.pid", "w")
    f.Write(DllCall("GetCurrentProcessId"))
    f.Close()
} catch {
}

; --- Auto-Reload Watcher ---
global ScriptModTime := ""
SetTimer WatchScript, 3000

WatchScript() {
    global ScriptModTime
    try {
        curModTime := FileGetTime(A_ScriptFullPath)
    } catch {
        return
    }
    if (ScriptModTime = "") {
        ScriptModTime := curModTime
        return
    }
    if (curModTime != ScriptModTime) {
        ToolTip("Reloading Script...")
        SetTimer(() => ToolTip(), -1000)
        Reload()
    }
}

; --- Watchdog Registration ---
ProcessWatchdog.Register("rzappengine.exe", "7.1 Surround Sound", () => AppActions.LaunchRazer71())

if (Config.WATCHDOG_ENABLED) {
    SetTimer(() => ProcessWatchdog.Poll(), Config.WATCHDOG_INTERVAL_MS)
}

; --- Bindings ---
#Include "bindings\Hotkeys.ahk"
