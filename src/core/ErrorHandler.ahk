#Requires AutoHotkey v2.0.26

class ErrorHandler {
    static Init() {
        OnError((thrown, mode) => this.OnGlobalError(thrown, mode))
    }

    static OnGlobalError(thrown, mode) {
        try {
            entry := Logger.FormatError("UNHANDLED ERROR (" . mode . ")", thrown)
            Logger.Log(entry)
            TrayTip(thrown.Message, "Hotkey Error Logged", 2)
        }
        return -1
    }

    static HandleLaunchError(prefix, err) {
        msg := (err is Error) ? err.Message : String(err)

        friendlyMsg := msg
        if InStr(msg, "Failed attempt to launch program") {
            friendlyMsg := "App not installed or shortcut is broken."
        } else if InStr(msg, "elevation") || InStr(msg, "Requires elevation") || InStr(msg, "740") {
            friendlyMsg := "Requires Administrator rights to open."
        } else if InStr(msg, "access is denied") || InStr(msg, "5") {
            friendlyMsg := "Access denied. Missing permission."
        } else if InStr(msg, "cannot find the file specified") || InStr(msg, "2") {
            friendlyMsg := "Application file not found."
        }

        TrayTip(friendlyMsg, prefix, 2)

        try {
            entry := Logger.FormatError(prefix, err)
            Logger.Log(entry)
        }
    }
}

ShowLaunchError(prefix, err) {
    ErrorHandler.HandleLaunchError(prefix, err)
}
