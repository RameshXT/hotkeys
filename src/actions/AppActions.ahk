#Requires AutoHotkey v2.0.26

class AppActions {
    static Run(path, args := "", name := "", workingDir := "") {
        if (name != "")
            NotificationManager.ShowTransient(name)
        try {
            if InStr(path, "://") || (RegExMatch(path, "^[a-zA-Z][a-zA-Z0-9+.-]+:") && !RegExMatch(path, "^[a-zA-Z]:[\\/]")) {
                Run(path)
            } else {
                if (InStr(path, "\") && !FileExist(path)) {
                    TrayTip(name != "" ? name : path, "Application not found", 2)
                    return
                }
                if (!InStr(path, "\") && !FileExist(path) && !Win32.SearchSystemPath(path)) {
                    TrayTip(name != "" ? name : path, "Application not found", 2)
                    return
                }
                Win32.SmartRun(path, args, workingDir)
            }
        } catch as e {
            ErrorHandler.HandleLaunchError("Launch Error", e)
        }
    }

    static RunAndNotify(path, args, name) {
        NotificationManager.ShowTransient(name)
        this.Run(path, args, name)
    }

    static LaunchChrome(pressDuration) {
        chromePath := AppResolver.Get("Chrome", "chrome.exe")
        if (chromePath = "chrome.exe" && !FileExist(chromePath) && !Win32.SearchSystemPath(chromePath)) {
            NotificationManager.ShowTransient("Opening Default Browser")
            try {
                if (pressDuration >= Config.LONG_PRESS_THRESHOLD)
                    Run(Win32.ResolveNativePath("cmd.exe") . " /c start microsoft-edge:-private")
                else
                    Run(Win32.ResolveNativePath("cmd.exe") . " /c start https://www.google.com")
            } catch as e {
                ErrorHandler.HandleLaunchError("Failed to launch Browser", e)
            }
            KeyWait "c", "T2"
            return
        }

        if (pressDuration >= Config.LONG_PRESS_THRESHOLD) {
            guard := Wow64RedirectionGuard()
            try {
                Run('"' . chromePath . '" --incognito')
            } catch as e {
                ErrorHandler.HandleLaunchError("Failed to launch Chrome", e)
                KeyWait "c"
                return
            }
            KeyWait "c"
        } else {
            KeyWait "c"
            guard := Wow64RedirectionGuard()
            try {
                Run('"' . chromePath . '"')
            } catch as e {
                ErrorHandler.HandleLaunchError("Failed to launch Chrome", e)
                return
            }
        }

        if WinWait("ahk_exe chrome.exe", , Config.WINDOW_WAIT_TIMEOUT) {
            try WinMaximize("ahk_exe chrome.exe")
        } else {
            NotificationManager.ShowTransient("Chrome window not detected")
        }
    }

    static LaunchMicrosoftStore() {
        NotificationManager.ShowTransient("Microsoft Store")
        try {
            Run("ms-windows-store:")
        } catch {
            try {
                Run("explorer.exe shell:AppsFolder\Microsoft.WindowsStore_8wekyb3d8bbwe!App")
            } catch as e {
                ErrorHandler.HandleLaunchError("Microsoft Store", e)
            }
        }
    }

    static LaunchRazer71() {
        razer71Path := AppResolver.Get("Razer71", "rzappengine.exe", [
            "%ProgramFiles%\Razer\RzAppEngine\rzappengine.exe",
            "%StartMenuCommon%\Programs\Razer\7.1 Surround Sound.lnk"
        ])
        SplitPath razer71Path, , &razer71Dir
        this.Run(razer71Path, "--url-params=apps=7.1-surround-sound --disable-background-timer-throttling",
            "7.1 Surround Sound", razer71Dir)
    }
}

RunApp(path, args := "", name := "", dir := "") => AppActions.Run(path, args, name, dir)
RunAppAndNotify(path, args, name) => AppActions.RunAndNotify(path, args, name)
LaunchMicrosoftStore() => AppActions.LaunchMicrosoftStore()
LaunchRazer71() => AppActions.LaunchRazer71()
