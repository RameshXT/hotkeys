; ==================[ Hotkey Reference ]==================
; Alt + 0 →     Calculator
; Alt + 1 →     Photoshop (Double Tap)
; Alt + A →     Antigravity  |  Double → Antigravity in Explorer folder
; Alt + C →     Chrome  |  Long Press → Chrome Incognito
; Alt + G →     Git Bash  |  Double → Git Bash in Explorer folder
; Alt + I →     Instagram
; Alt + M →     Microsoft Store
; Alt + N →     Notepad
; Alt + O →     CMD  |  Double → Admin CMD (in Folder or Home)
; Alt + P →     PowerShell  |  Double → PowerShell in Folder
; Alt + Q →     Close Active Window (hold to keep closing)
; Alt + S →     Slack
; Alt + T →     Telegram
; Alt + U →     Ubuntu 24.04 WSL | Double (in Folder wsl)
; Alt + V →     VS Code  |  Double → VS Code in Explorer folder
; Alt + W →     WhatsApp
; Alt + Y →     YouTube
; Alt + Z →     Unzip selected .zip file

; Ctrl + Shift + Alt + C       → Run Windows Cleanup Script
; Ctrl + Shift + Alt + L       → Open Logs Folder
; Ctrl + Shift + Alt + N       → Run Network Reset Script
; Ctrl + Shift + Alt + U       → Run Windows Updater Script
; Ctrl + Shift + Alt + Delete  → Empty Recycle Bin (with confirm)

; ====================[ Script Config & Variables ]====================
#Requires AutoHotkey v2.0.26
#SingleInstance Force
#Warn
Persistent()
SendMode "Input"
SetWorkingDir A_ScriptDir

; Auto-Reload on Script Change
SetTimer WatchScript, 1000

USER_HOME := EnvGet("USERPROFILE")
global DOUBLE_PRESS_DELAY   := 400
global GIT_BASH_EXE         := "C:\Program Files\Git\git-bash.exe"
global INSTAGRAM_APP        := "C:\Program Files\Instagram.lnk"
global LOGS_DIR             := USER_HOME . "\sys-scripts\logs"
global LONG_PRESS_THRESHOLD := 600
global o_LastPress          := 0
global one_LastPress        := 0
global p_LastPress          := 0
global ScriptModTime        := "" ; Used for Auto-Reload
global TOOLTIP_DURATION_MS  := 2000
global u_LastPress          := 0
global VSCODE_PATH          := USER_HOME . "\AppData\Local\Programs\Microsoft VS Code\Code.exe"
global WHATSAPP_APP         := "C:\Program Files\WhatsApp.lnk"
global WINDOW_WAIT_TIMEOUT  := 5
global YOUTUBE_LNK          := USER_HOME . "\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Chrome Apps\YouTube.lnk"

; ====================[ Helper Functions ]====================

DisableRedirection() {
    oldRedir := 0
    if (A_Is64bitOS && A_PtrSize = 4)
        DllCall("Wow64DisableWow64FsRedirection", "Ptr*", &oldRedir)
    return oldRedir
}

