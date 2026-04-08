; ==================[ Hotkey Reference ]==================
; Alt + V        → VS Code  |  Double → VS Code in Explorer folder
; Alt + A        → Antigravity  |  Double → Antigravity in Explorer folder
; Alt + G        → Git Bash  |  Double → Git Bash in Explorer folder
; Alt + U        → Ubuntu 22.04 WSL
; Alt + T        → CMD  |  Double → CMD (Admin)
; Alt + P        → PowerShell (Admin)
; Alt + Y        → YouTube
; Alt + W        → WhatsApp
; Alt + I        → Instagram
; Alt + S        → Slack
; Alt + C        → Chrome  |  Long Press → Chrome Incognito
; Alt + N        → Notepad
; Alt + Q        → Close Active Window (hold to keep closing)
; Alt + 0        → Calculator

; Ctrl+Shift+Alt+C       → Run Windows Cleanup Script
; Ctrl+Shift+Alt+U       → Run Windows Updater Script
; Ctrl+Shift+Alt+N       → Run Network Reset Script
; Ctrl+Shift+Alt+L       → Open Logs Folder
; Ctrl+Shift+Alt+Delete  → Empty Recycle Bin (with confirm)

; ====================[ Script Config ]====================
#NoEnv
#SingleInstance Force
#Persistent
#Warn
SendMode Input
SetWorkingDir %A_ScriptDir%

; Auto-Reload on Script Change
SetTimer, WatchScript, 1000

; ====================[ Path & URI Config ]====================
EnvGet, USER_HOME, USERPROFILE
global VSCODE_PATH      := USER_HOME . "\AppData\Local\Programs\Microsoft VS Code\Code.exe"
global GIT_BASH_EXE     := "C:\Program Files\Git\git-bash.exe"
global CHROME_PATH      := "C:\Program Files\Google\Chrome\Application\chrome.exe"
global LOGS_DIR         := USER_HOME . "\sys-scripts\logs"

; Apps and Direct Links
global WHATSAPP_APP     := "C:\Program Files\WhatsApp.lnk"
global INSTAGRAM_APP    := "C:\Program Files\Instagram.lnk"
global SLACK_LNK        := "C:\Program Files\Slack.lnk"
global YOUTUBE_LNK      := USER_HOME . "\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Chrome Apps\YouTube.lnk"
global CHROME_LNK       := "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Google Chrome.lnk"
global ANTIGRAVITY_LNK  := USER_HOME . "\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Antigravity\Antigravity.lnk"

; ====================[ Timing Config ]====================
global DOUBLE_PRESS_DELAY   := 400
global LONG_PRESS_THRESHOLD := 600
global WINDOW_WAIT_TIMEOUT  := 5

; ====================[ State Variables ]====================
global t_LastPress := 0
global u_LastPress := 0
global ScriptModTime := "" ; Used for Auto-Reload

; ====================[ Helper Functions ]====================

; Generic handler for Scheduled Tasks with Result waiting
TriggerScheduledTask(taskName, friendlyName, triggerFile := "", resultFile := "", timeoutSec := 60) {
    local ResultData, Parts, e
    
    if (resultFile != "" && FileExist(resultFile))
        FileDelete, %resultFile%

    if (triggerFile != "") {
        if FileExist(triggerFile)
            FileDelete, %triggerFile%
        try 
            FileAppend, hotkey, %triggerFile%
        catch e {
            ToolTip, Failed to write trigger file: %e%
            SetTimer, RemoveToolTip, -2000
            return
        }
    }

    try {
        Run, schtasks.exe /Run /TN "%taskName%" /I,, Hide
        ToolTip, %friendlyName% in progress...
        SetTimer, RemoveToolTip, -2000
    } catch e {
        ToolTip, Failed to trigger %friendlyName%: %e%
        SetTimer, RemoveToolTip, -2000
        return
    }

    if (resultFile == "")
        return

    Loop, % (timeoutSec * 2) { ; 500ms intervals
        Sleep, 500
        if FileExist(resultFile) {
            Sleep, 200
            FileRead, ResultData, %resultFile%
            FileDelete, %resultFile%
            ToolTip
            Parts := StrSplit(ResultData, "|")
            TrayTip, % Parts[1], % Parts[2], 4, (InStr(Parts[1], "success") ? 1 : 2)
            return
        }
    }
    ToolTip
    TrayTip, %friendlyName%, Timed out - check logs, 4, 3
}

; Generic handler for Single/Double press logic
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
            ToolTip, %name%
            SetTimer, RemoveToolTip, -2000
            RunApp(path, dPre . """" . dir . """")
        }
    } else {
        lastPresses[key] := now
        timerObj := Func("RunAppAndNotify").Bind(path, sArgs, name)
        timers[key] := timerObj
        SetTimer, % timerObj, % -DOUBLE_PRESS_DELAY
    }
}

