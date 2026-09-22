#Requires AutoHotkey v2.0.26

class AudioEndpoint {
    static volumeHistory := Map()
    static lastDevice := ""

    static Init() {
        try {
            initVol := SoundGetVolume()
            if (Round(initVol) = 25) {
                this.lastDevice := "Sony MDRX-50"
                this.volumeHistory["Sony MDRX-50"] := 25
            } else {
                this.lastDevice := "Black Shark V2"
                this.volumeHistory["Black Shark V2"] := initVol
            }
        } catch {
        }
    }

    static SwitchOutput(deviceNameSubstr, targetVolume := "", friendlyNameOverride := "", micNameSubstr := "") {
        deviceEnumerator := 0
        devicesCollection := 0
        try {
            deviceEnumerator := ComObject("{BCDE0395-E52F-467C-8E3D-C4579291692E}",
                "{A95664D2-9614-4F35-A746-DE8DB63617E6}")

            ComCall(3, deviceEnumerator, "int", 0, "uint", 1, "ptr*", &devicesCollection := 0)

            count := 0
            ComCall(3, devicesCollection, "uint*", &count)

            targetId := ""
            targetName := ""
            defaultFriendlyName := ""

            defaultId := ""
            defaultDevice := 0
            defaultIdPtr := 0
            try {
                ComCall(4, deviceEnumerator, "int", 0, "int", 0, "ptr*", &defaultDevice := 0)
                if (defaultDevice) {
                    ComCall(5, defaultDevice, "ptr*", &defaultIdPtr)
                    if (defaultIdPtr) {
                        defaultId := StrGet(defaultIdPtr, "UTF-16")
                        DllCall("Ole32\CoTaskMemFree", "ptr", defaultIdPtr)
                        defaultIdPtr := 0
                    }
                }
            } finally {
                if (defaultIdPtr)
                    DllCall("Ole32\CoTaskMemFree", "ptr", defaultIdPtr)
                if (defaultDevice)
                    ObjRelease(defaultDevice)
            }

            loop count {
                device := 0
                propertyStore := 0
                idPtr := 0
                try {
                    ComCall(4, devicesCollection, "uint", A_Index - 1, "ptr*", &device := 0)
                    if (!device)
                        continue

                    ComCall(5, device, "ptr*", &idPtr)
                    id := (idPtr) ? StrGet(idPtr, "UTF-16") : ""
                    if (idPtr) {
                        DllCall("Ole32\CoTaskMemFree", "ptr", idPtr)
                        idPtr := 0
                    }

                    ComCall(4, device, "uint", 0, "ptr*", &propertyStore := 0)
                    if (!propertyStore)
                        continue

                    keyGUID := Buffer(16)
                    DllCall("Ole32\CLSIDFromString", "str", "{A45C254E-DF1C-4EFD-8020-67D146A850E0}", "ptr", keyGUID)
                    propKey := Buffer(20)
                    DllCall("RtlMoveMemory", "ptr", propKey, "ptr", keyGUID, "ptr", 16)
                    NumPut("uint", 14, propKey, 16)

                    propVariant := Buffer(24, 0)
                    ComCall(5, propertyStore, "ptr", propKey, "ptr", propVariant)

                    friendlyName := ""
                    if (NumGet(propVariant, 0, "ushort") = 31) {
                        namePtr := NumGet(propVariant, 8, "ptr")
                        friendlyName := StrGet(namePtr, "UTF-16")
                    }
                    DllCall("Ole32\PropVariantClear", "ptr", propVariant)

                    if (InStr(friendlyName, deviceNameSubstr)) {
                        targetId := id
                        targetName := friendlyName
                    }
                    if (id = defaultId) {
                        defaultFriendlyName := friendlyName
                    }
                } finally {
                    if (idPtr)
                        DllCall("Ole32\CoTaskMemFree", "ptr", idPtr)
                    if (propertyStore)
                        ObjRelease(propertyStore)
                    if (device)
                        ObjRelease(device)
                }
            }

            if (targetId = "") {
                NotificationManager.ShowTransient("Audio device not found: " . deviceNameSubstr)
                return
            }

            if (this.lastDevice != "" && defaultFriendlyName != "") {
                try {
                    this.volumeHistory[this.lastDevice] := SoundGetVolume("", defaultFriendlyName)
                }
            }

            IPolicyConfig := ComObject("{870AF99C-171D-4F9E-AF0D-E63DF40C2BC9}", "{F8679F50-850A-41CF-9C72-430F290290C8}")
            if (targetId != defaultId) {
                try {
                    ComCall(13, IPolicyConfig, "Str", targetId, "UInt", 0)
                    ComCall(13, IPolicyConfig, "Str", targetId, "UInt", 1)
                    ComCall(13, IPolicyConfig, "Str", targetId, "UInt", 2)
                } catch as e {
                    NotificationManager.ShowTransient("Could not switch default audio device")
                    ErrorHandler.HandleLaunchError("Audio device switch failed", e)
                    return
                }
            }

            dispName := (friendlyNameOverride != "") ? friendlyNameOverride : targetName
            NotificationManager.ShowTransient("Active: " . dispName)

            if (targetVolume != "") {
                SoundSetVolume(targetVolume, , targetName)
            } else if (this.volumeHistory.Has(friendlyNameOverride)) {
                SoundSetVolume(this.volumeHistory[friendlyNameOverride], , targetName)
            }
            this.lastDevice := friendlyNameOverride

            if (micNameSubstr != "") {
                micsCollection := 0
                ComCall(3, deviceEnumerator, "int", 1, "uint", 1, "ptr*", &micsCollection := 0)
                try {
                    micCount := 0
                    ComCall(3, micsCollection, "uint*", &micCount)

                    micId := ""
                    loop micCount {
                        device := 0
                        propertyStore := 0
                        idPtr := 0
                        try {
                            ComCall(4, micsCollection, "uint", A_Index - 1, "ptr*", &device := 0)
                            if (!device)
                                continue

                            ComCall(5, device, "ptr*", &idPtr)
                            id := (idPtr) ? StrGet(idPtr, "UTF-16") : ""
                            if (idPtr) {
                                DllCall("Ole32\CoTaskMemFree", "ptr", idPtr)
                                idPtr := 0
                            }

                            ComCall(4, device, "uint", 0, "ptr*", &propertyStore := 0)
                            if (!propertyStore)
                                continue

                            keyGUID := Buffer(16)
                            DllCall("Ole32\CLSIDFromString", "str", "{A45C254E-DF1C-4EFD-8020-67D146A850E0}", "ptr", keyGUID)
                            propKey := Buffer(20)
                            DllCall("RtlMoveMemory", "ptr", propKey, "ptr", keyGUID, "ptr", 16)
                            NumPut("uint", 14, propKey, 16)

                            propVariant := Buffer(24, 0)
                            ComCall(5, propertyStore, "ptr", propKey, "ptr", propVariant)

                            friendlyName := ""
                            if (NumGet(propVariant, 0, "ushort") = 31) {
                                namePtr := NumGet(propVariant, 8, "ptr")
                                friendlyName := StrGet(namePtr, "UTF-16")
                            }
                            DllCall("Ole32\PropVariantClear", "ptr", propVariant)

                            if (InStr(friendlyName, micNameSubstr)) {
                                micId := id
                            }
                        } finally {
                            if (idPtr)
                                DllCall("Ole32\CoTaskMemFree", "ptr", idPtr)
                            if (propertyStore)
                                ObjRelease(propertyStore)
                            if (device)
                                ObjRelease(device)
                        }

                        if (micId != "")
                            break
                    }

                    if (micId != "") {
                        defaultMicId := ""
                        defaultMicDevice := 0
                        defaultMicIdPtr := 0
                        try {
                            ComCall(4, deviceEnumerator, "int", 1, "int", 0, "ptr*", &defaultMicDevice := 0)
                            if (defaultMicDevice) {
                                ComCall(5, defaultMicDevice, "ptr*", &defaultMicIdPtr)
                                if (defaultMicIdPtr) {
                                    defaultMicId := StrGet(defaultMicIdPtr, "UTF-16")
                                    DllCall("Ole32\CoTaskMemFree", "ptr", defaultMicIdPtr)
                                    defaultMicIdPtr := 0
                                }
                            }
                        } finally {
                            if (defaultMicIdPtr)
                                DllCall("Ole32\CoTaskMemFree", "ptr", defaultMicIdPtr)
                            if (defaultMicDevice)
                                ObjRelease(defaultMicDevice)
                        }

                        if (micId != defaultMicId) {
                            try {
                                ComCall(13, IPolicyConfig, "Str", micId, "UInt", 0)
                                ComCall(13, IPolicyConfig, "Str", micId, "UInt", 1)
                                ComCall(13, IPolicyConfig, "Str", micId, "UInt", 2)
                            } catch as e {
                                NotificationManager.ShowTransient("Could not switch default microphone")
                                ErrorHandler.HandleLaunchError("Microphone switch failed", e)
                            }
                        }
                    }
                } finally {
                    if (micsCollection)
                        ObjRelease(micsCollection)
                }
            }
        } catch as e {
            ErrorHandler.HandleLaunchError("Audio Switch Error", e)
        } finally {
            if (devicesCollection)
                ObjRelease(devicesCollection)
            deviceEnumerator := 0
        }
    }
}

SetAudioOutput(deviceNameSubstr, targetVolume := "", friendlyNameOverride := "", micNameSubstr := "") {
    AudioEndpoint.SwitchOutput(deviceNameSubstr, targetVolume, friendlyNameOverride, micNameSubstr)
}
