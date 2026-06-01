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
; Alt + P →     PowerShell (Admin)  |  Double → Admin PowerShell in Folder
; Alt + Q →     Close Active Window (hold to keep closing)
; Alt + S →     Slack
; Alt + T →     Telegram
; Alt + U →     Ubuntu 22.04 WSL
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
#Requires AutoHotkey v1.1
#NoEnv
#SingleInstance Force
#Persistent
#Warn
SendMode Input
SetWorkingDir %A_ScriptDir%

; Auto-Reload on Script Change
SetTimer, WatchScript, 1000

EnvGet, USER_HOME, USERPROFILE
global SYS_SCRIPTS_DIR  := A_ScriptDir . "\.."
global LOGS_DIR         := SYS_SCRIPTS_DIR . "\logs"

global DOUBLE_PRESS_DELAY   := 400
global LONG_PRESS_THRESHOLD := 600
global o_LastPress := 0
global one_LastPress := 0
global p_LastPress := 0
global ScriptModTime := "" ; Used for Auto-Reload
global TOOLTIP_DURATION_MS  := 2000
global u_LastPress := 0
global WINDOW_WAIT_TIMEOUT  := 5

; ====================[ Helper Functions ]====================

GetDynamicAppPath(exeName)
{
    local appPath
    RegRead, appPath, HKLM, SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\%exeName%
    if (appPath != "" && FileExist(appPath))
        return appPath
    RegRead, appPath, HKCU, SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\%exeName%
    if (appPath != "" && FileExist(appPath))
        return appPath
    return exeName ; fallback to PATH
}

FindAppShortcut(appName)
{
    local pattern, commonPrograms, userPrograms, found
    EnvGet, commonPrograms, ALLUSERSPROFILE
    commonPrograms := commonPrograms . "\Microsoft\Windows\Start Menu\Programs"
    userPrograms := A_Programs

    Loop, Files, %commonPrograms%\*.lnk, R
    {
        if InStr(A_LoopFileName, appName)
            return A_LoopFileFullPath
    }

    Loop, Files, %userPrograms%\*.lnk, R
    {
        if InStr(A_LoopFileName, appName)
            return A_LoopFileFullPath
    }
    return ""
}

GetGitBashPath()
{
    local appPath
    RegRead, appPath, HKLM, SOFTWARE\GitForWindows, InstallPath
    if (appPath != "" && FileExist(appPath . "\git-bash.exe"))
        return appPath . "\git-bash.exe"
    
    appPath := GetDynamicAppPath("git-bash.exe")
    if (appPath != "git-bash.exe")
        return appPath

    return "git-bash.exe"
}


DisableRedirection() {
    local oldRedir := 0
    if (A_Is64bitOS && A_PtrSize = 4)
        DllCall("Wow64DisableWow64FsRedirection", "Ptr*", oldRedir)
    return oldRedir
}

RevertRedirection(oldRedir) {
    if (A_Is64bitOS && A_PtrSize = 4)
        DllCall("Wow64RevertWow64FsRedirection", "Ptr", oldRedir)
}

