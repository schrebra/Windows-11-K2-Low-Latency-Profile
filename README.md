# K2 Profile Emulator

A lightweight, event-driven PowerShell and C# utility that brings the Windows 11 26H2 "K2" low-latency shell optimizations to any Windows 10 or Windows 11 system. 

Instead of permanently locking your CPU to a high-performance, high-heat state, this emulator hooks directly into the Windows UI message pump. It detects when you interact with the system shell (e.g., opening the Start Menu, right-clicking, or switching applications) and instantly triggers a 2-second maximum frequency CPU burst to eliminate UI stutter and wake-up latency.

## ✨ Features
* **Zero Polling:** Uses native `WinEventHook` APIs to react instantly to UI events without wasting CPU cycles in the background.
* **Smart Cooldown:** Built-in throttling prevents rapid, overlapping power state changes if you spam-click menus.
* **Asynchronous Execution:** Power state transitions happen on a background thread pool, ensuring your UI message pump never freezes.
* **Invisible Operation:** Runs silently as a background Scheduled Task with no open console windows.
* **Battery Aware:** Configured to gracefully handle laptop power states without draining battery life unnecessarily.

## ⚙️ How It Works
The native Windows 11 K2 implementation operates inside the kernel. This script provides the closest possible user-space emulation:
1. Listens for `EVENT_SYSTEM_FOREGROUND` (app switching) and `EVENT_SYSTEM_MENUPOPUPSTART` (system menus).
2. Upon detection, fires `powercfg -setactive` to engage your High Performance plan.
3. Holds the state for exactly 2 seconds.
4. Reverts back to your Balanced power plan to save energy and reduce heat.

## 🚀 Prerequisites
1. **Windows 10 (1809+) or Windows 11**.
2. **Administrator Privileges:** Required to modify power states and install the Scheduled Task.
3. **Verified Power Plan GUIDs:** The script uses the default Windows GUIDs for High Performance (`8c5e7fda...`) and Balanced (`381b4222...`). If your OEM (Dell, Asus, etc.) uses custom power plans, run `powercfg /list` in CMD and update the GUID variables in the script.

## 🛠️ Installation & Deployment

Do not run the monitor script manually every time. Use the provided deployment script to install it permanently as a hidden system service.

1. Open PowerShell as **Administrator**.
2. Run the deployment script:
