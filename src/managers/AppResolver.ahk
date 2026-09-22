#Requires AutoHotkey v2.0.26

class AppResolver {
    static cache := Map()

    static Get(appKey, exeName := "", searchPatterns := [], regPaths := []) {
        if this.cache.Has(appKey)
            return this.cache[appKey]

        resolvedPath := ""

        if (exeName != "") {
            for root in ["HKEY_LOCAL_MACHINE", "HKEY_CURRENT_USER"] {
                try {
                    val := RegRead(root . "\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\" . exeName, "")
                    if (val != "" && FileExist(val)) {
                        resolvedPath := val
                        break
                    }
                }
            }
        }

        if (resolvedPath = "" && regPaths.Length > 0) {
            for regSpec in regPaths {
                parts := StrSplit(regSpec, "|")
                keyPath := parts[1]
                valueName := parts.Length > 1 ? parts[2] : ""
                try {
                    val := RegRead(keyPath, valueName)
                    if (val != "") {
                        if (InStr(FileExist(val), "D")) {
                            if (exeName != "" && FileExist(val . "\" . exeName))
                                resolvedPath := val . "\" . exeName
                        } else if (FileExist(val)) {
                            resolvedPath := val
                        }
                    }
                }
                if (resolvedPath != "")
                    break
            }
        }

        if (resolvedPath = "") {
            for pattern in searchPatterns {
                expanded := this.ExpandEnvVars(pattern)
                if (expanded != "" && FileExist(expanded)) {
                    resolvedPath := expanded
                    break
                }
            }
        }

        if (resolvedPath = "") {
            resolvedPath := exeName != "" ? exeName : ""
        }

        if (resolvedPath != "" && (FileExist(resolvedPath) || InStr(resolvedPath, "://"))) {
            this.cache[appKey] := resolvedPath
        }
        return resolvedPath
    }

    static ExpandEnvVars(str) {
        if (!InStr(str, "%"))
            return str

        str := StrReplace(str, "%ProgramFilesCommon%", A_ProgramFiles . "\Common Files")
        str := StrReplace(str, "%ProgramFiles(x86)%", EnvGet("ProgramFiles(x86)") || A_ProgramFiles)
        str := StrReplace(str, "%StartMenuCommon%", A_StartMenuCommon)
        str := StrReplace(str, "%StartMenu%", A_StartMenu)
        str := StrReplace(str, "%AppData%", A_AppData)
        str := StrReplace(str, "%LocalAppData%", EnvGet("LocalAppData"))
        str := StrReplace(str, "%ProgramFiles%", A_ProgramFiles)

        pos := 1
        while (pos <= StrLen(str)) {
            if (RegExMatch(str, "%([^%]+)%", &match, pos)) {
                envVal := EnvGet(match[1])
                str := StrReplace(str, match[0], envVal)
                pos := match.Pos + StrLen(envVal)
            } else {
                break
            }
        }
        return str
    }
}
