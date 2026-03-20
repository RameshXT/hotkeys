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
; Ctrl+Shift+Alt+Delete  → Empty Recycle Bin (with confirm)

; ====================[ Script Config ]====================
#NoEnv
#SingleInstance Force
#Persistent
#Warn
SendMode Input
SetWorkingDir %A_ScriptDir%

; ====================[ Path Config ]====================
global USER_HOME := "C:\Users\rames"
global VSCODE_PATH := USER_HOME . "\AppData\Local\Programs\Microsoft VS Code\Code.exe"
global GIT_BASH_PATH := "C:\Program Files\Git\bin\bash.exe"
global GIT_BASH_EXE := "C:\Program Files\Git\git-bash.exe"
global CHROME_PATH := "C:\Program Files\Google\Chrome\Application\chrome.exe"
global WHATSAPP_LNK := "C:\Program Files\WhatsApp.lnk"
global INSTAGRAM_LNK := "C:\Program Files\Instagram.lnk"
global SLACK_LNK := "C:\Program Files\Slack.lnk"
global YOUTUBE_LNK := USER_HOME . "\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Chrome Apps\YouTube.lnk"
global CHROME_LNK := "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Google Chrome.lnk"
global ANTIGRAVITY_LNK := USER_HOME . "\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Antigravity\Antigravity.lnk"

; ====================[ Timing Config ]====================
global DOUBLE_PRESS_DELAY := 400
global LONG_PRESS_THRESHOLD := 600
global WINDOW_WAIT_TIMEOUT := 5

; ====================[ State Variables ]====================
global v_LastPress := 0
global g_LastPress := 0
global t_LastPress := 0
global a_LastPress := 0


; ====================[ Helper Functions ]====================
GetExplorerPath()
{
    local folderPath

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
    StringReplace, unixPath, winPath, \, /, All

    ; Convert drive letter (C: -> /c)
    if (SubStr(unixPath, 2, 1) = ":")
    {
        drive := SubStr(unixPath, 1, 1)
        StringLower, drive, drive
        unixPath := "/" . drive . SubStr(unixPath, 3)
    }

    return unixPath
}

; ====================[ Launch & Maximize Helper ]====================
LaunchAndMaximize(appPath, windowIdentifier := "", timeout := 5)
{
    local e

    if (!FileExist(appPath))
    {
        MsgBox, 16, Error, Application not found:`n%appPath%
        return false
    }

    try
    {
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


; ====================[ VS Code | Alt + V (Single / Double) ]====================
!v::
    now := A_TickCount
    timeSinceLastPress := now - v_LastPress

    if (timeSinceLastPress > 0 && timeSinceLastPress < DOUBLE_PRESS_DELAY)
    {
        ; Double press - open VS Code in current Explorer folder
        v_LastPress := 0
        SetTimer, V_SinglePress, Off

        path := GetValidExplorerPath()
        if (path = "")
            return

        if (!FileExist(VSCODE_PATH))
        {
            MsgBox, 16, Error, VS Code not found:`n%VSCODE_PATH%
            return
        }

        try
            Run, "%VSCODE_PATH%" "%path%"
        catch e
        {
            ToolTip, Failed to open VS Code: %e%
            SetTimer, RemoveToolTip, -2000
        }
    }
    else
    {
        ; First press - start timer for single press
        v_LastPress := now
        SetTimer, V_SinglePress, -%DOUBLE_PRESS_DELAY%
    }
return

V_SinglePress:
    v_LastPress := 0
    if (!FileExist(VSCODE_PATH))
    {
        MsgBox, 16, Error, VS Code not found:`n%VSCODE_PATH%
        return
    }
    try
        Run, "%VSCODE_PATH%"
    catch e
    {
        ToolTip, Failed to launch VS Code: %e%
        SetTimer, RemoveToolTip, -2000
    }
return


; ====================[ Antigravity | Alt + A (Single / Double) ]====================
!a::
    now := A_TickCount
    timeSinceLastPress := now - a_LastPress

    if (timeSinceLastPress > 0 && timeSinceLastPress < DOUBLE_PRESS_DELAY)
    {
        ; Double press - open Antigravity in current Explorer folder
        a_LastPress := 0
        SetTimer, A_SinglePress, Off

        path := GetValidExplorerPath()
        if (path = "")
            return

        if (!FileExist(ANTIGRAVITY_LNK))
        {
            MsgBox, 16, Error, Antigravity not found:`n%ANTIGRAVITY_LNK%
            return
        }

        try
            Run, "%ANTIGRAVITY_LNK%" "%path%"
        catch e
        {
            ToolTip, Failed to open Antigravity: %e%
            SetTimer, RemoveToolTip, -2000
        }
    }
    else
    {
        ; First press - start timer for single press
        a_LastPress := now
        SetTimer, A_SinglePress, -%DOUBLE_PRESS_DELAY%
    }
return

