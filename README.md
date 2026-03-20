# sys-scripts

Windows automation scripts for cleanup, updates, hotkeys, image organizer and etc.

---

## Structure
```
sys-scripts/
├── cleanup/
│   ├── cleanup.ps1
│   └── register_cleanup.ps1
├── hotkeys/
│   └── hotkeys.ahk
├── image-organizer/
│   ├── organize.ps1
│   └── undo.ps1
├── logs/
│   ├── cleanup_log.txt
│   └── update_log.txt
├── network/
│   ├── network-reset.ps1
│   └── register_netreset.ps1
└── update/
    ├── register_update.ps1
    ├── update.ps1
    └── update_result.txt
```

---

## Setup

Run these once as admin in PowerShell:
```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\rames\sys-scripts\cleanup\register_cleanup.ps1"
powershell -ExecutionPolicy Bypass -File "C:\Users\rames\sys-scripts\update\register_update.ps1"
powershell -ExecutionPolicy Bypass -File "C:\Users\rames\sys-scripts\network\register_netreset.ps1"
```

Place a shortcut to `hotkeys.ahk` in:
```
C:\Users\rames\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\
```

Right-click the shortcut → Properties → Advanced → check **Run as administrator**.

---

## [cleanup](./cleanup)

Cleans temp files, Windows Update cache, prefetch, WER reports, crash dumps, thumbnail cache, DNS cache, and memory standby list. Logs every run with freed space and duration.
```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\rames\sys-scripts\cleanup\register_cleanup.ps1"
```

Run the register script once as admin. After that use `Ctrl+Shift+Alt+C` — no UAC prompt.

---

## [hotkeys](./hotkeys)

AutoHotkey script that maps Alt and Ctrl+Shift+Alt combos to apps, tools, and system scripts.

Place a shortcut to `hotkeys.ahk` in Startup and set it to run as administrator.

| Hotkey | Action | Double / Long Press |
|--------|--------|---------------------|
| Alt + V | VS Code | Open in current Explorer folder |
| Alt + A | Antigravity | Open in current Explorer folder |
| Alt + G | Git Bash | Open in current Explorer folder |
| Alt + T | CMD | CMD (Admin) |
| Alt + C | Chrome | Long press → Chrome Incognito |
| Alt + U | Ubuntu 22.04 WSL | NA |
| Alt + P | PowerShell (Admin) | NA |
| Alt + Y | YouTube | NA |
| Alt + W | WhatsApp | NA |
| Alt + I | Instagram | NA |
| Alt + S | Slack | NA |
| Alt + N | Notepad | NA |
| Alt + 0 | Calculator | NA |
| Alt + Q | Close active window (hold to keep closing) | NA |
| Ctrl+Shift+Alt+C | Run Windows Cleanup | NA |
| Ctrl+Shift+Alt+U | Run Windows Updater | NA |
| Ctrl+Shift+Alt+N | Run Network Reset | NA |
| Ctrl+Shift+Alt+L | Open Logs Folder | NA |
| Ctrl+Shift+Alt+Delete | Empty Recycle Bin (with confirm) | NA |

---

## [image-organizer](./image-organizer)

Sorts photos and videos into date-based folders. Reads EXIF first, falls back to filename then file date.
```powershell
powershell -ExecutionPolicy Bypass -File ".\image-organizer\organize.ps1"
```

The script will prompt for source, destination, move or copy, subfolders, and an optional dry run.

Logs and HTML report are saved to `_organizer_logs\` inside the destination.
```
destination/
├── 2026/
│   └── 03-March/
└── _organizer_logs/
    ├── report_timestamp.html
    └── undo_timestamp.csv
```
```powershell
powershell -ExecutionPolicy Bypass -File ".\image-organizer\undo.ps1" -Log ".\destination\_organizer_logs\undo_timestamp.csv"
```

> [!NOTE]
> The HTML report includes the exact undo command. Open it if you're unsure of the log path.

---

## [network](./network)

Resets Wi-Fi adapter, flushes DNS, and renews IP in one shot. Use when internet feels slow or stuck.
```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\rames\sys-scripts\network\register_netreset.ps1"
```

Run the register script once as admin. After that use `Ctrl+Shift+Alt+N` — no UAC prompt.

---

## [update](./update)

Runs in 4 phases: Winget packages, Windows Update, Driver Update, Windows Store. Triggered automatically at logon (20 min delay) or manually via hotkey.
```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\rames\sys-scripts\update\register_update.ps1"
```

Run the register script once as admin. After that use `Ctrl+Shift+Alt+U` — no UAC prompt.

---

## Logs

- `logs/cleanup_log.txt`
- `logs/update_log.txt`

Logs are gitignored.
```
