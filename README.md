# hotkeys

Advanced AutoHotkey system providing context-aware application launching, system maintenance automation, and safe window management.

---

## Setup

1. Place a shortcut to `hotkeys.ahk` in your Windows Startup folder:
   ```
   %APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\
   ```
2. Right-click the shortcut → **Properties** → **Advanced** → check **Run as administrator**.
3. Run `hotkeys.ahk` once to initialize. The script is self-elevating and will request Administrator privileges to successfully control background applications.

---

## Key Features

- **Contextual Intelligence**:
  - **Double-Tap to Folder**: `Alt + V` (VS Code), `Alt + A` (Antigravity), `Alt + G` (Git Bash), `Alt + P` (PowerShell), and `Alt + U` (Ubuntu WSL) open the application directly in your **active File Explorer directory** when double-pressed.
  - **Double-Tap to Admin**: `Alt + O` (CMD) and `Alt + P` (PowerShell) open standard shell (in folder if active) on single press, and their respective **Administrator** versions (when no folder is active) on double press.
  - **Long-Press Interface**: `Alt + C` launches standard Chrome on a short tap, but triggers **Incognito Mode** if held for >600ms.
- **Safety & Protection**: `Alt + Q` (Close Window) supports continuous closing when held, but is logic-locked to **prevent accidental closure** of critical system components, showing "Nothing to close" if there is no active/non-system window.
- **Audio Output Switching**: Quickly switch audio playback and recording devices using `Ctrl + Shift + [Key]` combinations.
- **Friendly Balloon Notifications**: Automatically intercepts launch or system errors and shows clean Windows tray notifications instead of blocking error popups.
- **Self-Maintaining**: Automatically reloads and applies changes the moment you save `hotkeys.ahk`.

---

## Hotkey Reference

| Hotkey                | Action                | Double / Long Press             |
| --------------------- | --------------------- | ------------------------------- |
| Alt + 0               | Calculator            | NA                              |
| Alt + 1               | Photoshop             | Launch Photoshop (Double Press) |
| Alt + 7               | 7.1 Surround Sound    | NA                              |
| Alt + A               | Antigravity           | Open in current Explorer folder |
| Alt + C               | Google Chrome         | Long press → **Incognito Mode** |
| Alt + E               | Outlook               | Web / App Auto-Maximize         |
| Alt + G               | Git Bash              | Open in current Explorer folder |
| Alt + I               | Instagram             | Web / App Auto-Maximize         |
| Alt + M               | Microsoft Store       | NA                              |
| Alt + N               | Notepad               | NA                              |
| Alt + O               | CMD                   | Double press → **Admin CMD** (when no folder focused) |
| Alt + P               | PowerShell            | Double press → **Admin PowerShell** (when no folder focused) |
| Alt + Q               | Close active window   | Continuous Close (Protected)    |
| Alt + S               | Slack                 | Web / App Auto-Maximize         |
| Alt + T               | Telegram              | Web / App Auto-Maximize         |
| Alt + U               | Ubuntu WSL            | Open in current Explorer folder |
| Alt + V               | VS Code               | Open in current Explorer folder / Web Fallback |
| Alt + Shift + V       | WSL Path Paste        | Convert Windows clipboard path and paste as WSL/Unix format |
| Alt + W               | WhatsApp              | Web / App Auto-Maximize         |
| Alt + Y               | YouTube               | Web / App Auto-Maximize         |
| Alt + Z               | Unzip Selected ZIP    | NA                              |
| Ctrl + Shift + Q      | Switch to Sony MDRX50 | NA                              |
| Ctrl + Shift + X      | Switch to Black Shark | NA                              |
| Ctrl + Shift + Y      | Switch to Resound     | NA                              |
| Ctrl + Shift + Z      | Switch to Heat        | NA                              |
| Ctrl+Shift+Alt+C      | Run Windows Cleanup   | Result via TrayTip              |
| Ctrl+Shift+Alt+U      | Run Windows Updater   | Result via TrayTip              |
| Ctrl+Shift+Alt+N      | Run Network Reset     | Result via ToolTip              |
| Ctrl+Shift+Alt+L      | Open Logs Folder      | NA                              |
| Ctrl+Shift+Alt+Delete | Empty Recycle Bin     | Confirmation required           |
