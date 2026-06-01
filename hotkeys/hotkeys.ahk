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
global CHROME_LNK       := "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Google Chrome.lnk"
global CHROME_PATH      := "C:\Program Files\Google\Chrome\Application\chrome.exe"
global DOUBLE_PRESS_DELAY   := 400
global GIT_BASH_EXE     := "C:\Program Files\Git\git-bash.exe"
global INSTAGRAM_APP    := "C:\Program Files\Instagram.lnk"
global LOGS_DIR         := USER_HOME . "\sys-scripts\logs"
global LONG_PRESS_THRESHOLD := 600
global o_LastPress := 0
global one_LastPress := 0
global p_LastPress := 0
global ScriptModTime := "" ; Used for Auto-Reload
global TOOLTIP_DURATION_MS  := 2000
global u_LastPress := 0
global VSCODE_PATH      := USER_HOME . "\AppData\Local\Programs\Microsoft VS Code\Code.exe"
global WHATSAPP_APP     := "C:\Program Files\WhatsApp.lnk"
global WINDOW_WAIT_TIMEOUT  := 5
global YOUTUBE_LNK      := USER_HOME . "\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Chrome Apps\YouTube.lnk"

; ====================[ Helper Functions ]====================

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
    local class, selectedPath, fileDir, fileExtension, nameNoExt, targetDir, winrarPath, safeSelectedPath, safeTargetDir
    WinGetClass, class, A
    if (class != "CabinetWClass" && class != "ExploreWClass")
        return
    selectedPath := GetSelectedFilePath()
    if (selectedPath = "")
        return
    SplitPath, selectedPath, , fileDir, fileExtension, nameNoExt
    if (fileExtension != "zip" && fileExtension != "ZIP")
        return
    targetDir := fileDir . "\" . nameNoExt . "\"
    winrarPath := "C:\Program Files\WinRAR\WinRAR.exe"
    if FileExist(winrarPath) {
        oldR := DisableRedirection()
        Run, "%winrarPath%" x -o+ "%selectedPath%" "%targetDir%"
        RevertRedirection(oldR)
    }
    else
    {
        StringReplace, safeSelectedPath, selectedPath, ', '', All
        StringReplace, safeTargetDir, targetDir, ', '', All
        oldR := DisableRedirection()
        Run, powershell.exe -NoProfile -Command "Expand-Archive -Path '%safeSelectedPath%' -DestinationPath '%safeTargetDir%' -Force",, Hide
        RevertRedirection(oldR)
    }
}

GetAntigravityPath()
{
    local userHome, paths, index, path
    EnvGet, userHome, USERPROFILE
    paths := [ userHome . "\AppData\Local\Programs\Antigravity IDE\Antigravity IDE.exe"
             , "C:\Program Files\Antigravity IDE\Antigravity IDE.exe"
             , "C:\Program Files (x86)\Antigravity IDE\Antigravity IDE.exe"
             , userHome . "\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Antigravity\Antigravity.lnk"
             , userHome . "\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Antigravity IDE\Antigravity IDE.lnk" ]
    
    for index, path in paths
    {
        if FileExist(path)
            return path
    }
    
    return "antigravity-ide.cmd"
}

GetExplorerPath()
{
    local folderPath, window, e

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
    catch e
    {
        ShowLaunchError("Error getting Explorer path", e)
    }
    return ""
}

GetPhotoshopPath()
{
    local paths, index, path, userHome
    EnvGet, userHome, USERPROFILE
    paths := [ "C:\Program Files\Adobe\Adobe Photoshop 2024\Photoshop.exe"
             , "C:\Program Files\Adobe\Adobe Photoshop 2023\Photoshop.exe"
             , "C:\Program Files\Adobe\Adobe Photoshop 2022\Photoshop.exe"
             , "C:\Program Files\Adobe\Adobe Photoshop 2021\Photoshop.exe"
             , "C:\Program Files\Adobe\Adobe Photoshop 2020\Photoshop.exe"
             , "C:\Program Files\Adobe\Adobe Photoshop CC 2019\Photoshop.exe"
             , "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Adobe Photoshop.lnk"
             , userHome . "\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Adobe Photoshop.lnk" ]
    
    for index, path in paths
    {
        if FileExist(path)
            return path
    }
    
    return "Photoshop.exe"
}

GetSlackPath()
{
    local paths, index, path, userHome
    EnvGet, userHome, USERPROFILE
    paths := [ userHome . "\AppData\Local\slack\slack.exe"
             , "C:\Program Files\Slack\slack.exe"
             , "C:\Program Files\Slack.lnk"
             , "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Slack Technologies Inc\Slack.lnk"
             , userHome . "\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Slack Technologies Inc\Slack.lnk" ]
    
    for index, path in paths
    {
        if FileExist(path)
            return path
    }
    
    return "slack.exe"
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
    local class, path

    WinGetClass, class, A
    if (class != "CabinetWClass" && class != "ExploreWClass")
    {
        ShowTransientToolTip("Please focus on a File Explorer window")
        return ""
    }

    path := GetExplorerPath()
    if (path = "")
    {
        ShowTransientToolTip("Could not get folder path")
        return ""
    }

    return path
}

