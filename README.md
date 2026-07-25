# hotkeys

Advanced AutoHotkey system providing context-aware application launching, system maintenance automation, and safe window management.

---

## Hotkey Reference

### Application & Utility Hotkeys

| Hotkey | Action | Trigger Mode | Description |
| :--- | :--- | :--- | :--- |
| **Alt + 0** | Calculator | Single Press | Opens Windows Calculator |
| **Alt + 1** | Photoshop | Double Press | Opens Adobe Photoshop |
| **Alt + 7** | 7.1 Surround Sound | Single Press | Opens Razer 7.1 Surround Sound |
| **Alt + A** | Antigravity | Single Press | Opens Antigravity IDE |
| | | Double Press | Opens Antigravity in the active Explorer folder |
| **Alt + C** | Google Chrome | Single Press | Opens Google Chrome |
| | | Long Press | Opens Google Chrome in **Incognito Mode** |
| **Alt + E** | Outlook | Single Press | Opens Outlook (Auto-Maximized) |
| **Alt + G** | Git Bash | Single Press | Opens Git Bash |
| | | Double Press | Opens Git Bash in the active Explorer folder |
| **Alt + I** | Instagram | Single Press | Opens Instagram (Auto-Maximized) |
| **Alt + M** | Microsoft Store | Single Press | Opens Microsoft Store |
| **Alt + N** | Notepad | Single Press | Opens Notepad |
| **Alt + O** | CMD | Single Press | Opens Command Prompt |
| | | Double Press | Opens **Administrator CMD** |
| **Alt + P** | PowerShell | Single Press | Opens PowerShell |
| | | Double Press | Opens **Administrator PowerShell** |
| **Alt + Q** | Close Active Window | Single Press | Closes the active window safely |
| | | Hold (Long Press)| Continuously closes windows (protected) |
| **Alt + S** | Slack | Single Press | Opens Slack (Auto-Maximized) |
| **Alt + T** | Telegram | Single Press | Opens Telegram |
| **Alt + U** | Ubuntu WSL | Single Press | Opens WSL terminal |
| | | Double Press | Opens WSL in the active Explorer folder |
| **Alt + V** | VS Code | Single Press | Opens VS Code |
| | | Double Press | Opens VS Code in the active Explorer folder |
| **Alt + Shift + V** | WSL Path Paste | Single Press | Converts Windows clipboard path and pastes in WSL format |
| **Alt + W** | WhatsApp | Single Press | Opens WhatsApp (Auto-Maximized) |
| **Alt + Y** | YouTube | Single Press | Opens YouTube (Auto-Maximized) |
| **Alt + Z** | Unzip ZIP | Single Press | Extracts selected ZIP inside File Explorer |

### System & Media Hotkeys

| Hotkey | Action | Description |
| :--- | :--- | :--- |
| **Ctrl + Shift + Q** | Switch Audio | Set playback to **Sony MDRX-50** (mic: Sony) and volume to 25% |
| **Ctrl + Shift + X** | Switch Audio | Set playback to **Black Shark V2** (mic: Black Shark) |
| **Ctrl + Shift + Y** | Switch Audio | Set playback to **Resound** (mic: Sony) |
| **Ctrl + Shift + Z** | Switch Audio | Set playback to **HEAT** (mic: Sony) |
| **Ctrl + Shift + Alt + C** | Windows Cleanup | Runs background Windows Cleanup (tray notification on finish) |
| **Ctrl + Shift + Alt + U** | Windows Updater | Runs background Windows Update check (tray notification on finish) |
| **Ctrl + Shift + Alt + N** | Network Reset | Resets network adapters, flushes DNS, and renews IP |
| **Ctrl + Shift + Alt + L** | Logs Folder | Opens the logs directory in File Explorer |
| **Ctrl + Shift + Alt + Del** | Empty Recycle Bin | Empties the Recycle Bin (requires confirmation prompt) |

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
