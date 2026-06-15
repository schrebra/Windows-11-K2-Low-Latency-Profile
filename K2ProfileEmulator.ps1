# ==============================================================================
# K2 LOW-LATENCY EMULATOR (NATIVE API OPTIMIZED V2.3)
# ==============================================================================

# ------------------------------------------------------------------------------
# PART 1: ENVIRONMENT SETUP
# ------------------------------------------------------------------------------
# Define where the permanent script will live so it isn't accidentally deleted.
$TargetDir = "C:\ProgramData\K2Emulator"
$ScriptPath = "$TargetDir\K2Monitor.ps1"
$TaskName = "K2ProfileEmulator"

# Check if the folder exists. If not, create it silently.
if (-not (Test-Path $TargetDir)) {
    New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
}

# ------------------------------------------------------------------------------
# PART 2: THE CORE ENGINE (C# INSIDE POWERSHELL)
# ------------------------------------------------------------------------------
# We use a literal Here-String (@' ... '@) to hold the C# code. This ensures 
# PowerShell doesn't try to parse any $ symbols or quotes inside the C# logic.
$K2ScriptContent = @"
`$K2Code = @'
using System;
using System.Runtime.InteropServices;
using System.Threading;

public class K2ProfileEmulator
{
    // --- NATIVE WINDOWS API DEFINITIONS (P/INVOKE) ---
    // These lines allow our C# code to call directly into core Windows DLL files
    // bypassing the normal slow command-line tools.

    // 1. Defines the shape of the callback function Windows will use to talk to our app.
    delegate void WinEventDelegate(IntPtr hWinEventHook, uint eventType, IntPtr hwnd, int idObject, int idChild, uint dwEventThread, uint dwmsEventTime);

    // 2. Imports the function used to attach our app to the Windows UI event system.
    [DllImport("user32.dll")]
    static extern IntPtr SetWinEventHook(uint eventMin, uint eventMax, IntPtr hmodWinEventProc, WinEventDelegate lpfnWinEventProc, uint idProcess, uint idThread, uint dwFlags);

    // 3. Imports the function to safely detach our app when it closes.
    [DllImport("user32.dll")]
    static extern bool UnhookWinEvent(IntPtr hWinEventHook);

    // 4. Imports the "Message Pump" functions. Windows requires background apps 
    // to have an active loop checking for messages, otherwise it assumes the app is frozen.
    [DllImport("user32.dll")]
    static extern int GetMessage(out MSG lpMsg, IntPtr hWnd, uint wMsgFilterMin, uint wMsgFilterMax);
    [DllImport("user32.dll")]
    static extern bool TranslateMessage(ref MSG lpMsg);
    [DllImport("user32.dll")]
    static extern IntPtr DispatchMessage(ref MSG lpMsg);

    // 5. Imports the ultra-low-latency Power Management API. This is what replaces powercfg.exe.
    [DllImport("powrprof.dll", EntryPoint = "PowerSetActiveScheme", CharSet = CharSet.Auto)]
    public static extern uint PowerSetActiveScheme(IntPtr UserRootPowerKey, ref Guid SchemeGuid);

    // Defines the exact memory structure Windows expects for UI messages.
    [StructLayout(LayoutKind.Sequential)]
    public struct MSG { public IntPtr hwnd; public uint message; public IntPtr wParam; public IntPtr lParam; public uint time; public int pt_x; public int pt_y; }

    // --- SYSTEM EVENT CONSTANTS ---
    // Event ID 3: Fires when a new window is brought to the front (Alt-Tab, launching an app).
    const uint EVENT_SYSTEM_FOREGROUND = 3;       
    
    // Event ID 6: Fires when a system menu is drawn (Start menu, right-click, taskbar flyouts).
    const uint EVENT_SYSTEM_MENUPOPUPSTART = 6;   
    
    // Tells Windows we want to capture events globally, not just from our own process.
    const uint WINEVENT_OUTOFCONTEXT = 0;

    // --- STATE TRACKING VARIABLES ---
    static WinEventDelegate dele = null; // Holds our callback in memory so it isn't deleted by garbage collection.
    static DateTime lastBoost = DateTime.MinValue; // Tracks the last time we boosted to prevent spamming.
    
    // The exact internal IDs (GUIDs) Windows uses to identify High Performance and Balanced power plans.
    static Guid highPerfGuid = new Guid("8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c");
    static Guid balancedGuid = new Guid("381b4222-f694-41f0-9685-ff5bb260df2e");

    // --- MAIN INITIALIZATION FUNCTION ---
    public static void StartMonitoring()
    {
        // 1. Assign our WinEventProc method as the designated callback.
        dele = new WinEventDelegate(WinEventProc);
        
        // 2. Register the hook with the Windows Kernel. We are asking it to notify us 
        // for everything between EVENT 3 (Foreground) and EVENT 6 (Menu Popups).
        IntPtr hhook = SetWinEventHook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_MENUPOPUPSTART, IntPtr.Zero, dele, 0, 0, WINEVENT_OUTOFCONTEXT);
        
        // 3. Start the Message Pump loop. This keeps the thread alive infinitely 
        // and actively listens for the events we requested.
        MSG msg;
        while (GetMessage(out msg, IntPtr.Zero, 0, 0) != 0)
        {
            TranslateMessage(ref msg);
            DispatchMessage(ref msg);
        }
        
        // 4. Cleanup if the loop ever somehow breaks.
        UnhookWinEvent(hhook);
    }

    // --- THE CALLBACK FUNCTION (Fires when you click something) ---
    static void WinEventProc(IntPtr hWinEventHook, uint eventType, IntPtr hwnd, int idObject, int idChild, uint dwEventThread, uint dwmsEventTime)
    {
        // Cooldown Logic: Check if it has been more than 2.0 seconds since the last boost.
        // This prevents the CPU from thrashing if you rapidly click a menu 10 times.
        if ((DateTime.Now - lastBoost).TotalSeconds > 2.0)
        {
            lastBoost = DateTime.Now; // Update the cooldown timer.
            
            // Queue the power change on a background thread. 
            // If we did this on the main thread, your mouse/UI would freeze for 2 seconds!
            ThreadPool.QueueUserWorkItem(state => BoostCPU());
        }
    }

    // --- THE POWER EXECUTION FUNCTION ---
    static void BoostCPU()
    {
        // 1. Instantly shift hardware to High Performance via kernel API.
        PowerSetActiveScheme(IntPtr.Zero, ref highPerfGuid);
        
        // 2. Hold this state for exactly 2,000 milliseconds (2 seconds) - The "K2 Burst".
        Thread.Sleep(2000); 
        
        // 3. Return hardware to Balanced state to prevent overheating and save power.
        PowerSetActiveScheme(IntPtr.Zero, ref balancedGuid);
    }
}
'@

# Instruct PowerShell to compile the C# code above directly into the active memory session.
Add-Type -TypeDefinition `$K2Code

