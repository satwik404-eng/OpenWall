import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var preparingQuit = false
    func applicationDidFinishLaunching(_ notification: Notification) { Library.shared.start() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !preparingQuit else { return .terminateLater }
        preparingQuit = true
        Task { @MainActor in
            await Library.shared.freezeDesktopForQuit()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) { Library.shared.shutdown() }
}

@main
struct OpenWallApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        Window("OpenWall", id: "library") {
            LibraryView(library: Library.shared)
        }
        .defaultSize(width: 1120, height: 790)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Import Videos…") { Library.shared.chooseVideos() }.keyboardShortcut("o")
            }
        }
        MenuBarExtra("OpenWall", systemImage: "mountain.2.fill") {
            StatusMenu(library: Library.shared)
        }
    }
}
