; ==================[ Hotkey Reference ]==================
; Alt + 0  → Calculator
; Alt + 1  → Photoshop (Double)
; Alt + A  → Antigravity            | Double: Current Folder
; Alt + C  → Chrome                 | Hold: Incognito
; Alt + G  → Git Bash               | Double: Current Folder
; Alt + I  → Instagram
; Alt + M  → Microsoft Store
; Alt + N  → Notepad
; Alt + O  → CMD                    | Double: Admin
; Alt + P  → PowerShell             | Double: Current Folder
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
; Ctrl + Shift + Alt + C   → Cleanup
; Ctrl + Shift + Alt + L   → Logs
; Ctrl + Shift + Alt + N   → Network Reset
; Ctrl + Shift + Alt + U   → Windows Update
; Ctrl + Shift + Alt + Del → Empty Recycle Bin

; ====================[ Script Config & Variables ]====================
#Requires AutoHotkey v2.0.26
#SingleInstance Force
#Warn
Persistent()
SendMode "Input"
SetWorkingDir A_ScriptDir

SetTimer WatchScript, 1000

USER_HOME := EnvGet("USERPROFILE")
global DOUBLE_PRESS_DELAY   := GetEnvInt("AHK_DOUBLE_PRESS_DELAY", 400)
global LOGS_DIR             := USER_HOME . "\sys-scripts\logs"
global LONG_PRESS_THRESHOLD := GetEnvInt("AHK_LONG_PRESS_THRESHOLD", 600)
global ScriptModTime        := ""
global TOOLTIP_DURATION_MS  := GetEnvInt("AHK_TOOLTIP_DURATION_MS", 2000)
global WINDOW_WAIT_TIMEOUT  := GetEnvInt("AHK_WINDOW_WAIT_TIMEOUT", 5)
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
    if (initVol = 25) {
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

class Wow64RedirectionGuard {
    oldRedir := 0

    __New() {
        if (A_Is64bitOS && A_PtrSize = 4) {
            oldVal := 0
            DllCall("Wow64DisableWow64FsRedirection", "Ptr*", &oldVal)
            this.oldRedir := oldVal
        }
    }

    __Delete() {
        if (this.oldRedir != 0) {
            DllCall("Wow64RevertWow64FsRedirection", "Ptr", this.oldRedir)
            this.oldRedir := 0
        }
    }
}

ConvertToWSLPath(winPath) {
    if (winPath = "")
        return ""
    unixPath := StrReplace(winPath, "\", "/")
    if (SubStr(unixPath, 2, 1) = ":") {
        drive := Format("{:L}", SubStr(unixPath, 1, 1))
        unixPath := "/mnt/" . drive . SubStr(unixPath, 3)
    }
    return unixPath
}

DeleteFileIfExists(path) {
    if (path != "" && FileExist(path))
        FileDelete(path)
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
    targetDir := fileDir . "\" . nameNoExt . "\"
    winrarPath := AppResolver.Get("WinRAR", "WinRAR.exe", ["%ProgramFiles%\WinRAR\WinRAR.exe", "%ProgramFiles(x86)%\WinRAR\WinRAR.exe"])
    if FileExist(winrarPath) {
        guard := Wow64RedirectionGuard()
        Run('"' . winrarPath . '" x -o+ "' . selectedPath . '" "' . targetDir . '"')
    } else {
        safeSelectedPath := StrReplace(selectedPath, "'", "''")
        safeTargetDir := StrReplace(targetDir, "'", "''")
        guard := Wow64RedirectionGuard()
        Run("powershell.exe -NoProfile -Command `"Expand-Archive -Path '" . safeSelectedPath . "' -DestinationPath '" . safeTargetDir . "' -Force`"", , "Hide")
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

        this.cache[appKey] := resolvedPath
        return resolvedPath
    }

    static ExpandEnvVars(str) {
        if (!InStr(str, "%"))
            return str
        
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
                    ComCall(3, shellBrowser, "ptr*", &thisTab)
                    if (thisTab != activeTab)
                        continue
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
    hwnd := WinExist("A")
    for window in ComObject("Shell.Application").Windows {
        if (window.hwnd = hwnd) {
            for item in window.Document.SelectedItems
                return item.Path
        }
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
            RunApp(path, dPre . '"' . dir . '"')
        }
    } else {
        lastPresses[key] := now
        timerFn := RunAppAndNotify.Bind(path, sArgs, name)
        timers[key] := timerFn
        SetTimer timerFn, -DOUBLE_PRESS_DELAY
    }
}

IsProtectedWindowClass(windowClass) {
    return (windowClass = "Shell_TrayWnd" || windowClass = "Progman" || windowClass = "WorkerW")
}

SmartRun(targetPath, args := "", workingDir := "") {
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

LaunchAndMaximize(appPath, windowIdentifier := "", timeout := "") {
    if (timeout = "")
        timeout := WINDOW_WAIT_TIMEOUT

    if (InStr(appPath, "\") && !FileExist(appPath)) {
        MsgBox("Application not found:`n" . appPath, "Error", 16)
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
        MsgBox("Failed to launch:`n" . appPath . "`n`nError: " . e.Message, "Launch Error", 16)
        return false
    }

    if (windowIdentifier != "") {
        if WinWait(windowIdentifier, , timeout)
            WinMaximize
        else {
            ToolTip("Window not detected: " . windowIdentifier)
            SetTimer RemoveToolTip, -TOOLTIP_DURATION_MS
        }
    }

    return true
}

RunApp(path, args := "", name := "") {
    if (name != "")
        ShowTransientToolTip(name)
    try {
        if InStr(path, "://") {
            Run(path)
        } else {
            if (InStr(path, "\") && !FileExist(path)) {
                MsgBox("Target not found:`n" . path, "Error", 16)
                return
            }
            SmartRun(path, args)
        }
    } catch as e {
        ShowLaunchError("Launch Error", e)
    }
}

RunAppAndNotify(path, args, name) {
    ShowTransientToolTip(name)
    RunApp(path, args)
}

ShowLaunchError(prefix, err) {
    msg := (err is Error) ? err.Message : String(err)
    ShowTransientToolTip(prefix . ": " . msg)

    try {
        if !DirExist(LOGS_DIR)
            DirCreate(LOGS_DIR)

        logFile := LOGS_DIR . "\hotkey_errors.log"
        if FileExist(logFile) {
            if (FileGetSize(logFile) >= 2097152) {
                FileDelete(logFile)
            }
        }

        timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
        logLine := "[" . timestamp . "] " . prefix . ": " . msg . "`n"
        if (err is Error) {
            logLine .= "  File: " . err.File . "`n"
            logLine .= "  Line: " . err.Line . "`n"
            logLine .= "  What: " . err.What . "`n"
            logLine .= "  Extra: " . err.Extra . "`n"
        }
        logLine .= "----------------------------------------`n"

        FileAppend(logLine, logFile, "UTF-8")
    }
}

ShowTransientToolTip(message, durationMs := "") {
    if (durationMs = "")
        durationMs := TOOLTIP_DURATION_MS
    ToolTip(message)
    SetTimer RemoveToolTip, -durationMs
}

SetAudioOutput(deviceNameSubstr, targetVolume := "", friendlyNameOverride := "", micNameSubstr := "") {
    global LAST_SURROUND_VOLUME
    try {
        deviceEnumerator := ComObject("{BCDE0395-E52F-467C-8E3D-C4579291692E}", "{A95664D2-9614-4F35-A746-DE8DB63617E6}")

        ; 1. Switch Playback Device
        devicesCollection := 0
        ComCall(3, deviceEnumerator, "int", 0, "uint", 1, "ptr*", &devicesCollection := 0)

        count := 0
        ComCall(3, devicesCollection, "uint*", &count)

        targetId := ""
        targetName := ""

        Loop count {
            device := 0
            ComCall(4, devicesCollection, "uint", A_Index - 1, "ptr*", &device := 0)

            idPtr := 0
            ComCall(5, device, "ptr*", &idPtr)
            id := StrGet(idPtr, "UTF-16")
            DllCall("Ole32\CoTaskMemFree", "ptr", idPtr)

            propertyStore := 0
            ComCall(4, device, "uint", 0, "ptr*", &propertyStore := 0)

            keyGUID := Buffer(16)
            DllCall("Ole32\CLSIDFromString", "str", "{A45C254E-DF1C-4EFD-8020-67D146A850E0}", "ptr", keyGUID)
            propKey := Buffer(20)
            DllCall("RtlMoveMemory", "ptr", propKey, "ptr", keyGUID, "ptr", 16)
            NumPut("uint", 14, propKey, 16)

            propVariant := Buffer(16, 0)
            ComCall(5, propertyStore, "ptr", propKey, "ptr", propVariant)

            friendlyName := ""
            if (NumGet(propVariant, 0, "ushort") = 31) {
                namePtr := NumGet(propVariant, 8, "ptr")
                friendlyName := StrGet(namePtr, "UTF-16")
            }

            if (InStr(friendlyName, deviceNameSubstr)) {
                targetId := id
                targetName := friendlyName
            }

            ObjRelease(propertyStore)
            ObjRelease(device)

            if (targetId != "")
                break
        }

        ObjRelease(devicesCollection)

        if (targetId = "") {
            ShowTransientToolTip("Audio device not found: " . deviceNameSubstr)
            return
        }

        defaultId := ""
        try {
            defaultDevice := 0
            ComCall(4, deviceEnumerator, "int", 0, "int", 0, "ptr*", &defaultDevice := 0)
            defaultIdPtr := 0
            ComCall(5, defaultDevice, "ptr*", &defaultIdPtr)
            defaultId := StrGet(defaultIdPtr, "UTF-16")
            DllCall("Ole32\CoTaskMemFree", "ptr", defaultIdPtr)
            ObjRelease(defaultDevice)
        }

        global LAST_DEVICE, DEVICE_VOLUME_HISTORY
        if (LAST_DEVICE != "") {
            try {
                DEVICE_VOLUME_HISTORY[LAST_DEVICE] := SoundGetVolume()
            }
        }

        IPolicyConfig := ComObject("{870AF99C-171D-4F9E-AF0D-E63DF40C2BC9}", "{F8679F50-850A-41CF-9C72-430F290290C8}")
        if (targetId != defaultId) {
            ComCall(13, IPolicyConfig, "Str", targetId, "UInt", 0)
            ComCall(13, IPolicyConfig, "Str", targetId, "UInt", 1)
            ComCall(13, IPolicyConfig, "Str", targetId, "UInt", 2)
        }

        dispName := (friendlyNameOverride != "") ? friendlyNameOverride : targetName
        ShowTransientToolTip("Active: " . dispName)

        if (targetVolume != "") {
            Sleep 300
            SoundSetVolume(targetVolume)
        } else if (DEVICE_VOLUME_HISTORY.Has(friendlyNameOverride)) {
            Sleep 300
            SoundSetVolume(DEVICE_VOLUME_HISTORY[friendlyNameOverride])
        }
        LAST_DEVICE := friendlyNameOverride

        ; 2. Switch Recording Device (Microphone)
        if (micNameSubstr != "") {
            micsCollection := 0
            ComCall(3, deviceEnumerator, "int", 1, "uint", 1, "ptr*", &micsCollection := 0)
            micCount := 0
            ComCall(3, micsCollection, "uint*", &micCount)

            micId := ""
            Loop micCount {
                device := 0
                ComCall(4, micsCollection, "uint", A_Index - 1, "ptr*", &device := 0)

                idPtr := 0
                ComCall(5, device, "ptr*", &idPtr)
                id := StrGet(idPtr, "UTF-16")
                DllCall("Ole32\CoTaskMemFree", "ptr", idPtr)

                propertyStore := 0
                ComCall(4, device, "uint", 0, "ptr*", &propertyStore := 0)

                keyGUID := Buffer(16)
                DllCall("Ole32\CLSIDFromString", "str", "{A45C254E-DF1C-4EFD-8020-67D146A850E0}", "ptr", keyGUID)
                propKey := Buffer(20)
                DllCall("RtlMoveMemory", "ptr", propKey, "ptr", keyGUID, "ptr", 16)
                NumPut("uint", 14, propKey, 16)

                propVariant := Buffer(16, 0)
                ComCall(5, propertyStore, "ptr", propKey, "ptr", propVariant)

                friendlyName := ""
                if (NumGet(propVariant, 0, "ushort") = 31) {
                    namePtr := NumGet(propVariant, 8, "ptr")
                    friendlyName := StrGet(namePtr, "UTF-16")
                }

                if (InStr(friendlyName, micNameSubstr)) {
                    micId := id
                }

                ObjRelease(propertyStore)
                ObjRelease(device)

                if (micId != "")
                    break
            }
            ObjRelease(micsCollection)

            if (micId != "") {
                defaultMicId := ""
                try {
                    defaultMicDevice := 0
                    ComCall(4, deviceEnumerator, "int", 1, "int", 0, "ptr*", &defaultMicDevice := 0)
                    defaultMicIdPtr := 0
                    ComCall(5, defaultMicDevice, "ptr*", &defaultMicIdPtr)
                    defaultMicId := StrGet(defaultMicIdPtr, "UTF-16")
                    DllCall("Ole32\CoTaskMemFree", "ptr", defaultMicIdPtr)
                    ObjRelease(defaultMicDevice)
                }

                if (micId != defaultMicId) {
                    ComCall(13, IPolicyConfig, "Str", micId, "UInt", 0)
                    ComCall(13, IPolicyConfig, "Str", micId, "UInt", 1)
                    ComCall(13, IPolicyConfig, "Str", micId, "UInt", 2)
                }
            }
        }
    } catch as e {
        ShowLaunchError("Audio Switch Error", e)
    }
}

TriggerScheduledTask(taskName, friendlyName, triggerFile := "", resultFile := "", timeoutSec := 60) {
    if (taskName = "" || friendlyName = "") {
        ShowTransientToolTip("Scheduled task configuration is invalid")
        return
    }

    DeleteFileIfExists(resultFile)

    if (triggerFile != "") {
        DeleteFileIfExists(triggerFile)
        try
            FileAppend("hotkey", triggerFile)
        catch as e {
            ShowLaunchError("Failed to write trigger file", e)
            return
        }
    }

    guard := Wow64RedirectionGuard()
    try {
        Run('schtasks.exe /Run /TN "' . taskName . '" /I', , "Hide")
        ShowTransientToolTip(friendlyName . " in progress...")
    } catch as e {
        ShowLaunchError("Failed to trigger " . friendlyName, e)
        return
    }

    if (resultFile == "")
        return

    Loop (timeoutSec * 2) {
        Sleep 500
        if FileExist(resultFile) {
            Sleep 200
            ResultData := FileRead(resultFile)
            DeleteFileIfExists(resultFile)
            ToolTip()
            Parts := StrSplit(ResultData, "|")
            TrayTip(Parts[2], Parts[1], InStr(Parts[1], "success") ? 1 : 2)
            return
        }
    }
    ToolTip()
    TrayTip("Timed out - check logs", friendlyName, 3)
}

; ====================[ Subroutines & Timers ]====================
RemoveToolTip() {
    ToolTip()
}

WatchScript() {
    global ScriptModTime
    curModTime := FileGetTime(A_ScriptFullPath)
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
!0::RunApp("calc.exe", "", "Calculator")

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
        RunApp(photoshopPath, "", "Photoshop")
    }
    DoublePressManager.Handle("Photoshop", "", doublePress)
}

!a:: {
    antigravityPath := AppResolver.Get("Antigravity", "antigravity-ide.cmd", [
        "%LocalAppData%\Programs\Antigravity IDE\Antigravity IDE.exe",
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
    if (chromePath = "chrome.exe" && !FileExist(chromePath)) {
        MsgBox("Chrome not found.", "Error", 16)
        KeyWait "c", "T2"
        return
    }

    if (pressDuration >= LONG_PRESS_THRESHOLD) {
        guard := Wow64RedirectionGuard()
        try
            Run('"' . chromePath . '" --incognito')
        catch as e {
            ShowLaunchError("Failed to launch Chrome", e)
            KeyWait "c", "T2"
            return
        }
        KeyWait "c", "T2"
    } else {
        KeyWait "c", "T2"
        guard := Wow64RedirectionGuard()
        try
            Run('"' . chromePath . '"')
        catch as e {    
            ShowLaunchError("Failed to launch Chrome", e)
            return
        }
    }

    if WinWait("ahk_exe chrome.exe", , WINDOW_WAIT_TIMEOUT)
        WinMaximize
    else
        ShowTransientToolTip("Chrome window not detected")
}
#MaxThreadsPerHotkey 1

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
        "%ProgramFiles%\Instagram.lnk",
        "%StartMenuCommon%\Programs\Instagram.lnk",
        "%StartMenu%\Programs\Instagram.lnk"
    ])
    ShowTransientToolTip("Instagram")
    LaunchAndMaximize(instagramPath, "Instagram", WINDOW_WAIT_TIMEOUT)
}

!m::RunApp("ms-windows-store:", "", "Microsoft Store")

!n::RunApp("notepad.exe", "", "Notepad")

!p:: {
    singlePress() {
        ShowTransientToolTip("PowerShell")
        guard := Wow64RedirectionGuard()
        try
            Run("powershell.exe", USER_HOME)
        catch as e
            ShowLaunchError("Failed to launch PowerShell", e)
    }
    doublePress() {
        winClass := WinGetClass("A")
        dir := ""
        if (winClass = "CabinetWClass" || winClass = "ExploreWClass")
            dir := GetExplorerPath()
        
        if (dir != "") {
            ShowTransientToolTip("PowerShell in Folder")
            guard := Wow64RedirectionGuard()
            try
                Run("powershell.exe", dir)
            catch as e
                ShowLaunchError("Failed to launch PowerShell", e)
        } else {
            singlePress()
        }
    }
    DoublePressManager.Handle("PowerShell", singlePress, doublePress)
}

!q:: {
    while GetKeyState("q", "P") && GetKeyState("Alt", "P") {
        activeClass := WinGetClass("A")
        if IsProtectedWindowClass(activeClass) {
            ShowTransientToolTip("Cannot close system window")
            break
        }
        WinClose "A"
        Sleep 100
    }
}

!o:: {
    singlePress() {
        ShowTransientToolTip("CMD")
        guard := Wow64RedirectionGuard()
        try
            Run("cmd.exe", USER_HOME)
        catch as e
            ShowLaunchError("Failed to launch CMD", e)
    }
    doublePress() {
        winClass := WinGetClass("A")
        dir := ""
        if (winClass = "CabinetWClass" || winClass = "ExploreWClass")
            dir := GetExplorerPath()

        if (dir != "") {
            ShowTransientToolTip("Admin CMD in Folder")
            guard := Wow64RedirectionGuard()
            try
                Run('*RunAs cmd.exe /K cd /d "' . dir . '"')
            catch as e {
                if (A_LastError != 1223)
                    ShowLaunchError("Failed to launch Admin CMD", e)
            }
        } else {
            ShowTransientToolTip("Admin CMD")
            guard := Wow64RedirectionGuard()
            try
                Run("*RunAs cmd.exe", USER_HOME)
            catch as e {
                if (A_LastError != 1223)
                    ShowLaunchError("Failed to launch Admin CMD", e)
            }
        }
    }
    DoublePressManager.Handle("CMD", singlePress, doublePress)
}

!s:: {
    slackPath := AppResolver.Get("Slack", "slack.exe", [
        "%LocalAppData%\slack\slack.exe",
        "%ProgramFiles%\Slack\slack.exe",
        "%StartMenuCommon%\Programs\Slack.lnk"
    ])
    LaunchAndMaximize(slackPath, "ahk_exe slack.exe", WINDOW_WAIT_TIMEOUT)
}

!t::RunApp("tg://", "", "Telegram")

!u:: {
    singlePress() {
        ShowTransientToolTip("WSL")
        guard := Wow64RedirectionGuard()
        try
            Run('wsl.exe -- bash -lc "cd ~; exec bash"')
        catch as e
            ShowTransientToolTip("Failed to launch WSL`nIs WSL installed? " . e.Message)
    }
    doublePress() {
        dir := GetValidExplorerPath()
        if (dir != "") {
            unixPath := ConvertToWSLPath(dir)
            ShowTransientToolTip("WSL")
            guard := Wow64RedirectionGuard()
            try
                Run("wsl.exe -- bash -lc `"cd '" . unixPath . "'; exec bash`"")
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
    HandleContextHotkey("v", "VS Code", vscodePath)
}

!w:: {
    whatsappPath := AppResolver.Get("WhatsApp", "", [
        "%ProgramFiles%\WhatsApp.lnk",
        "%StartMenuCommon%\Programs\WhatsApp.lnk",
        "%StartMenu%\Programs\WhatsApp.lnk"
    ])
    ShowTransientToolTip("WhatsApp")
    LaunchAndMaximize(whatsappPath, "WhatsApp", WINDOW_WAIT_TIMEOUT)
}

!y:: {
    youtubePath := AppResolver.Get("YouTube", "", [
        "%AppData%\Microsoft\Windows\Start Menu\Programs\Chrome Apps\YouTube.lnk",
        "%StartMenuCommon%\Programs\Chrome Apps\YouTube.lnk"
    ])
    LaunchAndMaximize(youtubePath, "YouTube", WINDOW_WAIT_TIMEOUT)
}

!z::ExtractSelectedZip()

^+!c:: {
    TriggerScheduledTask("WindowsCleanup", "Cleanup"
        , USER_HOME . "\sys-scripts\cleanup\cleanup_trigger.txt"
        , USER_HOME . "\sys-scripts\cleanup\cleanup_result.txt", 60)
}

^+!Delete:: {
    result := MsgBox("Are you sure you want to permanently delete all items in the Recycle Bin?", "Empty Recycle Bin", 4)
    if (result = "Yes") {
        try {
            DllCall("shell32\SHEmptyRecycleBin", "Ptr", 0, "Ptr", 0, "UInt", 0x1)
            ShowTransientToolTip("Recycle Bin emptied")
        } catch as e {
            ShowLaunchError("Failed to empty Recycle Bin", e)
        }
    }
}

^+!l:: {
    if !FileExist(LOGS_DIR) {
        ShowTransientToolTip("Logs folder not found: " . LOGS_DIR)
        return
    }
    guard := Wow64RedirectionGuard()
    try
        Run('explorer.exe "' . LOGS_DIR . '"')
    catch as e
        ShowLaunchError("Failed to open logs folder", e)
}

^+!n:: {
    TriggerScheduledTask("NetworkReset", "Network Reset"
        , ""
        , USER_HOME . "\sys-scripts\network\netreset_result.txt", 90)
}

^+!u:: {
    today := FormatTime(, "yyyy-MM-dd")
    try
        lastRun := FileRead(USER_HOME . "\sys-scripts\update\update_lastrun.txt")
    catch
        lastRun := ""
    if (Trim(lastRun) = today) {
        ShowTransientToolTip("Update already completed today")
        return
    }
    TriggerScheduledTask("WindowsUpdater", "Update"
        , USER_HOME . "\sys-scripts\update\update_trigger.txt"
        , USER_HOME . "\sys-scripts\update\update_result.txt", 180)
}

^+q:: SetAudioOutput(AUDIO_DEVICE_1, 25, "Sony MDRX-50", AUDIO_MIC_1)
^+x:: SetAudioOutput(AUDIO_DEVICE_1, , "Black Shark V2", AUDIO_MIC_2)
^+y:: SetAudioOutput(AUDIO_DEVICE_2, , "Resound", AUDIO_MIC_1)
^+z:: SetAudioOutput(AUDIO_DEVICE_3, , "Heat", AUDIO_MIC_1)
