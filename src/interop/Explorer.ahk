#Requires AutoHotkey v2.0.26

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
