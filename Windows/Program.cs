namespace OpenWall.Windows;

internal static class Program {
    [STAThread] static void Main(string[] args) {
        ApplicationConfiguration.Initialize();
        if (args.Length > 0 || string.Equals(Path.GetExtension(Environment.ProcessPath), ".scr", StringComparison.OrdinalIgnoreCase)) {
            ScreenSaver.Run(args); return;
        }
        using var mutex = new Mutex(true, "OpenWall.Desktop.1", out bool first);
        if (!first) { MessageBox.Show("OpenWall is already running. Use its tray icon to open the library.", "OpenWall"); return; }
        Application.Run(new LibraryWindow());
    }
}
