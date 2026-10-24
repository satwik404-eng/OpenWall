namespace OpenWall.Windows;

internal readonly record struct ScreenRect(int Left, int Top, int Right, int Bottom);

internal static class FullScreenPolicy {
    public static bool ShouldPause(ScreenRect client, ScreenRect monitor, string windowClass,
        bool ownProcess, bool visible, bool minimized, bool cloaked, bool hasCaption) {
        // A maximized window's outer rectangle includes invisible resize borders.
        // Only a visible, external, borderless client covering the display counts.
        if (ownProcess || !visible || minimized || cloaked || hasCaption
            || windowClass is "Progman" or "WorkerW" or "SHELLDLL_DefView"
                or "Shell_TrayWnd" or "Shell_SecondaryTrayWnd") return false;
        if (client.Right <= client.Left || client.Bottom <= client.Top
            || monitor.Right <= monitor.Left || monitor.Bottom <= monitor.Top) return false;
        return client.Left <= monitor.Left + 2 && client.Top <= monitor.Top + 2
            && client.Right >= monitor.Right - 2 && client.Bottom >= monitor.Bottom - 2;
    }
}
