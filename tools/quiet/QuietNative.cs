using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

// Windows helpers for the quiet picture run (card #168). Compiled by Add-Type in
// tools/quiet_run.ps1 and tools/quiet_focus_check.ps1. Plain C# 5 so Windows PowerShell 5.1 builds it.
public static class QuietNative
{
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct MONITORINFOEX
    {
        public int cbSize;
        public RECT rcMonitor;
        public RECT rcWork;
        public uint dwFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string szDevice;
    }

    delegate bool MonitorEnumProc(IntPtr monitor, IntPtr dc, ref RECT rect, IntPtr data);
    delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr data);

    [DllImport("user32.dll")] static extern bool EnumDisplayMonitors(IntPtr dc, IntPtr clip, MonitorEnumProc cb, IntPtr data);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool GetMonitorInfo(IntPtr monitor, ref MONITORINFOEX info);
    [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr value);
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindowsProc cb, IntPtr data);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr hwnd, StringBuilder text, int max);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int cx, int cy, uint flags);

    const uint SWP_NOSIZE = 0x0001, SWP_NOMOVE = 0x0002, SWP_NOACTIVATE = 0x0010;
    static readonly IntPtr HWND_BOTTOM = new IntPtr(1);

    /// Real pixels, so the numbers match Godot's window positions. Call once, first.
    public static void MakeDpiAware()
    {
        try { if (SetProcessDpiAwarenessContext(new IntPtr(-4))) return; } catch (Exception) { }
        try { SetProcessDPIAware(); } catch (Exception) { }
    }

    /// One row per monitor: left, top, right, bottom, work left, work top, work right, work bottom, primary (1/0).
    public static int[][] Monitors()
    {
        List<int[]> list = new List<int[]>();
        EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, delegate (IntPtr m, IntPtr dc, ref RECT r, IntPtr d)
        {
            MONITORINFOEX info = new MONITORINFOEX();
            info.cbSize = Marshal.SizeOf(typeof(MONITORINFOEX));
            if (GetMonitorInfo(m, ref info))
            {
                list.Add(new int[] {
                    info.rcMonitor.Left, info.rcMonitor.Top, info.rcMonitor.Right, info.rcMonitor.Bottom,
                    info.rcWork.Left, info.rcWork.Top, info.rcWork.Right, info.rcWork.Bottom,
                    (info.dwFlags & 1) != 0 ? 1 : 0 });
            }
            return true;
        }, IntPtr.Zero);
        return list.ToArray();
    }

    /// The process that owns the window that has keyboard focus now (0 if none).
    public static uint ForegroundPid()
    {
        uint pid;
        GetWindowThreadProcessId(GetForegroundWindow(), out pid);
        return pid;
    }

    /// The window that has keyboard focus now: handle and title.
    public static string ForegroundDescription()
    {
        IntPtr h = GetForegroundWindow();
        StringBuilder sb = new StringBuilder(256);
        GetWindowText(h, sb, sb.Capacity);
        return h.ToInt64() + " \"" + sb + "\"";
    }

    /// Visible top-level windows of these processes: handle, left, top, right, bottom.
    public static long[][] WindowsOf(uint[] pids)
    {
        HashSet<uint> wanted = new HashSet<uint>(pids);
        List<long[]> list = new List<long[]>();
        EnumWindows(delegate (IntPtr h, IntPtr d)
        {
            uint pid;
            GetWindowThreadProcessId(h, out pid);
            RECT r;
            if (wanted.Contains(pid) && IsWindowVisible(h) && GetWindowRect(h, out r))
                list.Add(new long[] { h.ToInt64(), r.Left, r.Top, r.Right, r.Bottom });
            return true;
        }, IntPtr.Zero);
        return list.ToArray();
    }

    /// Moves a window to (x, y) without activating it, resizing it or changing its place in the stack.
    public static bool MoveTo(long hwnd, int x, int y)
    {
        return SetWindowPos(new IntPtr(hwnd), IntPtr.Zero, x, y, 0, 0, SWP_NOSIZE | SWP_NOACTIVATE | 0x0004);
    }

    /// Moves a window to the bottom of the stack without activating it or moving it.
    public static bool SendBehind(long hwnd)
    {
        return SetWindowPos(new IntPtr(hwnd), HWND_BOTTOM, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    }
}
