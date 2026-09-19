; ==================[ Hotkey Reference ]==================
; Alt + 0  → Calculator
; Alt + 1  → Photoshop (Double)
; Alt + 7  → 7.1 Surround Sound
; Alt + A  → Antigravity            | Double: Current Folder
; Alt + C  → Chrome                 | Hold: Incognito
; Alt + E  → Outlook
; Alt + G  → Git Bash               | Double: Current Folder
; Alt + I  → Instagram
; Alt + M  → Microsoft Store
; Alt + N  → Notepad
; Alt + O  → CMD                    | Double: Active Folder / Admin (otherwise) | Hold: Admin in Folder
; Alt + P  → PowerShell             | Double: Active Folder / Admin (otherwise) | Hold: Admin in Folder
; Alt + Q  → Close Window           | Hold: Repeat
; Alt + S  → Slack
; Alt + T  → Telegram
; Alt + U  → Ubuntu WSL             | Double: Current Folder
; Alt + V  → VS Code                | Double: Current Folder
; Alt + W  → WhatsApp
; Alt + Y  → YouTube
; Alt + Z  → Unzip ZIP
;
; Ctrl + Shift + Q         → Switch to Sony MDRX-50
; Ctrl + Shift + X         → Switch to Black Shark V2
; Ctrl + Shift + Y         → Switch to Resound
; Ctrl + Shift + Z         → Switch to HEAT
; Ctrl + Shift + Alt + Del → Empty Recycle Bin
; Alt + Shift + V          → Paste path as WSL

; ====================[ Core Environment Setup ]====================
#Requires AutoHotkey v2.0.26
#SingleInstance Force
#Warn
Persistent()
SendMode "Input"
SetWorkingDir A_ScriptDir

; ====================[ Modular Component Includes ]====================
#Include "src\config.ahk"
#Include "src\logging.ahk"
#Include "src\app-resolver.ahk"
#Include "src\helpers.ahk"
#Include "src\audio.ahk"
#Include "src\watchdog.ahk"

; ====================[ Process ID & Error Handlers ]====================
try {
    pidDir := EnvGet("LOCALAPPDATA") ? (EnvGet("LOCALAPPDATA") . "\xtkeys") : A_ScriptDir
    if !DirExist(pidDir)
        DirCreate(pidDir)
    f := FileOpen(pidDir . "\hotkeys.pid", "w")
    f.Write(DllCall("GetCurrentProcessId"))
    f.Close()
} catch {
}

SetTimer WatchScript, 3000
OnError(GlobalErrorHandler)

if (GetEnvInt("AHK_WATCHDOG_ENABLED", 1)) {
    SetTimer(() => ProcessWatchdog.Poll(), WATCHDOG_INTERVAL_MS)
}

; ====================[ Watchdog Process Registration ]====================
LaunchRazer71() {
    razer71Path := AppResolver.Get("Razer71", "rzappengine.exe", [
        "%ProgramFiles%\Razer\RzAppEngine\rzappengine.exe",
        "%StartMenuCommon%\Programs\Razer\7.1 Surround Sound.lnk"
    ])
    SplitPath razer71Path, , &razer71Dir
    RunApp(razer71Path, "--url-params=apps=7.1-surround-sound --disable-background-timer-throttling",
        "7.1 Surround Sound", razer71Dir)
}

ProcessWatchdog.Register("rzappengine.exe", "7.1 Surround Sound", LaunchRazer71)

; ====================[ Hotkeys ]====================
!0:: RunApp("calc.exe", "", "Calculator")

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
        RunApp(photoshopPath, "", "Photoshop", photoshopDir)
    }
    DoublePressManager.Handle("Photoshop", "", doublePress)
}

!7:: LaunchRazer71()

