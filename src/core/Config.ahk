#Requires AutoHotkey v2.0.26

class Config {
    static DOUBLE_PRESS_DELAY := 400
    static LONG_PRESS_THRESHOLD := 600
    static TOOLTIP_DURATION_MS := 2000
    static WINDOW_WAIT_TIMEOUT := 5
    static WATCHDOG_INTERVAL_MS := 30000
    static WATCHDOG_ENABLED := true
    static LOGS_DIR := A_ScriptDir . "\logs"

    static AUDIO_DEVICE_1 := "Surround"
    static AUDIO_DEVICE_2 := "Resound"
    static AUDIO_DEVICE_3 := "Speakers (Realtek"
    static AUDIO_MIC_1 := "Microphone (Realtek(R) Audio)"
    static AUDIO_MIC_2 := "Razer"
    static AUDIO_MIC_3 := "Array"

    static Init() {
        this.DOUBLE_PRESS_DELAY := this.GetEnvInt("AHK_DOUBLE_PRESS_DELAY", 400)
        this.LONG_PRESS_THRESHOLD := this.GetEnvInt("AHK_LONG_PRESS_THRESHOLD", 600)
        this.TOOLTIP_DURATION_MS := this.GetEnvInt("AHK_TOOLTIP_DURATION_MS", 2000)
        this.WINDOW_WAIT_TIMEOUT := this.GetEnvInt("AHK_WINDOW_WAIT_TIMEOUT", 5)
        this.WATCHDOG_INTERVAL_MS := this.GetEnvInt("AHK_WATCHDOG_INTERVAL_MS", 30000)
        this.WATCHDOG_ENABLED := this.GetEnvInt("AHK_WATCHDOG_ENABLED", 1) ? true : false
        this.LOGS_DIR := this.GetEnvString("AHK_LOGS_DIR", A_ScriptDir . "\logs")

        this.AUDIO_DEVICE_1 := this.GetEnvString("AHK_AUDIO_DEVICE_1", "Surround")
        this.AUDIO_DEVICE_2 := this.GetEnvString("AHK_AUDIO_DEVICE_2", "Resound")
        this.AUDIO_DEVICE_3 := this.GetEnvString("AHK_AUDIO_DEVICE_3", "Speakers (Realtek")
        this.AUDIO_MIC_1 := this.GetEnvString("AHK_AUDIO_MIC_1", "Microphone (Realtek(R) Audio)")
        this.AUDIO_MIC_2 := this.GetEnvString("AHK_AUDIO_MIC_2", "Razer")
        this.AUDIO_MIC_3 := this.GetEnvString("AHK_AUDIO_MIC_3", "Array")
    }

    static GetEnvInt(varName, defaultValue) {
        val := EnvGet(varName)
        return (val != "" && IsInteger(val)) ? Integer(val) : defaultValue
    }

    static GetEnvString(varName, defaultValue) {
        val := EnvGet(varName)
        return (val != "") ? val : defaultValue
    }
}
