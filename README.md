# K2 Profile Emulator (V4.2 - Tiered Dynamic Switching)

A lightweight, event-driven PowerShell and C# utility that brings dynamic, tiered power plan optimization to any Windows 10 or Windows 11 system. 

Instead of permanently locking your CPU to a high-performance state or relying on static power plans, this emulator actively manages your base power profile based on your power source. It hooks directly into the Windows UI message pump to detect shell interactions (e.g., opening the Start Menu, right-clicking, or switching applications) and instantly triggers a 2-second power plan burst to eliminate UI stutter and wake-up latency.

## ✨ Features

* **Zero Polling UI Hooks:** Uses native `WinEventHook` APIs to react instantly to UI events without wasting CPU cycles in the background.
* **Dynamic Tiered Power Switching:** Instead of tweaking hidden processor states, it physically switches between Windows power plans. On battery, it boosts from Power Saver to Balanced. On AC, it boosts from Balanced to High Performance.
* **Active Power Polling:** A background thread checks your AC/Battery status every 3 seconds, ensuring your base power plan is always perfectly matched to your current power source.
* **Smart Cooldown:** Built-in throttling prevents rapid, overlapping power state changes if you spam-click menus.
* **Asynchronous Execution:** Power state transitions happen on a background thread pool, ensuring your UI message pump never freezes.
* **Invisible Operation:** Runs silently as a background Scheduled Task with no open console windows.
* **Auto-Elevation & Lock Prevention:** Automatically requests Administrator privileges if missing, and safely stops previous instances before updating to prevent file-lock errors.
* **Self-Healing Power Plans:** Automatically restores missing default Windows power plans (Power Saver, Balanced, High Performance) silently at startup.

## ⚙️ How It Works

This script provides a highly responsive, user-space emulation of dynamic power management:

1. **Base Plan Management:** A background thread polls `GetSystemPowerStatus` every 3 seconds. If on battery, it sets the base plan to **Power Saver**. If plugged in, it sets the base plan to **Balanced**.
2. **Event Listening:** It listens for `EVENT_SYSTEM_FOREGROUND` (app switching) and `EVENT_SYSTEM_MENUPOPUPSTART` (system menus).
3. **Tiered Boost Execution:** When a UI event is triggered, it calculates the correct boost target based on the current power state:
   * *On Battery:* Instantly switches to **Balanced**.
   * *On AC Power:* Instantly switches to **High Performance**.
4. **Timed Reversion:** It holds this boosted state for exactly 2 seconds, then reverts to the correct base plan (Power Saver or Balanced), allowing the system to return to its optimal power/thermal state.

## 🚀 Prerequisites

* Windows 10 (1809+) or Windows 11.
* Administrator Privileges: Required to modify power states and install the Scheduled Task (the script will auto-prompt for UAC elevation if run without them).
* No Custom GUIDs Needed: The script dynamically targets the default Windows power plan GUIDs.

## 🛠️ Installation & Deployment

Do not run the monitor script manually every time. Use the provided deployment script to install it permanently as a hidden system service.

1. Save the deployment script as `K2_Install.ps1`.
2. Run the script (it will automatically elevate to Administrator if needed).
3. The script will stop any existing tasks to prevent file locks, restore missing power plans, compile the C# API hooks, register the hidden Scheduled Task, and start the optimization immediately. 
4. You will see the confirmation: `K2 Tiered Optimization Active`.
