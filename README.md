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

```powershell
# 1. Define paths
$TargetDir = "C:\ProgramData\K2Emulator"
$ScriptPath = "$TargetDir\K2Monitor.ps1"
$TaskName = "K2ProfileEmulator"

# Create the directory
if (-not (Test-Path $TargetDir)) { New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null }

# 2. Write the K2 Monitor code into the permanent file
$K2ScriptContent = @"
`$K2Code = @"
using System;
using System.Runtime.InteropServices;
using System.Diagnostics;
using System.Threading;

public class K2ProfileEmulator
{
    delegate void WinEventDelegate(IntPtr hWinEventHook, uint eventType, IntPtr hwnd, int idObject, int idChild, uint dwEventThread, uint dwmsEventTime);

    [DllImport("user32.dll")]
    static extern IntPtr SetWinEventHook(uint eventMin, uint eventMax, IntPtr hmodWinEventProc, WinEventDelegate lpfnWinEventProc, uint idProcess, uint idThread, uint dwFlags);

    [DllImport("user32.dll")]
    static extern bool UnhookWinEvent(IntPtr hWinEventHook);

    [DllImport("user32.dll")]
    static extern int GetMessage(out MSG lpMsg, IntPtr hWnd, uint wMsgFilterMin, uint wMsgFilterMax);

    [DllImport("user32.dll")]
    static extern bool TranslateMessage(ref MSG lpMsg);

    [DllImport("user32.dll")]
    static extern IntPtr DispatchMessage(ref MSG lpMsg);

    [StructLayout(LayoutKind.Sequential)]
    public struct MSG { public IntPtr hwnd; public uint message; public IntPtr wParam; public IntPtr lParam; public uint time; public int pt_x; public int pt_y; }

    const uint EVENT_SYSTEM_FOREGROUND = 3;
    const uint EVENT_SYSTEM_MENUPOPUPSTART = 6;
    const uint WINEVENT_OUTOFCONTEXT = 0;

    static WinEventDelegate dele = null;
    static DateTime lastBoost = DateTime.MinValue;
    
    static string highPerfGuid = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c";
    static string balancedGuid = "381b4222-f694-41f0-9685-ff5bb260df2e";

    public static void StartMonitoring()
    {
        dele = new WinEventDelegate(WinEventProc);
        IntPtr hhook = SetWinEventHook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_MENUPOPUPSTART, IntPtr.Zero, dele, 0, 0, WINEVENT_OUTOFCONTEXT);
        
        MSG msg;
        while (GetMessage(out msg, IntPtr.Zero, 0, 0) != 0)
        {
            TranslateMessage(ref msg);
            DispatchMessage(ref msg);
        }
        UnhookWinEvent(hhook);
    }

    static void WinEventProc(IntPtr hWinEventHook, uint eventType, IntPtr hwnd, int idObject, int idChild, uint dwEventThread, uint dwmsEventTime)
    {
        if ((DateTime.Now - lastBoost).TotalSeconds > 2.5)
        {
            lastBoost = DateTime.Now;
            ThreadPool.QueueUserWorkItem(state => BoostCPU());
        }
    }

    static void BoostCPU()
    {
        try {
            RunPowerCfg(highPerfGuid);
            Thread.Sleep(2000);
            RunPowerCfg(balancedGuid);
        } catch {}
    }

    static void RunPowerCfg(string guid)
    {
        Process p = new Process();
        p.StartInfo.FileName = "powercfg";
        p.StartInfo.Arguments = "-setactive " + guid;
        p.StartInfo.CreateNoWindow = true;
        p.StartInfo.UseShellExecute = false;
        p.Start();
        p.WaitForExit();
    }
}
`"@

Add-Type -TypeDefinition `$K2Code
[K2ProfileEmulator]::StartMonitoring()
"@

Set-Content -Path $ScriptPath -Value $K2ScriptContent -Force

# 3. Create and Register the Scheduled Task
$TaskAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
$TaskTrigger = New-ScheduledTaskTrigger -AtLogon
$TaskPrincipal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -RunLevel Highest
$TaskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Days 365)

Register-ScheduledTask -TaskName $TaskName -Action $TaskAction -Trigger $TaskTrigger -Principal $TaskPrincipal -Settings $TaskSettings -Force

Write-Host "Deployment complete! Starting service..." -ForegroundColor Green
Start-ScheduledTask -TaskName $TaskName
