; ====================[ Helper Utilities & Explorer Functions ]====================
#Requires AutoHotkey v2.0.26

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
