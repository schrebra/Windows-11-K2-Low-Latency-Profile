# ==============================================================================
# K2 LOW-LATENCY EMULATOR (NATIVE API OPTIMIZED V3.0 - STEALTH BOOST)
# ==============================================================================

# ------------------------------------------------------------------------------
# PART 1: ENVIRONMENT SETUP & PLAN RESTORATION
# ------------------------------------------------------------------------------
 $TargetDir = "C:\ProgramData\K2Emulator"
 $ScriptPath = "$TargetDir\K2Monitor.ps1"
 $TaskName = "K2ProfileEmulator"

if (-not (Test-Path $TargetDir)) {
    New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
}

Write-Host "Restoring missing default power plans..." -ForegroundColor Cyan
# Force Windows to rebuild the default Balanced, High Performance, and Power Saver plans
powercfg -restoredefaultschemes

# Unhide and restore Ultimate Performance if it's missing
 $ultimatePerfGuid = "e9a42b02-d5df-448d-aa00-03f14749eb61"
 $existingPlans = powercfg -list
if ($existingPlans -notmatch $ultimatePerfGuid) {
    powercfg -duplicatescheme $ultimatePerfGuid
}

# ------------------------------------------------------------------------------
# PART 2: THE CORE ENGINE (C# INSIDE POWERSHELL)
# ------------------------------------------------------------------------------
 $K2ScriptContent = @"
`$K2Code = @'
using System;
using System.Runtime.InteropServices;
using System.Threading;

public class K2ProfileEmulator
{
    // --- NATIVE WINDOWS API DEFINITIONS (P/INVOKE) ---
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

    // --- POWER API P/INVOKE ---
    [DllImport("powrprof.dll", EntryPoint = "PowerGetActiveScheme")]
    public static extern uint PowerGetActiveScheme(IntPtr UserRootPowerKey, out IntPtr ActivePolicyGuid);

    [DllImport("powrprof.dll", EntryPoint = "PowerReadACValueIndex")]
    static extern uint PowerReadACValueIndex(IntPtr RootPowerKey, ref Guid SchemeGuid, ref Guid SubGroupOfPowerSettingsGuid, ref Guid PowerSettingGuid, out uint AcValueIndex);

    [DllImport("powrprof.dll", EntryPoint = "PowerReadDCValueIndex")]
    static extern uint PowerReadDCValueIndex(IntPtr RootPowerKey, ref Guid SchemeGuid, ref Guid SubGroupOfPowerSettingsGuid, ref Guid PowerSettingGuid, out uint DcValueIndex);

    [DllImport("powrprof.dll", EntryPoint = "PowerWriteACValueIndex")]
    static extern uint PowerWriteACValueIndex(IntPtr RootPowerKey, ref Guid SchemeGuid, ref Guid SubGroupOfPowerSettingsGuid, ref Guid PowerSettingGuid, uint AcValueIndex);

    [DllImport("powrprof.dll", EntryPoint = "PowerWriteDCValueIndex")]
    static extern uint PowerWriteDCValueIndex(IntPtr RootPowerKey, ref Guid SchemeGuid, ref Guid SubGroupOfPowerSettingsGuid, ref Guid PowerSettingGuid, uint DcValueIndex);

    [DllImport("kernel32.dll")]
    static extern IntPtr LocalFree(IntPtr hMem);

    [StructLayout(LayoutKind.Sequential)]
    public struct MSG { public IntPtr hwnd; public uint message; public IntPtr wParam; public IntPtr lParam; public uint time; public int pt_x; public int pt_y; }

    // --- SYSTEM EVENT CONSTANTS ---
    const uint EVENT_SYSTEM_FOREGROUND = 3;
    const uint EVENT_SYSTEM_MENUPOPUPSTART = 6;
    const uint WINEVENT_OUTOFCONTEXT = 0;

    // --- STATE TRACKING VARIABLES ---
    static WinEventDelegate dele = null;
    static DateTime lastBoost = DateTime.MinValue;

    // --- PROCESSOR POWER GUIDs ---
    // Subgroup for Processor Power Management
    static Guid procSubGroup = new Guid("54533251-82be-4824-96c1-47b60b740d00");
    // Setting for Minimum Processor State
    static Guid minProcState = new Guid("893dee8e-2bef-41e0-89c6-b55d0929964c");

    // --- MAIN INITIALIZATION FUNCTION ---
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

    // --- THE CALLBACK FUNCTION ---
    static void WinEventProc(IntPtr hWinEventHook, uint eventType, IntPtr hwnd, int idObject, int idChild, uint dwEventThread, uint dwmsEventTime)
    {
        if ((DateTime.Now - lastBoost).TotalSeconds > 2.0)
        {
            lastBoost = DateTime.Now;
            ThreadPool.QueueUserWorkItem(state => BoostCPU());
        }
    }

    // --- THE STEALTH BOOST EXECUTION FUNCTION ---
    static void BoostCPU()
    {
        // 1. Get the currently active power plan (whichever one the user is currently on)
        IntPtr activeSchemePtr;
        PowerGetActiveScheme(IntPtr.Zero, out activeSchemePtr);
        Guid activeScheme = (Guid)Marshal.PtrToStructure(activeSchemePtr, typeof(Guid));
        LocalFree(activeSchemePtr);

        // 2. Save the current Minimum Processor States (AC and DC)
        uint acVal = 0, dcVal = 0;
        bool hasAC = PowerReadACValueIndex(IntPtr.Zero, ref activeScheme, ref procSubGroup, ref minProcState, out acVal) == 0;
        bool hasDC = PowerReadDCValueIndex(IntPtr.Zero, ref activeScheme, ref procSubGroup, ref minProcState, out dcVal) == 0;

        // 3. Temporarily set Minimum Processor State to 100% (The K2 Burst)
        // This forces the CPU to max frequency without changing the active power plan!
        if (hasAC) PowerWriteACValueIndex(IntPtr.Zero, ref activeScheme, ref procSubGroup, ref minProcState, 100);
        if (hasDC) PowerWriteDCValueIndex(IntPtr.Zero, ref activeScheme, ref procSubGroup, ref minProcState, 100);

        // 4. Hold this state for exactly 2,000 milliseconds (2 seconds).
        Thread.Sleep(2000);

        // 5. Restore the original Minimum Processor States so it can downclock to save power
        if (hasAC) PowerWriteACValueIndex(IntPtr.Zero, ref activeScheme, ref procSubGroup, ref minProcState, acVal);
        if (hasDC) PowerWriteDCValueIndex(IntPtr.Zero, ref activeScheme, ref procSubGroup, ref minProcState, dcVal);
    }
}
'@

Add-Type -TypeDefinition `$K2Code

[K2ProfileEmulator]::StartMonitoring()
"@

Set-Content -Path $ScriptPath -Value $K2ScriptContent -Force

# ------------------------------------------------------------------------------
# PART 3: SCHEDULED TASK REGISTRATION
# ------------------------------------------------------------------------------
 $ArgsString = "-WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""

 $TaskAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $ArgsString
 $TaskTrigger = New-ScheduledTaskTrigger -AtLogon

 $TaskPrincipal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -RunLevel Highest

 $TaskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Days 365)

Register-ScheduledTask -TaskName $TaskName -Action $TaskAction -Trigger $TaskTrigger -Principal $TaskPrincipal -Settings $TaskSettings -Force

Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
Start-ScheduledTask -TaskName $TaskName

Write-Host "Deployment complete! Plans restored, flicker eliminated, and Stealth Boost is active." -ForegroundColor Green