RevertRedirection(oldRedir) {
    if (A_Is64bitOS && A_PtrSize = 4)
        DllCall("Wow64RevertWow64FsRedirection", "Ptr", oldRedir)
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
    winrarPath := "C:\Program Files\WinRAR\WinRAR.exe"
    if FileExist(winrarPath) {
        oldR := DisableRedirection()
        Run('"' . winrarPath . '" x -o+ "' . selectedPath . '" "' . targetDir . '"')
        RevertRedirection(oldR)
    } else {
        safeSelectedPath := StrReplace(selectedPath, "'", "''")
        safeTargetDir := StrReplace(targetDir, "'", "''")
        oldR := DisableRedirection()
        Run("powershell.exe -NoProfile -Command `"Expand-Archive -Path '" . safeSelectedPath . "' -DestinationPath '" . safeTargetDir . "' -Force`"", , "Hide")
        RevertRedirection(oldR)
    }
}

GetAntigravityPath() {
    userHome := EnvGet("USERPROFILE")
    paths := [ userHome . "\AppData\Local\Programs\Antigravity IDE\Antigravity IDE.exe"
             , "C:\Program Files\Antigravity IDE\Antigravity IDE.exe"
             , "C:\Program Files (x86)\Antigravity IDE\Antigravity IDE.exe"
             , userHome . "\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Antigravity\Antigravity.lnk"
             , userHome . "\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Antigravity IDE\Antigravity IDE.lnk" ]

    for index, path in paths
        if FileExist(path)
            return path

    return "antigravity-ide.cmd"
}

GetExplorerPath() {
    try {
        for window in ComObject("Shell.Application").Windows {
            try {
                if (window.hwnd = WinActive("A")) {
                    folderPath := window.Document.Folder.Self.Path
                    if (folderPath != "")
                        return folderPath
                }
            } catch {
                continue
            }
        }
    } catch as e {
        ShowLaunchError("Error getting Explorer path", e)
    }
    return ""
}

GetChromePath() {
    try {
        path := RegRead("HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe", "")
        if (path != "" && FileExist(path))
            return path
    }
    try {
        path := RegRead("HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe", "")
        if (path != "" && FileExist(path))
            return path
    }
    paths := [ EnvGet("ProgramFiles") . "\Google\Chrome\Application\chrome.exe"
             , EnvGet("ProgramFiles(x86)") . "\Google\Chrome\Application\chrome.exe"
             , EnvGet("LocalAppData") . "\Google\Chrome\Application\chrome.exe" ]
    for index, path in paths
        if (path != "" && FileExist(path))
            return path
    return "chrome.exe"
}

GetPhotoshopPath() {
    userHome := EnvGet("USERPROFILE")
    paths := [ "C:\Program Files\Adobe\Adobe Photoshop 2024\Photoshop.exe"
             , "C:\Program Files\Adobe\Adobe Photoshop 2023\Photoshop.exe"
             , "C:\Program Files\Adobe\Adobe Photoshop 2022\Photoshop.exe"
             , "C:\Program Files\Adobe\Adobe Photoshop 2021\Photoshop.exe"
             , "C:\Program Files\Adobe\Adobe Photoshop 2020\Photoshop.exe"
             , "C:\Program Files\Adobe\Adobe Photoshop CC 2019\Photoshop.exe"
             , "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Adobe Photoshop.lnk"
             , userHome . "\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Adobe Photoshop.lnk" ]

    for index, path in paths
        if FileExist(path)
            return path

    return "Photoshop.exe"
}

GetSlackPath() {
    userHome := EnvGet("USERPROFILE")
    paths := [ userHome . "\AppData\Local\slack\slack.exe"
             , "C:\Program Files\Slack\slack.exe"
             , "C:\Program Files\Slack.lnk"
             , "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Slack Technologies Inc\Slack.lnk"
             , userHome . "\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Slack Technologies Inc\Slack.lnk" ]

    for index, path in paths
        if FileExist(path)
            return path

    return "slack.exe"
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

LaunchAndMaximize(appPath, windowIdentifier := "", timeout := 5) {
    if (InStr(appPath, "\") && !FileExist(appPath)) {
        MsgBox("Application not found:`n" . appPath, "Error", 16)
        return false
    }

    oldR := DisableRedirection()
    try {
        if InStr(appPath, "://")
            Run(appPath)
        else
            Run('"' . appPath . '"')
    } catch as e {
        RevertRedirection(oldR)
        MsgBox("Failed to launch:`n" . appPath . "`n`nError: " . e.Message, "Launch Error", 16)
        return false
    }
    RevertRedirection(oldR)

    if (windowIdentifier != "") {
        if WinWait(windowIdentifier, , timeout)
            WinMaximize
        else {
            ToolTip("Window not detected: " . windowIdentifier)
            SetTimer RemoveToolTip, -2000
        }
    }

    return true
}

RunApp(path, args := "", name := "") {
    if (name != "")
        ShowTransientToolTip(name)
    oldR := DisableRedirection()
    try {
        if InStr(path, "://") {
            Run(path)
        } else {
            if (InStr(path, "\") && !FileExist(path)) {
                RevertRedirection(oldR)
                MsgBox("Target not found:`n" . path, "Error", 16)
                return
            }

            if (args != "")
                Run('"' . path . '" ' . args)
            else
                Run('"' . path . '"')
        }
    } catch as e {
        ShowLaunchError("Launch Error", e)
    }
    RevertRedirection(oldR)
}

RunAppAndNotify(path, args, name) {
    ShowTransientToolTip(name)
    RunApp(path, args)
}

ShowLaunchError(prefix, err) {
    msg := (err is Error) ? err.Message : String(err)
    ShowTransientToolTip(prefix . ": " . msg)
}

ShowTransientToolTip(message, durationMs := "") {
    if (durationMs = "")
        durationMs := TOOLTIP_DURATION_MS
    ToolTip(message)
    SetTimer RemoveToolTip, -durationMs
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

    oldR := DisableRedirection()
    try {
        Run('schtasks.exe /Run /TN "' . taskName . '" /I', , "Hide")
        ShowTransientToolTip(friendlyName . " in progress...")
    } catch as e {
        RevertRedirection(oldR)
        ShowLaunchError("Failed to trigger " . friendlyName, e)
        return
    }
    RevertRedirection(oldR)

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

P_SinglePress() {
    ShowTransientToolTip("PowerShell")
    oldR := DisableRedirection()
    try
        Run("powershell.exe", USER_HOME)
    catch as e
        ShowLaunchError("Failed to launch PowerShell", e)
    RevertRedirection(oldR)
}

O_SinglePress() {
    ShowTransientToolTip("CMD")
    oldR := DisableRedirection()
    try
        Run("cmd.exe", USER_HOME)
    catch as e
        ShowLaunchError("Failed to launch CMD", e)
    RevertRedirection(oldR)
}

U_SinglePress() {
    ShowTransientToolTip("WSL")
    oldR := DisableRedirection()
    try
        Run('wsl.exe -d Ubuntu-24.04 -- bash -lc "cd ~; exec bash"')
    catch as e
        ShowTransientToolTip("Failed to launch Ubuntu 24.04`nIs WSL installed? " . e.Message)
    RevertRedirection(oldR)
}

; ====================[ Hotkeys ]====================

!0::RunApp("calc.exe", "", "Calculator")

!1:: {
    global one_LastPress
    now := A_TickCount
    timeSinceLastPress := now - one_LastPress
    one_LastPress := now
    if (timeSinceLastPress > 0 && timeSinceLastPress < DOUBLE_PRESS_DELAY) {
        one_LastPress := 0
        RunApp(GetPhotoshopPath(), "", "Photoshop")
    }
}

!a::HandleContextHotkey("a", "Antigravity", GetAntigravityPath())

#MaxThreadsPerHotkey 1
!c:: {
    pressStart := A_TickCount

    ; Wait up to LONG_PRESS_THRESHOLD ms for key release
    KeyWait "c", "T0.6"

    pressDuration := A_TickCount - pressStart

    chromePath := GetChromePath()
    if (chromePath = "chrome.exe" && !FileExist(chromePath)) {
        MsgBox("Chrome not found.", "Error", 16)
        KeyWait "c", "T2"
        return
    }

    if (pressDuration >= LONG_PRESS_THRESHOLD) {
        ; Long press: incognito fires immediately at 600ms, then wait for release (max 2s)
        oldR := DisableRedirection()
        try
            Run('"' . chromePath . '" --incognito')
        catch as e {
            RevertRedirection(oldR)
            ShowLaunchError("Failed to launch Chrome", e)
            KeyWait "c", "T2"
            return
        }
        RevertRedirection(oldR)
        KeyWait "c", "T2"
    } else {
        ; Short press: wait for release (max 2s) then open normal Chrome
        KeyWait "c", "T2"
        oldR := DisableRedirection()
        try
            Run('"' . chromePath . '"')
        catch as e {    
            RevertRedirection(oldR)
            ShowLaunchError("Failed to launch Chrome", e)
            return
        }
        RevertRedirection(oldR)
    }

    if WinWait("ahk_exe chrome.exe", , WINDOW_WAIT_TIMEOUT)
        WinMaximize
    else
        ShowTransientToolTip("Chrome window not detected")
}
#MaxThreadsPerHotkey 1

!g::HandleContextHotkey("g", "Git Bash", GIT_BASH_EXE, "--cd-to-home", "--cd=")

!i:: {
    ShowTransientToolTip("Instagram")
    LaunchAndMaximize(INSTAGRAM_APP, "Instagram", WINDOW_WAIT_TIMEOUT)
}

!m::RunApp("ms-windows-store:", "", "Microsoft Store")

!n::RunApp("notepad.exe", "", "Notepad")

!p:: {
    global p_LastPress
    now := A_TickCount
    timeSinceLastPress := now - p_LastPress

    if (timeSinceLastPress > 0 && timeSinceLastPress < DOUBLE_PRESS_DELAY) {
        p_LastPress := 0
        SetTimer P_SinglePress, 0

        winClass := WinGetClass("A")
        dir := ""
        if (winClass = "CabinetWClass" || winClass = "ExploreWClass")
            dir := GetExplorerPath()

        if (dir != "") {
            ShowTransientToolTip("PowerShell in Folder")
            oldR := DisableRedirection()
            try
                Run("powershell.exe", dir)
            catch as e
                ShowLaunchError("Failed to launch PowerShell", e)
            RevertRedirection(oldR)
        } else {
            ShowTransientToolTip("PowerShell")
            oldR := DisableRedirection()
            try
                Run("powershell.exe", USER_HOME)
            catch as e
                ShowLaunchError("Failed to launch PowerShell", e)
            RevertRedirection(oldR)
        }
    } else {
        p_LastPress := now
        SetTimer P_SinglePress, -DOUBLE_PRESS_DELAY
    }
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
    global o_LastPress
    now := A_TickCount
    timeSinceLastPress := now - o_LastPress

    if (timeSinceLastPress > 0 && timeSinceLastPress < DOUBLE_PRESS_DELAY) {
        o_LastPress := 0
        SetTimer O_SinglePress, 0

        winClass := WinGetClass("A")
        dir := ""
        if (winClass = "CabinetWClass" || winClass = "ExploreWClass")
            dir := GetExplorerPath()

        if (dir != "") {
            ShowTransientToolTip("Admin CMD in Folder")
            oldR := DisableRedirection()
            try
                Run('*RunAs cmd.exe /K cd /d "' . dir . '"')
            catch as e {
                if (A_LastError != 1223)
                    ShowLaunchError("Failed to launch Admin CMD", e)
            }
            RevertRedirection(oldR)
        } else {
            ShowTransientToolTip("Admin CMD")
            oldR := DisableRedirection()
            try
                Run("*RunAs cmd.exe", USER_HOME)
            catch as e {
                if (A_LastError != 1223)
                    ShowLaunchError("Failed to launch Admin CMD", e)
            }
            RevertRedirection(oldR)
        }
    } else {
        o_LastPress := now
        SetTimer O_SinglePress, -DOUBLE_PRESS_DELAY
    }
}

!s:: {
    LaunchAndMaximize(GetSlackPath(), "ahk_exe slack.exe", WINDOW_WAIT_TIMEOUT)
}

!t::RunApp("tg://", "", "Telegram")

!u:: {
    global u_LastPress
    now := A_TickCount
    timeSinceLastPress := now - u_LastPress

    if (timeSinceLastPress > 0 && timeSinceLastPress < DOUBLE_PRESS_DELAY) {
        u_LastPress := 0
        SetTimer U_SinglePress, 0

        dir := GetValidExplorerPath()
        if (dir != "") {
            unixPath := ConvertToWSLPath(dir)
            ShowTransientToolTip("WSL")
            oldR := DisableRedirection()
            try
                Run("wsl.exe -d Ubuntu-24.04 -- bash -lc `"cd '" . unixPath . "'; exec bash`"")
            catch as e
                ShowTransientToolTip("Failed to launch Ubuntu 24.04`nIs WSL installed? " . e.Message)
            RevertRedirection(oldR)
        }
    } else {
        u_LastPress := now
        SetTimer U_SinglePress, -DOUBLE_PRESS_DELAY
    }
}

!v::HandleContextHotkey("v", "VS Code", VSCODE_PATH)

!w:: {
    ShowTransientToolTip("WhatsApp")
    LaunchAndMaximize(WHATSAPP_APP, "WhatsApp", WINDOW_WAIT_TIMEOUT)
}

!y:: {
    LaunchAndMaximize(YOUTUBE_LNK, "YouTube", WINDOW_WAIT_TIMEOUT)
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
    oldR := DisableRedirection()
    try
        Run('explorer.exe "' . LOGS_DIR . '"')
    catch as e
        ShowLaunchError("Failed to open logs folder", e)
    RevertRedirection(oldR)
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
