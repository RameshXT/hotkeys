#Requires AutoHotkey v2.0.26

class Logger {
    static MAX_LOG_SIZE := 5242880 ; 5 MB

    static Log(entry) {
        OutputDebug(entry)
        try {
            logsDir := Config.LOGS_DIR
            if !DirExist(logsDir)
                DirCreate(logsDir)

            logFile := logsDir . "\hotkey_errors.log"
            if FileExist(logFile) && FileGetSize(logFile) >= this.MAX_LOG_SIZE {
                oldLog := logsDir . "\hotkey_errors.log.old"
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

    static FormatError(prefix, err) {
        timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
        msg := (err is Error) ? err.Message : String(err)
        
        entry := "--------------------------------------------------------------------------------`n`n"
        entry .= "  [" . timestamp . "] " . prefix . "`n"
        entry .= "  Message: " . msg . "`n"
        if (err is Error) {
            entry .= "  File:    " . err.File . "`n"
            entry .= "  Line:    " . err.Line . "`n"
            entry .= "  What:    " . err.What . "`n"
            if (err.Extra != "")
                entry .= "  Extra:   " . err.Extra . "`n"
            if (err.Stack != "") {
                entry .= "  Stack:`n"
                for line in StrSplit(err.Stack, "`n", "`r") {
                    if (line != "")
                        entry .= "    " . line . "`n"
                }
            }
        }
        entry .= "`n--------------------------------------------------------------------------------`n`n"
        return entry
    }
}
