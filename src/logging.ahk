; ====================[ Logging & Error Reporting ]====================
#Requires AutoHotkey v2.0.26

WriteLogEntry(entry) {
    OutputDebug(entry)
    try {
        if !DirExist(LOGS_DIR)
            DirCreate(LOGS_DIR)

        logFile := LOGS_DIR . "\hotkey_errors.log"
        maxLogSize := 5242880 ; 5 MB
        if FileExist(logFile) && FileGetSize(logFile) >= maxLogSize {
            oldLog := LOGS_DIR . "\hotkey_errors.log.old"
            if FileExist(oldLog)
                FileDelete(oldLog)
            FileMove(logFile, oldLog, 1)
        }

        FileAppend(entry, logFile, "UTF-8")
    } catch as primaryErr {
        try {
            tempLog := A_Temp . "\xtkeys_hotkey_errors.log"
            FileAppend(entry, tempLog, "UTF-8")
        } catch as fallbackErr {
            TrayTip("Log write failed: " . primaryErr.Message, "xtkeys Logging Error", "Icon!")
        }
    }
}

GlobalErrorHandler(thrown, mode) {
    try {
        timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
        entry := "--------------------------------------------------------------------------------`n`n"
        entry .= "  [" . timestamp . "] UNHANDLED ERROR (" . mode . ")`n"
        entry .= "  Message: " . thrown.Message . "`n"
        entry .= "  What:    " . thrown.What . "`n"
        entry .= "  File:    " . thrown.File . "`n"
        entry .= "  Line:    " . thrown.Line . "`n"
        if (thrown.Extra != "")
            entry .= "  Extra:   " . thrown.Extra . "`n"
        if (thrown.Stack != "") {
            entry .= "  Stack:`n"
            for line in StrSplit(thrown.Stack, "`n", "`r") {
                if (line != "")
                    entry .= "    " . line . "`n"
            }
        }
        entry .= "`n--------------------------------------------------------------------------------`n`n"

        WriteLogEntry(entry)
        TrayTip(thrown.Message, "Hotkey Error Logged", 2)
    }
    return -1
}

ShowLaunchError(prefix, err) {
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

    timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
    logLine := "[" . timestamp . "] " . prefix . ": " . msg . "`n"
    WriteLogEntry(logLine)

    ShowTransientToolTip(prefix . "`n" . friendlyMsg, 3000)
}

ShowTransientToolTip(message, durationMs := "") {
    if (durationMs = "")
        durationMs := TOOLTIP_DURATION_MS
    ToolTip(message)
    SetTimer RemoveToolTip, -durationMs
}

RemoveToolTip() {
    ToolTip()
}
