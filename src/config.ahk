; ====================[ Configuration & Global State ]====================
#Requires AutoHotkey v2.0.26

GetEnvInt(varName, defaultValue) {
    val := EnvGet(varName)
    return (val != "" && IsInteger(val)) ? Integer(val) : defaultValue
}

GetEnvString(varName, defaultValue) {
    val := EnvGet(varName)
    return (val != "") ? val : defaultValue
}

global USER_HOME := EnvGet("USERPROFILE")
global DOUBLE_PRESS_DELAY := GetEnvInt("AHK_DOUBLE_PRESS_DELAY", 400)
global LOGS_DIR := GetEnvString("AHK_LOGS_DIR", A_ScriptDir . "\logs")
global LONG_PRESS_THRESHOLD := GetEnvInt("AHK_LONG_PRESS_THRESHOLD", 600)
global ScriptModTime := ""
global TOOLTIP_DURATION_MS := GetEnvInt("AHK_TOOLTIP_DURATION_MS", 2000)
global WINDOW_WAIT_TIMEOUT := GetEnvInt("AHK_WINDOW_WAIT_TIMEOUT", 5)
global WATCHDOG_INTERVAL_MS := GetEnvInt("AHK_WATCHDOG_INTERVAL_MS", 30000)

; Audio Output & Input Device Configuration
global AUDIO_DEVICE_1 := GetEnvString("AHK_AUDIO_DEVICE_1", "Surround")
global AUDIO_DEVICE_2 := GetEnvString("AHK_AUDIO_DEVICE_2", "Resound")
global AUDIO_DEVICE_3 := GetEnvString("AHK_AUDIO_DEVICE_3", "Speakers (Realtek")
global AUDIO_MIC_1 := GetEnvString("AHK_AUDIO_MIC_1", "Microphone (Realtek(R) Audio)")
global AUDIO_MIC_2 := GetEnvString("AHK_AUDIO_MIC_2", "Razer")
global AUDIO_MIC_3 := GetEnvString("AHK_AUDIO_MIC_3", "Array")

global DEVICE_VOLUME_HISTORY := Map()
global LAST_DEVICE := ""

try {
    initVol := SoundGetVolume()
    if (Round(initVol) = 25) {
        LAST_DEVICE := "Sony MDRX-50"
        DEVICE_VOLUME_HISTORY["Sony MDRX-50"] := 25
    } else {
        LAST_DEVICE := "Black Shark V2"
        DEVICE_VOLUME_HISTORY["Black Shark V2"] := initVol
    }
}
