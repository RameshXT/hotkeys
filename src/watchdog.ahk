; ====================[ Background Process Watchdog & Self-Healing ]====================
#Requires AutoHotkey v2.0.26

class ProcessWatchdog {
    static registered := Map()
    static restartHistory := Map()
    static procHandles := Map()
    static maxRestarts := 5
    static windowMs := 300000

    static Register(exeName, friendlyName, launchCallback) {
        this.registered[exeName] := {
            name: friendlyName,
            launcher: launchCallback,
            wasRunning: false
        }
        if !this.restartHistory.Has(exeName)
            this.restartHistory[exeName] := []
    }

    static Poll() {
        static PROCESS_SYNCHRONIZE := 0x00100000
        now := A_TickCount

        for exeName, info in this.registered {
            isRunning := false
            hProc := this.procHandles.Has(exeName) ? this.procHandles[exeName] : 0

            if (hProc) {
                waitResult := DllCall("WaitForSingleObject", "ptr", hProc, "uint", 0, "uint")
                if (waitResult = 258) {
                    isRunning := true
                } else {
                    DllCall("CloseHandle", "ptr", hProc)
                    this.procHandles.Delete(exeName)
                    hProc := 0
                }
            }

            if (!isRunning) {
                pid := ProcessExist(exeName)
                if (pid) {
                    isRunning := true
                    newHandle := DllCall("OpenProcess", "uint", PROCESS_SYNCHRONIZE, "int", 0, "uint", pid, "ptr")
                    if (newHandle) {
                        this.procHandles[exeName] := newHandle
                    }
                }
            }

            if (isRunning) {
                info.wasRunning := true
            } else if (info.wasRunning) {
                info.wasRunning := false

                recent := []
                for t in this.restartHistory[exeName] {
                    if (now - t < this.windowMs)
                        recent.Push(t)
                }
                this.restartHistory[exeName] := recent

                if (recent.Length >= this.maxRestarts) {
                    this.LogWatchdogEvent("CIRCUIT BREAKER TRIPPED", info.name,
                        "Process crashed " . recent.Length . " times within 5 minutes. Auto-recovery suspended.")
                    TrayTip("Auto-recovery suspended (repeated crashes)", info.name, 2)
                    continue
                }

                recent.Push(now)
                this.restartHistory[exeName] := recent

                this.LogWatchdogEvent("PROCESS AUTO-HEALED", info.name,
                    "Process terminated unexpectedly. Automatically respawned (attempt " . recent.Length . "/" . this.maxRestarts . ").")
                ShowTransientToolTip(info.name . " recovered")

                try {
                    info.launcher()
                } catch as err {
                    ShowLaunchError("Watchdog Recovery Failed: " . info.name, err)
                }
            }
        }
    }

    static LogWatchdogEvent(eventTitle, processName, details) {
        timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
        entry := "--------------------------------------------------------------------------------`n`n"
        entry .= "  [" . timestamp . "] " . eventTitle . "`n"
        entry .= "  Target:  " . processName . "`n"
        entry .= "  Details: " . details . "`n`n"
        entry .= "--------------------------------------------------------------------------------`n`n"

        WriteLogEntry(entry)
    }
}
