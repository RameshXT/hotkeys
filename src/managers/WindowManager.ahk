#Requires AutoHotkey v2.0.26

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
