#Requires AutoHotkey v2.0.26

class ProcessWatchdog {
    static targets := Map()
    static restartHistory := Map()
    static maxRestarts := 3
    static windowMs := 300000

    static Register(exeName, friendlyName, launchFn) {
        this.targets[exeName] := { name: friendlyName, launcher: launchFn, wasRunning: false, hProcess: 0, pid: 0 }
        this.restartHistory[exeName] := []
    }

    static Poll() {
        now := A_TickCount
        for exeName, info in this.targets {
            isRunning := false

            if (info.hProcess != 0) {
                waitRes := DllCall("WaitForSingleObject", "ptr", info.hProcess, "uint", 0, "uint")
                if (waitRes = 258) {
                    isRunning := true
                } else {
                    DllCall("CloseHandle", "ptr", info.hProcess)
                    info.hProcess := 0
                    info.pid := 0
                }
            }

            if (!isRunning) {
                newPid := ProcessExist(exeName)
                if (newPid != 0) {
                    isRunning := true
                    info.pid := newPid
                    static PROCESS_QUERY_LIMITED_INFORMATION := 0x1000
                    static SYNCHRONIZE := 0x00100000
                    hProc := DllCall("OpenProcess", "uint", PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE, "int", false, "uint", newPid, "ptr")
                    if (hProc != 0)
                        info.hProcess := hProc
                }
            }

            if (isRunning) {
                info.wasRunning := true
            } else if (info.wasRunning) {
                history := this.restartHistory[exeName]
                recentRestarts := []
                for timestamp in history {
                    if (now - timestamp < this.windowMs)
                        recentRestarts.Push(timestamp)
                }
                this.restartHistory[exeName] := recentRestarts

                if (recentRestarts.Length >= this.maxRestarts) {
                    NotificationManager.Toast("Process Watchdog", info.name . " crashed repeatedly. Auto-restart suspended for safety.", 2)
                    info.wasRunning := false
                    continue
                }

                recentRestarts.Push(now)
                this.restartHistory[exeName] := recentRestarts

                try {
                    info.launcher()
                    NotificationManager.ShowTransient(info.name . " recovered")
                } catch as e {
                    ErrorHandler.HandleLaunchError("Watchdog Recovery: " . info.name, e)
                }

                info.wasRunning := false
            }
        }
    }
}
