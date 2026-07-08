# ==============================================================================
# K2 LOW-LATENCY EMULATOR (TIERED AC/DC BOOSTING V4.4 - ULTIMATE BRIGHTNESS LOCK)
# ==============================================================================

# --- AUTO-ELEVATION CHECK ---
$currentUser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "Administrator privileges required. Attempting to restart as Admin..." -ForegroundColor Yellow
    
    $scriptPath = $PSCommandPath
    if (-not $scriptPath) { $scriptPath = $MyInvocation.ScriptName }
    
    if ($scriptPath) {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs
        exit
    } else {
        Write-Warning "Cannot auto-elevate because the script is being pasted directly into the console."
        Write-Warning "Please close this window, right-click the Start Button, select 'Windows PowerShell (Admin)' or 'Terminal (Admin)', and try again."
        exit
    }
}

# ------------------------------------------------------------------------------
# PART 1: ENVIRONMENT SETUP & PLAN RESTORATION
# ------------------------------------------------------------------------------
$TargetDir = "C:\ProgramData\K2Emulator"
$ScriptPath = "$TargetDir\K2Monitor.ps1"
$TaskName = "K2ProfileEmulator"

Write-Host "Stopping existing K2 tasks to prevent file locks..." -ForegroundColor Cyan
$existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2 
}

if (-not (Test-Path $TargetDir)) {
    New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
}

Write-Host "Restoring missing default power plans..." -ForegroundColor Cyan
powercfg -restoredefaultschemes

$powerSaverGuid = "a1841308-3541-4fab-bc81-f71556f20b4a"
$balancedGuid   = "381b4222-f694-41f0-9685-ff5bb260df2e"
$highPerfGuid   = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"

$existingPlans = powercfg -list

if ($existingPlans -notmatch $powerSaverGuid) { powercfg -duplicatescheme $powerSaverGuid }
if ($existingPlans -notmatch $balancedGuid)   { powercfg -duplicatescheme $balancedGuid }
if ($existingPlans -notmatch $highPerfGuid)   { powercfg -duplicatescheme $highPerfGuid }

