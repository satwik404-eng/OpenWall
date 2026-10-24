using System.Runtime.InteropServices;
using System.Text;

namespace OpenWall.Windows;

internal static class NativeDesktop {
    [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] private struct Point { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] private struct MonitorInfo { public int Size; public Rect Monitor, Work; public uint Flags; }
    private delegate bool EnumWindow(nint handle, nint parameter);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern nint FindWindow(string? className, string? title);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern nint FindWindowEx(nint parent, nint after, string? className, string? title);
    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindow callback, nint parameter);
    [DllImport("user32.dll", SetLastError = true)] private static extern nint SetParent(nint child, nint parent);
    [DllImport("user32.dll")] private static extern nint SendMessageTimeout(nint window, uint message, nint wParam, nint lParam, uint flags, uint timeout, out nint result);
    [DllImport("user32.dll")] private static extern int GetWindowLong(nint window, int index);
    [DllImport("user32.dll")] private static extern int SetWindowLong(nint window, int index, int value);
    [DllImport("user32.dll")] private static extern bool SetWindowPos(nint window, nint after, int x, int y, int width, int height, uint flags);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(nint window, out Rect rect);
    [DllImport("user32.dll")] private static extern bool GetClientRect(nint window, out Rect rect);
    [DllImport("user32.dll")] private static extern bool ClientToScreen(nint window, ref Point point);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(nint window);
    [DllImport("user32.dll")] private static extern bool IsIconic(nint window);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(nint window, out uint processId);
    [DllImport("dwmapi.dll")] private static extern int DwmGetWindowAttribute(nint window, uint attribute, out int value, int size);
    [DllImport("user32.dll")] private static extern nint GetForegroundWindow();
    [DllImport("user32.dll")] private static extern nint GetShellWindow();
    [DllImport("user32.dll")] private static extern nint MonitorFromWindow(nint window, uint flags);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern bool GetMonitorInfo(nint monitor, ref MonitorInfo info);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetClassName(nint window, StringBuilder name, int length);
    [DllImport("user32.dll")] public static extern bool IsWindow(nint window);
    [DllImport("user32.dll")] private static extern nint GetAncestor(nint window, uint flags);

    public static nint Attach(Form form, Screen screen) {
        var progman = FindWindow("Progman", null);
        if (progman == 0) throw new InvalidOperationException("Windows Explorer's desktop is not available.");
        // Explorer does not expose a supported live-wallpaper API. This message asks
        // Explorer to create its background WorkerW; compatibility may vary by build.
        SendMessageTimeout(progman, 0x052C, 0xD, 0, 2, 1000, out _);
        SendMessageTimeout(progman, 0x052C, 0xD, 1, 2, 1000, out _);
        nint worker = 0;
        EnumWindows((window, _) => {
            if (FindWindowEx(window, 0, "SHELLDLL_DefView", null) != 0)
                worker = FindWindowEx(0, window, "WorkerW", null);
            return true;
        }, 0);
        if (worker == 0) worker = FindWindowEx(progman, 0, "WorkerW", null);
        if (worker == 0) throw new InvalidOperationException("Explorer did not provide a wallpaper host. Restart Explorer and try again.");
        GetWindowRect(worker, out var host);
        var style = GetWindowLong(form.Handle, -16);
        SetWindowLong(form.Handle, -16, (style & unchecked((int)~0x80000000u)) | 0x40000000);
        Marshal.SetLastPInvokeError(0);
        SetParent(form.Handle, worker);
        if (Marshal.GetLastPInvokeError() != 0) throw new System.ComponentModel.Win32Exception(Marshal.GetLastPInvokeError());
        var bounds = screen.Bounds;
        if (!SetWindowPos(form.Handle, 0, bounds.X - host.Left, bounds.Y - host.Top, bounds.Width, bounds.Height, 0x0010 | 0x0040 | 0x0020))
            throw new InvalidOperationException("The wallpaper window could not be placed on this display.");
        return worker;
    }
    public static bool FullScreenActive() {
        var window = GetForegroundWindow();
        if (window == 0 || window == GetShellWindow()) return false;
        window = GetAncestor(window, 2); // GA_ROOT: a WebView child may belong to the desktop host.
        if (window == 0 || window == GetShellWindow()) return false;
        GetWindowThreadProcessId(window, out var processId);
        var name = new StringBuilder(256); GetClassName(window, name, name.Capacity);
        if (!GetClientRect(window, out var client)) return false;
        var origin = new Point { X = client.Left, Y = client.Top };
        var end = new Point { X = client.Right, Y = client.Bottom };
        if (!ClientToScreen(window, ref origin) || !ClientToScreen(window, ref end)) return false;
        var info = new MonitorInfo { Size = Marshal.SizeOf<MonitorInfo>() };
        if (!GetMonitorInfo(MonitorFromWindow(window, 2), ref info)) return false;
        DwmGetWindowAttribute(window, 14, out var cloaked, sizeof(int)); // DWMWA_CLOAKED
        return FullScreenPolicy.ShouldPause(new(origin.X, origin.Y, end.X, end.Y),
            new(info.Monitor.Left, info.Monitor.Top, info.Monitor.Right, info.Monitor.Bottom),
            name.ToString(), processId == Environment.ProcessId, IsWindowVisible(window),
            IsIconic(window), cloaked != 0, (GetWindowLong(window, -16) & 0x00C00000) == 0x00C00000);
    }
    public static bool DesktopHostAlive(Form form) => IsWindow(form.Handle) && IsWindow(GetAncestor(form.Handle, 1));
}