ConvertToWSLPath(winPath)
{
    local unixPath, drive

    if (winPath = "")
        return ""

    ; Replace backslashes with forward slashes
    unixPath := StrReplace(winPath, "\", "/")

    ; Convert drive letter (C: -> /c)
    if (SubStr(unixPath, 2, 1) = ":")
    {
        drive := SubStr(unixPath, 1, 1)
        drive := Format("{:L}", drive)
        unixPath := "/mnt/" . drive . SubStr(unixPath, 3)
    }

    return unixPath
}

DeleteFileIfExists(path) {
    if (path != "" && FileExist(path))
        FileDelete, %path%
}

ExtractSelectedZip()
{
    local winClass, selectedPath, fileDir, fileExtension, nameNoExt, targetDir, winrarPath, safeSelectedPath, safeTargetDir, oldRedir
    WinGetClass, winClass, A
    if (winClass != "CabinetWClass" && winClass != "ExploreWClass")
        return
    selectedPath := GetSelectedFilePath()
    if (selectedPath = "")
        return
    SplitPath, selectedPath, , fileDir, fileExtension, nameNoExt
    if (fileExtension != "zip" && fileExtension != "ZIP")
        return
    targetDir := fileDir . "\" . nameNoExt . "\"
    winrarPath := GetDynamicAppPath("WinRAR.exe")
    if FileExist(winrarPath) {
        oldRedir := DisableRedirection()
        Run, "%winrarPath%" x -o+ "%selectedPath%" "%targetDir%"
        RevertRedirection(oldRedir)
    }
    else
    {
        StringReplace, safeSelectedPath, selectedPath, ', '', All
        StringReplace, safeTargetDir, targetDir, ', '', All
        oldRedir := DisableRedirection()
        Run, powershell.exe -NoProfile -Command "Expand-Archive -LiteralPath '%safeSelectedPath%' -DestinationPath '%safeTargetDir%' -Force",, Hide
        RevertRedirection(oldRedir)
    }
}

GetAntigravityPath()
{
    local appPath := GetDynamicAppPath("Antigravity IDE.exe")
    if (appPath != "Antigravity IDE.exe")
        return appPath
    
    appPath := FindAppShortcut("Antigravity")
    if (appPath != "")
        return appPath

    return "Antigravity IDE.exe"
}

GetExplorerPath()
{
    local folderPath, window, err

    try
    {
        for window in ComObjCreate("Shell.Application").Windows
        {
            try
            {
                if (window.hwnd = WinActive("A"))
                {
                    folderPath := window.Document.Folder.Self.Path
                    if (folderPath != "")
                        return folderPath
                }
            }
            catch
            {
                continue
            }
        }
    }
    catch err
    {
        ShowLaunchError("Error getting Explorer path", err)
    }
    return ""
}

GetPhotoshopPath()
{
    local appPath := GetDynamicAppPath("Photoshop.exe")
    if (appPath != "Photoshop.exe")
        return appPath
    
    appPath := FindAppShortcut("Adobe Photoshop")
    if (appPath != "")
        return appPath

    return "Photoshop.exe"
}

GetSlackPath()
{
    local appPath := GetDynamicAppPath("slack.exe")
    if (appPath != "slack.exe")
        return appPath
    
    appPath := FindAppShortcut("Slack")
    if (appPath != "")
        return appPath

    return "slack://"
}

GetSelectedFilePath()
{
    local hwnd, window, sel, item
    hwnd := WinExist("A")
    for window in ComObjCreate("Shell.Application").Windows
    {
        if (window.hwnd = hwnd)
        {
            for item in window.Document.SelectedItems
            {
                return item.Path
            }
        }
    }
    return ""
}

GetValidExplorerPath()
{
    local winClass, folderPath

    WinGetClass, winClass, A
    if (winClass != "CabinetWClass" && winClass != "ExploreWClass")
    {
        ShowTransientToolTip("Please focus on a File Explorer window")
        return ""
    }

    folderPath := GetExplorerPath()
    if (folderPath = "")
    {
        ShowTransientToolTip("Could not get folder path")
        return ""
    }

    return folderPath
}

HandleContextHotkey(key, name, appPath, sArgs := "", dPre := "", maximize := false) {
    global DOUBLE_PRESS_DELAY
    static lastPresses := {}
    static timers := {}

    tickNow := A_TickCount
    last := lastPresses[key] ? lastPresses[key] : 0

    if (tickNow - last < DOUBLE_PRESS_DELAY) {
        lastPresses[key] := 0
        if (timers[key]) {
            SetTimer, % timers[key], Off
            timers[key] := ""
        }

        activeFolder := GetValidExplorerPath()
        if (activeFolder != "") {
            ShowTransientToolTip(name)
            RunApp(appPath, dPre . """" . activeFolder . """", name, maximize)
        }
    } else {
        lastPresses[key] := tickNow
        timerObj := Func("RunAppAndNotify").Bind(appPath, sArgs, name, maximize)
        timers[key] := timerObj
        SetTimer, % timerObj, % -DOUBLE_PRESS_DELAY
    }
}

IsProtectedWindowClass(windowClass) {
    return (windowClass = "Shell_TrayWnd" || windowClass = "Progman" || windowClass = "WorkerW")
}

LaunchAndMaximize(appPath, windowIdentifier := "", timeout := 5, args := "")
{
    local err, oldRedir
    oldRedir := DisableRedirection()
    try
    {
        if InStr(appPath, "://") || InStr(appPath, "ms-windows-store:")
            Run, %appPath% %args%
        else
        {
            if (args != "")
                Run, "%appPath%" %args%
            else
                Run, "%appPath%"
        }
    }
    catch err
    {
        RevertRedirection(oldRedir)
        ShowLaunchError("Failed to launch app", err)
        return
    }
    RevertRedirection(oldRedir)

    if (windowIdentifier != "")
    {
        WinWait, %windowIdentifier%,, %timeout%
        if (!ErrorLevel)
            WinMaximize
        else
            ShowTransientToolTip("Window not detected: " . windowIdentifier)
    }
}

RunApp(appPath, args := "", name := "", maximize := false) {
    local err, oldRedir
    oldRedir := DisableRedirection()
    try {
        if InStr(appPath, "://") || InStr(appPath, "ms-windows-store:") {
            Run, %appPath% %args%, , % maximize ? "Max" : ""
        } else {
            if !FileExist(appPath) {
                ShowTransientToolTip(name . " not found at:`n" . appPath)
                RevertRedirection(oldRedir)
                return
            }
            if (args != "")
                Run, "%appPath%" %args%, , % maximize ? "Max" : ""
            else
                Run, "%appPath%", , % maximize ? "Max" : ""
        }
    } catch err {
        ShowLaunchError("Failed to launch " . name, err)
    }
    RevertRedirection(oldRedir)
}

RunAppAndNotify(appPath, args := "", name := "", maximize := false) {
    ShowTransientToolTip(name)
    RunApp(appPath, args, name, maximize)
}

ShowLaunchError(prefix, err) {
    ShowTransientToolTip(prefix . ": " . err)
}

ShowTransientToolTip(message, durationMs := "") {
    if (durationMs = "")
        durationMs := TOOLTIP_DURATION_MS
    ToolTip, %message%
    SetTimer, RemoveToolTip, % -durationMs
}

TriggerScheduledTask(taskName, friendlyName, triggerFile := "", resultFile := "", timeoutSec := 60) {
    local ResultData, Parts, err, oldRedir

    if (taskName = "" || friendlyName = "") {
        ShowTransientToolTip("Scheduled task configuration is invalid")
        return
    }

    DeleteFileIfExists(resultFile)

    if (triggerFile != "") {
        DeleteFileIfExists(triggerFile)
        try
            FileAppend, hotkey, %triggerFile%
        catch err {
            ShowLaunchError("Failed to write trigger file", err)
            return
        }
    }

    oldRedir := DisableRedirection()
    try {
        Run, schtasks.exe /Run /TN "%taskName%" /I,, Hide
        ShowTransientToolTip(friendlyName . " in progress...")
    } catch err {
        RevertRedirection(oldRedir)
        ShowLaunchError("Failed to trigger " . friendlyName, err)
        return
    }
    RevertRedirection(oldRedir)

    if (resultFile == "")
        return

    Loop, % (timeoutSec * 2) { ; 500ms intervals
        Sleep, 500
        if FileExist(resultFile) {
            Sleep, 200
            FileRead, ResultData, %resultFile%
            DeleteFileIfExists(resultFile)
            ToolTip
            Parts := StrSplit(ResultData, "|")
            TrayTip, % Parts[1], % Parts[2], 4, (InStr(Parts[1], "success") ? 1 : 2)
            return
        }
    }
    ToolTip
    TrayTip, %friendlyName%, Timed out - check logs, 4, 3
}

; ====================[ Subroutines & Timers ]====================

RemoveToolTip:
    ToolTip
return

WatchScript:
    FileGetTime, curModTime, %A_ScriptFullPath%
    if (ScriptModTime = "") {
        ScriptModTime := curModTime
        return
    }
    if (curModTime != ScriptModTime) {
        ToolTip, Reloading Script...
        SetTimer, RemoveToolTip, -1000
        Reload
    }
return

; ====================[ Hotkeys ]====================

!0::RunApp("calc.exe", "", "Calculator")

!1::
    now := A_TickCount
    timeSinceLastPress := now - one_LastPress
    one_LastPress := now
    if (timeSinceLastPress > 0 && timeSinceLastPress < DOUBLE_PRESS_DELAY)
    {
        one_LastPress := 0
        RunApp(GetPhotoshopPath(), "", "Photoshop", true)
    }
return

!a::HandleContextHotkey("a", "Antigravity", GetAntigravityPath(), "", "", true)

#MaxThreadsPerHotkey 1
!c::
    pressStart := A_TickCount

    ; Wait up to LONG_PRESS_THRESHOLD ms for key release
    KeyWait, c, T0.6

    pressDuration := A_TickCount - pressStart
    path := GetDynamicAppPath("chrome.exe")

    if (pressDuration >= LONG_PRESS_THRESHOLD)
    {
        ; Long press: incognito fires immediately at 600ms, then block until key released
        if (!FileExist(path))
        {
            MsgBox, 16, Error, Chrome not found:`n%path%
            KeyWait, c
            return
        }
        oldR := DisableRedirection()
        try
            Run, "%path%" --incognito
        catch e
        {
            RevertRedirection(oldR)
            ShowLaunchError("Failed to launch Chrome", e)
            KeyWait, c
            return
        }
        RevertRedirection(oldR)
        KeyWait, c
    }
    else
    {
        ; Short press: wait for release then open normal Chrome
        KeyWait, c
        if (!FileExist(path))
        {
            MsgBox, 16, Error, Chrome not found:`n%path%
            return
        }
        oldR := DisableRedirection()
        try
            Run, "%path%"
        catch e
        {
            RevertRedirection(oldR)
            ShowLaunchError("Failed to launch Chrome", e)
            return
        }
        RevertRedirection(oldR)
    }

    WinWait, ahk_exe chrome.exe,, %WINDOW_WAIT_TIMEOUT%
    if (!ErrorLevel)
        WinMaximize
    else
        ShowTransientToolTip("Chrome window not detected")
return
#MaxThreadsPerHotkey 1

!g::HandleContextHotkey("g", "Git Bash", GetGitBashPath(), "--cd-to-home", "--cd=")

!i::
    ShowTransientToolTip("Instagram")
    path := FindAppShortcut("Instagram")
    if (path != "")
        LaunchAndMaximize(path, "Instagram", WINDOW_WAIT_TIMEOUT)
    else
        LaunchAndMaximize(GetDynamicAppPath("chrome.exe"), "Instagram", WINDOW_WAIT_TIMEOUT, "--app=https://www.instagram.com/")
return

!m::RunApp("ms-windows-store:", "", "Microsoft Store", true)

!n::RunApp("notepad.exe", "", "Notepad")

!p::
    now := A_TickCount
    timeSinceLastPress := now - p_LastPress

    if (timeSinceLastPress > 0 && timeSinceLastPress < DOUBLE_PRESS_DELAY)
    {
        p_LastPress := 0
        SetTimer, P_SinglePress, Off

        WinGetClass, class, A
        dir := ""
        if (class = "CabinetWClass" || class = "ExploreWClass")
            dir := GetExplorerPath()

        if (dir != "")
        {
            ShowTransientToolTip("Admin PowerShell in Folder")
            oldR := DisableRedirection()
            try
                Run, *RunAs powershell.exe -NoExit -Command "Set-Location -LiteralPath '%dir%'"
            catch e
            {
                if (A_LastError != 1223)
                    ShowLaunchError("Failed to launch Admin PowerShell", e)
            }
            RevertRedirection(oldR)
        }
        else
        {
            ShowTransientToolTip("Admin PowerShell")
            oldR := DisableRedirection()
            try
                Run, *RunAs powershell.exe, %USER_HOME%
            catch e
            {
                if (A_LastError != 1223)
                    ShowLaunchError("Failed to launch Admin PowerShell", e)
            }
            RevertRedirection(oldR)
        }
    }
    else
    {
        p_LastPress := now
        SetTimer, P_SinglePress, -%DOUBLE_PRESS_DELAY%
    }
return

P_SinglePress:
    ShowTransientToolTip("Admin PowerShell")
    oldR := DisableRedirection()
    try
        Run, *RunAs powershell.exe, %USER_HOME%
    catch e
    {
        if (A_LastError != 1223)
            ShowLaunchError("Failed to launch Admin PowerShell", e)
    }
    RevertRedirection(oldR)
return

!q::
    while GetKeyState("q", "P") && GetKeyState("Alt", "P")
    {
        WinGetClass, activeClass, A
        if IsProtectedWindowClass(activeClass)
        {
            ShowTransientToolTip("Cannot close system window")
            break
        }
        WinClose, A
        Sleep, 100
    }
return

!o::
    now := A_TickCount
    timeSinceLastPress := now - o_LastPress

    if (timeSinceLastPress > 0 && timeSinceLastPress < DOUBLE_PRESS_DELAY)
    {
        o_LastPress := 0
        SetTimer, O_SinglePress, Off

        WinGetClass, class, A
        dir := ""
        if (class = "CabinetWClass" || class = "ExploreWClass")
            dir := GetExplorerPath()

        if (dir != "")
        {
            ShowTransientToolTip("Admin CMD in Folder")
            oldR := DisableRedirection()
            try
                Run, *RunAs cmd.exe /K cd /d "%dir%"
            catch e
            {
                if (A_LastError != 1223)
                    ShowLaunchError("Failed to launch Admin CMD", e)
            }
            RevertRedirection(oldR)
        }
        else
        {
            ShowTransientToolTip("Admin CMD")
            oldR := DisableRedirection()
            try
                Run, *RunAs cmd.exe, %USER_HOME%
            catch e
            {
                if (A_LastError != 1223)
                    ShowLaunchError("Failed to launch Admin CMD", e)
            }
            RevertRedirection(oldR)
        }
    }
    else
    {
        o_LastPress := now
        SetTimer, O_SinglePress, -%DOUBLE_PRESS_DELAY%
    }
return

O_SinglePress:
    ShowTransientToolTip("CMD")
    oldR := DisableRedirection()
    try
        Run, cmd.exe, %USER_HOME%
    catch e
    {
        ShowLaunchError("Failed to launch CMD", e)
    }
    RevertRedirection(oldR)
return

!s::
    LaunchAndMaximize(GetSlackPath(), "ahk_exe slack.exe", WINDOW_WAIT_TIMEOUT)
return

!t::
    LaunchAndMaximize("tg://", "ahk_exe Telegram.exe", WINDOW_WAIT_TIMEOUT)
return

!u::
    now := A_TickCount
    timeSinceLastPress := now - u_LastPress

    if (timeSinceLastPress > 0 && timeSinceLastPress < DOUBLE_PRESS_DELAY)
    {
        u_LastPress := 0
        SetTimer, U_SinglePress, Off
        
        dir := GetValidExplorerPath()
        if (dir != "")
        {
            unixPath := ConvertToWSLPath(dir)
            ShowTransientToolTip("WSL")
            oldR := DisableRedirection()
            try
                Run, wsl.exe -d Ubuntu-22.04 -- bash -lc "cd '%unixPath%'; exec bash"
            catch e
                ShowTransientToolTip("Failed to launch Ubuntu 22.04`nIs WSL installed? " . e)
            RevertRedirection(oldR)
        }
    }
    else
    {
        u_LastPress := now
        SetTimer, U_SinglePress, -%DOUBLE_PRESS_DELAY%
    }
return

U_SinglePress:
    ShowTransientToolTip("WSL")
    oldR := DisableRedirection()
    try
        Run, wsl.exe -d Ubuntu-22.04 -- bash -lc "cd ~; exec bash"
    catch e
    {
        ShowTransientToolTip("Failed to launch Ubuntu 22.04`nIs WSL installed? " . e)
    }
    RevertRedirection(oldR)
return

!v::HandleContextHotkey("v", "VS Code", GetDynamicAppPath("Code.exe"), "", "", true)

!w::
    ShowTransientToolTip("WhatsApp")
    LaunchAndMaximize("whatsapp://", "WhatsApp", WINDOW_WAIT_TIMEOUT)
return

!y::
    LaunchAndMaximize(GetDynamicAppPath("chrome.exe"), "YouTube", WINDOW_WAIT_TIMEOUT, "--app=https://www.youtube.com/")
return

!z::ExtractSelectedZip()

^+!c::
    TriggerScheduledTask("WindowsCleanup", "Cleanup"
        , SYS_SCRIPTS_DIR . "\cleanup\cleanup_trigger.txt"
        , SYS_SCRIPTS_DIR . "\cleanup\cleanup_result.txt", 60)
return

^+!Delete::
    MsgBox, 4, Empty Recycle Bin, Are you sure you want to permanently delete all items in the Recycle Bin?
    IfMsgBox, Yes
    {
        try
        {
            DllCall("shell32\SHEmptyRecycleBin", "Ptr", 0, "Ptr", 0, "UInt", 0x1)
            ShowTransientToolTip("Recycle Bin emptied")
        }
        catch e
        {
            ShowLaunchError("Failed to empty Recycle Bin", e)
        }
    }
return

^+!l::
    if !FileExist(LOGS_DIR)
    {
        ShowTransientToolTip("Logs folder not found: " . LOGS_DIR)
        return
    }
    oldR := DisableRedirection()
    try
        Run, explorer.exe "%LOGS_DIR%"
    catch e
    {
        ShowLaunchError("Failed to open logs folder", e)
    }
    RevertRedirection(oldR)
return

^+!n::
    TriggerScheduledTask("NetworkReset", "Network Reset"
        , ""
        , SYS_SCRIPTS_DIR . "\network\netreset_result.txt", 90)
return

^+!u::
    FormatTime, today,, yyyy-MM-dd
    FileRead, lastRun, %SYS_SCRIPTS_DIR%\update\update_lastrun.txt
    if (Trim(lastRun) = today)
    {
        ShowTransientToolTip("Update already completed today")
        return
    }
    TriggerScheduledTask("WindowsUpdater", "Update"
        , SYS_SCRIPTS_DIR . "\update\update_trigger.txt"
        , SYS_SCRIPTS_DIR . "\update\update_result.txt", 180)
return
