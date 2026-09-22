#Requires AutoHotkey v2.0.26
#SingleInstance Force
#Warn
Persistent()
SendMode "Input"
SetWorkingDir A_ScriptDir

; --- Module Inclusions ---

class Config {
    static DOUBLE_PRESS_DELAY := 400
    static LONG_PRESS_THRESHOLD := 600
    static TOOLTIP_DURATION_MS := 2000
    static WINDOW_WAIT_TIMEOUT := 5
    static WATCHDOG_INTERVAL_MS := 30000
    static WATCHDOG_ENABLED := true
    static LOGS_DIR := A_ScriptDir . "\logs"

    static AUDIO_DEVICE_1 := "Surround"
    static AUDIO_DEVICE_2 := "Resound"
    static AUDIO_DEVICE_3 := "Speakers (Realtek"
    static AUDIO_MIC_1 := "Microphone (Realtek(R) Audio)"
    static AUDIO_MIC_2 := "Razer"
    static AUDIO_MIC_3 := "Array"

    static Init() {
        this.DOUBLE_PRESS_DELAY := this.GetEnvInt("AHK_DOUBLE_PRESS_DELAY", 400)
        this.LONG_PRESS_THRESHOLD := this.GetEnvInt("AHK_LONG_PRESS_THRESHOLD", 600)
        this.TOOLTIP_DURATION_MS := this.GetEnvInt("AHK_TOOLTIP_DURATION_MS", 2000)
        this.WINDOW_WAIT_TIMEOUT := this.GetEnvInt("AHK_WINDOW_WAIT_TIMEOUT", 5)
        this.WATCHDOG_INTERVAL_MS := this.GetEnvInt("AHK_WATCHDOG_INTERVAL_MS", 30000)
        this.WATCHDOG_ENABLED := this.GetEnvInt("AHK_WATCHDOG_ENABLED", 1) ? true : false
        this.LOGS_DIR := this.GetEnvString("AHK_LOGS_DIR", A_ScriptDir . "\logs")

        this.AUDIO_DEVICE_1 := this.GetEnvString("AHK_AUDIO_DEVICE_1", "Surround")
        this.AUDIO_DEVICE_2 := this.GetEnvString("AHK_AUDIO_DEVICE_2", "Resound")
        this.AUDIO_DEVICE_3 := this.GetEnvString("AHK_AUDIO_DEVICE_3", "Speakers (Realtek")
        this.AUDIO_MIC_1 := this.GetEnvString("AHK_AUDIO_MIC_1", "Microphone (Realtek(R) Audio)")
        this.AUDIO_MIC_2 := this.GetEnvString("AHK_AUDIO_MIC_2", "Razer")
        this.AUDIO_MIC_3 := this.GetEnvString("AHK_AUDIO_MIC_3", "Array")
    }

    static GetEnvInt(varName, defaultValue) {
        val := EnvGet(varName)
        return (val != "" && IsInteger(val)) ? Integer(val) : defaultValue
    }

    static GetEnvString(varName, defaultValue) {
        val := EnvGet(varName)
        return (val != "") ? val : defaultValue
    }
}

class Logger {
    static MAX_LOG_SIZE := 5242880 ; 5 MB