HandleContextHotkey(key, name, path, sArgs := "", dPre := "") {

    static lastPresses := {}
    static timers := {}
    local now, last, timerObj, dir

    now := A_TickCount
    last := lastPresses[key] ? lastPresses[key] : 0
    
    if (now - last < DOUBLE_PRESS_DELAY) {
        lastPresses[key] := 0
        timerObj := timers[key]
        SetTimer, % timerObj, Off
        
        dir := GetValidExplorerPath()
        if (dir != "") {
            ShowTransientToolTip(name)
            RunApp(path, dPre . """" . dir . """")
        }
    } else {
        lastPresses[key] := now
        timerObj := Func("RunAppAndNotify").Bind(path, sArgs, name)
        timers[key] := timerObj
        SetTimer, % timerObj, % -DOUBLE_PRESS_DELAY
    }
}

IsProtectedWindowClass(windowClass) {
    return (windowClass = "Shell_TrayWnd" || windowClass = "Progman" || windowClass = "WorkerW")
}

LaunchAndMaximize(appPath, windowIdentifier := "", timeout := 5)
{
    local e
    if (InStr(appPath, "\") && !FileExist(appPath))
    {
        MsgBox, 16, Error, Application not found:`n%appPath%
        return false
    }

    oldR := DisableRedirection()
    try
    {
        if InStr(appPath, "://")
            Run, %appPath%
        else
            Run, "%appPath%"
    }
    catch e
    {
        RevertRedirection(oldR)
        MsgBox, 16, Launch Error, Failed to launch:`n%appPath%`n`nError: %e%
        return false
    }
    RevertRedirection(oldR)

    if (windowIdentifier != "")
    {
        WinWait, %windowIdentifier%,, %timeout%
        if (!ErrorLevel)
            WinMaximize
        else
        {
            ToolTip, Window not detected: %windowIdentifier%
            SetTimer, RemoveToolTip, -2000
        }
    }

    return true
}

RunApp(path, args := "", name := "") {
    local e
    if (name != "") {
        ShowTransientToolTip(name)
    }
    oldR := DisableRedirection()
    try {
        if InStr(path, "://") {
            Run, %path%
        } else {
            ; Only check for existence if a specific path is provided (contains a backslash)
            if (InStr(path, "\") && !FileExist(path)) {
                RevertRedirection(oldR)
                MsgBox, 16, Error, Target not found:`n%path%
                return
            }
            
            if (args != "")
                Run, "%path%" %args%
            else
                Run, "%path%"
        }
    } catch e {
        ShowLaunchError("Launch Error", e)
    }
    RevertRedirection(oldR)
}

RunAppAndNotify(path, args, name) {
    ShowTransientToolTip(name)
    RunApp(path, args)
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
    local ResultData, Parts, e

    if (taskName = "" || friendlyName = "") {
        ShowTransientToolTip("Scheduled task configuration is invalid")
        return
    }

    DeleteFileIfExists(resultFile)

    if (triggerFile != "") {
        DeleteFileIfExists(triggerFile)
        try
            FileAppend, hotkey, %triggerFile%
        catch e {
            ShowLaunchError("Failed to write trigger file", e)
            return
        }
    }

    oldR := DisableRedirection()
    try {
        Run, schtasks.exe /Run /TN "%taskName%" /I,, Hide
        ShowTransientToolTip(friendlyName . " in progress...")
    } catch e {
        RevertRedirection(oldR)
        ShowLaunchError("Failed to trigger " . friendlyName, e)
        return
    }
    RevertRedirection(oldR)

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
        RunApp(GetPhotoshopPath(), "", "Photoshop")
    }
return

!a::HandleContextHotkey("a", "Antigravity", GetAntigravityPath())

#MaxThreadsPerHotkey 1
!c::
    pressStart := A_TickCount

    ; Wait up to LONG_PRESS_THRESHOLD ms for key release
    KeyWait, c, T0.6

    pressDuration := A_TickCount - pressStart

    if (pressDuration >= LONG_PRESS_THRESHOLD)
    {
        ; Long press: incognito fires immediately at 600ms, then block until key released
        if (!FileExist(CHROME_PATH))
        {
            MsgBox, 16, Error, Chrome not found:`n%CHROME_PATH%
            KeyWait, c
            return
        }
        oldR := DisableRedirection()
        try
            Run, "%CHROME_PATH%" --incognito
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
        if (!FileExist(CHROME_LNK))
        {
            MsgBox, 16, Error, Chrome shortcut not found:`n%CHROME_LNK%
            return
        }
        oldR := DisableRedirection()
        try
            Run, "%CHROME_LNK%"
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

!g::HandleContextHotkey("g", "Git Bash", GIT_BASH_EXE, "--cd-to-home", "--cd=")

!i::
    ShowTransientToolTip("Instagram")
    LaunchAndMaximize(INSTAGRAM_APP, "Instagram", WINDOW_WAIT_TIMEOUT)
return

!m::RunApp("ms-windows-store:", "", "Microsoft Store")

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

!v::HandleContextHotkey("v", "VS Code", VSCODE_PATH)

!w::
    ShowTransientToolTip("WhatsApp")
    LaunchAndMaximize(WHATSAPP_APP, "WhatsApp", WINDOW_WAIT_TIMEOUT)
return

!y::
    LaunchAndMaximize(YOUTUBE_LNK, "YouTube", WINDOW_WAIT_TIMEOUT)
return

!z::ExtractSelectedZip()

^+!c::
    TriggerScheduledTask("WindowsCleanup", "Cleanup"
        , USER_HOME . "\sys-scripts\cleanup\cleanup_trigger.txt"
        , USER_HOME . "\sys-scripts\cleanup\cleanup_result.txt", 60)
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
        , USER_HOME . "\sys-scripts\network\netreset_result.txt", 90)
return

^+!u::
    FormatTime, today,, yyyy-MM-dd
    FileRead, lastRun, %USER_HOME%\sys-scripts\update\update_lastrun.txt
    if (Trim(lastRun) = today)
    {
        ShowTransientToolTip("Update already completed today")
        return
    }
    TriggerScheduledTask("WindowsUpdater", "Update"
        , USER_HOME . "\sys-scripts\update\update_trigger.txt"
        , USER_HOME . "\sys-scripts\update\update_result.txt", 180)
return
