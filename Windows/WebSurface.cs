using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace OpenWall.Windows;

internal static class WebSurface {
    public static async Task Configure(WebView2 view, CoreWebView2Environment environment, string media) {
        await view.EnsureCoreWebView2Async(environment);
        var core = view.CoreWebView2;
        core.SetVirtualHostNameToFolderMapping("app.openwall.local", Path.Combine(AppContext.BaseDirectory, "Assets"), CoreWebView2HostResourceAccessKind.DenyCors);
        // The local library draws video frames into a canvas for cached JPEG previews.
        core.SetVirtualHostNameToFolderMapping("media.openwall.local", media, CoreWebView2HostResourceAccessKind.Allow);
        var thumbnails = Path.Combine(Path.GetDirectoryName(media)!, "Thumbnails");
        Directory.CreateDirectory(thumbnails);
        core.SetVirtualHostNameToFolderMapping("thumbnails.openwall.local", thumbnails, CoreWebView2HostResourceAccessKind.DenyCors);
        var quality = Path.Combine(Path.GetDirectoryName(media)!, "VideoQuality"); Directory.CreateDirectory(quality);
        core.SetVirtualHostNameToFolderMapping("quality.openwall.local", quality, CoreWebView2HostResourceAccessKind.DenyCors);
        core.Settings.AreDefaultContextMenusEnabled = false;
        core.Settings.AreDevToolsEnabled = false;
        core.Settings.IsStatusBarEnabled = false;
        core.Settings.IsZoomControlEnabled = false;
        core.Settings.IsBuiltInErrorPageEnabled = false;
        core.Settings.AreBrowserAcceleratorKeysEnabled = false;
        core.NewWindowRequested += (_, e) => e.Handled = true;
        core.PermissionRequested += (_, e) => e.State = CoreWebView2PermissionState.Deny;
        core.NavigationStarting += (_, e) => {
            if (e.Uri != "about:blank" && (!Uri.TryCreate(e.Uri, UriKind.Absolute, out var uri) || uri.Host != "app.openwall.local")) e.Cancel = true;
        };
        core.AddWebResourceRequestedFilter("*", CoreWebView2WebResourceContext.All);
        core.WebResourceRequested += (_, e) => {
            if (Uri.TryCreate(e.Request.Uri, UriKind.Absolute, out var uri)
                && uri.Scheme is "http" or "https" && uri.Host is not ("app.openwall.local" or "media.openwall.local" or "thumbnails.openwall.local" or "quality.openwall.local"))
                e.Response = environment.CreateWebResourceResponse(new MemoryStream(), 403, "External requests are disabled", "Content-Type: text/plain");
        };
    }
}

internal sealed class WallpaperWindow : Form {
    private readonly WebView2 browser = new() { Dock = DockStyle.Fill, DefaultBackgroundColor = Color.Black };
    private bool? lastPaused;
    private double lastSpeed;
    private int lastFPS;
    public string? QualityFilename { get; private set; }
    private readonly Wallpaper wallpaper;
    public string WallpaperId => wallpaper.Id;
    protected override bool ShowWithoutActivation => true;
    protected override CreateParams CreateParams {
        get { var p = base.CreateParams; p.ExStyle |= 0x08000000 | 0x00000080 | 0x00000020; return p; }
    }
    public WallpaperWindow(Wallpaper wallpaper) {
        this.wallpaper = wallpaper;
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false; BackColor = Color.Black;
        Controls.Add(browser);
    }
    public async Task Initialize(CoreWebView2Environment environment, string media, Screen screen, bool paused, double speed, int motionFPS, string? qualityFilename, Action<string> error) {
        QualityFilename = qualityFilename;
        Bounds = screen.Bounds;
        Show();
        NativeDesktop.Attach(this, screen);
        await WebSurface.Configure(browser, environment, media);
        browser.CoreWebView2.WebMessageReceived += (_, e) => {
            using var message = System.Text.Json.JsonDocument.Parse(e.WebMessageAsJson);
            if (message.RootElement.TryGetProperty("error", out var errorValue)) error("Could not play " + wallpaper.Name + ". Try an MP4/H.264 video supported by Windows.");
        };
        var ready = new TaskCompletionSource();
        browser.CoreWebView2.NavigationCompleted += (_, e) => {
            if (e.IsSuccess) ready.TrySetResult();
            else ready.TrySetException(new InvalidOperationException("The local wallpaper renderer could not load."));
        };
        browser.Source = new Uri("https://app.openwall.local/wallpaper.html");
        await ready.Task.WaitAsync(TimeSpan.FromSeconds(20));
        await browser.ExecuteScriptAsync("initializeWallpaper(" + System.Text.Json.JsonSerializer.Serialize(new {
            id = wallpaper.Id, filename = qualityFilename ?? wallpaper.Filename, qualityCopy = qualityFilename is not null, paused, speed, motionFPS
        }) + ")");
        lastPaused = paused; lastSpeed = speed; lastFPS = motionFPS;
    }
    public async Task SetPlayback(bool paused, double speed, int motionFPS) {
        if (lastPaused == paused && lastSpeed == speed && lastFPS == motionFPS) return;
        await browser.ExecuteScriptAsync($"setPlayback({(paused ? "true" : "false")}, {speed.ToString(System.Globalization.CultureInfo.InvariantCulture)}, {motionFPS})");
        lastPaused = paused; lastSpeed = speed; lastFPS = motionFPS;
    }
    public async Task CaptureImage(string path) {
        await using var stream = File.Create(path);
        await browser.CoreWebView2.CapturePreviewAsync(CoreWebView2CapturePreviewImageFormat.Png, stream);
    }
}
