#Requires AutoHotkey v2.0.26
#Include "../core/Config.ahk"
#Include "../core/ToolTip.ahk"
#Include "../core/ErrorHandler.ahk"
#Include "../interop/Win32.ahk"
#Include "../interop/Explorer.ahk"
#Include "../managers/AppResolver.ahk"
#Include "../managers/GestureManager.ahk"
#Include "../managers/WindowManager.ahk"
#Include "../actions/AppActions.ahk"
#Include "../actions/AudioActions.ahk"
#Include "../actions/UtilityActions.ahk"

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
    wtPath := EnvGet("LOCALAPPDATA") "\Microsoft\WindowsApps\wt.exe"

    now := A_TickCount
    last := GestureManager.lastPresses.Has("g") ? GestureManager.lastPresses["g"] : 0

    if (now - last < Config.DOUBLE_PRESS_DELAY) {
        GestureManager.lastPresses["g"] := 0
        if GestureManager.timers.Has("g") {
            SetTimer GestureManager.timers["g"], 0
            GestureManager.timers.Delete("g")
        }
        dir := ShellExplorer.GetValidExplorerPath()
        if (dir != "") {
            NotificationManager.ShowTransient("Git Bash")
            wtDir := StrReplace(dir, ";", "\;")
            if (SubStr(wtDir, -1) == "\")
                wtDir .= "."
            if FileExist(wtPath) {
                try {
                    Run('"' . wtPath . '" -w new -p "Git Bash" -d "' . wtDir . '"')
                } catch as e {
                    NotificationManager.ShowTransient("WT failed, using Git Bash")
                    AppActions.Run(gitBashPath, '--cd="' . dir . '"')
                }
            } else {
                NotificationManager.ShowTransient("wt.exe not found, using Git Bash")
                AppActions.Run(gitBashPath, '--cd="' . dir . '"')
            }
        }
    } else {
        GestureManager.lastPresses["g"] := now
        _wtPath := wtPath
        _gitBashPath := gitBashPath
        timerFn := () => (
            GestureManager.timers.Delete("g"),
            NotificationManager.ShowTransient("Git Bash"),
            FileExist(_wtPath)
                ? (Run('"' . _wtPath . '" -w new -p "Git Bash"'), 0)
                : (NotificationManager.ShowTransient("wt.exe not found, using Git Bash"),
                   AppActions.Run(_gitBashPath, "--cd-to-home"), 0)
        )
        GestureManager.timers["g"] := timerFn
        SetTimer timerFn, -Config.DOUBLE_PRESS_DELAY
    }
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