A_SinglePress:
    a_LastPress := 0
    if (!FileExist(ANTIGRAVITY_LNK))
    {
        MsgBox, 16, Error, Antigravity not found:`n%ANTIGRAVITY_LNK%
        return
    }
    try
        Run, "%ANTIGRAVITY_LNK%"
    catch e
    {
        ToolTip, Failed to launch Antigravity: %e%
        SetTimer, RemoveToolTip, -2000
    }
return


; ====================[ Git Bash | Alt + G (Single / Double) ]====================
!g::
    now := A_TickCount
    timeSinceLastPress := now - g_LastPress

    if (timeSinceLastPress > 0 && timeSinceLastPress < DOUBLE_PRESS_DELAY)
    {
        g_LastPress := 0
        SetTimer, G_SinglePress, Off

        path := GetValidExplorerPath()
        if (path = "")
            return

        if (!FileExist(GIT_BASH_EXE))
        {
            MsgBox, 16, Error, Git Bash not found:`n%GIT_BASH_EXE%
            return
        }

        try
            Run, "%GIT_BASH_EXE%" --cd="%path%"
        catch e
        {
            ToolTip, Failed to launch Git Bash: %e%
            SetTimer, RemoveToolTip, -2000
        }
    }
    else
    {
        g_LastPress := now
        SetTimer, G_SinglePress, -%DOUBLE_PRESS_DELAY%
    }
return

G_SinglePress:
    g_LastPress := 0
    if (!FileExist(GIT_BASH_EXE))
    {
        MsgBox, 16, Error, Git Bash not found:`n%GIT_BASH_EXE%
        return
    }
    try
        Run, "%GIT_BASH_EXE%" --cd-to-home
    catch e
    {
        ToolTip, Failed to launch Git Bash: %e%
        SetTimer, RemoveToolTip, -2000
    }
return


; ====================[ Ubuntu 22.04 - Always Home | Alt + U ]====================
!u::
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
    t_LastPress := 0
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
    LaunchAndMaximize(WHATSAPP_LNK, "WhatsApp", WINDOW_WAIT_TIMEOUT)
return


; ====================[ Instagram App - New Window (Always) | Alt + I ]====================
!i::
    LaunchAndMaximize(INSTAGRAM_LNK, "Instagram", WINDOW_WAIT_TIMEOUT)
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
!n::
    try
        Run, notepad.exe
    catch e
    {
        ToolTip, Failed to launch Notepad: %e%
        SetTimer, RemoveToolTip, -2000
    }
return


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
!0::
    try
        Run, calc.exe
    catch e
    {
        ToolTip, Failed to launch Calculator: %e%
        SetTimer, RemoveToolTip, -2000
    }
return


; ====================[ Windows Cleanup | Ctrl+Shift+Alt+C ]====================
^+!c::
    ResultFile := USER_HOME . "\cleanup_result.txt"

    ; Delete any old result file before triggering
    if FileExist(ResultFile)
        FileDelete, %ResultFile%

    ; Write trigger hint file so cleanup.ps1 knows this came from hotkey
    TriggerFile := USER_HOME . "\cleanup_trigger.txt"
    FileAppend, hotkey, %TriggerFile%

    try
    {
        Run, schtasks.exe /Run /TN "WindowsCleanup" /I,, Hide
        ToolTip, Cleaning...
        SetTimer, RemoveToolTip, -2000
    }
    catch e
    {
        if (A_LastError != 1223)
        {
            ToolTip, Failed to trigger cleanup: %e%
            SetTimer, RemoveToolTip, -2000
        }
        return
    }

    ; Poll for result file (max 60s)
    Loop, 120
    {
        Sleep, 500
        if FileExist(ResultFile)
        {
            Sleep, 200
            FileRead, MsgBody, %ResultFile%
            FileDelete, %ResultFile%
            ToolTip
            MsgBox, 64, Cleanup Done, %MsgBody%
            return
        }
    }

    ToolTip
    ToolTip, Cleanup timed out - check cleanup_log.txt
    SetTimer, RemoveToolTip, -2000
return


; ====================[ Windows Updater | Ctrl+Shift+Alt+U ]====================
^+!u::
    ; Delete any stale trigger file
    TriggerFile := USER_HOME . "\update_trigger.txt"
    if FileExist(TriggerFile)
        FileDelete, %TriggerFile%

    ; Write trigger hint so update.ps1 knows this came from hotkey
    FileAppend, hotkey, %TriggerFile%

    try
    {
        Run, schtasks.exe /Run /TN "WindowsUpdater" /I,, Hide
    }
    catch e
    {
        if (A_LastError != 1223)
        {
            ToolTip, Failed to trigger updater: %e%
            SetTimer, RemoveToolTip, -2000
        }
    }
return


; ====================[ Network Reset | Ctrl+Shift+Alt+N ]====================
^+!n::
    try
    {
        Run, schtasks.exe /Run /TN "NetworkReset" /I,, Hide
        ToolTip, Resetting network...
        SetTimer, RemoveToolTip, -2000
    }
    catch e
    {
        if (A_LastError != 1223)
        {
            ToolTip, Failed to trigger network reset: %e%
            SetTimer, RemoveToolTip, -2000
        }
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
