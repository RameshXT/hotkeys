#Requires AutoHotkey v2.0.26

class NotificationManager {
    static ShowTransient(message, durationMs := "") {
        if (durationMs = "")
            durationMs := Config.TOOLTIP_DURATION_MS

        ToolTip(message)
        SetTimer(() => ToolTip(), -durationMs)
    }

    static Clear() {
        ToolTip()
    }

    static Toast(title, message, icon := 1) {
        TrayTip(message, title, icon)
    }
}

ShowTransientToolTip(message, durationMs := "") {
    NotificationManager.ShowTransient(message, durationMs)
}

RemoveToolTip() {
    NotificationManager.Clear()
}
