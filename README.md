# sys-scripts

Windows automation scripts for cleanup, updates, and hotkeys.

---

## Structure

```
sys-scripts/
├── cleanup/
│   ├── cleanup.ps1
│   ├── cleanup_log.txt
│   └── register_cleanup.ps1
├── hotkeys/
│   └── hotkeys.ahk
└── update/
    ├── register_update.ps1
    ├── update.ps1
    └── update_log.txt
```

---

## Setup

Run these once as admin in PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\rames\sys-scripts\cleanup\register_cleanup.ps1"
powershell -ExecutionPolicy Bypass -File "C:\Users\rames\sys-scripts\update\register_update.ps1"
```

Place a shortcut to `hotkeys.ahk` in:
```
C:\Users\rames\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\
```

---

## Hotkeys

| Hotkey | Action | Double / Long Press |
|--------|--------|---------------------|
| Alt + V | VS Code | Open in current Explorer folder |
| Alt + A | Antigravity | Open in current Explorer folder |
| Alt + G | Git Bash | Open in current Explorer folder |
| Alt + T | CMD | CMD (Admin) |
| Alt + C | Chrome | Long press → Chrome Incognito |
| Alt + U | Ubuntu 22.04 WSL | — |
| Alt + P | PowerShell (Admin) | — |
| Alt + Y | YouTube | — |
| Alt + W | WhatsApp | — |
| Alt + I | Instagram | — |
| Alt + S | Slack | — |
| Alt + N | Notepad | — |
| Alt + 0 | Calculator | — |
| Alt + Q | Close active window (hold to keep closing) | — |
| Ctrl+Shift+Alt+C | Run Windows Cleanup | — |
| Ctrl+Shift+Alt+U | Run Windows Updater | — |
| Ctrl+Shift+Alt+Delete | Empty Recycle Bin (with confirm) | — |

---

## Logs

- `cleanup/cleanup_log.txt`
- `update/update_log.txt`

Logs are gitignored.
