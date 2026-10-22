import SwiftUI
import AVKit

let accent = Color(red: 0.66, green: 0.91, blue: 0.68)

struct LibraryView: View {
    @Bindable var library: Library
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().overlay(.white.opacity(0.06))
            VStack(alignment: .leading, spacing: 24) {
                header
                if library.section == "Settings" { settings }
                else if library.section == "Playlist" { PlaylistView(library: library) }
                else { content }
                Spacer(minLength: 0)
                footer
            }
            .padding(30)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.065, green: 0.075, blue: 0.085))
        }
        .frame(minWidth: 900, minHeight: 680)
        .preferredColorScheme(.dark)
        .tint(accent)
        .alert("OpenWall", isPresented: Binding(get: { library.notice != nil }, set: { if !$0 { library.notice = nil } })) {
            Button("OK") { library.notice = nil }
        } message: { Text(library.notice ?? "") }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 30) {
            HStack(spacing: 10) {
                Image(systemName: "mountain.2.fill").font(.system(size: 27)).foregroundStyle(accent)
                Text("OpenWall").font(.system(size: 21, weight: .semibold, design: .rounded)).lineLimit(1).fixedSize()
            }.padding(.top, 12)
            VStack(alignment: .leading, spacing: 7) {
                Text("YOUR SPACE").font(.system(size: 10, weight: .bold)).tracking(2).foregroundStyle(.secondary).padding(.bottom, 8)
                nav("All wallpapers", icon: "square.grid.2x2")
                nav("Motion collection", icon: "sparkles")
                nav("My videos", icon: "film")
                nav("Playlist", icon: "list.bullet.rectangle")
                nav("Settings", icon: "slider.horizontal.3")
            }
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "leaf").foregroundStyle(accent)
                Text("A little more life.\nA space that's yours.").font(.system(size: 14, weight: .medium)).lineSpacing(4)
                Text("Free & open source · MIT\nBuilt for your Mac").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(5)
            }
        }
        .padding(22)
        .frame(width: 225)
        .frame(maxHeight: .infinity)
        .background(Color(red: 0.045, green: 0.052, blue: 0.062))
    }

    private func nav(_ title: String, icon: String) -> some View {
        Button { library.section = title } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).frame(width: 18)
                Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 12)
            .foregroundStyle(library.section == title ? accent : .white.opacity(0.60))
            .background(library.section == title ? accent.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text(library.section == "Settings" ? "Make yourself at home." : "Give your desktop a little life.")
                    .font(.system(size: 27, weight: .semibold, design: .rounded))
                Text(library.section == "Settings" ? "Small preferences. Your way." : "Click a wallpaper to apply it. Build a playlist to keep it changing.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { library.chooseVideos() } label: {
                Label(library.importing ? "Importing…" : "Import videos", systemImage: "plus")
                    .font(.system(size: 12, weight: .semibold)).padding(.horizontal, 14).padding(.vertical, 11)
                    .foregroundStyle(.black).background(accent, in: RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain).disabled(library.importing)
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                HStack {
                    Text(library.section).font(.system(size: 16, weight: .semibold))
                    Text("\(library.filtered.count)").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    Spacer()
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Find a wallpaper", text: $library.search).textFieldStyle(.plain)
                    }
                    .font(.system(size: 12)).padding(9)
                    .frame(width: 185).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
                }
                if library.filtered.isEmpty {
                    ContentUnavailableView(library.search.isEmpty ? "Bring your own view" : "No wallpapers found", systemImage: "film", description: Text(library.search.isEmpty ? "Import an MP4, MOV, or another video macOS can play." : "Try another search."))
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 185), spacing: 16)], spacing: 16) {
                        ForEach(library.filtered) { item in
                            WallpaperCard(item: item, selected: library.selection == item.id,
                                          active: library.state.assignments.values.contains(item.id),
                                          inPlaylist: library.playlistEntry(for: item.id) != nil,
                                          apply: { library.apply(item) }, add: { library.addToPlaylist(item) }, remove: { library.remove(item) })
                        }
                    }
                }
            }
        }.scrollIndicators(.hidden)
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            WallpaperPreview(item: library.selected)
            LinearGradient(colors: [.clear, .black.opacity(0.78)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 8) {
                Text(library.selected.isVideo ? "FROM YOUR LIBRARY" : "THE MOTION COLLECTION")
                    .font(.system(size: 9, weight: .bold)).tracking(2).foregroundStyle(accent)
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(library.selected.name).font(.system(size: 30, weight: .semibold, design: .rounded)).lineLimit(1)
                        Text(library.selected.isVideo ? "Your video. Seamlessly looped. Always local." : "Slow, flowing color. Made entirely from code.")
                            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.70))
                    }
                    Spacer()
                    Button { library.addToPlaylist(library.selected) } label: {
                        Label(library.playlistEntry(for: library.selected.id) == nil ? "Add to playlist" : "In playlist", systemImage: "text.badge.plus").font(.system(size: 12, weight: .semibold)).padding(.horizontal, 14).padding(.vertical, 11)
                            .foregroundStyle(.black).background(accent, in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain)
                        .disabled(library.playlistEntry(for: library.selected.id) != nil)
                }
            }.padding(24)
        }
        .frame(height: 265)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .topTrailing) {
            Text(library.selected.isVideo ? "LOCAL VIDEO" : "GENERATIVE")
                .font(.system(size: 9, weight: .semibold)).tracking(1)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(.black.opacity(0.30), in: Capsule()).padding(16)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Circle().fill(library.state.assignments.isEmpty || library.paused ? .gray : accent).frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 3) {
                Text(library.status).font(.system(size: 11, weight: .medium))
                Text("\(library.displays.count) display\(library.displays.count == 1 ? "" : "s") connected")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Apply to", selection: $library.target) {
                Text("All displays").tag("all")
                ForEach(library.displays) { Text($0.name).tag($0.id) }
            }.font(.system(size: 11)).frame(width: 200)
            Button { library.togglePause() } label: { Image(systemName: library.state.manualPause ? "play.fill" : "pause.fill") }
                .help(library.state.manualPause ? "Resume wallpapers" : "Pause wallpapers")
                .disabled(library.state.assignments.isEmpty)
            Button("Stop") { library.stop() }.help("Remove all OpenWall wallpapers and reveal the desktop underneath")
        }
        .padding(.top, 12)
        .overlay(alignment: .top) { Divider() }
    }

    private var settings: some View {
        Form {
            Section("Playback") {
                Toggle("Pause in full screen", isOn: $library.state.pauseInFullScreen)
                    .onChange(of: library.state.pauseInFullScreen) { library.settingsChanged() }
                Toggle("Pause on battery power", isOn: $library.state.pauseOnBattery)
                    .onChange(of: library.state.pauseOnBattery) { library.settingsChanged() }
                Picker("Video speed", selection: $library.state.speed) {
                    Text("0.5×").tag(0.5); Text("1×").tag(1.0); Text("1.5×").tag(1.5); Text("2×").tag(2.0)
                }.onChange(of: library.state.speed) { library.settingsChanged() }
                Button("Edit wallpaper playlist") { library.section = "Playlist" }
                Text("Full-screen or display-covering apps pause all wallpapers. Playback resumes when you return, unless another pause setting is active. Videos are muted; display sleep also pauses playback.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Lock screen & screen saver") {
                Button("Install OpenWall screen saver…") { library.installScreenSaver() }
                Button("Open Screen Saver settings") { library.openScreenSaverSettings() }
                Text("Choose OpenWall in macOS Screen Saver settings once. It reads the current wallpaper from your local OpenWall library, including imported videos. Set Require password to Immediately in Lock Screen settings for a protected screen saver. The sign-in prompt and the screen saver are separate OS views.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Your Mac") {
                Toggle("Open at login", isOn: Binding(get: { library.loginEnabled }, set: { library.setLogin($0) }))
                Text("Move OpenWall to Applications before enabling login startup. macOS may ask you to approve it in Login Items.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Local by design") {
                Text("No account, analytics, subscription, or cloud connection. Imported videos are copied into OpenWall’s library; your original files stay where they are.")
                Button("Show local library in Finder") { NSWorkspace.shared.open(Storage.root) }
                Text("OpenWall 1.2 · MIT License\nIndependent software. Not affiliated with Wallper.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
}

struct WallpaperPreview: View {
    let item: Wallpaper
    var body: some View {
        if item.isVideo {
            if let image = NSImage(contentsOf: Storage.thumbnails.appendingPathComponent(item.id + ".jpg")) {
                GeometryReader { geometry in
                    Image(nsImage: image).resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped()
                }
            } else {
                ZStack { Color.black; Image(systemName: "film").font(.largeTitle).foregroundStyle(.secondary) }
            }
        } else { MotionArtwork(preset: item.id) }
    }
}

struct WallpaperCard: View {
    let item: Wallpaper
    let selected: Bool
    let active: Bool
    let inPlaylist: Bool
    let apply: () -> Void
    let add: () -> Void
    let remove: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
          Button(action: apply) {
            VStack(alignment: .leading, spacing: 9) {
                WallpaperPreview(item: item).frame(height: 105).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .overlay(alignment: .topTrailing) {
                        if active { Image(systemName: "checkmark.circle.fill").foregroundStyle(accent).padding(8) }
                    }
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Text(item.isVideo ? "LOCAL · VIDEO" : "ORIGINAL · MOTION").font(.system(size: 8, weight: .medium)).tracking(1).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if selected { Circle().fill(accent).frame(width: 5, height: 5) }
                }
            }
          }.buttonStyle(.plain).accessibilityLabel("Apply \(item.name)")
          Button(action: add) { Label(inPlaylist ? "In playlist" : "Add to playlist", systemImage: inPlaylist ? "checkmark" : "plus")
                  .font(.system(size: 10, weight: .medium)).foregroundStyle(inPlaylist ? .secondary : accent)
          }.buttonStyle(.plain).disabled(inPlaylist).accessibilityLabel("Add \(item.name) to playlist")
        }.padding(8)
        .background(selected ? .white.opacity(0.045) : .clear, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(selected ? accent.opacity(0.7) : .white.opacity(0.07), lineWidth: 1) }
        .contextMenu { if item.isVideo { Button("Remove from OpenWall", role: .destructive, action: remove) } }
    }
}

struct StatusMenu: View {
    let library: Library
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(library.status)
        Button("Open OpenWall") { openWindow(id: "library"); NSApp.activate(ignoringOtherApps: true) }
        Divider()
        Button(library.state.manualPause ? "Resume wallpapers" : "Pause wallpapers") { library.togglePause() }
        Button("Next in playlist") { library.nextInPlaylist() }.disabled(!library.hasPlaylistPlayback)
        Button("Stop all wallpapers") { library.stop() }.disabled(library.state.assignments.isEmpty)
        Divider()
        Button("Quit OpenWall") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
