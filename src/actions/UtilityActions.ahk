#Requires AutoHotkey v2.0.26

class UtilityActions {
    static ConvertToWSLPath(winPath) {
        if (winPath = "")
            return ""
        unixPath := StrReplace(winPath, "\", "/")
        if (RegExMatch(unixPath, "i)^//wsl(?:\.localhost)?/[^/]+(/.*)?$", &m)) {
            return m[1] != "" ? m[1] : "/"
        } else if (SubStr(unixPath, 2, 1) = ":") {
            drive := Format("{:L}", SubStr(unixPath, 1, 1))
            unixPath := "/mnt/" . drive . SubStr(unixPath, 3)
        }
        return unixPath
    }

    static ZipHasRootFolder(zipPath) {
        try {
            shell := ComObject("Shell.Application")
            zipObj := shell.Namespace(zipPath)
            if (zipObj) {
                items := zipObj.Items()
                if (items.Count = 1) {
                    return items.Item(0).IsFolder ? true : false
                }
            }
        }
        return false
    }

    static ExtractSelectedZip() {
        winClass := WinGetClass("A")
        if (winClass != "CabinetWClass" && winClass != "ExploreWClass")
            return
        selectedPath := ShellExplorer.GetSelectedFilePath()
        if (selectedPath = "")
            return
        SplitPath selectedPath, , &fileDir, &fileExtension, &nameNoExt
        if (fileExtension != "zip" && fileExtension != "ZIP")
            return

        hasRootFolder := this.ZipHasRootFolder(selectedPath)
        targetDir := hasRootFolder ? fileDir : (fileDir . "\" . nameNoExt)

        winrarPath := AppResolver.Get("WinRAR", "WinRAR.exe", [
            "%ProgramFiles%\WinRAR\WinRAR.exe",
            "%ProgramFiles(x86)%\WinRAR\WinRAR.exe"
        ])
        if FileExist(winrarPath) {
            guard := Wow64RedirectionGuard()
            Run('"' . winrarPath . '" x -o+ "' . selectedPath . '" "' . targetDir . '"')
            return
        }

        tarExe := Win32.ResolveNativePath("tar.exe")
        if FileExist(tarExe) {
            try DirCreate(targetDir)
            guard := Wow64RedirectionGuard()
            Run('"' . tarExe . '" -xf "' . selectedPath . '" -C "' . targetDir . '"', , "Hide")
            return
        }

        try {
            DirCreate(targetDir)
            shell := ComObject("Shell.Application")
            zipFolder := shell.Namespace(selectedPath)
            destFolder := shell.Namespace(targetDir)
            if (zipFolder && destFolder) {
                destFolder.CopyHere(zipFolder.Items(), 4 | 16 | 512 | 1024)
            }
        }
    }

    static PasteClipboardAsWSL() {
        static isPasting := false
        if (isPasting)
            return

        clipText := Trim(A_Clipboard, '`t`n`r "')
        if (clipText != "" && (RegExMatch(clipText, "i)^[A-Z]:") || InStr(clipText, "\"))) {
            isPasting := true
            wslPath := this.ConvertToWSLPath(clipText)
            oldClip := ClipboardAll()
            A_Clipboard := wslPath
            Send("^v")
            Sleep 50
            A_Clipboard := oldClip
            isPasting := false
        } else {
            Send("^v")
        }
    }

    static EmptyRecycleBin() {
        result := MsgBox("Are you sure you want to permanently delete all items in the Recycle Bin?", "Empty Recycle Bin", 4)
        if (result = "Yes") {
            try {
                DllCall("shell32\SHEmptyRecycleBin", "Ptr", 0, "Ptr", 0, "UInt", 0x1)
                NotificationManager.ShowTransient("Recycle Bin emptied")
            } catch as e {
                ErrorHandler.HandleLaunchError("Failed to empty Recycle Bin", e)
            }
        }
    }
}

ConvertToWSLPath(winPath) => UtilityActions.ConvertToWSLPath(winPath)
ExtractSelectedZip() => UtilityActions.ExtractSelectedZip()
