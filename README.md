# K2 Profile Emulator

A lightweight, event-driven PowerShell and C# utility that brings the Windows 11 26H2 "K2" low-latency shell optimizations to any Windows 10 or Windows 11 system. 

Instead of permanently locking your CPU to a high-performance, high-heat state, this emulator hooks directly into the Windows UI message pump. It detects when you interact with the system shell (e.g., opening the Start Menu, right-clicking, or switching applications) and instantly triggers a 2-second maximum frequency CPU burst to eliminate UI stutter and wake-up latency.

## ✨ Features
* **Zero Polling:** Uses native `WinEventHook` APIs to react instantly to UI events without wasting CPU cycles in the background.
* **Smart Cooldown:** Built-in throttling prevents rapid, overlapping power state changes if you spam-click menus.
* **Asynchronous Execution:** Power state transitions happen on a background thread pool, ensuring your UI message pump never freezes.
* **Invisible Operation:** Runs silently as a background Scheduled Task with no open console windows.
* **Laptop & Desktop Optimized:** Universally compatible. Automatically disables the CPU boost when a laptop is unplugged to preserve battery life, while remaining always-active on desktops.
* **Flicker-Free Stealth Boost:** Modifies the *currently active* power plan's minimum processor state directly via the Windows kernel API, rather than switching between "Balanced" and "High Performance" plans. This prevents screen brightness flickering and stops the Windows Control Panel UI from glitching or disappearing.
* **Self-Healing Power Plans:** Automatically restores missing default Windows power plans (including the hidden "Ultimate Performance" plan) silently at startup via the `PowerRestoreDefaultPowerSchemes` API.

## ⚙️ How It Works
The native Windows 11 K2 implementation operates inside the kernel. This script provides the closest possible user-space emulation:
1. Listens for `EVENT_SYSTEM_FOREGROUND` (app switching) and `EVENT_SYSTEM_MENUPOPUPSTART` (system menus).
2. Checks `GetSystemPowerStatus`. If the device is on battery power, the event is ignored to save battery.
3. If plugged in (or on a desktop), it captures the currently active power plan and reads its existing minimum processor state.
4. Uses the `PowerWriteACValueIndex` API to instantly force the active plan's minimum processor state to 100%, engaging an instant CPU burst without changing the active plan itself.
5. Holds this state for exactly 2 seconds.
6. Restores the original minimum processor state values, allowing the CPU to downclock and save energy.

## 🚀 Prerequisites
1. **Windows 10 (1809+) or Windows 11**.
2. **Administrator Privileges:** Required to modify power states and install the Scheduled Task.
3. **No Custom GUIDs Needed:** Because the script now dynamically targets whatever power plan is currently active, you no longer need to manually hunt down and update OEM-specific power plan GUIDs.

## 🛠️ Installation & Deployment

Do not run the monitor script manually every time. Use the provided deployment script to install it permanently as a hidden system service.

1. Open PowerShell as **Administrator**.
2. Run the deployment script:
3. The script will automatically restore missing power plans, compile the C# API hooks, register the hidden Scheduled Task, and start the optimization immediately. You will see the confirmation: `K2 Optimization Active`.
