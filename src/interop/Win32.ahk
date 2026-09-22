#Requires AutoHotkey v2.0.26

class Wow64RedirectionGuard {
    oldRedir := 0
    disabled := false

    __New() {
        if (A_Is64bitOS && A_PtrSize = 4) {
            oldVal := 0
            if DllCall("Wow64DisableWow64FsRedirection", "Ptr*", &oldVal) {
                this.oldRedir := oldVal
                this.disabled := true
            }
        }
    }

    __Delete() {
        if (this.disabled) {
            DllCall("Wow64RevertWow64FsRedirection", "Ptr", this.oldRedir)
            this.disabled := false
        }
    }
}

class Win32 {
    static ResolveNativePath(cmd) {
        if (A_Is64bitOS && A_PtrSize = 4) {
            if (SubStr(cmd, 1, 7) = "*RunAs ") {
                prefix := "*RunAs "
                actualCmd := SubStr(cmd, 8)
            } else {
                prefix := ""
                actualCmd := cmd
            }

            if (actualCmd = "cmd.exe" || SubStr(actualCmd, 1, 8) = "cmd.exe ") {
                return prefix . "C:\Windows\Sysnative\" . actualCmd
            }
            if (actualCmd = "powershell.exe" || SubStr(actualCmd, 1, 15) = "powershell.exe ") {
                return prefix . "C:\Windows\Sysnative\WindowsPowerShell\v1.0\" . actualCmd
            }
        }
        return cmd
    }

    static SearchSystemPath(exeName) {
        if (exeName = "")
            return false
        if FileExist(A_WorkingDir . "\" . exeName)
            return true
        pathEnv := EnvGet("PATH")
        for dir in StrSplit(pathEnv, ";") {
            if (dir != "" && FileExist(dir . "\" . exeName))
                return true
        }
        return false
    }

    static IsProtectedWindowClass(windowClass) {
        return (windowClass = "Shell_TrayWnd" || windowClass = "Progman" || windowClass = "WorkerW"
            || windowClass = "ApplicationFrameHost"
            || windowClass = "Windows.UI.Core.CoreWindow"
            || windowClass = "SearchHost"
            || windowClass = "StartMenuExperienceHostWindow"
            || windowClass = "ImmersiveLauncher")
    }

    static SmartRun(targetPath, args := "", workingDir := "") {
        targetPath := this.ResolveNativePath(targetPath)
        guard := Wow64RedirectionGuard()
        try {
            if (args != "")
                Run('"' . targetPath . '" ' . args, workingDir)
            else
                Run('"' . targetPath . '"', workingDir)
            return true
        } catch as e {
            if (A_LastError = 740 || A_LastError = 5 || InStr(e.Message, "elevation")) {
                try {
                    if (args != "")
                        Run('*RunAs "' . targetPath . '" ' . args, workingDir)
                    else
                        Run('*RunAs "' . targetPath . '"', workingDir)
                    return true
                } catch as uacErr {
                    if (A_LastError = 1223)
                        return false
                    throw uacErr
                }
            }
            throw e
        }
    }
}

ResolveNativePath(cmd) => Win32.ResolveNativePath(cmd)
SearchSystemPath(exe) => Win32.SearchSystemPath(exe)
SmartRun(target, args := "", dir := "") => Win32.SmartRun(target, args, dir)
IsProtectedWindowClass(cls) => Win32.IsProtectedWindowClass(cls)
