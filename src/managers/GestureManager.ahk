#Requires AutoHotkey v2.0.26

class GestureManager {
    static lastPresses := Map()
    static timers := Map()

    static HandleDoublePress(key, singlePressCallback := "", doublePressCallback := "") {
        now := A_TickCount
        last := this.lastPresses.Has(key) ? this.lastPresses[key] : 0

        if (now - last < Config.DOUBLE_PRESS_DELAY) {
            this.lastPresses[key] := 0
            if this.timers.Has(key) {
                SetTimer this.timers[key], 0
                this.timers.Delete(key)
            }
            if (doublePressCallback != "")
                doublePressCallback()
        } else {
            this.lastPresses[key] := now
            if (singlePressCallback != "") {
                timerFn := () => this.ExecuteAndClear(key, singlePressCallback)
                this.timers[key] := timerFn
                SetTimer timerFn, -Config.DOUBLE_PRESS_DELAY
            }
        }
    }

    static ExecuteAndClear(key, callback) {
        if this.timers.Has(key)
            this.timers.Delete(key)
        callback()
    }

    static HandleContextHotkey(key, name, path, sArgs := "", dPre := "") {
        now := A_TickCount
        last := this.lastPresses.Has(key) ? this.lastPresses[key] : 0

        if (now - last < Config.DOUBLE_PRESS_DELAY) {
            this.lastPresses[key] := 0
            if this.timers.Has(key) {
                SetTimer this.timers[key], 0
                this.timers.Delete(key)
            }

            dir := ShellExplorer.GetValidExplorerPath()
            if (dir != "") {
                NotificationManager.ShowTransient(name)
                cleanDir := (SubStr(dir, -1) == "\") ? (dir . "\") : dir
                AppActions.Run(path, dPre . '"' . cleanDir . '"')
            }
        } else {
            this.lastPresses[key] := now
            timerFn := () => (this.timers.Delete(key), AppActions.RunAndNotify(path, sArgs, name))
            this.timers[key] := timerFn
            SetTimer timerFn, -Config.DOUBLE_PRESS_DELAY
        }
    }
}

class DoublePressManager {
    static Handle(key, singlePressCallback := "", doublePressCallback := "") {
        GestureManager.HandleDoublePress(key, singlePressCallback, doublePressCallback)
    }
}

HandleContextHotkey(key, name, path, sArgs := "", dPre := "") {
    GestureManager.HandleContextHotkey(key, name, path, sArgs, dPre)
}
