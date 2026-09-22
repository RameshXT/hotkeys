#Requires AutoHotkey v2.0.26

class AudioActions {
    static SwitchToSony() {
        AudioEndpoint.SwitchOutput(Config.AUDIO_DEVICE_1, 25, "Sony MDRX-50", Config.AUDIO_MIC_1)
    }

    static SwitchToBlackShark() {
        AudioEndpoint.SwitchOutput(Config.AUDIO_DEVICE_1, , "Black Shark V2", Config.AUDIO_MIC_2)
    }

    static SwitchToResound() {
        AudioEndpoint.SwitchOutput(Config.AUDIO_DEVICE_2, , "Resound", Config.AUDIO_MIC_1)
    }

    static SwitchToHeat() {
        AudioEndpoint.SwitchOutput(Config.AUDIO_DEVICE_3, , "Heat", Config.AUDIO_MIC_1)
    }
}