# ------------------------------------------------------------------------------
# PART 2: THE CORE ENGINE (C# INSIDE POWERSHELL)
# ------------------------------------------------------------------------------
$K2ScriptContent = @"
`$K2Code = @'
using System;
using System.Runtime.InteropServices;
using System.Threading;
using System.Management;
using System.Diagnostics;

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
    [DllImport("powrprof.dll", EntryPoint = "PowerSetActiveScheme")]
    static extern uint PowerSetActiveScheme(IntPtr UserRootPowerKey, ref Guid SchemeGuid);

    [DllImport("powrprof.dll", SetLastError = true)]
    static extern uint PowerGetActiveScheme(IntPtr UserRootPowerKey, out IntPtr ActivePolicyGuid);

    [DllImport("powrprof.dll", SetLastError = true)]
    static extern uint PowerReadACValueIndex(IntPtr RootPowerKey, ref Guid SchemeGuid, ref Guid SubGroupOfPowerSettings, ref Guid PowerSettingGuid, out uint AcValueIndex);

    [DllImport("powrprof.dll", SetLastError = true)]
    static extern uint PowerReadDCValueIndex(IntPtr RootPowerKey, ref Guid SchemeGuid, ref Guid SubGroupOfPowerSettings, ref Guid PowerSettingGuid, out uint DcValueIndex);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr LocalFree(IntPtr hMem);

    // --- LAPTOP BATTERY CHECK API ---
    [DllImport("kernel32.dll")]
    static extern bool GetSystemPowerStatus(ref SYSTEM_POWER_STATUS lpSystemPowerStatus);

    [StructLayout(LayoutKind.Sequential)]
    public struct SYSTEM_POWER_STATUS
    {
        public byte ACLineStatus;
        public byte BatteryFlag;
        public byte BatteryLifePercent;
        public byte SystemStatusFlag;
        public uint BatteryLifeTime;
        public uint BatteryFullLifeTime;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MSG { public IntPtr hwnd; public uint message; public IntPtr wParam; public IntPtr lParam; public uint time; public int pt_x; public int pt_y; }

    // --- SYSTEM EVENT CONSTANTS ---
    const uint EVENT_SYSTEM_FOREGROUND = 3;
    const uint EVENT_SYSTEM_MENUPOPUPSTART = 6;
    const uint WINEVENT_OUTOFCONTEXT = 0;

    // --- STATE TRACKING VARIABLES ---
    static WinEventDelegate dele = null;
    static DateTime lastBoost = DateTime.MinValue;
    
    static bool currentDetectedAC = false;
    static bool lastAppliedAC = false;
    static bool isBoosting = false;
    static bool initialized = false;
    static int lastSyncedBrightness = -1;

    // --- POWER PLAN GUIDs ---
    static Guid powerSaverGuid = new Guid("a1841308-3541-4fab-bc81-f71556f20b4a");
    static Guid balancedGuid   = new Guid("381b4222-f694-41f0-9685-ff5bb260df2e");
    static Guid highPerfGuid   = new Guid("8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c");

    // --- BRIGHTNESS GUIDs ---
    static Guid SUB_VIDEO = new Guid("7516b95f-f776-4464-8c53-06167f40cc99");
    static Guid VIDEONORMALLEVEL = new Guid("aded5e82-b909-4619-9949-f5d71dac0bcb");

    // --- MAIN INITIALIZATION FUNCTION ---
    public static void StartMonitoring()
    {
        Thread pollingThread = new Thread(PollPowerStatus);
        pollingThread.IsBackground = true;
        pollingThread.Start();

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

    static void PollPowerStatus()
    {
        while (true)
        {
            UpdatePowerState();
            Thread.Sleep(3000); 
        }
    }

    // --- ADVANCED BRIGHTNESS MANAGEMENT ---
    static Guid GetActiveSchemeGuid()
    {
        try
        {
            IntPtr pGuid;
            uint res = PowerGetActiveScheme(IntPtr.Zero, out pGuid);
            if (res == 0 && pGuid != IntPtr.Zero)
            {
                Guid guid = (Guid)Marshal.PtrToStructure(pGuid, typeof(Guid));
                LocalFree(pGuid);
                return guid;
            }
        }
        catch { }
        return Guid.Empty;
    }

    static int GetBrightness()
    {
        try
        {
            using (var searcher = new ManagementObjectSearcher("root\\wmi", "SELECT CurrentBrightness FROM WmiMonitorBrightness"))
            {
                foreach (ManagementObject obj in searcher.Get())
                {
                    return Convert.ToInt32(obj["CurrentBrightness"]);
                }
            }
        }
        catch { }
        return -1;
    }

    static int GetActivePlanBrightness()
    {
        try
        {
            Guid activeGuid = GetActiveSchemeGuid();
            if (activeGuid == Guid.Empty) return -1;

            SYSTEM_POWER_STATUS status = new SYSTEM_POWER_STATUS();
            GetSystemPowerStatus(ref status);
            bool isAC = (status.ACLineStatus == 1);

            uint val = 0;
            uint res;
            if (isAC)
            {
                res = PowerReadACValueIndex(IntPtr.Zero, ref activeGuid, ref SUB_VIDEO, ref VIDEONORMALLEVEL, out val);
            }
            else
            {
                res = PowerReadDCValueIndex(IntPtr.Zero, ref activeGuid, ref SUB_VIDEO, ref VIDEONORMALLEVEL, out val);
            }

            if (res == 0)
            {
                return (int)val;
            }
        }
        catch { }
        return -1;
    }

    static int GetTargetBrightness()
    {
        int planBrightness = GetActivePlanBrightness();
        if (planBrightness >= 0 && planBrightness <= 100) return planBrightness;
        return GetBrightness();
    }

    static void SetBrightness(int brightness)
    {
        if (brightness < 0 || brightness > 100) return;
        try
        {
            using (var searcher = new ManagementObjectSearcher("root\\wmi", "SELECT * FROM WmiMonitorBrightnessMethods"))
            {
                foreach (ManagementObject obj in searcher.Get())
                {
                    obj.InvokeMethod("WmiSetBrightness", new object[] { (uint)0, (byte)brightness });
                    break;
                }
            }
        }
        catch { }
    }

    static void SyncAllPlansBrightness(int brightness)
    {
        if (brightness == lastSyncedBrightness) return;
        if (brightness < 0 || brightness > 100) return;
        
        string[] guids = {
            "a1841308-3541-4fab-bc81-f71556f20b4a",
            "381b4222-f694-41f0-9685-ff5bb260df2e",
            "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
        };
        string subVideo = "7516b95f-f776-4464-8c53-06167f40cc99";
        string vidNorm = "aded5e82-b909-4619-9949-f5d71dac0bcb";

        foreach (string guid in guids)
        {
            RunPowercfg(`$"-setacvalueindex {guid} {subVideo} {vidNorm} {brightness}");
            RunPowercfg(`$"-setdcvalueindex {guid} {subVideo} {vidNorm} {brightness}");
        }
        
        lastSyncedBrightness = brightness;
    }

    static void RunPowercfg(string args)
    {
        try 
        {
            var psi = new System.Diagnostics.ProcessStartInfo("powercfg.exe", args);
            psi.CreateNoWindow = true;
            psi.UseShellExecute = false;
            psi.RedirectStandardOutput = true;
            psi.RedirectStandardError = true;
            using (var proc = System.Diagnostics.Process.Start(psi))
            {
                proc.WaitForExit(2000);
            }
        }
        catch { }
    }

    // --- DYNAMIC BASE PLAN SWITCHING LOGIC ---
    static void UpdatePowerState()
    {
        SYSTEM_POWER_STATUS status = new SYSTEM_POWER_STATUS();
        if (GetSystemPowerStatus(ref status))
        {
            currentDetectedAC = (status.ACLineStatus == 1);
        }
        
        if (currentDetectedAC != lastAppliedAC || !initialized)
        {
            initialized = true;
            if (!isBoosting)
            {
                lastAppliedAC = currentDetectedAC;
                
                int currentBrightness = GetTargetBrightness();
                SyncAllPlansBrightness(currentBrightness);

                if (currentDetectedAC)
                {
                    PowerSetActiveScheme(IntPtr.Zero, ref balancedGuid);
                }
                else
                {
                    PowerSetActiveScheme(IntPtr.Zero, ref powerSaverGuid);
                }
                
                SetBrightness(currentBrightness);
            }
        }
    }

    // --- THE CALLBACK FUNCTION (WINDOW FOCUS) ---
    static void WinEventProc(IntPtr hWinEventHook, uint eventType, IntPtr hwnd, int idObject, int idChild, uint dwEventThread, uint dwmsEventTime)
    {
        if ((DateTime.Now - lastBoost).TotalSeconds > 2.0 && !isBoosting)
        {
            lastBoost = DateTime.Now;
            ThreadPool.QueueUserWorkItem(state => BoostCPU());
        }
    }

    // --- THE TIERED BOOST EXECUTION FUNCTION ---
    static void BoostCPU()
    {
        isBoosting = true;
        
        int currentBrightness = GetTargetBrightness();
        SyncAllPlansBrightness(currentBrightness);

        Guid boostTarget = currentDetectedAC ? highPerfGuid : balancedGuid;
        Guid revertTarget = currentDetectedAC ? balancedGuid : powerSaverGuid;

        PowerSetActiveScheme(IntPtr.Zero, ref boostTarget);
        SetBrightness(currentBrightness);
        
        Thread.Sleep(2000);
        
        PowerSetActiveScheme(IntPtr.Zero, ref revertTarget);
        SetBrightness(currentBrightness);
        
        isBoosting = false;
    }
}
'@

if (-not ("K2ProfileEmulator" -as [type])) {
    try { Add-Type -AssemblyName "System.Management" -ErrorAction SilentlyContinue } catch {}
    Add-Type -TypeDefinition `$K2Code -ReferencedAssemblies "System.Management" -ErrorAction SilentlyContinue
}

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

Write-Host "K2 Tiered Optimization Active (Ultimate Brightness Lock)" -ForegroundColor Green
Write-Host "- Brightness is now perfectly synced across all power plans." -ForegroundColor Yellow
Write-Host "- Battery Base: Power Saver | Window Boost: Balanced" -ForegroundColor Yellow
Write-Host "- Plugged In Base: Balanced | Window Boost: High Performance" -ForegroundColor Cyan
