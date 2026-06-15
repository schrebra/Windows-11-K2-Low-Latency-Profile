# 1. Define paths
$TargetDir = "C:\ProgramData\K2Emulator"
$ScriptPath = "$TargetDir\K2Monitor.ps1"
$TaskName = "K2ProfileEmulator"

# Create the directory if it doesn't exist
if (-not (Test-Path $TargetDir)) {
    New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
}

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
Write-Host "K2 Monitor script successfully saved to $ScriptPath" -ForegroundColor Green


# 3. Create and Register the Scheduled Task
Write-Host "Creating Windows Scheduled Task..." -ForegroundColor Cyan

# Define the action: Launch powershell silently in the background
$TaskAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""

# Define the trigger: Fire immediately when your user logs into the desktop
$TaskTrigger = New-ScheduledTaskTrigger -AtLogon

# Define permissions: Run with local Admin rights (Required for powercfg changes)
$TaskPrincipal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -RunLevel Highest

# Define task configurations
$TaskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Days 365)

# Register the task into the OS
Register-ScheduledTask -TaskName $TaskName -Action $TaskAction -Trigger $TaskTrigger -Principal $TaskPrincipal -Settings $TaskSettings -Force

Write-Host "Deployment complete! The K2 profile emulator will now run completely hidden in the background every time you log in." -ForegroundColor Green
Write-Host "To test it right now without logging out, run: Start-ScheduledTask -TaskName '$TaskName'" -ForegroundColor Yellow

Start-ScheduledTask -TaskName 'K2ProfileEmulator'-verbose