    static Log(entry) {
        OutputDebug(entry)
        try {
            logsDir := Config.LOGS_DIR
            if !DirExist(logsDir)
                DirCreate(logsDir)

            logFile := logsDir . "\hotkey_errors.log"
            if FileExist(logFile) && FileGetSize(logFile) >= this.MAX_LOG_SIZE {
                oldLog := logsDir . "\hotkey_errors.log.old"
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

    static FormatError(prefix, err) {
        timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
        msg := (err is Error) ? err.Message : String(err)
        
        entry := "--------------------------------------------------------------------------------`n`n"
        entry .= "  [" . timestamp . "] " . prefix . "`n"
        entry .= "  Message: " . msg . "`n"
        if (err is Error) {
            entry .= "  File:    " . err.File . "`n"
            entry .= "  Line:    " . err.Line . "`n"
            entry .= "  What:    " . err.What . "`n"
            if (err.Extra != "")
                entry .= "  Extra:   " . err.Extra . "`n"
            if (err.Stack != "") {
                entry .= "  Stack:`n"
                for line in StrSplit(err.Stack, "`n", "`r") {
                    if (line != "")
                        entry .= "    " . line . "`n"
                }
            }
        }
        entry .= "`n--------------------------------------------------------------------------------`n`n"
        return entry
    }
}

class NotificationManager {
    static ShowTransient(message, durationMs := "") {
        if (durationMs = "")
            durationMs := Config.TOOLTIP_DURATION_MS

        ToolTip(message)
        SetTimer(() => ToolTip(), -durationMs)
    }

    static Clear() {
        ToolTip()
    }

    static Toast(title, message, icon := 1) {
        TrayTip(message, title, icon)
    }
}

ShowTransientToolTip(message, durationMs := "") {
    NotificationManager.ShowTransient(message, durationMs)
}

RemoveToolTip() {
    NotificationManager.Clear()
}

class ErrorHandler {
    static Init() {
        OnError((thrown, mode) => this.OnGlobalError(thrown, mode))
    }

    static OnGlobalError(thrown, mode) {
        try {
            entry := Logger.FormatError("UNHANDLED ERROR (" . mode . ")", thrown)
            Logger.Log(entry)
            TrayTip(thrown.Message, "Hotkey Error Logged", 2)
        }
        return -1
    }

    static HandleLaunchError(prefix, err) {
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
            entry := Logger.FormatError(prefix, err)
            Logger.Log(entry)
        }
    }
}

ShowLaunchError(prefix, err) {
    ErrorHandler.HandleLaunchError(prefix, err)
}

class ProcessWatchdog {
    static targets := Map()
    static restartHistory := Map()
    static maxRestarts := 3
    static windowMs := 300000

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

            if (!isRunning) {
                newPid := ProcessExist(exeName)
                if (newPid != 0) {
                    isRunning := true
                    info.pid := newPid
                    static PROCESS_QUERY_LIMITED_INFORMATION := 0x1000
                    static SYNCHRONIZE := 0x00100000
                    hProc := DllCall("OpenProcess", "uint", PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE, "int", false, "uint", newPid, "ptr")
                    if (hProc != 0)
                        info.hProcess := hProc
                }
            }

            if (isRunning) {
                info.wasRunning := true
            } else if (info.wasRunning) {
                history := this.restartHistory[exeName]
                recentRestarts := []
                for timestamp in history {
                    if (now - timestamp < this.windowMs)
                        recentRestarts.Push(timestamp)
                }
                this.restartHistory[exeName] := recentRestarts

                if (recentRestarts.Length >= this.maxRestarts) {
                    NotificationManager.Toast("Process Watchdog", info.name . " crashed repeatedly. Auto-restart suspended for safety.", 2)
                    info.wasRunning := false
                    continue
                }

                recentRestarts.Push(now)
                this.restartHistory[exeName] := recentRestarts

                try {
                    info.launcher()
                    NotificationManager.ShowTransient(info.name . " recovered")
                } catch as e {
                    ErrorHandler.HandleLaunchError("Watchdog Recovery: " . info.name, e)
                }

                info.wasRunning := false
            }
        }
    }
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

class Win32 {
    static ResolveNativePath(cmd) {
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

    static SearchSystemPath(exeName) {
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

    static IsProtectedWindowClass(windowClass) {
        return (windowClass = "Shell_TrayWnd" || windowClass = "Progman" || windowClass = "WorkerW"
            || windowClass = "ApplicationFrameHost"
            || windowClass = "Windows.UI.Core.CoreWindow"
            || windowClass = "SearchHost"
            || windowClass = "StartMenuExperienceHostWindow"
            || windowClass = "ImmersiveLauncher")
    }

    static SmartRun(targetPath, args := "", workingDir := "") {
        targetPath := this.ResolveNativePath(targetPath)
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
}

ResolveNativePath(cmd) => Win32.ResolveNativePath(cmd)
SearchSystemPath(exe) => Win32.SearchSystemPath(exe)
SmartRun(target, args := "", dir := "") => Win32.SmartRun(target, args, dir)
IsProtectedWindowClass(cls) => Win32.IsProtectedWindowClass(cls)

class ShellExplorer {
    static GetActiveExplorerPath() {
        hwnd := WinActive("A")
        if (!hwnd)
            return ""

        winClass := WinGetClass(hwnd)
        if (winClass = "Progman" || winClass = "WorkerW")
            return A_Desktop

        if (winClass != "CabinetWClass" && winClass != "ExploreWClass")
            return ""

        try {
            candidatePaths := []
            activeTabHwnd := 0
            try {
                focusedHwnd := DllCall("user32\GetFocus", "ptr")
                if (focusedHwnd && DllCall("user32\IsChild", "ptr", hwnd, "ptr", focusedHwnd))
                    activeTabHwnd := focusedHwnd
            }

            for window in ComObject("Shell.Application").Windows {
                try {
                    if (window.hwnd != hwnd)
                        continue

                    path := ""
                    try path := window.Document.Folder.Self.Path

                    if (path = "" || InStr(path, "::{")) {
                        try {
                            locUrl := window.LocationURL
                            if (locUrl != "" && RegExMatch(locUrl, "i)^file:///(.+)$", &m)) {
                                decoded := StrReplace(m[1], "/", "\")
                                decoded := StrReplace(decoded, "%20", " ")
                                if (DirExist(decoded))
                                    path := decoded
                            }
                        }
                    }

                    if (path != "" && !InStr(path, "::{") && DirExist(path)) {
                        if (activeTabHwnd) {
                            try {
                                static IID_IShellBrowser := "{000214E2-0000-0000-C000-000000000046}"
                                shellBrowser := ComObjQuery(window, IID_IShellBrowser, IID_IShellBrowser)
                                if (shellBrowser) {
                                    thisTab := 0
                                    ComCall(3, shellBrowser, "ptr*", &thisTab)
                                    ObjRelease(shellBrowser)
                                    if (thisTab && (thisTab == activeTabHwnd || DllCall("user32\IsChild", "ptr", thisTab, "ptr", activeTabHwnd)))
                                        return path
                                }
                            }
                        }
                        candidatePaths.Push(path)
                    }
                } catch {
                    continue
                }
            }

            if (candidatePaths.Length > 0)
                return candidatePaths[1]
        } catch {
        }

        try {
            loop 5 {
                ctrlName := "ToolbarWindow32" . A_Index
                try {
                    text := ControlGetText(ctrlName, hwnd)
                    if (text != "" && RegExMatch(text, "i)Address:\s*(.+)$", &m)) {
                        candidate := Trim(m[1])
                        if (DirExist(candidate))
                            return candidate
                    }
                }
            }
        } catch {
        }

        try {
            editPath := ControlGetText("Edit1", hwnd)
            if (editPath != "" && DirExist(editPath))
                return editPath
        } catch {
        }

        return ""
    }

    static GetSelectedFilePath() {
        hwnd := WinActive("A")
        if (!hwnd)
            return ""

        winClass := WinGetClass(hwnd)
        if (winClass != "CabinetWClass" && winClass != "ExploreWClass" && winClass != "Progman" && winClass != "WorkerW")
            return ""

        try {
            for window in ComObject("Shell.Application").Windows {
                try {
                    if (window.hwnd != hwnd)
                        continue

                    for item in window.Document.SelectedItems {
                        if (item.Path != "")
                            return item.Path
                    }
                } catch {
                    continue
                }
            }
        } catch as e {
            ErrorHandler.HandleLaunchError("Error getting selected file", e)
        }
        return ""
    }

    static GetValidExplorerPath() {
        hwnd := WinActive("A")
        if (!hwnd) {
            NotificationManager.ShowTransient("Please focus on a File Explorer window")
            return ""
        }

        winClass := WinGetClass(hwnd)
        if (winClass = "Progman" || winClass = "WorkerW")
            return A_Desktop

        if (winClass != "CabinetWClass" && winClass != "ExploreWClass") {
            NotificationManager.ShowTransient("Please focus on a File Explorer window")
            return ""
        }

        path := this.GetActiveExplorerPath()
        if (path = "") {
            sel := this.GetSelectedFilePath()
            if (sel != "") {
                if (DirExist(sel))
                    return sel
                SplitPath sel, , &parentDir
                if (parentDir != "" && DirExist(parentDir))
                    return parentDir
            }
            NotificationManager.ShowTransient("Could not get folder path")
            return ""
        }

        return path
    }
}

GetExplorerPath() => ShellExplorer.GetActiveExplorerPath()
GetSelectedFilePath() => ShellExplorer.GetSelectedFilePath()
GetValidExplorerPath() => ShellExplorer.GetValidExplorerPath()

class AudioEndpoint {
    static volumeHistory := Map()
    static lastDevice := ""

    static Init() {
        try {
            initVol := SoundGetVolume()
            if (Round(initVol) = 25) {
                this.lastDevice := "Sony MDRX-50"
                this.volumeHistory["Sony MDRX-50"] := 25
            } else {
                this.lastDevice := "Black Shark V2"
                this.volumeHistory["Black Shark V2"] := initVol
            }
        } catch {
        }
    }

    static SwitchOutput(deviceNameSubstr, targetVolume := "", friendlyNameOverride := "", micNameSubstr := "") {
        deviceEnumerator := 0
        devicesCollection := 0
        try {
            deviceEnumerator := ComObject("{BCDE0395-E52F-467C-8E3D-C4579291692E}",
                "{A95664D2-9614-4F35-A746-DE8DB63617E6}")

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
                NotificationManager.ShowTransient("Audio device not found: " . deviceNameSubstr)
                return
            }

            if (this.lastDevice != "" && defaultFriendlyName != "") {
                try {
                    this.volumeHistory[this.lastDevice] := SoundGetVolume("", defaultFriendlyName)
                }
            }

            IPolicyConfig := ComObject("{870AF99C-171D-4F9E-AF0D-E63DF40C2BC9}", "{F8679F50-850A-41CF-9C72-430F290290C8}")
            if (targetId != defaultId) {
                try {
                    ComCall(13, IPolicyConfig, "Str", targetId, "UInt", 0)
                    ComCall(13, IPolicyConfig, "Str", targetId, "UInt", 1)
                    ComCall(13, IPolicyConfig, "Str", targetId, "UInt", 2)
                } catch as e {
                    NotificationManager.ShowTransient("Could not switch default audio device")
                    ErrorHandler.HandleLaunchError("Audio device switch failed", e)
                    return
                }
            }

            dispName := (friendlyNameOverride != "") ? friendlyNameOverride : targetName
            NotificationManager.ShowTransient("Active: " . dispName)

            if (targetVolume != "") {
                SoundSetVolume(targetVolume, , targetName)
            } else if (this.volumeHistory.Has(friendlyNameOverride)) {
                SoundSetVolume(this.volumeHistory[friendlyNameOverride], , targetName)
            }
            this.lastDevice := friendlyNameOverride

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
                                NotificationManager.ShowTransient("Could not switch default microphone")
                                ErrorHandler.HandleLaunchError("Microphone switch failed", e)
                            }
                        }
                    }
                } finally {
                    if (micsCollection)
                        ObjRelease(micsCollection)
                }
            }
        } catch as e {
            ErrorHandler.HandleLaunchError("Audio Switch Error", e)
        } finally {
            if (devicesCollection)
                ObjRelease(devicesCollection)
            deviceEnumerator := 0
        }
    }
}

