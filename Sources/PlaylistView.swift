import SwiftUI

struct PlaylistView: View {
    let library: Library
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your wallpaper playlist").font(.title2.bold())
                    Text("Each wallpaper gets its own timer. The list repeats in order.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Start playlist") { library.startPlaylist() }.disabled(library.state.playlist.isEmpty)
                Button { library.nextInPlaylist() } label: { Image(systemName: "forward.end.fill") }
                    .help("Next in playlist").accessibilityLabel("Next in playlist").disabled(!library.hasPlaylistPlayback)
                Button("Stop playlist") { library.stopPlaylist() }.disabled(!library.hasPlaylistPlayback)
            }
            if library.state.playlist.isEmpty {
                ContentUnavailableView {
                    Label("Make a playlist", systemImage: "list.bullet.rectangle")
                } description: {
                    Text("Use Add to playlist on any wallpaper, or start with your whole library.")
                } actions: {
                    Button("Add all wallpapers") { library.wallpapers.forEach { library.addToPlaylist($0) } }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(library.state.playlist) { entry in
                            PlaylistRow(entry: entry, library: library)
                        }
                    }
                }.scrollIndicators(.hidden)
                PlaylistProgressView(library: library)
                Text("Forever holds until you skip. Timers pause during full screen, sleep, and other playback pauses. Stop playlist keeps the current wallpaper.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct PlaylistRow: View {
    let entry: PlaylistEntry
    let library: Library
    var body: some View {
        let item = library.wallpapers.first { $0.id == entry.wallpaperID }
        let index = library.state.playlist.firstIndex { $0.id == entry.id } ?? 0
        HStack(spacing: 12) {
            Text("\(index + 1)").monospacedDigit().foregroundStyle(.secondary).frame(width: 20)
            Button {
                if let item { library.apply(item) }
            } label: {
                HStack(spacing: 12) {
                    if let item {
                        WallpaperPreview(item: item).frame(width: 70, height: 46)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item?.name ?? "Unavailable wallpaper").font(.system(size: 12, weight: .medium)).lineLimit(1)
                        if library.state.playlistPlayback.values.contains(where: { $0.entryID == entry.id }) {
                            Text("NOW PLAYING").font(.system(size: 8, weight: .semibold)).tracking(1).foregroundStyle(accent)
                        }
                    }
                    Spacer(minLength: 4)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Apply \(item?.name ?? "wallpaper") from playlist")
            Picker("Duration for \(item?.name ?? "wallpaper")", selection: Binding(
                get: { entry.duration }, set: { library.setDuration($0, for: entry.id) }
            )) {
                ForEach(WallpaperDuration.allCases) { Text($0.title).tag($0) }
            }.labelsHidden().frame(width: 135)
            VStack(spacing: 5) {
                Button { library.movePlaylistEntry(entry.id, by: -1) } label: { Image(systemName: "chevron.up") }
                    .disabled(index == 0).accessibilityLabel("Move \(item?.name ?? "wallpaper") up")
                Button { library.movePlaylistEntry(entry.id, by: 1) } label: { Image(systemName: "chevron.down") }
                    .disabled(index == library.state.playlist.count - 1).accessibilityLabel("Move \(item?.name ?? "wallpaper") down")
            }.buttonStyle(.plain)
            Button { library.removeFromPlaylist(entry.id) } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Remove from playlist")
                .accessibilityLabel("Remove \(item?.name ?? "wallpaper") from playlist")
        }
        .padding(12)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct PlaylistProgressView: View {
    let library: Library
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            VStack(alignment: .leading, spacing: 6) {
                ForEach(library.displays) { display in
                    if let progress = library.state.playlistPlayback[display.id] {
                        HStack {
                            Image(systemName: library.paused ? "pause.circle" : "play.circle").foregroundStyle(accent)
                            Text(display.name).fontWeight(.medium)
                            Spacer()
                            if let remaining = library.remainingPlaylistTime(on: display.id) {
                                Text("\(library.paused ? "Paused · " : "Next in ")\(formatted(remaining))").monospacedDigit()
                            } else if progress.remainingSeconds == nil { Text("Forever · skip to continue") }
                        }.font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
    private func formatted(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(ceil(seconds)))
        let hours = total / 3600
        if hours > 0 { return String(format: "%dh %02dm %02ds", hours, (total % 3600) / 60, total % 60) }
        return String(format: "%dm %02ds", total / 60, total % 60)
    }
}
