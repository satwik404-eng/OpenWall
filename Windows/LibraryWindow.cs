using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;
using Microsoft.Win32;
using System.Diagnostics;
using System.Text.Json;

namespace OpenWall.Windows;

internal sealed class LibraryWindow : Form {
    private readonly string root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "OpenWall");
    private readonly WebView2 browser = new() { Dock = DockStyle.Fill, DefaultBackgroundColor = Color.FromArgb(16, 19, 22) };
    private readonly NotifyIcon tray = new();
    private readonly System.Windows.Forms.Timer timer = new() { Interval = 2000 };
    private readonly SemaphoreSlim gate = new(1, 1);
    private readonly Dictionary<string, WallpaperWindow> desktops = [];
    private readonly PlaylistModel model;
    private readonly ThumbnailCache thumbnails;
    private CoreWebView2Environment? environment;
    private bool quitting, sleeping, locked, ready, importing;
    private string target = "all";
    private bool onBattery, fullScreen;
    private string Media => Path.Combine(root, "Media");
    private string[] Connected => Screen.AllScreens.Select(s => s.DeviceName).ToArray();
    private string[] Targets => Connected.Where(id => target == "all" || target == id).ToArray();

    public LibraryWindow() {
        Text = "OpenWall 1.3.0 — Windows";
        Size = new(1120, 780); MinimumSize = new(900, 650);
        StartPosition = FormStartPosition.CenterScreen;
        Icon = Icon.ExtractAssociatedIcon(Environment.ProcessPath!) ?? SystemIcons.Application;
        Directory.CreateDirectory(Media);
        model = new(Path.Combine(root, "library.json"));
        thumbnails = new(Path.Combine(root, "Thumbnails"));
        try { thumbnails.Prune(model.State.Videos.Select(w => w.Id)); } catch (IOException) { } catch (UnauthorizedAccessException) { }
        Controls.Add(browser);
        var menu = new ContextMenuStrip();
        menu.Items.Add("Open OpenWall", null, (_, _) => { Show(); WindowState = FormWindowState.Normal; Activate(); });
        menu.Items.Add("Pause / Resume", null, async (_, _) => await Command("pause"));
        menu.Items.Add("Next in playlist", null, async (_, _) => await Command("next"));
        menu.Items.Add("Stop wallpapers", null, async (_, _) => await Command("stop"));
        menu.Items.Add("Quit OpenWall", null, (_, _) => Quit());
        tray.Icon = Icon; tray.Text = "OpenWall"; tray.ContextMenuStrip = menu; tray.Visible = true;
        tray.DoubleClick += (_, _) => { Show(); Activate(); };
        Shown += async (_, _) => await Initialize();
        FormClosing += (_, e) => { if (!quitting) { e.Cancel = true; Hide(); } };
        timer.Tick += async (_, _) => await Poll();
        SystemEvents.PowerModeChanged += PowerChanged;
        SystemEvents.DisplaySettingsChanged += DisplaysChanged;
        SystemEvents.SessionSwitch += SessionChanged;
    }

    private async Task Initialize() {
        try {
            environment = await CoreWebView2Environment.CreateAsync(null, Path.Combine(root, "Browser"),
                new CoreWebView2EnvironmentOptions("--autoplay-policy=no-user-gesture-required --disable-background-networking"));
            await WebSurface.Configure(browser, environment, Media);
            browser.CoreWebView2.WebMessageReceived += async (_, e) => {
                try {
                    using var document = JsonDocument.Parse(e.WebMessageAsJson);
                    var message = document.RootElement;
                    if (message.TryGetProperty("command", out var command)) {
                        if (command.GetString() == "thumbnail") SaveThumbnail(message);
                        else if (command.GetString() == "thumbnailInvalid") {
                            var id = message.GetProperty("id").GetString();
                            if (id is not null && model.State.Videos.Any(w => w.Id == id)) { thumbnails.Remove(id); SendState(); }
                        }
                        else await Command(command.GetString()!, message);
                    }
                } catch (Exception error) { Report(error, "Reading library message"); }
            };
            browser.Source = new Uri("https://app.openwall.local/index.html");
            UpdatePause();
            // The page ready command restores playback under the command gate.
            // Starting another restore here can create duplicate WebView controllers.
            timer.Start();
            if (model.LoadError is not null) Notice(model.LoadError);
        } catch (WebView2RuntimeNotFoundException) {
            ShowRuntimeHelp();
        } catch (Exception error) { Report(error, "Starting OpenWall"); }
    }

    private void ShowRuntimeHelp() {
        browser.Visible = false;
        var label = new Label { Dock = DockStyle.Top, Height = 110, Padding = new(25), Text = "OpenWall needs Microsoft Edge WebView2 Runtime. Install the Evergreen Runtime from Microsoft, then reopen OpenWall.", ForeColor = Color.White, BackColor = Color.FromArgb(16,19,22) };
        var button = new Button { Dock = DockStyle.Top, Height = 45, Text = "Open Microsoft WebView2 download page" };
        button.Click += (_, _) => Process.Start(new ProcessStartInfo("https://developer.microsoft.com/microsoft-edge/webview2/") { UseShellExecute = true });
        Controls.Add(button); Controls.Add(label);
    }

    private void Notice(string text) {
        if (ready && browser.CoreWebView2 is not null) browser.CoreWebView2.PostWebMessageAsJson(JsonSerializer.Serialize(new { notice = text }));
        else MessageBox.Show(this, text, "OpenWall", MessageBoxButtons.OK, MessageBoxIcon.Information);
    }
    private void Report(Exception error, string operation) {
        var details = operation + Environment.NewLine + error;
        try { File.WriteAllText(Path.Combine(root, "last-error.txt"), details[..Math.Min(details.Length, 8192)]); } catch (IOException) { } catch (UnauthorizedAccessException) { }
        Notice(operation + ": " + error.Message);
    }

    private string Status => model.State.Assignments.Count == 0 ? "Ready when you are"
        : model.State.ManualPause ? "Paused by you" : locked ? "Session locked" : sleeping ? "Display asleep"
        : model.State.PauseOnBattery && onBattery ? "Paused on battery"
        : model.State.PauseInFullScreen && fullScreen ? "Paused in full screen" : "Wallpaper is live";

    private void UpdatePause() {
        onBattery = SystemInformation.PowerStatus.PowerLineStatus == PowerLineStatus.Offline;
        fullScreen = model.State.PauseInFullScreen && NativeDesktop.FullScreenActive();
        model.SetPaused(model.State.ManualPause || sleeping || locked || (model.State.PauseOnBattery && onBattery)
            || (model.State.PauseInFullScreen && fullScreen), Connected);
    }

    private void SendState() {
        if (!ready || browser.CoreWebView2 is null) return;
        model.Checkpoint(); model.Anchor(Connected);
        browser.CoreWebView2.PostWebMessageAsJson(JsonSerializer.Serialize(new {
            state = model.State, wallpapers = model.Wallpapers.Select(w => new {
                w.Id, w.Name, w.Filename, thumbnail = thumbnails.Name(w.Id), thumbnailRevision = thumbnails.Revision(w.Id)
            }), target, status = Status,
            paused = model.Paused, importing, version = "1.3.0 Windows",
            sentAt = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
            displays = Screen.AllScreens.Select((s, i) => new { id = s.DeviceName, name = "Display " + (i + 1) + (s.Primary ? " · Main" : "") })
        }, PlaylistModel.Json));
    }

    private void SaveThumbnail(JsonElement data) {
        if (!data.TryGetProperty("id", out var idValue) || !data.TryGetProperty("jpeg", out var jpegValue)) return;
        var id = idValue.GetString();
        if (id is null || !model.State.Videos.Any(w => w.Id == id)) return;
        try {
            if (thumbnails.Store(id, jpegValue.GetString() ?? "")) SendState();
        } catch (IOException) { } catch (UnauthorizedAccessException) { }
    }

    private async Task Command(string command, JsonElement data = default) {
        if (!await gate.WaitAsync(0)) return;
        try {
            string Arg(string name) => data.ValueKind == JsonValueKind.Object && data.TryGetProperty(name, out var property) ? property.ToString() : "";
            model.Checkpoint();
            switch (command) {
            case "ready": ready = true; break;
            case "import": await ImportVideos(); break;
            case "apply": model.Apply(Arg("id"), Targets); break;
            case "add": model.Add(Arg("id")); break;
            case "addAll": foreach (var item in model.Wallpapers) model.Add(item.Id); break;
            case "duration": model.SetDuration(Arg("id"), int.Parse(Arg("seconds"))); break;
            case "move": model.Move(Arg("id"), int.Parse(Arg("direction"))); break;
            case "removeEntry": model.RemoveEntry(Arg("id")); break;
            case "start":
                if (model.State.Playlist.FirstOrDefault() is { } first) model.Apply(first.WallpaperId, Targets);
                break;
            case "stopPlaylist": foreach (var screen in Targets) model.State.Playback.Remove(screen); break;
            case "next": foreach (var screen in Targets) model.Next(screen); break;
            case "pause": model.State.ManualPause = !model.State.ManualPause; break;
            case "stop": model.State.Playback.Clear(); model.State.Assignments.Clear(); break;
            case "battery": model.State.PauseOnBattery = Arg("value") == "true"; break;
            case "fullscreen": model.State.PauseInFullScreen = Arg("value") == "true"; break;
            case "speed":
                var speed = double.Parse(Arg("value"), System.Globalization.CultureInfo.InvariantCulture);
                if (new[] { 0.5, 1, 1.5, 2 }.Contains(speed)) model.State.Speed = speed;
                break;
            case "target": if (Arg("id") == "all" || Connected.Contains(Arg("id"))) target = Arg("id"); break;
            case "removeVideo": RemoveVideo(Arg("id")); break;
            case "installSaver": ScreenSaver.Install(); break;
            case "saverSettings": ScreenSaver.Settings(); break;
            case "lockImage": await SetLockImage(); break;
            case "quit": Quit(); return;
            }
            UpdatePause();
            await Restore();
        } catch (Exception error) { Report(error, "Updating wallpaper"); }
        finally {
            // A desktop/codec failure must not hide the library or prevent previews.
            if (!quitting) {
                try { model.Save(); SendState(); } catch (Exception error) { Report(error, "Saving library"); }
            }
            gate.Release();
        }
    }

    private async Task ImportVideos() {
        using var picker = new OpenFileDialog { Title = "Import video wallpapers", Multiselect = true,
            Filter = "Video files|*.mp4;*.webm;*.m4v;*.mov|All files|*.*" };
        if (picker.ShowDialog(this) != DialogResult.OK) return;
        importing = true; SendState();
        try {
            foreach (var source in picker.FileNames) {
                var id = Guid.NewGuid().ToString("N"); var name = id + Path.GetExtension(source).ToLowerInvariant();
                await Task.Run(() => File.Copy(source, Path.Combine(Media, name)));
                model.State.Videos.Add(new(id, Path.GetFileNameWithoutExtension(source), name));
            }
        } finally { importing = false; }
    }

    private async Task SetLockImage() {
        var form = Targets.Select(id => desktops.GetValueOrDefault(id)).FirstOrDefault(f => f is not null);
        if (form is null) { Notice("Click a wallpaper first, then choose Use current wallpaper as lock-screen image."); return; }
        var cache = Path.Combine(root, "LockScreen"); Directory.CreateDirectory(cache);
        var path = Path.Combine(cache, Guid.NewGuid().ToString("N") + ".png");
        await form.CaptureImage(path);
        var file = await global::Windows.Storage.StorageFile.GetFileFromPathAsync(path);
        await global::Windows.System.UserProfile.LockScreen.SetImageFileAsync(file);
        foreach (var old in Directory.GetFiles(cache, "*.png").Where(f => f != path)) File.Delete(old);
        Notice("Lock-screen image updated from your current wallpaper. Windows uses a still image on its sign-in screen.");
    }

    private void RemoveVideo(string id) {
        var item = model.State.Videos.FirstOrDefault(w => w.Id == id);
        if (item?.Filename is null) return;
        foreach (var entry in model.State.Playlist.Where(e => e.WallpaperId == id).ToArray()) model.RemoveEntry(entry.Id);
        foreach (var screen in model.State.Assignments.Where(p => p.Value == id).Select(p => p.Key).ToArray()) {
            model.State.Assignments.Remove(screen); model.State.Playback.Remove(screen);
        }
        model.State.Videos.Remove(item);
        thumbnails.Remove(id);
        File.Delete(Path.Combine(Media, item.Filename));
    }

    private async Task Restore() {
        if (environment is null) return;
        var screens = Screen.AllScreens.ToDictionary(s => s.DeviceName);
        foreach (var id in desktops.Keys.ToArray()) {
            if (!screens.ContainsKey(id) || !model.State.Assignments.ContainsKey(id)
                || desktops[id].WallpaperId != model.State.Assignments[id] || !NativeDesktop.DesktopHostAlive(desktops[id])) {
                desktops[id].Dispose(); desktops.Remove(id);
            }
        }
        foreach (var (screenId, id) in model.State.Assignments) {
            if (!screens.TryGetValue(screenId, out var screen)) continue;
            if (!desktops.TryGetValue(screenId, out var form)) {
                var item = model.Wallpapers.FirstOrDefault(w => w.Id == id);
                if (item is null) continue;
                if (item.Filename is not null && !File.Exists(Path.Combine(Media, item.Filename))) continue;
                form = new(item);
                try { await form.Initialize(environment, Media, screen, model.Paused, model.State.Speed, Notice); desktops[screenId] = form; }
                catch { form.Dispose(); throw; }
            }
            await form.SetPlayback(model.Paused, model.State.Speed);
        }
    }

    private async Task Poll() {
        if (quitting || !ready || !await gate.WaitAsync(0)) return;
        try {
            var previousStatus = Status;
            UpdatePause();
            bool advanced = model.Tick(Connected);
            await Restore();
            if (advanced) model.Save();
            if (advanced || previousStatus != Status) SendState();
        } catch (Exception error) { timer.Stop(); Report(error, "Refreshing wallpaper"); }
        finally { gate.Release(); }
    }
    private void PowerChanged(object sender, PowerModeChangedEventArgs e) {
        if (quitting || !IsHandleCreated) return;
        BeginInvoke(async () => { sleeping = e.Mode == PowerModes.Suspend; await Poll(); });
    }
    private void SessionChanged(object sender, SessionSwitchEventArgs e) {
        if (!quitting && IsHandleCreated) BeginInvoke(async () => {
            if (e.Reason == SessionSwitchReason.SessionLock) locked = true;
            if (e.Reason == SessionSwitchReason.SessionUnlock) locked = false;
            await Poll();
        });
    }
    private void DisplaysChanged(object? sender, EventArgs e) {
        if (!quitting && IsHandleCreated) BeginInvoke(async () => { foreach (var form in desktops.Values) form.Dispose(); desktops.Clear(); await Poll(); SendState(); });
    }
    private void Quit() {
        quitting = true; timer.Stop(); model.Checkpoint(); model.Save();
        foreach (var form in desktops.Values) form.Dispose(); desktops.Clear();
        SystemEvents.PowerModeChanged -= PowerChanged;
        SystemEvents.DisplaySettingsChanged -= DisplaysChanged;
        SystemEvents.SessionSwitch -= SessionChanged;
        tray.Visible = false; tray.Dispose();
        Application.Exit();
    }
    protected override void Dispose(bool disposing) {
        if (disposing) { timer.Dispose(); tray.Dispose(); browser.Dispose(); }
        base.Dispose(disposing);
    }
}
