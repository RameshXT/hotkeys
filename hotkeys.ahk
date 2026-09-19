; ==================[ Hotkey Reference ]==================
; Alt + 0  → Calculator
; Alt + 1  → Photoshop (Double)
; Alt + 7  → 7.1 Surround Sound
; Alt + A  → Antigravity            | Double: Current Folder
; Alt + C  → Chrome                 | Hold: Incognito
; Alt + E  → Outlook
; Alt + G  → Git Bash               | Double: Current Folder
; Alt + I  → Instagram
; Alt + M  → Microsoft Store
; Alt + N  → Notepad
; Alt + O  → CMD                    | Double: Active Folder / Admin (otherwise) | Hold: Admin in Folder
; Alt + P  → PowerShell             | Double: Active Folder / Admin (otherwise) | Hold: Admin in Folder
; Alt + Q  → Close Window           | Hold: Repeat
; Alt + S  → Slack
; Alt + T  → Telegram
; Alt + U  → Ubuntu WSL             | Double: Current Folder
; Alt + V  → VS Code                | Double: Current Folder
; Alt + W  → WhatsApp
; Alt + Y  → YouTube
; Alt + Z  → Unzip ZIP

; Ctrl + Shift + Q         → Switch to Sony MDRX-50
; Ctrl + Shift + X         → Switch to Black Shark V2
; Ctrl + Shift + Y         → Switch to Resound
; Ctrl + Shift + Z         → Switch to HEAT
; Ctrl + Shift + Alt + Del → Empty Recycle Bin
; Alt + Shift + V          → Paste path as WSL

; ====================[ Script Config & Variables ]====================
#Requires AutoHotkey v2.0.26
#SingleInstance Force
#Warn
Persistent()
SendMode "Input"
SetWorkingDir A_ScriptDir

try {
    pidDir := EnvGet("LOCALAPPDATA") ? (EnvGet("LOCALAPPDATA") . "\xtkeys") : A_ScriptDir
    if !DirExist(pidDir)
        DirCreate(pidDir)
    f := FileOpen(pidDir . "\hotkeys.pid", "w")
    f.Write(DllCall("GetCurrentProcessId"))
    f.Close()
} catch {
}

SetTimer WatchScript, 3000
OnError(GlobalErrorHandler)

global WATCHDOG_INTERVAL_MS := GetEnvInt("AHK_WATCHDOG_INTERVAL_MS", 30000)
if (GetEnvInt("AHK_WATCHDOG_ENABLED", 1)) {
    SetTimer(() => ProcessWatchdog.Poll(), WATCHDOG_INTERVAL_MS)
}

USER_HOME := EnvGet("USERPROFILE")
global DOUBLE_PRESS_DELAY := GetEnvInt("AHK_DOUBLE_PRESS_DELAY", 400)
global LOGS_DIR := GetEnvString("AHK_LOGS_DIR", A_ScriptDir . "\logs")
global LONG_PRESS_THRESHOLD := GetEnvInt("AHK_LONG_PRESS_THRESHOLD", 600)
global ScriptModTime := ""
global TOOLTIP_DURATION_MS := GetEnvInt("AHK_TOOLTIP_DURATION_MS", 2000)
global WINDOW_WAIT_TIMEOUT := GetEnvInt("AHK_WINDOW_WAIT_TIMEOUT", 5)
global AUDIO_DEVICE_1 := GetEnvString("AHK_AUDIO_DEVICE_1", "Surround")
global AUDIO_DEVICE_2 := GetEnvString("AHK_AUDIO_DEVICE_2", "Resound")
global AUDIO_DEVICE_3 := GetEnvString("AHK_AUDIO_DEVICE_3", "Speakers (Realtek")
global AUDIO_MIC_1 := GetEnvString("AHK_AUDIO_MIC_1", "Microphone (Realtek(R) Audio)")
global AUDIO_MIC_2 := GetEnvString("AHK_AUDIO_MIC_2", "Razer")
global AUDIO_MIC_3 := GetEnvString("AHK_AUDIO_MIC_3", "Array")
global DEVICE_VOLUME_HISTORY := Map()
global LAST_DEVICE := ""
try {
    initVol := SoundGetVolume()
    if (Round(initVol) = 25) {
        LAST_DEVICE := "Sony MDRX-50"
        DEVICE_VOLUME_HISTORY["Sony MDRX-50"] := 25
    } else {
        LAST_DEVICE := "Black Shark V2"
        DEVICE_VOLUME_HISTORY["Black Shark V2"] := initVol
    }
}

; ====================[ Helper Functions ]====================
GetEnvInt(varName, defaultValue) {
    val := EnvGet(varName)
    return (val != "" && IsInteger(val)) ? Integer(val) : defaultValue
}

GetEnvString(varName, defaultValue) {
    val := EnvGet(varName)
    return (val != "") ? val : defaultValue
}

ResolveNativePath(cmd) {
    if (A_Is64bitOS && A_PtrSize = 4) {
        if (SubStr(cmd, 1, 7) = "*RunAs ") {
            prefix := "*RunAs "
            actualCmd := SubStr(cmd, 8)
        } else {
            prefix := ""
            actualCmd := cmd
        }

        if (actualCmd = "cmd.exe" || SubStr(actualCmd, 1, 8) = "cmd.exe ") {
            return prefix . "C:\Windows\Sysnative\" . actualCmd
        }
        if (actualCmd = "powershell.exe" || SubStr(actualCmd, 1, 15) = "powershell.exe ") {
            return prefix . "C:\Windows\Sysnative\WindowsPowerShell\v1.0\" . actualCmd
        }
    }
    return cmd
}

class Wow64RedirectionGuard {
    oldRedir := 0
    disabled := false

    __New() {
        if (A_Is64bitOS && A_PtrSize = 4) {
            oldVal := 0
            if DllCall("Wow64DisableWow64FsRedirection", "Ptr*", &oldVal) {
                this.oldRedir := oldVal
                this.disabled := true
            }
        }
    }

    __Delete() {
        if (this.disabled) {
            DllCall("Wow64RevertWow64FsRedirection", "Ptr", this.oldRedir)
            this.disabled := false
        }
    }
}

