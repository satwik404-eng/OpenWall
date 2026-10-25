using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;
using Microsoft.Win32;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace OpenWall.Windows;

internal static class ScreenSaver {
    [StructLayout(LayoutKind.Sequential)] private struct LastInput { public uint Size, Time; }
    [DllImport("user32.dll")] private static extern bool GetLastInputInfo(ref LastInput input);
    [DllImport("user32.dll", SetLastError = true)] private static extern nint SetParent(nint child, nint parent);
    [DllImport("user32.dll")] private static extern bool GetClientRect(nint window, out NativeDesktop.Rect rect);
    [DllImport("user32.dll")] private static extern int SetWindowLong(nint window, int index, int value);
    [DllImport("user32.dll")] private static extern bool SystemParametersInfo(uint action, uint value, nint parameter, uint flags);
    private static uint InputTime() { var input = new LastInput { Size = (uint)Marshal.SizeOf<LastInput>() }; GetLastInputInfo(ref input); return input.Time; }

    public static void Install() {
        var path = Path.Combine(AppContext.BaseDirectory, "OpenWall.scr");
        if (!File.Exists(path)) throw new FileNotFoundException("Keep OpenWall.scr beside OpenWall.exe in the extracted app folder.");
        using var key = Registry.CurrentUser.OpenSubKey(@"Control Panel\Desktop", true) ?? throw new InvalidOperationException("Screen saver preferences are unavailable.");
        key.SetValue("SCRNSAVE.EXE", path, RegistryValueKind.String);
        key.SetValue("ScreenSaveActive", "1", RegistryValueKind.String);
        key.SetValue("ScreenSaverIsSecure", "1", RegistryValueKind.String);
        SystemParametersInfo(0x0011, 1, 0, 3); // SPI_SETSCREENSAVEACTIVE; keep the user's idle timeout.
        Settings();
    }
    public static void Settings() => Process.Start(new ProcessStartInfo("control.exe", "desk.cpl,,@screensaver") { UseShellExecute = true });

    public static void Run(string[] args) {
        var mode = args.FirstOrDefault()?.ToLowerInvariant() ?? "/c";
        if (mode.StartsWith("/c") || mode.StartsWith("-c")) {
            MessageBox.Show("Choose wallpapers and playlist times in OpenWall. The screen saver displays the current wallpaper on each display. Windows manages password protection.\n\nUse OpenWall Settings to enable the screen saver.", "OpenWall Screen Saver");
            return;
        }
        bool preview = mode.StartsWith("/p") || mode.StartsWith("-p");
        nint parent = 0;
        if (preview) {
            var value = mode.Contains(':') ? mode.Split(':')[1] : args.ElementAtOrDefault(1);
            if (!long.TryParse(value, out var handle) || !NativeDesktop.IsWindow((nint)handle)) return;
            parent = (nint)handle;
        } else if (!mode.StartsWith("/s") && !mode.StartsWith("-s")) return;
        var context = new ApplicationContext();
        var forms = new List<Form>();
        var started = Environment.TickCount64;
        uint input = InputTime();
        var monitor = new System.Windows.Forms.Timer { Interval = 250 };
        monitor.Tick += (_, _) => {
            if (preview) { if (!NativeDesktop.IsWindow(parent)) context.ExitThread(); return; }
            if (Environment.TickCount64 - started < 1500) { input = InputTime(); return; }
            if (InputTime() != input) context.ExitThread();
        };
        var root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "OpenWall");
        var state = new PlaylistModel(Path.Combine(root, "library.json")).State;
        async Task Initialize(Form form, WebView2 web, Screen screen) {
            try {
                var env = await CoreWebView2Environment.CreateAsync(null, Path.Combine(root, "ScreenSaverBrowser"),
                    new CoreWebView2EnvironmentOptions("--autoplay-policy=no-user-gesture-required --disable-background-networking"));
                await WebSurface.Configure(web, env, Path.Combine(root, "Media"));
                var id = state.Assignments.GetValueOrDefault(screen.DeviceName) ?? state.Assignments.OrderBy(p => p.Key).FirstOrDefault().Value ?? "aurora";
                var item = PlaylistModel.Presets.Concat(state.Videos).FirstOrDefault(w => w.Id == id) ?? PlaylistModel.Presets[0];
                web.CoreWebView2.NavigationCompleted += async (_, e) => {
                    if (!e.IsSuccess) return;
                    bool paused = state.PauseOnBattery && SystemInformation.PowerStatus.PowerLineStatus == PowerLineStatus.Offline;
                    await web.ExecuteScriptAsync("initializeWallpaper(" + System.Text.Json.JsonSerializer.Serialize(new { id = item.Id, filename = new VideoQualityCache(Path.Combine(root, "VideoQuality")).CachedName(item, state.VideoQuality.GetValueOrDefault(item.Id)) ?? item.Filename, qualityCopy = new VideoQualityCache(Path.Combine(root, "VideoQuality")).CachedName(item, state.VideoQuality.GetValueOrDefault(item.Id)) is not null, paused, speed = state.Speed, motionFPS = state.MotionFPS }) + ")");
                };
                web.Source = new Uri("https://app.openwall.local/wallpaper.html");
            } catch { /* Keep a black saver on renderer failure; no dialog over the lock screen. */ }
        }
        foreach (var screen in preview ? new[] { Screen.PrimaryScreen! } : Screen.AllScreens) {
            var form = new Form { FormBorderStyle = FormBorderStyle.None, ShowInTaskbar = false, BackColor = Color.Black, Bounds = screen.Bounds, TopMost = !preview };
            var web = new WebView2 { Dock = DockStyle.Fill, DefaultBackgroundColor = Color.Black };
            form.Controls.Add(web); forms.Add(form);
            if (preview) {
                _ = form.Handle;
                SetWindowLong(form.Handle, -16, 0x40000000 | 0x10000000);
                SetParent(form.Handle, parent);
                GetClientRect(parent, out var rect); form.Bounds = new(0, 0, rect.Right, rect.Bottom);
            }
            form.Shown += async (_, _) => await Initialize(form, web, screen);
            form.Show();
        }
        if (!preview) Cursor.Hide();
        monitor.Start();
        try { Application.Run(context); }
        finally {
            monitor.Stop(); monitor.Dispose();
            foreach (var form in forms) form.Dispose();
            if (!preview) Cursor.Show();
        }
    }
}