!a:: {
    antigravityPath := AppResolver.Get("Antigravity", "Antigravity IDE.exe", [
        "%LocalAppData%\Programs\Antigravity IDE\Antigravity IDE.exe",
        "%LocalAppData%\Programs\Antigravity IDE\bin\antigravity-ide.cmd",
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
    if (chromePath = "chrome.exe" && !FileExist(chromePath) && !SearchSystemPath(chromePath)) {
        ShowTransientToolTip("Opening Default Browser")
        try {
            if (pressDuration >= LONG_PRESS_THRESHOLD)
                Run(ResolveNativePath("cmd.exe") . " /c start microsoft-edge:-private")
            else
                Run(ResolveNativePath("cmd.exe") . " /c start https://www.google.com")
        } catch as e {
            ShowLaunchError("Failed to launch Browser", e)
        }
        KeyWait "c", "T2"
        return
    }

    if (pressDuration >= LONG_PRESS_THRESHOLD) {
        guard := Wow64RedirectionGuard()
        try
            Run('"' . chromePath . '" --incognito')
        catch as e {
            ShowLaunchError("Failed to launch Chrome", e)
            KeyWait "c"
            return
        }
        KeyWait "c"
    } else {
        KeyWait "c"
        guard := Wow64RedirectionGuard()
        try
            Run('"' . chromePath . '"')
        catch as e {
            ShowLaunchError("Failed to launch Chrome", e)
            return
        }
    }

    if WinWait("ahk_exe chrome.exe", , WINDOW_WAIT_TIMEOUT) {
        try WinMaximize("ahk_exe chrome.exe")
    } else
        ShowTransientToolTip("Chrome window not detected")
}
#MaxThreadsPerHotkey 1

!e:: {
    outlookPath := AppResolver.Get("Outlook", "", [
        "%AppData%\Microsoft\Windows\Start Menu\Programs\Chrome Apps\Outlook (PWA).lnk",
        "%StartMenuCommon%\Programs\Chrome Apps\Outlook (PWA).lnk"
    ])
    if (outlookPath != "" && FileExist(outlookPath)) {
        LaunchAndMaximize(outlookPath, "Outlook", WINDOW_WAIT_TIMEOUT, "Outlook")
    } else {
        try {
            RunApp("ms-outlook://", "", "Outlook")
        } catch {
            RunApp("https://outlook.live.com", "", "Outlook")
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
    HandleContextHotkey("g", "Git Bash", gitBashPath, "--cd-to-home", "--cd=")
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
        ShowTransientToolTip("Instagram")
        LaunchAndMaximize(instagramPath, "Instagram", WINDOW_WAIT_TIMEOUT, "Instagram")
    } else {
        try {
            RunApp("instagram://", "", "Instagram")
        } catch {
            RunApp("https://www.instagram.com", "", "Instagram")
        }
    }
}

!m:: RunApp("ms-windows-store:", "", "Microsoft Store")

!n:: RunApp("notepad.exe", "", "Notepad")

#MaxThreadsPerHotkey 1
!p:: {
    pressStart := A_TickCount
    KeyWait "p", "T" . (LONG_PRESS_THRESHOLD / 1000)
    pressDuration := A_TickCount - pressStart

    if (pressDuration >= LONG_PRESS_THRESHOLD) {
        dir := GetValidExplorerPath()
        if (dir != "") {
            ShowTransientToolTip("Admin PowerShell in Folder")
            try {
                LaunchAndPosition("*RunAs powershell.exe", dir)
            } catch as e {
                if (A_LastError != 1223)
                    ShowLaunchError("Failed to launch Admin PowerShell in Folder", e)
            }
        }
        KeyWait "p"
    } else {
        singlePress() {
            ShowTransientToolTip("PowerShell")
            try
                LaunchAndPosition("powershell.exe", USER_HOME)
            catch as e
                ShowLaunchError("Failed to launch PowerShell", e)
        }
        doublePress() {
            winClass := ""
            try winClass := WinGetClass("A")
            dir := ""
            if (winClass = "CabinetWClass" || winClass = "ExploreWClass")
                dir := GetExplorerPath()

            if (dir != "") {
                ShowTransientToolTip("PowerShell in Folder")
                try
                    LaunchAndPosition("powershell.exe", dir)
                catch as e
                    ShowLaunchError("Failed to launch PowerShell", e)
            } else {
                ShowTransientToolTip("Admin PowerShell")
                try
                    LaunchAndPosition("*RunAs powershell.exe", USER_HOME)
                catch as e {
                    if (A_LastError != 1223)
                        ShowLaunchError("Failed to launch Admin PowerShell", e)
                }
            }
        }
        DoublePressManager.Handle("PowerShell", singlePress, doublePress)
    }
}
#MaxThreadsPerHotkey 1

!q:: {
    isFirst := true
    while GetKeyState("q", "P") && GetKeyState("Alt", "P") {
        if !WinExist("A")
            break
        try {
            activeClass := WinGetClass("A")
            if IsProtectedWindowClass(activeClass) {
                ShowTransientToolTip("Nothing to close")
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

#MaxThreadsPerHotkey 1
!o:: {
    pressStart := A_TickCount
    KeyWait "o", "T" . (LONG_PRESS_THRESHOLD / 1000)
    pressDuration := A_TickCount - pressStart

    if (pressDuration >= LONG_PRESS_THRESHOLD) {
        dir := GetValidExplorerPath()
        if (dir != "") {
            ShowTransientToolTip("Admin CMD in Folder")
            try {
                LaunchAndPosition("*RunAs cmd.exe", dir)
            } catch as e {
                if (A_LastError != 1223)
                    ShowLaunchError("Failed to launch Admin CMD in Folder", e)
            }
        }
        KeyWait "o"
    } else {
        singlePress() {
            ShowTransientToolTip("CMD")
            try
                LaunchAndPosition("cmd.exe", USER_HOME)
            catch as e
                ShowLaunchError("Failed to launch CMD", e)
        }
        doublePress() {
            winClass := ""
            try winClass := WinGetClass("A")
            dir := ""
            if (winClass = "CabinetWClass" || winClass = "ExploreWClass")
                dir := GetExplorerPath()

            if (dir != "") {
                ShowTransientToolTip("CMD in Folder")
                try
                    LaunchAndPosition("cmd.exe", dir)
                catch as e
                    ShowLaunchError("Failed to launch CMD", e)
            } else {
                ShowTransientToolTip("Admin CMD")
                try
                    LaunchAndPosition("*RunAs cmd.exe", USER_HOME)
                catch as e {
                    if (A_LastError != 1223)
                        ShowLaunchError("Failed to launch Admin CMD", e)
                }
            }
        }
        DoublePressManager.Handle("CMD", singlePress, doublePress)
    }
}
#MaxThreadsPerHotkey 1

!s:: {
    slackPath := AppResolver.Get("Slack", "slack.exe", [
        "%LocalAppData%\slack\slack.exe",
        "%ProgramFiles%\Slack\slack.exe",
        "%StartMenuCommon%\Programs\Slack.lnk"
    ])
    if (slackPath != "" && (FileExist(slackPath) || SearchSystemPath(slackPath))) {
        LaunchAndMaximize(slackPath, "ahk_exe slack.exe", WINDOW_WAIT_TIMEOUT, "Slack")
    } else {
        RunApp("slack://", "", "Slack")
    }
}

!t:: {
    telegramPath := AppResolver.Get("Telegram", "", [
        "%AppData%\Microsoft\Windows\Start Menu\Programs\Chrome Apps\Telegram Web.lnk",
        "%StartMenuCommon%\Programs\Chrome Apps\Telegram Web.lnk"
    ])
    if (telegramPath != "" && FileExist(telegramPath)) {
        ShowTransientToolTip("Telegram")
        LaunchAndMaximize(telegramPath, "Telegram", WINDOW_WAIT_TIMEOUT)
    } else {
        RunApp("tg://", "", "Telegram")
    }
}

!u:: {
    singlePress() {
        ShowTransientToolTip("WSL")
        try
            LaunchAndPosition('wsl.exe --cd ~')
        catch as e
            ShowTransientToolTip("Failed to launch WSL`nIs WSL installed? " . e.Message)
    }
    doublePress() {
        dir := GetValidExplorerPath()
        if (dir != "") {
            ShowTransientToolTip("WSL")
            try
                LaunchAndPosition('wsl.exe --cd "' . dir . '"')
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
    if (vscodePath != "" && (FileExist(vscodePath) || SearchSystemPath(vscodePath))) {
        HandleContextHotkey("v", "VS Code", vscodePath)
    } else {
        RunApp("https://vscode.dev", "", "VS Code Web")
    }
}

!+v:: {
    static isPasting := false
    if (isPasting)
        return

    clipText := Trim(A_Clipboard, '`t`n`r "')
    if (clipText != "" && (RegExMatch(clipText, "i)^[A-Z]:") || InStr(clipText, "\"))) {
        isPasting := true
        wslPath := ConvertToWSLPath(clipText)
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

!w:: {
    whatsappPath := AppResolver.Get("WhatsApp", "", [
        "%AppData%\Microsoft\Windows\Start Menu\Programs\Chrome Apps\WhatsApp Web.lnk",
        "%StartMenuCommon%\Programs\Chrome Apps\WhatsApp Web.lnk",
        "%ProgramFiles%\WhatsApp.lnk",
        "%StartMenuCommon%\Programs\WhatsApp.lnk",
        "%StartMenu%\Programs\WhatsApp.lnk"
    ])
    if (whatsappPath != "" && (FileExist(whatsappPath) || InStr(whatsappPath, "\") = 0)) {
        ShowTransientToolTip("WhatsApp")
        LaunchAndMaximize(whatsappPath, "WhatsApp", WINDOW_WAIT_TIMEOUT, "WhatsApp")
    } else {
        RunApp("whatsapp://", "", "WhatsApp")
    }
}

!y:: {
    youtubePath := AppResolver.Get("YouTube", "", [
        "%AppData%\Microsoft\Windows\Start Menu\Programs\Chrome Apps\YouTube.lnk",
        "%StartMenuCommon%\Programs\Chrome Apps\YouTube.lnk"
    ])
    if (youtubePath != "" && FileExist(youtubePath)) {
        LaunchAndMaximize(youtubePath, "YouTube", WINDOW_WAIT_TIMEOUT, "YouTube")
    } else {
        RunApp("https://www.youtube.com", "", "YouTube")
    }
}

!z:: ExtractSelectedZip()

^+!Delete:: {
    result := MsgBox("Are you sure you want to permanently delete all items in the Recycle Bin?", "Empty Recycle Bin",
        4)
    if (result = "Yes") {
        try {
            DllCall("shell32\SHEmptyRecycleBin", "Ptr", 0, "Ptr", 0, "UInt", 0x1)
            ShowTransientToolTip("Recycle Bin emptied")
        } catch as e {
            ShowLaunchError("Failed to empty Recycle Bin", e)
        }
    }
}

^+q:: SetAudioOutput(AUDIO_DEVICE_1, 25, "Sony MDRX-50", AUDIO_MIC_1)
^+x:: SetAudioOutput(AUDIO_DEVICE_1, , "Black Shark V2", AUDIO_MIC_2)
^+y:: SetAudioOutput(AUDIO_DEVICE_2, , "Resound", AUDIO_MIC_1)
^+z:: SetAudioOutput(AUDIO_DEVICE_3, , "Heat", AUDIO_MIC_1)
