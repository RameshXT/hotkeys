# hotkeys

Advanced AutoHotkey system providing context-aware application launching, system maintenance automation, and safe window management.

---

## Hotkey Reference

### 1. Double-Press & Long-Press Shortcuts
Special keys that change their behavior when double-pressed or held down:

| Hotkey | Target App | Single Press | Double Press | Long Press (Hold >600ms) |
| :--- | :--- | :--- | :--- | :--- |
| **Alt + C** | Google Chrome | Launch / Focus Chrome | - | Open in **Incognito Mode** |
| **Alt + 1** | Photoshop | - | Launch Photoshop | - |
| **Alt + A** | Antigravity IDE | Launch / Focus IDE | Open in current Explorer folder | - |
| **Alt + G** | Git Bash | Launch / Focus Git Bash | Open in current Explorer folder | - |
| **Alt + O** | Command Prompt (CMD) | Launch CMD | Launch as **Administrator** | - |
| **Alt + P** | PowerShell | Launch PowerShell | Launch as **Administrator** | - |
| **Alt + U** | Ubuntu WSL | Launch WSL | Open in current Explorer folder | - |
| **Alt + V** | VS Code | Launch / Focus VS Code | Open in current Explorer folder | - |

---

### 2. Standard App Launchers
Single-press shortcuts to quickly launch or switch to apps:

| Hotkey | Target App | Launch Behavior |
| :--- | :--- | :--- |
| **Alt + 0** | Calculator | Standard launch |
| **Alt + 7** | 7.1 Surround Sound | Standard launch |
| **Alt + E** | Outlook | Auto-Maximize PWA / Web fallback |
| **Alt + I** | Instagram | Auto-Maximize PWA / Web fallback |
| **Alt + M** | Microsoft Store | Standard launch |
| **Alt + N** | Notepad | Standard launch |
| **Alt + S** | Slack | Auto-Maximize App / UWP fallback |
| **Alt + T** | Telegram | Auto-Maximize App / UWP fallback |
| **Alt + W** | WhatsApp | Auto-Maximize App / UWP fallback |
| **Alt + Y** | YouTube | Auto-Maximize PWA / Web fallback |

---

### 3. Productivity & Window Management
Special utilities to speed up window operations and file path conversion:

| Hotkey | Action | Behavior |
| :--- | :--- | :--- |
| **Alt + Q** | Close Active Window | Continuous closing (hold to repeat) with system protection |
| **Alt + Z** | Unzip Selected File | Extracts the currently selected ZIP file in Explorer |
| **Alt + Shift + V** | WSL Path Paste | Converted Windows path on clipboard to Unix format and paste |

---

### 4. System Audio Output Switches
Instantly redirect sound output and microphone sources:

| Hotkey | Playback Target | Microphone Target |
| :--- | :--- | :--- |
| **Ctrl + Shift + Q** | Sony MDRX-50 (sets vol to 25%) | Built-in Mic |
| **Ctrl + Shift + X** | Black Shark V2 | Razer Mic |
| **Ctrl + Shift + Y** | Resound | Built-in Mic |
| **Ctrl + Shift + Z** | HEAT | Built-in Mic |

---

### 5. Automated Maintenance Tasks
Triggers background Windows scheduled tasks with real-time TrayTip status results:

| Hotkey | Action | Behavior |
| :--- | :--- | :--- |
| **Ctrl + Shift + Alt + C** | Run System Cleanup | Executes background storage cleanup |
| **Ctrl + Shift + Alt + U** | Run Windows Updater | Executes background updates |
| **Ctrl + Shift + Alt + N** | Run Network Reset | Resets adapters and flushes DNS |
| **Ctrl + Shift + Alt + L** | Open Logs Folder | Opens directory containing error logs |
| **Ctrl + Shift + Alt + Del** | Empty Recycle Bin | Clears recycle bin (requires confirmation) |

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

- **Contextual Intelligence**: Shell and editor shortcuts automatically detect if you are in File Explorer and adjust their working directory.
- **Safety & Protection**: Prevents accidental closures of desktop shell components (like the Taskbar).
- **Friendly Balloon Notifications**: Translates standard Windows CLI errors into simplified tray notifications.
- **Self-Maintaining**: Automatically reloads and applies changes the moment you save `hotkeys.ahk`.