SetAudioOutput(deviceNameSubstr, targetVolume := "", friendlyNameOverride := "", micNameSubstr := "") {
    AudioEndpoint.SwitchOutput(deviceNameSubstr, targetVolume, friendlyNameOverride, micNameSubstr)
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

class GestureManager {
    static lastPresses := Map()
    static timers := Map()

    static HandleDoublePress(key, singlePressCallback := "", doublePressCallback := "") {
        now := A_TickCount
        last := this.lastPresses.Has(key) ? this.lastPresses[key] : 0

        if (now - last < Config.DOUBLE_PRESS_DELAY) {
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
                timerFn := () => this.ExecuteAndClear(key, singlePressCallback)
                this.timers[key] := timerFn
                SetTimer timerFn, -Config.DOUBLE_PRESS_DELAY
            }
        }
    }

    static ExecuteAndClear(key, callback) {
        if this.timers.Has(key)
            this.timers.Delete(key)
        callback()
    }

    static HandleContextHotkey(key, name, path, sArgs := "", dPre := "") {
        now := A_TickCount
        last := this.lastPresses.Has(key) ? this.lastPresses[key] : 0

        if (now - last < Config.DOUBLE_PRESS_DELAY) {
            this.lastPresses[key] := 0
            if this.timers.Has(key) {
                SetTimer this.timers[key], 0
                this.timers.Delete(key)
            }

            dir := ShellExplorer.GetValidExplorerPath()
            if (dir != "") {
                NotificationManager.ShowTransient(name)
                cleanDir := (SubStr(dir, -1) == "\") ? (dir . "\") : dir
                AppActions.Run(path, dPre . '"' . cleanDir . '"')
            }
        } else {
            this.lastPresses[key] := now
            timerFn := () => (this.timers.Delete(key), AppActions.RunAndNotify(path, sArgs, name))
            this.timers[key] := timerFn
            SetTimer timerFn, -Config.DOUBLE_PRESS_DELAY
        }
    }
}

class DoublePressManager {
    static Handle(key, singlePressCallback := "", doublePressCallback := "") {
        GestureManager.HandleDoublePress(key, singlePressCallback, doublePressCallback)
    }
}

HandleContextHotkey(key, name, path, sArgs := "", dPre := "") {
    GestureManager.HandleContextHotkey(key, name, path, sArgs, dPre)
}

class WindowManager {
    static SafeCloseActiveWindow() {
        isFirst := true
        while GetKeyState("q", "P") && GetKeyState("Alt", "P") {
            if !WinExist("A")
                break
            try {
                activeClass := WinGetClass("A")
                if Win32.IsProtectedWindowClass(activeClass) {
                    NotificationManager.ShowTransient("Nothing to close")
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

    static LaunchAndMaximize(appPath, windowIdentifier := "", timeout := "", friendlyName := "") {
        if (timeout = "")
            timeout := Config.WINDOW_WAIT_TIMEOUT

        displayName := (friendlyName != "") ? friendlyName : (windowIdentifier != "" ? windowIdentifier : appPath)

        if (InStr(appPath, "\") && !FileExist(appPath)) {
            TrayTip(appPath, "Application not found", 2)
            return false
        }
        if (!InStr(appPath, "\") && !FileExist(appPath) && !Win32.SearchSystemPath(appPath)) {
            TrayTip(displayName, "Application not found", 2)
            return false
        }

        try {
            if InStr(appPath, "://") {
                Run(appPath)
            } else {
                if (!Win32.SmartRun(appPath))
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
                SetTimer(() => ToolTip(), -Config.TOOLTIP_DURATION_MS)
            }
            SetTitleMatchMode oldMatchMode
        }

        return true
    }

    static LaunchAndPosition(cmd, workingDir := "") {
        cmd := Win32.ResolveNativePath(cmd)
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
}

LaunchAndMaximize(path, ident := "", timeout := "", friendly := "") => WindowManager.LaunchAndMaximize(path, ident, timeout, friendly)
LaunchAndPosition(cmd, dir := "") => WindowManager.LaunchAndPosition(cmd, dir)


class AppActions {
    static Run(path, args := "", name := "", workingDir := "") {
        if (name != "")
            NotificationManager.ShowTransient(name)
        try {
            if InStr(path, "://") || (RegExMatch(path, "^[a-zA-Z][a-zA-Z0-9+.-]+:") && !RegExMatch(path, "^[a-zA-Z]:[\\/]")) {
                Run(path)
            } else {
                if (InStr(path, "\") && !FileExist(path)) {
                    TrayTip(name != "" ? name : path, "Application not found", 2)
                    return
                }
                if (!InStr(path, "\") && !FileExist(path) && !Win32.SearchSystemPath(path)) {
                    TrayTip(name != "" ? name : path, "Application not found", 2)
                    return
                }
                Win32.SmartRun(path, args, workingDir)
            }
        } catch as e {
            ErrorHandler.HandleLaunchError("Launch Error", e)
        }
    }

    static RunAndNotify(path, args, name) {
        NotificationManager.ShowTransient(name)
        this.Run(path, args, name)
    }

    static LaunchChrome(pressDuration) {
        chromePath := AppResolver.Get("Chrome", "chrome.exe")
        if (chromePath = "chrome.exe" && !FileExist(chromePath) && !Win32.SearchSystemPath(chromePath)) {
            NotificationManager.ShowTransient("Opening Default Browser")
            try {
                if (pressDuration >= Config.LONG_PRESS_THRESHOLD)
                    Run(Win32.ResolveNativePath("cmd.exe") . " /c start microsoft-edge:-private")
                else
                    Run(Win32.ResolveNativePath("cmd.exe") . " /c start https://www.google.com")
            } catch as e {
                ErrorHandler.HandleLaunchError("Failed to launch Browser", e)
            }
            KeyWait "c", "T2"
            return
        }

        if (pressDuration >= Config.LONG_PRESS_THRESHOLD) {
            guard := Wow64RedirectionGuard()
            try {
                Run('"' . chromePath . '" --incognito')
            } catch as e {
                ErrorHandler.HandleLaunchError("Failed to launch Chrome", e)
                KeyWait "c"
                return
            }
            KeyWait "c"
        } else {
            KeyWait "c"
            guard := Wow64RedirectionGuard()
            try {
                Run('"' . chromePath . '"')
            } catch as e {
                ErrorHandler.HandleLaunchError("Failed to launch Chrome", e)
                return
            }
        }

        if WinWait("ahk_exe chrome.exe", , Config.WINDOW_WAIT_TIMEOUT) {
            try WinMaximize("ahk_exe chrome.exe")
        } else {
            NotificationManager.ShowTransient("Chrome window not detected")
        }
    }

    static LaunchMicrosoftStore() {
        NotificationManager.ShowTransient("Microsoft Store")
        try {
            Run("ms-windows-store:")
        } catch {
            try {
                Run("explorer.exe shell:AppsFolder\Microsoft.WindowsStore_8wekyb3d8bbwe!App")
            } catch as e {
                ErrorHandler.HandleLaunchError("Microsoft Store", e)
            }
        }
    }

    static LaunchRazer71() {
        razer71Path := AppResolver.Get("Razer71", "rzappengine.exe", [
            "%ProgramFiles%\Razer\RzAppEngine\rzappengine.exe",
            "%StartMenuCommon%\Programs\Razer\7.1 Surround Sound.lnk"
        ])
        SplitPath razer71Path, , &razer71Dir
        this.Run(razer71Path, "--url-params=apps=7.1-surround-sound --disable-background-timer-throttling",
            "7.1 Surround Sound", razer71Dir)
    }
}

RunApp(path, args := "", name := "", dir := "") => AppActions.Run(path, args, name, dir)
RunAppAndNotify(path, args, name) => AppActions.RunAndNotify(path, args, name)
LaunchMicrosoftStore() => AppActions.LaunchMicrosoftStore()
LaunchRazer71() => AppActions.LaunchRazer71()

class AudioActions {
    static SwitchToSony() {
        AudioEndpoint.SwitchOutput(Config.AUDIO_DEVICE_1, 25, "Sony MDRX-50", Config.AUDIO_MIC_1)
    }

    static SwitchToBlackShark() {
        AudioEndpoint.SwitchOutput(Config.AUDIO_DEVICE_1, , "Black Shark V2", Config.AUDIO_MIC_2)
    }

    static SwitchToResound() {
        AudioEndpoint.SwitchOutput(Config.AUDIO_DEVICE_2, , "Resound", Config.AUDIO_MIC_1)
    }

    static SwitchToHeat() {
        AudioEndpoint.SwitchOutput(Config.AUDIO_DEVICE_3, , "Heat", Config.AUDIO_MIC_1)
    }
}

class UtilityActions {
    static ConvertToWSLPath(winPath) {
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

    static ZipHasRootFolder(zipPath) {
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

    static ExtractSelectedZip() {
        winClass := WinGetClass("A")
        if (winClass != "CabinetWClass" && winClass != "ExploreWClass")
            return
        selectedPath := ShellExplorer.GetSelectedFilePath()
        if (selectedPath = "")
            return
        SplitPath selectedPath, , &fileDir, &fileExtension, &nameNoExt
        if (fileExtension != "zip" && fileExtension != "ZIP")
            return

        hasRootFolder := this.ZipHasRootFolder(selectedPath)
        targetDir := hasRootFolder ? fileDir : (fileDir . "\" . nameNoExt)

        winrarPath := AppResolver.Get("WinRAR", "WinRAR.exe", [
            "%ProgramFiles%\WinRAR\WinRAR.exe",
            "%ProgramFiles(x86)%\WinRAR\WinRAR.exe"
        ])
        if FileExist(winrarPath) {
            guard := Wow64RedirectionGuard()
            Run('"' . winrarPath . '" x -o+ "' . selectedPath . '" "' . targetDir . '"')
            return
        }

        tarExe := Win32.ResolveNativePath("tar.exe")
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

    static PasteClipboardAsWSL() {
        static isPasting := false
        if (isPasting)
            return

        clipText := Trim(A_Clipboard, '`t`n`r "')
        if (clipText != "" && (RegExMatch(clipText, "i)^[A-Z]:") || InStr(clipText, "\"))) {
            isPasting := true
            wslPath := this.ConvertToWSLPath(clipText)
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

    static EmptyRecycleBin() {
        result := MsgBox("Are you sure you want to permanently delete all items in the Recycle Bin?", "Empty Recycle Bin", 4)
        if (result = "Yes") {
            try {
                DllCall("shell32\SHEmptyRecycleBin", "Ptr", 0, "Ptr", 0, "UInt", 0x1)
                NotificationManager.ShowTransient("Recycle Bin emptied")
            } catch as e {
                ErrorHandler.HandleLaunchError("Failed to empty Recycle Bin", e)
            }
        }
    }
}

ConvertToWSLPath(winPath) => UtilityActions.ConvertToWSLPath(winPath)
ExtractSelectedZip() => UtilityActions.ExtractSelectedZip()

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

; ====================[ Application & Utility Hotkeys ]====================
!0:: AppActions.Run("calc.exe", "", "Calculator")

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
        AppActions.Run(photoshopPath, "", "Photoshop", photoshopDir)
    }
    GestureManager.HandleDoublePress("Photoshop", "", doublePress)
}

!7:: AppActions.LaunchRazer71()

!a:: {
    antigravityPath := AppResolver.Get("Antigravity", "Antigravity IDE.exe", [
        "%LocalAppData%\Programs\Antigravity IDE\Antigravity IDE.exe",
        "%LocalAppData%\Programs\Antigravity IDE\bin\antigravity-ide.cmd",
        "%ProgramFiles%\Antigravity IDE\Antigravity IDE.exe",
        "%ProgramFiles(x86)%\Antigravity IDE\Antigravity IDE.exe",
        "%StartMenu%\Programs\Antigravity\Antigravity.lnk",
        "%StartMenu%\Programs\Antigravity IDE\Antigravity IDE.lnk"
    ])
    GestureManager.HandleContextHotkey("a", "Antigravity", antigravityPath)
}

#MaxThreadsPerHotkey 1
!c:: {
    pressStart := A_TickCount
    KeyWait "c", "T" . (Config.LONG_PRESS_THRESHOLD / 1000)
    pressDuration := A_TickCount - pressStart
    AppActions.LaunchChrome(pressDuration)
}
#MaxThreadsPerHotkey 1

!e:: {
    outlookPath := AppResolver.Get("Outlook", "", [
        "%AppData%\Microsoft\Windows\Start Menu\Programs\Chrome Apps\Outlook (PWA).lnk",
        "%StartMenuCommon%\Programs\Chrome Apps\Outlook (PWA).lnk"
    ])
    if (outlookPath != "" && FileExist(outlookPath)) {
        WindowManager.LaunchAndMaximize(outlookPath, "Outlook", Config.WINDOW_WAIT_TIMEOUT, "Outlook")
    } else {
        try {
            AppActions.Run("ms-outlook://", "", "Outlook")
        } catch {
            AppActions.Run("https://outlook.live.com", "", "Outlook")
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
    GestureManager.HandleContextHotkey("g", "Git Bash", gitBashPath, "--cd-to-home", "--cd=")
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
        NotificationManager.ShowTransient("Instagram")
        WindowManager.LaunchAndMaximize(instagramPath, "Instagram", Config.WINDOW_WAIT_TIMEOUT, "Instagram")
    } else {
        try {
            AppActions.Run("instagram://", "", "Instagram")
        } catch {
            AppActions.Run("https://www.instagram.com", "", "Instagram")
        }
    }
}

!m:: AppActions.LaunchMicrosoftStore()
!n:: AppActions.Run("notepad.exe", "", "Notepad")

#MaxThreadsPerHotkey 1
!o:: {
    userHome := EnvGet("USERPROFILE")
    pressStart := A_TickCount
    KeyWait "o", "T" . (Config.LONG_PRESS_THRESHOLD / 1000)
    pressDuration := A_TickCount - pressStart

    if (pressDuration >= Config.LONG_PRESS_THRESHOLD) {
        dir := ShellExplorer.GetValidExplorerPath()
        if (dir != "") {
            NotificationManager.ShowTransient("Admin CMD in Folder")
            try {
                WindowManager.LaunchAndPosition("*RunAs cmd.exe", dir)
            } catch as e {
                if (A_LastError != 1223)
                    ErrorHandler.HandleLaunchError("Failed to launch Admin CMD in Folder", e)
            }
        }
        KeyWait "o"
    } else {
        singlePress() {
            NotificationManager.ShowTransient("CMD")
            try
                WindowManager.LaunchAndPosition("cmd.exe", userHome)
            catch as e
                ErrorHandler.HandleLaunchError("Failed to launch CMD", e)
        }
        doublePress() {
            winClass := ""
            try winClass := WinGetClass("A")
            dir := ""
            if (winClass = "CabinetWClass" || winClass = "ExploreWClass")
                dir := ShellExplorer.GetActiveExplorerPath()

            if (dir != "") {
                NotificationManager.ShowTransient("CMD in Folder")
                try
                    WindowManager.LaunchAndPosition("cmd.exe", dir)
                catch as e
                    ErrorHandler.HandleLaunchError("Failed to launch CMD", e)
            } else {
                NotificationManager.ShowTransient("Admin CMD")
                try
                    WindowManager.LaunchAndPosition("*RunAs cmd.exe", userHome)
                catch as e {
                    if (A_LastError != 1223)
                        ErrorHandler.HandleLaunchError("Failed to launch Admin CMD", e)
                }
            }
        }
        GestureManager.HandleDoublePress("CMD", singlePress, doublePress)
    }
}
#MaxThreadsPerHotkey 1

#MaxThreadsPerHotkey 1
!p:: {
    userHome := EnvGet("USERPROFILE")
    pressStart := A_TickCount
    KeyWait "p", "T" . (Config.LONG_PRESS_THRESHOLD / 1000)
    pressDuration := A_TickCount - pressStart

    if (pressDuration >= Config.LONG_PRESS_THRESHOLD) {
        dir := ShellExplorer.GetValidExplorerPath()
        if (dir != "") {
            NotificationManager.ShowTransient("Admin PowerShell in Folder")
            try {
                WindowManager.LaunchAndPosition("*RunAs powershell.exe", dir)
            } catch as e {
                if (A_LastError != 1223)
                    ErrorHandler.HandleLaunchError("Failed to launch Admin PowerShell in Folder", e)
            }
        }
        KeyWait "p"
    } else {
        singlePress() {
            NotificationManager.ShowTransient("PowerShell")
            try
                WindowManager.LaunchAndPosition("powershell.exe", userHome)
            catch as e
                ErrorHandler.HandleLaunchError("Failed to launch PowerShell", e)
        }
        doublePress() {
            winClass := ""
            try winClass := WinGetClass("A")
            dir := ""
            if (winClass = "CabinetWClass" || winClass = "ExploreWClass")
                dir := ShellExplorer.GetActiveExplorerPath()

            if (dir != "") {
                NotificationManager.ShowTransient("PowerShell in Folder")
                try
                    WindowManager.LaunchAndPosition("powershell.exe", dir)
                catch as e
                    ErrorHandler.HandleLaunchError("Failed to launch PowerShell", e)
            } else {
                NotificationManager.ShowTransient("Admin PowerShell")
                try
                    WindowManager.LaunchAndPosition("*RunAs powershell.exe", userHome)
                catch as e {
                    if (A_LastError != 1223)
                        ErrorHandler.HandleLaunchError("Failed to launch Admin PowerShell", e)
                }
            }
        }
        GestureManager.HandleDoublePress("PowerShell", singlePress, doublePress)
    }
}
#MaxThreadsPerHotkey 1

!q:: WindowManager.SafeCloseActiveWindow()

!s:: {
    slackPath := AppResolver.Get("Slack", "slack.exe", [
        "%LocalAppData%\slack\slack.exe",
        "%ProgramFiles%\Slack\slack.exe",
        "%StartMenuCommon%\Programs\Slack.lnk"
    ])
    if (slackPath != "" && (FileExist(slackPath) || Win32.SearchSystemPath(slackPath))) {
        WindowManager.LaunchAndMaximize(slackPath, "ahk_exe slack.exe", Config.WINDOW_WAIT_TIMEOUT, "Slack")
    } else {
        AppActions.Run("slack://", "", "Slack")
    }
}

!t:: {
    telegramPath := AppResolver.Get("Telegram", "", [
        "%AppData%\Microsoft\Windows\Start Menu\Programs\Chrome Apps\Telegram Web.lnk",
        "%StartMenuCommon%\Programs\Chrome Apps\Telegram Web.lnk"
    ])
    if (telegramPath != "" && FileExist(telegramPath)) {
        NotificationManager.ShowTransient("Telegram")
        WindowManager.LaunchAndMaximize(telegramPath, "Telegram", Config.WINDOW_WAIT_TIMEOUT)
    } else {
        AppActions.Run("tg://", "", "Telegram")
    }
}

!u:: {
    singlePress() {
        NotificationManager.ShowTransient("WSL")
        try
            WindowManager.LaunchAndPosition('wsl.exe --cd ~')
        catch as e
            NotificationManager.ShowTransient("Failed to launch WSL`nIs WSL installed? " . e.Message)
    }
    doublePress() {
        dir := ShellExplorer.GetValidExplorerPath()
        if (dir != "") {
            NotificationManager.ShowTransient("WSL")
            try
                WindowManager.LaunchAndPosition('wsl.exe --cd "' . dir . '"')
            catch as e
                NotificationManager.ShowTransient("Failed to launch WSL`nIs WSL installed? " . e.Message)
        }
    }
    GestureManager.HandleDoublePress("WSL", singlePress, doublePress)
}

!v:: {
    vscodePath := AppResolver.Get("VSCode", "Code.exe", [
        "%LocalAppData%\Programs\Microsoft VS Code\Code.exe",
        "%ProgramFiles%\Microsoft VS Code\Code.exe"
    ])
    if (vscodePath != "" && (FileExist(vscodePath) || Win32.SearchSystemPath(vscodePath))) {
        GestureManager.HandleContextHotkey("v", "VS Code", vscodePath)
    } else {
        AppActions.Run("https://vscode.dev", "", "VS Code Web")
    }
}

!+v:: UtilityActions.PasteClipboardAsWSL()

!w:: {
    whatsappPath := AppResolver.Get("WhatsApp", "", [
        "%AppData%\Microsoft\Windows\Start Menu\Programs\Chrome Apps\WhatsApp Web.lnk",
        "%StartMenuCommon%\Programs\Chrome Apps\WhatsApp Web.lnk",
        "%ProgramFiles%\WhatsApp.lnk",
        "%StartMenuCommon%\Programs\WhatsApp.lnk",
        "%StartMenu%\Programs\WhatsApp.lnk"
    ])
    if (whatsappPath != "" && (FileExist(whatsappPath) || InStr(whatsappPath, "\") = 0)) {
        NotificationManager.ShowTransient("WhatsApp")
        WindowManager.LaunchAndMaximize(whatsappPath, "WhatsApp", Config.WINDOW_WAIT_TIMEOUT, "WhatsApp")
    } else {
        AppActions.Run("whatsapp://", "", "WhatsApp")
    }
}

!y:: {
    youtubePath := AppResolver.Get("YouTube", "", [
        "%AppData%\Microsoft\Windows\Start Menu\Programs\Chrome Apps\YouTube.lnk",
        "%StartMenuCommon%\Programs\Chrome Apps\YouTube.lnk"
    ])
    if (youtubePath != "" && FileExist(youtubePath)) {
        WindowManager.LaunchAndMaximize(youtubePath, "YouTube", Config.WINDOW_WAIT_TIMEOUT, "YouTube")
    } else {
        AppActions.Run("https://www.youtube.com", "", "YouTube")
    }
}

!z:: UtilityActions.ExtractSelectedZip()

^+!Delete:: UtilityActions.EmptyRecycleBin()

; ====================[ Audio Switcher Hotkeys ]====================
^+q:: AudioActions.SwitchToSony()
^+x:: AudioActions.SwitchToBlackShark()
^+y:: AudioActions.SwitchToResound()
^+z:: AudioActions.SwitchToHeat()