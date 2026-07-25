# hotkeys

Advanced AutoHotkey system providing context-aware application launching, system maintenance automation, and safe window management.

---

## Hotkey Reference

### Application & Utility Hotkeys

| Hotkey | Single Press | Double Press | Long Press / Hold |
| :--- | :--- | :--- | :--- |
| **Alt + 0** | Calculator | - | - |
| **Alt + 1** | - | Photoshop | - |
| **Alt + 7** | 7.1 Surround Sound | - | - |
| **Alt + A** | Antigravity IDE | Open in active Explorer folder | - |
| **Alt + C** | Google Chrome | - | **Incognito Mode** (Hold >600ms) |
| **Alt + E** | Outlook (Auto-Maximize) | - | - |
| **Alt + G** | Git Bash | Open in active Explorer folder | - |
| **Alt + I** | Instagram (Auto-Maximize) | - | - |
| **Alt + M** | Microsoft Store | - | - |
| **Alt + N** | Notepad | - | - |
| **Alt + O** | Command Prompt (CMD) | **Administrator CMD** | - |
| **Alt + P** | PowerShell | **Administrator PowerShell** | - |
| **Alt + Q** | Close Active Window | - | Continuous safe window close |
| **Alt + S** | Slack (Auto-Maximize) | - | - |
| **Alt + T** | Telegram | - | - |
| **Alt + U** | Ubuntu WSL | Open in active Explorer folder | - |
| **Alt + V** | VS Code | Open in active Explorer folder | - |
| **Alt + Shift + V** | Paste clipboard path as WSL | - | - |
| **Alt + W** | WhatsApp (Auto-Maximize) | - | - |
| **Alt + Y** | YouTube (Auto-Maximize) | - | - |
| **Alt + Z** | Unzip Selected ZIP | - | - |

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

To install and register the hotkeys globally on your machine, simply run the included custom `xt` CLI tool:

1. Open PowerShell or Command Prompt at the repository root folder.
2. Run the installer:
   ```cmd
   xt install
   ```
   *(This automatically copies the runtime files to `%LocalAppData%\xt`, registers the `xt` command in your User `PATH`, creates the Startup shortcut, configures it to run as Administrator, and launches the script.)*
3. Restart your terminal to begin using the `xt` command globally!

### CLI Commands Reference

Once installed, you can manage the hotkeys globally from any command line:

* **`xt status`**: Checks if the script is active and running.
* **`xt update`**: Installs your latest local repository changes to the runtime folder and restarts the hotkeys.
* **`xt uninstall`**: Removes the Startup shortcut, deletes all runtime files, and removes `xt` from your User `PATH`.

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
