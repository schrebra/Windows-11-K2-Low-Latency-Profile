# K2 Low-Latency Emulator (Tiered AC/DC Boosting V4.4)

A high-performance PowerShell utility that dynamically switches Windows Power Plans based on window focus and power source, while maintaining a **locked, consistent screen brightness** across all states to prevent flickering.

## 🚀 Features

- **Dynamic Plan Switching:** Automatically switches between *Power Saver*, *Balanced*, and *High Performance* plans based on whether a window is in focus.
- **Ultimate Brightness Lock:** Solves the common issue of screen brightness flickering when switching power plans by synchronizing brightness values across all active schemes using native Windows APIs.
- **AC/DC Awareness:** Adapts its "Base" and "Boost" targets depending on whether you are plugged in or on battery.
- **Zero-CPU Overhead:** Uses efficient event hooks and smart caching to only perform actions when necessary.
- **Persistent Setup:** Installs itself as a Scheduled Task to run automatically at logon with highest privileges.

## ⚙️ How It Works

| State | Power Source | Base Plan | Window Focus Boost |
| :--- | :--- | :--- | :--- |
| **Idle** | 🔋 Battery | Power Saver | Balanced |
| **Active** | 🔋 Battery | Power Saver | Balanced |
| **Idle** | 🔌 Plugged In | Balanced | High Performance |
| **Active** | 🔌 Plugged In | Balanced | High Performance |

### The Brightness Fix (V4.4)
Previous versions suffered from brightness adjustments because Windows stores different brightness levels for each power plan. V4.4 implements:
1. **Direct Memory Reading:** Uses `PowerReadACValueIndex` to get the exact brightness from the active plan's memory.
2. **Bulletproof Syncing:** Uses `powercfg.exe` to force-write that exact value to all three power plans simultaneously.
3. **Smart Caching:** Only syncs when a change is detected, keeping background resource usage at zero.

## 📥 Installation

1. **Download** the `K2Monitor.ps1` script.
2. **Right-click** the file and select **Run with PowerShell** (or run as Administrator in your terminal).
3. The script will automatically:
   - Restore default power plans if missing.
   - Create the necessary directory at `C:\ProgramData\K2Emulator`.
   - Register a Scheduled Task named `K2ProfileEmulator`.

## 🛠️ Technical Details

- **Language:** PowerShell / C# (via `Add-Type`)
- **APIs Used:** `user32.dll` (Event Hooks), `powrprof.dll` (Power Management), `kernel32.dll` (System Status)
- **Requirements:** Windows 10/11, Administrator Privileges

## ⚠️ Disclaimer

This tool modifies system power settings. While it includes safety checks to restore defaults, use it at your own risk. If you experience any issues, you can remove the scheduled task via Task Scheduler and run `powercfg -restoredefaultschemes` in an admin terminal.