SearchSystemPath(exeName) {
    if (exeName = "")
        return false
    if FileExist(A_WorkingDir . "\" . exeName)
        return true
    pathEnv := EnvGet("PATH")
    for dir in StrSplit(pathEnv, ";") {
        if (dir != "" && FileExist(dir . "\" . exeName))
            return true
    }
    return false
}

ConvertToWSLPath(winPath) {
    if (winPath = "")
        return ""
    unixPath := StrReplace(winPath, "\", "/")
    if (RegExMatch(unixPath, "i)^//wsl(?:\.localhost)?/[^/]+(/.*)?$", &m)) {
        return m[1] != "" ? m[1] : "/"
    } else if (SubStr(unixPath, 2, 1) = ":") {
        drive := Format("{:L}", SubStr(unixPath, 1, 1))
        unixPath := "/mnt/" . drive . SubStr(unixPath, 3)
    }
    return unixPath
}

DeleteFileIfExists(path) {
    if (path != "" && FileExist(path))
        FileDelete(path)
}

ZipHasRootFolder(zipPath) {
    try {
        shell := ComObject("Shell.Application")
        zipObj := shell.Namespace(zipPath)
        if (zipObj) {
            items := zipObj.Items()
            if (items.Count = 1) {
                return items.Item(0).IsFolder ? true : false
            }
        }
    }
    return false
}

ExtractSelectedZip() {
    winClass := WinGetClass("A")
    if (winClass != "CabinetWClass" && winClass != "ExploreWClass")
        return
    selectedPath := GetSelectedFilePath()
    if (selectedPath = "")
        return
    SplitPath selectedPath, , &fileDir, &fileExtension, &nameNoExt
    if (fileExtension != "zip" && fileExtension != "ZIP")
        return

    hasRootFolder := ZipHasRootFolder(selectedPath)
    targetDir := hasRootFolder ? fileDir : (fileDir . "\" . nameNoExt)

    winrarPath := AppResolver.Get("WinRAR", "WinRAR.exe", ["%ProgramFiles%\WinRAR\WinRAR.exe",
        "%ProgramFiles(x86)%\WinRAR\WinRAR.exe"])
    if FileExist(winrarPath) {
        guard := Wow64RedirectionGuard()
        Run('"' . winrarPath . '" x -o+ "' . selectedPath . '" "' . targetDir . '"')
        return
    }

    tarExe := ResolveNativePath("tar.exe")
    if FileExist(tarExe) {
        try DirCreate(targetDir)
        guard := Wow64RedirectionGuard()
        Run('"' . tarExe . '" -xf "' . selectedPath . '" -C "' . targetDir . '"', , "Hide")
        return
    }

    try {
        DirCreate(targetDir)
        shell := ComObject("Shell.Application")
        zipFolder := shell.Namespace(selectedPath)
        destFolder := shell.Namespace(targetDir)
        if (zipFolder && destFolder) {
            destFolder.CopyHere(zipFolder.Items(), 4 | 16 | 512 | 1024)
        }
    }
}

class AppResolver {
    static cache := Map()

    static Get(appKey, exeName := "", searchPatterns := [], regPaths := []) {
        if this.cache.Has(appKey)
            return this.cache[appKey]

        resolvedPath := ""

        if (exeName != "") {
            for root in ["HKEY_LOCAL_MACHINE", "HKEY_CURRENT_USER"] {
                try {
                    val := RegRead(root . "\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\" . exeName, "")
                    if (val != "" && FileExist(val)) {
                        resolvedPath := val
                        break
                    }
                }
            }
        }

        if (resolvedPath = "" && regPaths.Length > 0) {
            for regSpec in regPaths {
                parts := StrSplit(regSpec, "|")
                keyPath := parts[1]
                valueName := parts.Length > 1 ? parts[2] : ""
                try {
                    val := RegRead(keyPath, valueName)
                    if (val != "") {
                        if (InStr(FileExist(val), "D")) {
                            if (exeName != "" && FileExist(val . "\" . exeName))
                                resolvedPath := val . "\" . exeName
                        } else if (FileExist(val)) {
                            resolvedPath := val
                        }
                    }
                }
                if (resolvedPath != "")
                    break
            }
        }

        if (resolvedPath = "") {
            for pattern in searchPatterns {
                expanded := this.ExpandEnvVars(pattern)
                if (expanded != "" && FileExist(expanded)) {
                    resolvedPath := expanded
                    break
                }
            }
        }

        if (resolvedPath = "") {
            resolvedPath := exeName != "" ? exeName : ""
        }

        if (resolvedPath != "" && (FileExist(resolvedPath) || InStr(resolvedPath, "://"))) {
            this.cache[appKey] := resolvedPath
        }
        return resolvedPath
    }

    static ExpandEnvVars(str) {
        if (!InStr(str, "%"))
            return str

        str := StrReplace(str, "%ProgramFilesCommon%", A_ProgramFiles . "\Common Files")
        str := StrReplace(str, "%ProgramFiles(x86)%", EnvGet("ProgramFiles(x86)") || A_ProgramFiles)
        str := StrReplace(str, "%StartMenuCommon%", A_StartMenuCommon)
        str := StrReplace(str, "%StartMenu%", A_StartMenu)
        str := StrReplace(str, "%AppData%", A_AppData)
        str := StrReplace(str, "%LocalAppData%", EnvGet("LocalAppData"))
        str := StrReplace(str, "%ProgramFiles%", A_ProgramFiles)

        pos := 1
        while (pos <= StrLen(str)) {
            if (RegExMatch(str, "%([^%]+)%", &match, pos)) {
                envVal := EnvGet(match[1])
                str := StrReplace(str, match[0], envVal)
                pos := match.Pos + StrLen(envVal)
            } else {
                break
            }
        }
        return str
    }
}

class DoublePressManager {
    static lastPresses := Map()
    static timers := Map()

    static Handle(key, singlePressCallback := "", doublePressCallback := "") {
        now := A_TickCount
        last := this.lastPresses.Has(key) ? this.lastPresses[key] : 0

        if (now - last < DOUBLE_PRESS_DELAY) {
            this.lastPresses[key] := 0
            if this.timers.Has(key) {
                SetTimer this.timers[key], 0
                this.timers.Delete(key)
            }
            if (doublePressCallback != "")
                doublePressCallback()
        } else {
            this.lastPresses[key] := now
            if (singlePressCallback != "") {
                timerFn := this.ExecuteAndClear.Bind(this, key, singlePressCallback)
                this.timers[key] := timerFn
                SetTimer timerFn, -DOUBLE_PRESS_DELAY
            }
        }
    }

    static ExecuteAndClear(key, callback) {
        if this.timers.Has(key)
            this.timers.Delete(key)
        callback()
    }
}

GetExplorerPath() {
    hwnd := WinActive("A")
    if (!hwnd || !(WinGetClass(hwnd) ~= "CabinetWClass|ExploreWClass"))
        return ""

    activeTab := 0
    try activeTab := ControlGetHwnd("ShellTabWindowClass1", hwnd)

    try {
        for window in ComObject("Shell.Application").Windows {
            try {
                if (window.hwnd != hwnd)
                    continue

                if (activeTab) {
                    static IID_IShellBrowser := "{000214E2-0000-0000-C000-000000000046}"
                    shellBrowser := ComObjQuery(window, IID_IShellBrowser, IID_IShellBrowser)
                    thisTab := 0
                    if (shellBrowser) {
                        ComCall(3, shellBrowser, "ptr*", &thisTab)
                        ObjRelease(shellBrowser)
                        if (thisTab != activeTab)
                            continue
                    }
                }

                folderPath := window.Document.Folder.Self.Path
                if (folderPath != "")
                    return folderPath
            } catch {
                continue
            }
        }
    } catch as e {
        ShowLaunchError("Error getting Explorer path", e)
    }
    return ""
}

GetSelectedFilePath() {
    hwnd := WinActive("A")
    if (!hwnd || !(WinGetClass(hwnd) ~= "CabinetWClass|ExploreWClass"))
        return ""

    activeTab := 0
    try activeTab := ControlGetHwnd("ShellTabWindowClass1", hwnd)

    try {
        for window in ComObject("Shell.Application").Windows {
            try {
                if (window.hwnd != hwnd)
                    continue

                if (activeTab) {
                    static IID_IShellBrowser := "{000214E2-0000-0000-C000-000000000046}"
                    shellBrowser := ComObjQuery(window, IID_IShellBrowser, IID_IShellBrowser)
                    thisTab := 0
                    if (shellBrowser) {
                        ComCall(3, shellBrowser, "ptr*", &thisTab)
                        ObjRelease(shellBrowser)
                        if (thisTab != activeTab)
                            continue
                    }
                }

                for item in window.Document.SelectedItems
                    return item.Path
            } catch {
                continue
            }
        }
    } catch as e {
        ShowLaunchError("Error getting selected file", e)
    }
    return ""
}

GetValidExplorerPath() {
    winClass := WinGetClass("A")
    if (winClass != "CabinetWClass" && winClass != "ExploreWClass") {
        ShowTransientToolTip("Please focus on a File Explorer window")
        return ""
    }

    path := GetExplorerPath()
    if (path = "") {
        ShowTransientToolTip("Could not get folder path")
        return ""
    }

    return path
}

HandleContextHotkey(key, name, path, sArgs := "", dPre := "") {
    static lastPresses := Map()
    static timers := Map()

    now := A_TickCount
    last := lastPresses.Has(key) ? lastPresses[key] : 0

    if (now - last < DOUBLE_PRESS_DELAY) {
        lastPresses[key] := 0
        if timers.Has(key)
            SetTimer timers[key], 0

        dir := GetValidExplorerPath()
        if (dir != "") {
            ShowTransientToolTip(name)
            cleanDir := (SubStr(dir, -1) == "\") ? (dir . "\") : dir
            RunApp(path, dPre . '"' . cleanDir . '"')
        }
    } else {
        lastPresses[key] := now
        timerFn := RunAppAndNotify.Bind(path, sArgs, name)
        timers[key] := timerFn
        SetTimer timerFn, -DOUBLE_PRESS_DELAY
    }
}

IsProtectedWindowClass(windowClass) {
    return (windowClass = "Shell_TrayWnd" || windowClass = "Progman" || windowClass = "WorkerW"
        || windowClass = "ApplicationFrameHost"
        || windowClass = "Windows.UI.Core.CoreWindow"
        || windowClass = "SearchHost"
        || windowClass = "StartMenuExperienceHostWindow"
        || windowClass = "ImmersiveLauncher")
}

SmartRun(targetPath, args := "", workingDir := "") {
    targetPath := ResolveNativePath(targetPath)
    guard := Wow64RedirectionGuard()
    try {
        if (args != "")
            Run('"' . targetPath . '" ' . args, workingDir)
        else
            Run('"' . targetPath . '"', workingDir)
        return true
    } catch as e {
        if (A_LastError = 740 || A_LastError = 5 || InStr(e.Message, "elevation")) {
            try {
                if (args != "")
                    Run('*RunAs "' . targetPath . '" ' . args, workingDir)
                else
                    Run('*RunAs "' . targetPath . '"', workingDir)
                return true
            } catch as uacErr {
                if (A_LastError = 1223)
                    return false
                throw uacErr
            }
        }
        throw e
    }
}

LaunchAndMaximize(appPath, windowIdentifier := "", timeout := "", friendlyName := "") {
    if (timeout = "")
        timeout := WINDOW_WAIT_TIMEOUT

    displayName := (friendlyName != "") ? friendlyName : (windowIdentifier != "" ? windowIdentifier : appPath)

    if (InStr(appPath, "\") && !FileExist(appPath)) {
        TrayTip(appPath, "Application not found", 2)
        return false
    }
    if (!InStr(appPath, "\") && !FileExist(appPath) && !SearchSystemPath(appPath)) {
        TrayTip(displayName, "Application not found", 2)
        return false
    }

    try {
        if InStr(appPath, "://") {
            Run(appPath)
        } else {
            if (!SmartRun(appPath))
                return false
        }
    } catch as e {
        TrayTip("Failed to launch: " . e.Message, displayName, 2)
        return false
    }

    if (windowIdentifier != "") {
        oldMatchMode := A_TitleMatchMode
        SetTitleMatchMode 2
        if WinWait(windowIdentifier, , timeout) {
            WinActivate(windowIdentifier)
            WinMaximize(windowIdentifier)
            loop 10 {
                if (WinGetMinMax(windowIdentifier) = 1)
                    break
                WinMaximize(windowIdentifier)
                Sleep 50
            }
        } else {
            ToolTip("Window not detected: " . windowIdentifier)
            SetTimer RemoveToolTip, -TOOLTIP_DURATION_MS
        }
        SetTitleMatchMode oldMatchMode
    }

    return true
}
LaunchAndPosition(cmd, workingDir := "") {
    cmd := ResolveNativePath(cmd)
    if (SubStr(cmd, 1, 7) = "*RunAs " && workingDir != "") {
        actualCmd := SubStr(cmd, 8)
        if InStr(actualCmd, "cmd.exe") {
            if !InStr(actualCmd, " /") {
                cmd := '*RunAs ' . actualCmd . ' /k cd /d "' . StrReplace(workingDir, '"', '\"') . '"'
                workingDir := ""
            }
        } else if InStr(actualCmd, "powershell.exe") {
            if !InStr(actualCmd, " -") {
                cmd := '*RunAs ' . actualCmd . " -NoExit -Command Set-Location -LiteralPath '" . StrReplace(workingDir, "'", "''") . "'"
                workingDir := ""
            }
        }
    }
    prevDetect := A_DetectHiddenWindows
    DetectHiddenWindows True

    existingWindows := WinGetList("ahk_class ConsoleWindowClass")
    existingWT := WinGetList("ahk_class CASCADIA_HOSTING_WINDOW_CLASS")

    pid := 0
    guard := Wow64RedirectionGuard()
    try {
        Run(cmd, workingDir, , &pid)
    } catch as e {
        DetectHiddenWindows prevDetect
        throw e
    }

    targetHwnd := 0
    loop 8 {
        if (pid != 0 && WinExist("ahk_pid " . pid)) {
            targetHwnd := WinExist("ahk_pid " . pid)
            break
        }

        currentWindows := WinGetList("ahk_class ConsoleWindowClass")
        for hwnd in currentWindows {
            found := false
            for oldHwnd in existingWindows {
                if (hwnd == oldHwnd) {
                    found := true
                    break
                }
            }
            if (!found) {
                targetHwnd := hwnd
                break
            }
        }
        if (targetHwnd != 0)
            break

        currentWT := WinGetList("ahk_class CASCADIA_HOSTING_WINDOW_CLASS")
        for hwnd in currentWT {
            found := false
            for oldHwnd in existingWT {
                if (hwnd == oldHwnd) {
                    found := true
                    break
                }
            }
            if (!found) {
                targetHwnd := hwnd
                break
            }
        }
        if (targetHwnd != 0)
            break

        Sleep 50
    }

    if (targetHwnd != 0) {
        try {
            MouseGetPos(&mX, &mY)
            matched := false
            loop MonitorGetCount() {
                MonitorGetWorkArea(A_Index, &wLeft, &wTop, &wRight, &wBottom)
                if (mX >= wLeft && mX <= wRight && mY >= wTop && mY <= wBottom) {
                    targetLeft := wLeft - 3
                    targetTop := wTop + 5
                    matched := true
                    break
                }
            }
            if (!matched) {
                MonitorGetWorkArea(1, &wLeft, &wTop, &wRight, &wBottom)
                targetLeft := wLeft - 3
                targetTop := wTop + 5
            }
            WinMove(targetLeft, targetTop, , , "ahk_id " . targetHwnd)
        } catch {
        }
    }

    DetectHiddenWindows prevDetect
    return targetHwnd != 0
}

RunApp(path, args := "", name := "", workingDir := "") {
    if (name != "")
        ShowTransientToolTip(name)
    try {
        if InStr(path, "://") {
            Run(path)
        } else {
            if (InStr(path, "\") && !FileExist(path)) {
                TrayTip(name != "" ? name : path, "Application not found", 2)
                return
            }
            if (!InStr(path, "\") && !FileExist(path) && !SearchSystemPath(path)) {
                TrayTip(name != "" ? name : path, "Application not found", 2)
                return
            }
            SmartRun(path, args, workingDir)
        }
    } catch as e {
        ShowLaunchError("Launch Error", e)
    }
}

RunAppAndNotify(path, args, name) {
    ShowTransientToolTip(name)
    RunApp(path, args, name)
}

WriteLogEntry(entry) {
    OutputDebug(entry)
    try {
        if !DirExist(LOGS_DIR)
            DirCreate(LOGS_DIR)

        logFile := LOGS_DIR . "\hotkey_errors.log"
        maxLogSize := 5242880 ; 5 MB
        if FileExist(logFile) && FileGetSize(logFile) >= maxLogSize {
            oldLog := LOGS_DIR . "\hotkey_errors.log.old"
            if FileExist(oldLog)
                FileDelete(oldLog)
            FileMove(logFile, oldLog, 1)
        }

        FileAppend(entry, logFile, "UTF-8")
    } catch as primaryErr {
        try {
            tempLog := A_Temp . "\xtkeys_hotkey_errors.log"
            FileAppend(entry, tempLog, "UTF-8")
        } catch as fallbackErr {
            TrayTip("Log write failed: " . primaryErr.Message, "xtkeys Logging Error", "Icon!")
        }
    }
}

GlobalErrorHandler(thrown, mode) {
    try {
        timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
        entry := "--------------------------------------------------------------------------------`n`n"
        entry .= "  [" . timestamp . "] UNHANDLED ERROR (" . mode . ")`n"
        entry .= "  Message: " . thrown.Message . "`n"
        entry .= "  What:    " . thrown.What . "`n"
        entry .= "  File:    " . thrown.File . "`n"
        entry .= "  Line:    " . thrown.Line . "`n"
        if (thrown.Extra != "")
            entry .= "  Extra:   " . thrown.Extra . "`n"
        if (thrown.Stack != "") {
            entry .= "  Stack:`n"
            for line in StrSplit(thrown.Stack, "`n", "`r") {
                if (line != "")
                    entry .= "    " . line . "`n"
            }
        }
        entry .= "`n--------------------------------------------------------------------------------`n`n"

        WriteLogEntry(entry)
        TrayTip(thrown.Message, "Hotkey Error Logged", 2)
    }
    return -1
}

ShowLaunchError(prefix, err) {
    msg := (err is Error) ? err.Message : String(err)

    friendlyMsg := msg
    if InStr(msg, "Failed attempt to launch program") {
        friendlyMsg := "App not installed or shortcut is broken."
    } else if InStr(msg, "elevation") || InStr(msg, "Requires elevation") || InStr(msg, "740") {
        friendlyMsg := "Requires Administrator rights to open."
    } else if InStr(msg, "access is denied") || InStr(msg, "5") {
        friendlyMsg := "Access denied. Missing permission."
    } else if InStr(msg, "cannot find the file specified") || InStr(msg, "2") {
        friendlyMsg := "Application file not found."
    }

    TrayTip(friendlyMsg, prefix, 2)

    try {
        timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
        logLine := "--------------------------------------------------------------------------------`n`n"
        logLine .= "  [" . timestamp . "] " . prefix . "`n"
        logLine .= "  Message: " . msg . "`n"
        if (err is Error) {
            logLine .= "  File:    " . err.File . "`n"
            logLine .= "  Line:    " . err.Line . "`n"
            logLine .= "  What:    " . err.What . "`n"
            if (err.Extra != "")
                logLine .= "  Extra:   " . err.Extra . "`n"
            if (err.Stack != "") {
                logLine .= "  Stack:`n"
                for line in StrSplit(err.Stack, "`n", "`r") {
                    if (line != "")
                        logLine .= "    " . line . "`n"
                }
            }
        }
        logLine .= "`n--------------------------------------------------------------------------------`n`n"

        WriteLogEntry(logLine)
    }
}

class ProcessWatchdog {
    static targets := Map()
    static restartHistory := Map()
    static maxRestarts := 3
    static windowMs := 300000 ; 5-minute sliding window

    static Register(exeName, friendlyName, launchFn) {
        this.targets[exeName] := { name: friendlyName, launcher: launchFn, wasRunning: false, hProcess: 0, pid: 0 }
        this.restartHistory[exeName] := []
    }

    static Poll() {
        now := A_TickCount
        for exeName, info in this.targets {
            isRunning := false

            if (info.hProcess != 0) {
                waitRes := DllCall("WaitForSingleObject", "ptr", info.hProcess, "uint", 0, "uint")
                if (waitRes = 258) {
                    isRunning := true
                } else {
                    DllCall("CloseHandle", "ptr", info.hProcess)
                    info.hProcess := 0
                    info.pid := 0
                }
            }

            if (!isRunning && info.hProcess = 0) {
                pid := ProcessExist(exeName)
                if (pid != 0) {
                    info.pid := pid
                    info.hProcess := DllCall("OpenProcess", "uint", 0x00100000, "int", 0, "uint", pid, "ptr")
                    isRunning := true
                }
            }

            if (isRunning) {
                info.wasRunning := true
            } else if (info.wasRunning) {
                info.wasRunning := false

                recent := []
                for t in this.restartHistory[exeName] {
                    if (now - t < this.windowMs)
                        recent.Push(t)
                }
                this.restartHistory[exeName] := recent

                if (recent.Length >= this.maxRestarts) {
                    this.LogWatchdogEvent("CIRCUIT BREAKER TRIPPED", info.name,
                        "Process crashed " . recent.Length . " times within 5 minutes. Auto-recovery suspended.")
                    TrayTip("Auto-recovery suspended (repeated crashes)", info.name, 2)
                    continue
                }

                recent.Push(now)
                this.restartHistory[exeName] := recent

                this.LogWatchdogEvent("PROCESS AUTO-HEALED", info.name,
                    "Process terminated unexpectedly. Automatically respawned (attempt " . recent.Length . "/" . this.maxRestarts . ").")
                ShowTransientToolTip(info.name . " recovered")

                try {
                    info.launcher()
                } catch as err {
                    ShowLaunchError("Watchdog Recovery Failed: " . info.name, err)
                }
            }
        }
    }

    static LogWatchdogEvent(eventTitle, processName, details) {
        timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
        entry := "--------------------------------------------------------------------------------`n`n"
        entry .= "  [" . timestamp . "] " . eventTitle . "`n"
        entry .= "  Target:  " . processName . "`n"
        entry .= "  Details: " . details . "`n`n"
        entry .= "--------------------------------------------------------------------------------`n`n"

        WriteLogEntry(entry)
    }
}

ShowTransientToolTip(message, durationMs := "") {
    if (durationMs = "")
        durationMs := TOOLTIP_DURATION_MS
    ToolTip(message)
    SetTimer RemoveToolTip, -durationMs
}

SetAudioOutput(deviceNameSubstr, targetVolume := "", friendlyNameOverride := "", micNameSubstr := "") {
    deviceEnumerator := 0
    devicesCollection := 0
    try {
        deviceEnumerator := ComObject("{BCDE0395-E52F-467C-8E3D-C4579291692E}",
            "{A95664D2-9614-4F35-A746-DE8DB63617E6}")

        ; 1. Switch Playback Device
        ComCall(3, deviceEnumerator, "int", 0, "uint", 1, "ptr*", &devicesCollection := 0)

        count := 0
        ComCall(3, devicesCollection, "uint*", &count)

        targetId := ""
        targetName := ""
        defaultFriendlyName := ""

        defaultId := ""
        defaultDevice := 0
        defaultIdPtr := 0
        try {
            ComCall(4, deviceEnumerator, "int", 0, "int", 0, "ptr*", &defaultDevice := 0)
            if (defaultDevice) {
                ComCall(5, defaultDevice, "ptr*", &defaultIdPtr)
                if (defaultIdPtr) {
                    defaultId := StrGet(defaultIdPtr, "UTF-16")
                    DllCall("Ole32\CoTaskMemFree", "ptr", defaultIdPtr)
                    defaultIdPtr := 0
                }
            }
        } finally {
            if (defaultIdPtr)
                DllCall("Ole32\CoTaskMemFree", "ptr", defaultIdPtr)
            if (defaultDevice)
                ObjRelease(defaultDevice)
        }

        loop count {
            device := 0
            propertyStore := 0
            idPtr := 0
            try {
                ComCall(4, devicesCollection, "uint", A_Index - 1, "ptr*", &device := 0)
                if (!device)
                    continue

                ComCall(5, device, "ptr*", &idPtr)
                id := (idPtr) ? StrGet(idPtr, "UTF-16") : ""
                if (idPtr) {
                    DllCall("Ole32\CoTaskMemFree", "ptr", idPtr)
                    idPtr := 0
                }

                ComCall(4, device, "uint", 0, "ptr*", &propertyStore := 0)
                if (!propertyStore)
                    continue

                keyGUID := Buffer(16)
                DllCall("Ole32\CLSIDFromString", "str", "{A45C254E-DF1C-4EFD-8020-67D146A850E0}", "ptr", keyGUID)
                propKey := Buffer(20)
                DllCall("RtlMoveMemory", "ptr", propKey, "ptr", keyGUID, "ptr", 16)
                NumPut("uint", 14, propKey, 16)

                propVariant := Buffer(24, 0)
                ComCall(5, propertyStore, "ptr", propKey, "ptr", propVariant)

                friendlyName := ""
                if (NumGet(propVariant, 0, "ushort") = 31) {
                    namePtr := NumGet(propVariant, 8, "ptr")
                    friendlyName := StrGet(namePtr, "UTF-16")
                }
                DllCall("Ole32\PropVariantClear", "ptr", propVariant)

                if (InStr(friendlyName, deviceNameSubstr)) {
                    targetId := id
                    targetName := friendlyName
                }
                if (id = defaultId) {
                    defaultFriendlyName := friendlyName
                }
            } finally {
                if (idPtr)
                    DllCall("Ole32\CoTaskMemFree", "ptr", idPtr)
                if (propertyStore)
                    ObjRelease(propertyStore)
                if (device)
                    ObjRelease(device)
            }
        }

        if (targetId = "") {
            ShowTransientToolTip("Audio device not found: " . deviceNameSubstr)
            return
        }

        global LAST_DEVICE, DEVICE_VOLUME_HISTORY
        if (LAST_DEVICE != "" && defaultFriendlyName != "") {
            try {
                DEVICE_VOLUME_HISTORY[LAST_DEVICE] := SoundGetVolume("", defaultFriendlyName)
            }
        }

        IPolicyConfig := ComObject("{870AF99C-171D-4F9E-AF0D-E63DF40C2BC9}", "{F8679F50-850A-41CF-9C72-430F290290C8}")
        if (targetId != defaultId) {
            try {
                ComCall(13, IPolicyConfig, "Str", targetId, "UInt", 0)
                ComCall(13, IPolicyConfig, "Str", targetId, "UInt", 1)
                ComCall(13, IPolicyConfig, "Str", targetId, "UInt", 2)
            } catch as e {
                ShowTransientToolTip("Could not switch default audio device")
                ShowLaunchError("Audio device switch failed", e)
                return
            }
        }

        dispName := (friendlyNameOverride != "") ? friendlyNameOverride : targetName
        ShowTransientToolTip("Active: " . dispName)

        if (targetVolume != "") {
            SoundSetVolume(targetVolume, , targetName)
        } else if (DEVICE_VOLUME_HISTORY.Has(friendlyNameOverride)) {
            SoundSetVolume(DEVICE_VOLUME_HISTORY[friendlyNameOverride], , targetName)
        }
        LAST_DEVICE := friendlyNameOverride

        ; 2. Switch Recording Device (Microphone)
        if (micNameSubstr != "") {
            micsCollection := 0
            ComCall(3, deviceEnumerator, "int", 1, "uint", 1, "ptr*", &micsCollection := 0)
            try {
                micCount := 0
                ComCall(3, micsCollection, "uint*", &micCount)

                micId := ""
                loop micCount {
                    device := 0
                    propertyStore := 0
                    idPtr := 0
                    try {
                        ComCall(4, micsCollection, "uint", A_Index - 1, "ptr*", &device := 0)
                        if (!device)
                            continue

                        ComCall(5, device, "ptr*", &idPtr)
                        id := (idPtr) ? StrGet(idPtr, "UTF-16") : ""
                        if (idPtr) {
                            DllCall("Ole32\CoTaskMemFree", "ptr", idPtr)
                            idPtr := 0
                        }

                        ComCall(4, device, "uint", 0, "ptr*", &propertyStore := 0)
                        if (!propertyStore)
                            continue

                        keyGUID := Buffer(16)
                        DllCall("Ole32\CLSIDFromString", "str", "{A45C254E-DF1C-4EFD-8020-67D146A850E0}", "ptr", keyGUID)
                        propKey := Buffer(20)
                        DllCall("RtlMoveMemory", "ptr", propKey, "ptr", keyGUID, "ptr", 16)
                        NumPut("uint", 14, propKey, 16)

                        propVariant := Buffer(24, 0)
                        ComCall(5, propertyStore, "ptr", propKey, "ptr", propVariant)

                        friendlyName := ""
                        if (NumGet(propVariant, 0, "ushort") = 31) {
                            namePtr := NumGet(propVariant, 8, "ptr")
                            friendlyName := StrGet(namePtr, "UTF-16")
                        }
                        DllCall("Ole32\PropVariantClear", "ptr", propVariant)

                        if (InStr(friendlyName, micNameSubstr)) {
                            micId := id
                        }
                    } finally {
                        if (idPtr)
                            DllCall("Ole32\CoTaskMemFree", "ptr", idPtr)
                        if (propertyStore)
                            ObjRelease(propertyStore)
                        if (device)
                            ObjRelease(device)
                    }

                    if (micId != "")
                        break
                }

                if (micId != "") {
                    defaultMicId := ""
                    defaultMicDevice := 0
                    defaultMicIdPtr := 0
                    try {
                        ComCall(4, deviceEnumerator, "int", 1, "int", 0, "ptr*", &defaultMicDevice := 0)
                        if (defaultMicDevice) {
                            ComCall(5, defaultMicDevice, "ptr*", &defaultMicIdPtr)
                            if (defaultMicIdPtr) {
                                defaultMicId := StrGet(defaultMicIdPtr, "UTF-16")
                                DllCall("Ole32\CoTaskMemFree", "ptr", defaultMicIdPtr)
                                defaultMicIdPtr := 0
                            }
                        }
                    } finally {
                        if (defaultMicIdPtr)
                            DllCall("Ole32\CoTaskMemFree", "ptr", defaultMicIdPtr)
                        if (defaultMicDevice)
                            ObjRelease(defaultMicDevice)
                    }

                    if (micId != defaultMicId) {
                        try {
                            ComCall(13, IPolicyConfig, "Str", micId, "UInt", 0)
                            ComCall(13, IPolicyConfig, "Str", micId, "UInt", 1)
                            ComCall(13, IPolicyConfig, "Str", micId, "UInt", 2)
                        } catch as e {
                            ShowTransientToolTip("Could not switch default microphone")
                            ShowLaunchError("Microphone switch failed", e)
                        }
                    }
                }
            } finally {
                if (micsCollection)
                    ObjRelease(micsCollection)
            }
        }
    } catch as e {
        ShowLaunchError("Audio Switch Error", e)
    } finally {
        if (devicesCollection)
            ObjRelease(devicesCollection)
        deviceEnumerator := 0
    }
}


; ====================[ Subroutines & Timers ]====================
RemoveToolTip() {
    ToolTip()
}

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
        SetTimer RemoveToolTip, -1000
        Reload()
    }
}

; ====================[ Hotkeys ]====================
!0:: RunApp("calc.exe", "", "Calculator")

!1:: {
    doublePress() {
        photoshopPath := AppResolver.Get("Photoshop", "Photoshop.exe", [
            "%ProgramFiles%\Adobe\Adobe Photoshop 2024\Photoshop.exe",
            "%ProgramFiles%\Adobe\Adobe Photoshop 2023\Photoshop.exe",
            "%ProgramFiles%\Adobe\Adobe Photoshop 2022\Photoshop.exe",
            "%ProgramFiles%\Adobe\Adobe Photoshop 2021\Photoshop.exe",
            "%ProgramFiles%\Adobe\Adobe Photoshop 2020\Photoshop.exe",
            "%ProgramFiles%\Adobe\Adobe Photoshop CC 2019\Photoshop.exe",
            "%ProgramFilesCommon%\Adobe Photoshop.lnk",
            "%StartMenuCommon%\Programs\Adobe Photoshop.lnk",
            "%StartMenu%\Programs\Adobe Photoshop.lnk"
        ])
        SplitPath photoshopPath, , &photoshopDir
        RunApp(photoshopPath, "", "Photoshop", photoshopDir)
    }
    DoublePressManager.Handle("Photoshop", "", doublePress)
}

LaunchRazer71() {
    razer71Path := AppResolver.Get("Razer71", "rzappengine.exe", [
        "%ProgramFiles%\Razer\RzAppEngine\rzappengine.exe",
        "%StartMenuCommon%\Programs\Razer\7.1 Surround Sound.lnk"
    ])
    SplitPath razer71Path, , &razer71Dir
    RunApp(razer71Path, "--url-params=apps=7.1-surround-sound --disable-background-timer-throttling",
        "7.1 Surround Sound", razer71Dir)
}

ProcessWatchdog.Register("rzappengine.exe", "7.1 Surround Sound", LaunchRazer71)

!7:: LaunchRazer71()

!a:: {
    antigravityPath := AppResolver.Get("Antigravity", "Antigravity IDE.exe", [
        "%LocalAppData%\Programs\Antigravity IDE\Antigravity IDE.exe",
        "%LocalAppData%\Programs\Antigravity IDE\bin\antigravity-ide.cmd",
        "%ProgramFiles%\Antigravity IDE\Antigravity IDE.exe",
        "%ProgramFiles(x86)%\Antigravity IDE\Antigravity IDE.exe",
        "%StartMenu%\Programs\Antigravity\Antigravity.lnk",
        "%StartMenu%\Programs\Antigravity IDE\Antigravity IDE.lnk"
    ])
    HandleContextHotkey("a", "Antigravity", antigravityPath)
}

#MaxThreadsPerHotkey 1
!c:: {
    pressStart := A_TickCount

    KeyWait "c", "T" . (LONG_PRESS_THRESHOLD / 1000)

    pressDuration := A_TickCount - pressStart

    chromePath := AppResolver.Get("Chrome", "chrome.exe")
    if (chromePath = "chrome.exe" && !FileExist(chromePath) && !SearchSystemPath(chromePath)) {
        ShowTransientToolTip("Opening Default Browser")
        try {
            if (pressDuration >= LONG_PRESS_THRESHOLD)
                Run(ResolveNativePath("cmd.exe") . " /c start microsoft-edge:-private")
            else
                Run(ResolveNativePath("cmd.exe") . " /c start https://www.google.com")
        } catch as e {
            ShowLaunchError("Failed to launch Browser", e)
        }
        KeyWait "c", "T2"
        return
    }

    if (pressDuration >= LONG_PRESS_THRESHOLD) {
        guard := Wow64RedirectionGuard()
        try
            Run('"' . chromePath . '" --incognito')
        catch as e {
            ShowLaunchError("Failed to launch Chrome", e)
            KeyWait "c"
            return
        }
        KeyWait "c"
    } else {
        KeyWait "c"
        guard := Wow64RedirectionGuard()
        try
            Run('"' . chromePath . '"')
        catch as e {
            ShowLaunchError("Failed to launch Chrome", e)
            return
        }
    }

    if WinWait("ahk_exe chrome.exe", , WINDOW_WAIT_TIMEOUT) {
        try WinMaximize("ahk_exe chrome.exe")
    } else
        ShowTransientToolTip("Chrome window not detected")
}
#MaxThreadsPerHotkey 1

!e:: {
    outlookPath := AppResolver.Get("Outlook", "", [
        "%AppData%\Microsoft\Windows\Start Menu\Programs\Chrome Apps\Outlook (PWA).lnk",
        "%StartMenuCommon%\Programs\Chrome Apps\Outlook (PWA).lnk"
    ])
    if (outlookPath != "" && FileExist(outlookPath)) {
        LaunchAndMaximize(outlookPath, "Outlook", WINDOW_WAIT_TIMEOUT, "Outlook")
    } else {
        try {
            RunApp("ms-outlook://", "", "Outlook")
        } catch {
            RunApp("https://outlook.live.com", "", "Outlook")
        }
    }
}

!g:: {
    gitBashPath := AppResolver.Get("GitBash", "git-bash.exe", [
        "%ProgramFiles%\Git\git-bash.exe",
        "%ProgramFiles(x86)%\Git\git-bash.exe"
    ], [
        "HKEY_LOCAL_MACHINE\SOFTWARE\GitForWindows|InstallPath"
    ])
    HandleContextHotkey("g", "Git Bash", gitBashPath, "--cd-to-home", "--cd=")
}

!i:: {
    instagramPath := AppResolver.Get("Instagram", "", [
        "%AppData%\Microsoft\Windows\Start Menu\Programs\Chrome Apps\Instagram.lnk",
        "%StartMenuCommon%\Programs\Chrome Apps\Instagram.lnk",
        "%ProgramFiles%\Instagram.lnk",
        "%StartMenuCommon%\Programs\Instagram.lnk",
        "%StartMenu%\Programs\Instagram.lnk"
    ])
    if (instagramPath != "" && FileExist(instagramPath)) {
        ShowTransientToolTip("Instagram")
        LaunchAndMaximize(instagramPath, "Instagram", WINDOW_WAIT_TIMEOUT, "Instagram")
    } else {
        try {
            RunApp("instagram://", "", "Instagram")
        } catch {
            RunApp("https://www.instagram.com", "", "Instagram")
        }
    }
}

!m:: RunApp("ms-windows-store:", "", "Microsoft Store")

!n:: RunApp("notepad.exe", "", "Notepad")

#MaxThreadsPerHotkey 1
!p:: {
    pressStart := A_TickCount
    KeyWait "p", "T" . (LONG_PRESS_THRESHOLD / 1000)
    pressDuration := A_TickCount - pressStart

    if (pressDuration >= LONG_PRESS_THRESHOLD) {
        dir := GetValidExplorerPath()
        if (dir != "") {
            ShowTransientToolTip("Admin PowerShell in Folder")
            try {
                LaunchAndPosition("*RunAs powershell.exe", dir)
            } catch as e {
                if (A_LastError != 1223)
                    ShowLaunchError("Failed to launch Admin PowerShell in Folder", e)
            }
        }
        KeyWait "p"
    } else {
        singlePress() {
            ShowTransientToolTip("PowerShell")
            try
                LaunchAndPosition("powershell.exe", USER_HOME)
            catch as e
                ShowLaunchError("Failed to launch PowerShell", e)
        }
        doublePress() {
            winClass := ""
            try winClass := WinGetClass("A")
            dir := ""
            if (winClass = "CabinetWClass" || winClass = "ExploreWClass")
                dir := GetExplorerPath()

            if (dir != "") {
                ShowTransientToolTip("PowerShell in Folder")
                try
                    LaunchAndPosition("powershell.exe", dir)
                catch as e
                    ShowLaunchError("Failed to launch PowerShell", e)
            } else {
                ShowTransientToolTip("Admin PowerShell")
                try
                    LaunchAndPosition("*RunAs powershell.exe", USER_HOME)
                catch as e {
                    if (A_LastError != 1223)
                        ShowLaunchError("Failed to launch Admin PowerShell", e)
                }
            }
        }
        DoublePressManager.Handle("PowerShell", singlePress, doublePress)
    }
}
#MaxThreadsPerHotkey 1

!q:: {
    isFirst := true
    while GetKeyState("q", "P") && GetKeyState("Alt", "P") {
        if !WinExist("A")
            break
        try {
            activeClass := WinGetClass("A")
            if IsProtectedWindowClass(activeClass) {
                ShowTransientToolTip("Nothing to close")
                break
            }
            WinClose "A"
        } catch {
            break
        }
        if (isFirst) {
            Sleep 400
            isFirst := false
        } else {
            Sleep 250
        }
    }
}

#MaxThreadsPerHotkey 1
!o:: {
    pressStart := A_TickCount
    KeyWait "o", "T" . (LONG_PRESS_THRESHOLD / 1000)
    pressDuration := A_TickCount - pressStart

    if (pressDuration >= LONG_PRESS_THRESHOLD) {
        dir := GetValidExplorerPath()
        if (dir != "") {
            ShowTransientToolTip("Admin CMD in Folder")
            try {
                LaunchAndPosition("*RunAs cmd.exe", dir)
            } catch as e {
                if (A_LastError != 1223)
                    ShowLaunchError("Failed to launch Admin CMD in Folder", e)
            }
        }
        KeyWait "o"
    } else {
        singlePress() {
            ShowTransientToolTip("CMD")
            try
                LaunchAndPosition("cmd.exe", USER_HOME)
            catch as e
                ShowLaunchError("Failed to launch CMD", e)
        }
        doublePress() {
            winClass := ""
            try winClass := WinGetClass("A")
            dir := ""
            if (winClass = "CabinetWClass" || winClass = "ExploreWClass")
                dir := GetExplorerPath()

            if (dir != "") {
                ShowTransientToolTip("CMD in Folder")
                try
                    LaunchAndPosition("cmd.exe", dir)
                catch as e
                    ShowLaunchError("Failed to launch CMD", e)
            } else {
                ShowTransientToolTip("Admin CMD")
                try
                    LaunchAndPosition("*RunAs cmd.exe", USER_HOME)
                catch as e {
                    if (A_LastError != 1223)
                        ShowLaunchError("Failed to launch Admin CMD", e)
                }
            }
        }
        DoublePressManager.Handle("CMD", singlePress, doublePress)
    }
}
#MaxThreadsPerHotkey 1

!s:: {
    slackPath := AppResolver.Get("Slack", "slack.exe", [
        "%LocalAppData%\slack\slack.exe",
        "%ProgramFiles%\Slack\slack.exe",
        "%StartMenuCommon%\Programs\Slack.lnk"
    ])
    if (slackPath != "" && (FileExist(slackPath) || SearchSystemPath(slackPath))) {
        LaunchAndMaximize(slackPath, "ahk_exe slack.exe", WINDOW_WAIT_TIMEOUT, "Slack")
    } else {
        RunApp("slack://", "", "Slack")
    }
}

!t:: {
    telegramPath := AppResolver.Get("Telegram", "", [
        "%AppData%\Microsoft\Windows\Start Menu\Programs\Chrome Apps\Telegram Web.lnk",
        "%StartMenuCommon%\Programs\Chrome Apps\Telegram Web.lnk"
    ])
    if (telegramPath != "" && FileExist(telegramPath)) {
        ShowTransientToolTip("Telegram")
        LaunchAndMaximize(telegramPath, "Telegram", WINDOW_WAIT_TIMEOUT)
    } else {
        RunApp("tg://", "", "Telegram")
    }
}

!u:: {
    singlePress() {
        ShowTransientToolTip("WSL")
        try
            LaunchAndPosition('wsl.exe --cd ~')
        catch as e
            ShowTransientToolTip("Failed to launch WSL`nIs WSL installed? " . e.Message)
    }
    doublePress() {
        dir := GetValidExplorerPath()
        if (dir != "") {
            ShowTransientToolTip("WSL")
            try
                LaunchAndPosition('wsl.exe --cd "' . dir . '"')
            catch as e
                ShowTransientToolTip("Failed to launch WSL`nIs WSL installed? " . e.Message)
        }
    }
    DoublePressManager.Handle("WSL", singlePress, doublePress)
}

!v:: {
    vscodePath := AppResolver.Get("VSCode", "Code.exe", [
        "%LocalAppData%\Programs\Microsoft VS Code\Code.exe",
        "%ProgramFiles%\Microsoft VS Code\Code.exe"
    ])
    if (vscodePath != "" && (FileExist(vscodePath) || SearchSystemPath(vscodePath))) {
        HandleContextHotkey("v", "VS Code", vscodePath)
    } else {
        RunApp("https://vscode.dev", "", "VS Code Web")
    }
}

!+v:: {
    static isPasting := false
    if (isPasting)
        return

    clipText := Trim(A_Clipboard, '`t`n`r "')
    if (clipText != "" && (RegExMatch(clipText, "i)^[A-Z]:") || InStr(clipText, "\"))) {
        isPasting := true
        wslPath := ConvertToWSLPath(clipText)
        oldClip := ClipboardAll()
        A_Clipboard := wslPath
        Send("^v")
        Sleep 50
        A_Clipboard := oldClip
        isPasting := false
    } else {
        Send("^v")
    }
}

!w:: {
    whatsappPath := AppResolver.Get("WhatsApp", "", [
        "%AppData%\Microsoft\Windows\Start Menu\Programs\Chrome Apps\WhatsApp Web.lnk",
        "%StartMenuCommon%\Programs\Chrome Apps\WhatsApp Web.lnk",
        "%ProgramFiles%\WhatsApp.lnk",
        "%StartMenuCommon%\Programs\WhatsApp.lnk",
        "%StartMenu%\Programs\WhatsApp.lnk"
    ])
    if (whatsappPath != "" && (FileExist(whatsappPath) || InStr(whatsappPath, "\") = 0)) {
        ShowTransientToolTip("WhatsApp")
        LaunchAndMaximize(whatsappPath, "WhatsApp", WINDOW_WAIT_TIMEOUT, "WhatsApp")
    } else {
        RunApp("whatsapp://", "", "WhatsApp")
    }
}

!y:: {
    youtubePath := AppResolver.Get("YouTube", "", [
        "%AppData%\Microsoft\Windows\Start Menu\Programs\Chrome Apps\YouTube.lnk",
        "%StartMenuCommon%\Programs\Chrome Apps\YouTube.lnk"
    ])
    if (youtubePath != "" && FileExist(youtubePath)) {
        LaunchAndMaximize(youtubePath, "YouTube", WINDOW_WAIT_TIMEOUT, "YouTube")
    } else {
        RunApp("https://www.youtube.com", "", "YouTube")
    }
}

!z:: ExtractSelectedZip()

^+!Delete:: {
    result := MsgBox("Are you sure you want to permanently delete all items in the Recycle Bin?", "Empty Recycle Bin",
        4)
    if (result = "Yes") {
        try {
            DllCall("shell32\SHEmptyRecycleBin", "Ptr", 0, "Ptr", 0, "UInt", 0x1)
            ShowTransientToolTip("Recycle Bin emptied")
        } catch as e {
            ShowLaunchError("Failed to empty Recycle Bin", e)
        }
    }
}

^+q:: SetAudioOutput(AUDIO_DEVICE_1, 25, "Sony MDRX-50", AUDIO_MIC_1)
^+x:: SetAudioOutput(AUDIO_DEVICE_1, , "Black Shark V2", AUDIO_MIC_2)
^+y:: SetAudioOutput(AUDIO_DEVICE_2, , "Resound", AUDIO_MIC_1)
^+z:: SetAudioOutput(AUDIO_DEVICE_3, , "Heat", AUDIO_MIC_1)