; Helper to Run App and show ToolTip for single press
RunAppAndNotify(path, args, name) {
    ToolTip, %name%
    SetTimer, RemoveToolTip, -2000
    RunApp(path, args)
}

; Robust App Runner supporting Paths and URIs
RunApp(path, args := "", name := "") {
    local e
    if (name != "") {
        ToolTip, %name%
        SetTimer, RemoveToolTip, -2000
    }
    try {
        if InStr(path, "://") {
            Run, %path%
        } else {
            ; Only check for existence if a specific path is provided (contains a backslash)
            if (InStr(path, "\") && !FileExist(path)) {
                MsgBox, 16, Error, Target not found:`n%path%
                return
            }
            
            if (args != "")
                Run, "%path%" %args%
            else
                Run, "%path%"
        }
    } catch e {
        ToolTip, Launch Error: %e%
        SetTimer, RemoveToolTip, -2000
    }
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
        ToolTip, Error getting Explorer path: %e%
        SetTimer, RemoveToolTip, -2000
    }
    return ""
}

; ====================[ Convert Path to WSL Format ]====================
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

; ====================[ Launch & Maximize Helper ]====================
LaunchAndMaximize(appPath, windowIdentifier := "", timeout := 5)
{
    local e
    if (!InStr(appPath, "://") && !FileExist(appPath))
    {
        MsgBox, 16, Error, Application not found:`n%appPath%
        return false
    }

    try
    {
        if InStr(appPath, "://")
            Run, %appPath%
        else
            Run, "%appPath%"
    }
    catch e
    {
        MsgBox, 16, Launch Error, Failed to launch:`n%appPath%`n`nError: %e%
        return false
    }

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

; ====================[ Protected Explorer Path Helper ]====================
GetValidExplorerPath()
{
    local class, path

    WinGetClass, class, A
    if (class != "CabinetWClass" && class != "ExploreWClass")
    {
        ToolTip, Please focus on a File Explorer window
        SetTimer, RemoveToolTip, -2000
        return ""
    }

    path := GetExplorerPath()
    if (path = "")
    {
        ToolTip, Could not get folder path
        SetTimer, RemoveToolTip, -2000
        return ""
    }

    return path
}

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


; ====================[ Context Apps | Alt + V, A, G ]====================
!v::HandleContextHotkey("v", "VS Code", VSCODE_PATH)
!a::HandleContextHotkey("a", "Antigravity", ANTIGRAVITY_LNK)
!g::HandleContextHotkey("g", "Git Bash", GIT_BASH_EXE, "--cd-to-home", "--cd=")


; ====================[ Ubuntu 22.04 - Context Aware | Alt + U ]====================
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
            ToolTip, WSL
            SetTimer, RemoveToolTip, -2000
            try
                Run, wsl.exe -d Ubuntu-22.04 -- bash -lc "cd '%unixPath%'; exec bash"
            catch e
                ToolTip, Failed to launch Ubuntu 22.04`nIs WSL installed? %e%
        }
    }
    else
    {
        u_LastPress := now
        SetTimer, U_SinglePress, -%DOUBLE_PRESS_DELAY%
    }
return

U_SinglePress:
    ToolTip, WSL
    SetTimer, RemoveToolTip, -2000
    try
        Run, wsl.exe -d Ubuntu-22.04 -- bash -lc "cd ~; exec bash"
    catch e
    {
        ToolTip, Failed to launch Ubuntu 22.04`nIs WSL installed? %e%
        SetTimer, RemoveToolTip, -2000
    }
return


; ====================[ CMD - Always Home | Alt + T (Single / Double) ]====================
!t::
    now := A_TickCount
    timeSinceLastPress := now - t_LastPress

    if (timeSinceLastPress > 0 && timeSinceLastPress < DOUBLE_PRESS_DELAY)
    {
        t_LastPress := 0
        SetTimer, T_SinglePress, Off

        ToolTip, Admin CMD
        SetTimer, RemoveToolTip, -2000
        try
            Run, *RunAs cmd.exe, %USER_HOME%
        catch e
        {
            if (A_LastError != 1223) ; 1223 = user cancelled UAC
            {
                ToolTip, Failed to launch Admin CMD: %e%
                SetTimer, RemoveToolTip, -2000
            }
        }
    }
    else
    {
        t_LastPress := now
        SetTimer, T_SinglePress, -%DOUBLE_PRESS_DELAY%
    }
return

T_SinglePress:
    ToolTip, CMD
    SetTimer, RemoveToolTip, -2000
    try
        Run, cmd.exe, %USER_HOME%
    catch e
    {
        ToolTip, Failed to launch CMD: %e%
        SetTimer, RemoveToolTip, -2000
    }
return


; ====================[ PowerShell - (Admin) | Alt + P ]====================
!p::
    try
        Run, *RunAs powershell.exe
    catch e
    {
        if (A_LastError != 1223) ; 1223 = user cancelled UAC
        {
            ToolTip, Failed to launch Admin PowerShell: %e%
            SetTimer, RemoveToolTip, -2000
        }
    }
return
; ====================[ YouTube App - New Window (Always) | Alt + Y ]====================
!y::
    LaunchAndMaximize(YOUTUBE_LNK, "YouTube", WINDOW_WAIT_TIMEOUT)
return


; ====================[ WhatsApp App - New Window (Always) | Alt + W ]====================
!w::
    ToolTip, WhatsApp
    SetTimer, RemoveToolTip, -2000
    LaunchAndMaximize(WHATSAPP_APP, "WhatsApp", WINDOW_WAIT_TIMEOUT)
return


; ====================[ Instagram App - New Window (Always) | Alt + I ]====================
!i::
    ToolTip, Instagram
    SetTimer, RemoveToolTip, -2000
    LaunchAndMaximize(INSTAGRAM_APP, "Instagram", WINDOW_WAIT_TIMEOUT)
return


; ====================[ Slack - Default Open | Alt + S ]====================
!s::
    LaunchAndMaximize(SLACK_LNK, "ahk_exe slack.exe", WINDOW_WAIT_TIMEOUT)
return


; ====================[ Chrome - Single / Long Press | Alt + C ]====================
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
        try
            Run, "%CHROME_PATH%" --incognito
        catch e
        {
            ToolTip, Failed to launch Chrome: %e%
            SetTimer, RemoveToolTip, -2000
            KeyWait, c
            return
        }
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
        try
            Run, "%CHROME_LNK%"
        catch e
        {
            ToolTip, Failed to launch Chrome: %e%
            SetTimer, RemoveToolTip, -2000
            return
        }
    }

    WinWait, ahk_exe chrome.exe,, %WINDOW_WAIT_TIMEOUT%
    if (!ErrorLevel)
        WinMaximize
    else
    {
        ToolTip, Chrome window not detected
        SetTimer, RemoveToolTip, -2000
    }
return
#MaxThreadsPerHotkey 1


; ====================[ Notepad | Alt + N ]====================
!n::RunApp("notepad.exe", "", "Notepad")


; ====================[ Close Active App | Alt + Q (Continuous) ]====================
!q::
    while GetKeyState("q", "P") && GetKeyState("Alt", "P")
    {
        WinGetClass, activeClass, A
        if (activeClass = "Shell_TrayWnd" || activeClass = "Progman" || activeClass = "WorkerW")
        {
            ToolTip, Cannot close system window
            SetTimer, RemoveToolTip, -2000
            break
        }
        WinClose, A
        Sleep, 100
    }
return


; ====================[ Calculator | Alt + 0 ]====================
!0::RunApp("calc.exe", "", "Calculator")


; ====================[ Windows Cleanup | Ctrl+Shift+Alt+C ]====================
^+!c::
    TriggerScheduledTask("WindowsCleanup", "Cleanup"
        , USER_HOME . "\sys-scripts\cleanup\cleanup_trigger.txt"
        , USER_HOME . "\sys-scripts\cleanup\cleanup_result.txt", 60)
return


; ====================[ Windows Updater | Ctrl+Shift+Alt+U ]====================
^+!u::
    TriggerScheduledTask("WindowsUpdater", "Update"
        , USER_HOME . "\sys-scripts\update\update_trigger.txt"
        , USER_HOME . "\sys-scripts\update\update_result.txt", 180)
return


; ====================[ Network Reset | Ctrl+Shift+Alt+N ]====================
^+!n::TriggerScheduledTask("NetworkReset", "Network Reset")


; ====================[ Open Logs Folder | Ctrl+Shift+Alt+L ]====================
^+!l::
    if !FileExist(LOGS_DIR)
    {
        ToolTip, Logs folder not found: %LOGS_DIR%
        SetTimer, RemoveToolTip, -2000
        return
    }
    try
        Run, explorer.exe "%LOGS_DIR%"
    catch e
    {
        ToolTip, Failed to open logs folder: %e%
        SetTimer, RemoveToolTip, -2000
    }
return


; ====================[ Empty Recycle Bin | Ctrl+Shift+Alt+Delete ]====================
^+!Delete::
    MsgBox, 4, Empty Recycle Bin, Are you sure you want to permanently delete all items in the Recycle Bin?
    IfMsgBox, Yes
    {
        try
        {
            DllCall("shell32\SHEmptyRecycleBin", "Ptr", 0, "Ptr", 0, "UInt", 0x1)
            ToolTip, Recycle Bin emptied
            SetTimer, RemoveToolTip, -2000
        }
        catch e
        {
            ToolTip, Failed to empty Recycle Bin: %e%
            SetTimer, RemoveToolTip, -2000
        }
    }
return