# Execute the StartMonitoring function, which starts the infinite listener loop.
[K2ProfileEmulator]::StartMonitoring()
"@

# Write this entire assembled script block out to the hard drive.
Set-Content -Path $ScriptPath -Value $K2ScriptContent -Force

# ------------------------------------------------------------------------------
# PART 3: SCHEDULED TASK REGISTRATION
# ------------------------------------------------------------------------------
# Define the exact command line to launch our script silently.
# -WindowStyle Hidden prevents a black box from flashing on screen.
$ArgsString = "-WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""

# Create the specific actions and triggers for the Windows Task Scheduler.
$TaskAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $ArgsString
$TaskTrigger = New-ScheduledTaskTrigger -AtLogon # Start automatically when the user signs in.

# Ensure the task runs as an Administrator (Highest privileges). This is required to change power states.
$TaskPrincipal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -RunLevel Highest

# Configure battery rules so the script doesn't disable itself if you unplug a laptop.
$TaskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Days 365)

# Register all these settings into the actual Windows Task Scheduler.
Register-ScheduledTask -TaskName $TaskName -Action $TaskAction -Trigger $TaskTrigger -Principal $TaskPrincipal -Settings $TaskSettings -Force

# Stop any currently running instances of the script, then start the new one.
Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
Start-ScheduledTask -TaskName $TaskName

Write-Host "Deployment complete! Native API execution is active." -ForegroundColor Green
