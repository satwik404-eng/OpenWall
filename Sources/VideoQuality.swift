import Foundation
import AppKit
import AVFoundation

enum VideoQuality {
    static let levels = [1080, 1440, 2160]
    static func options(width: Int, height: Int) -> [Int] {
        let edge = min(width, height)
        let available = levels.filter { $0 <= edge }
        return levels.contains(edge) ? available : [0] + available
    }
    static func title(_ level: Int) -> String { level == 0 ? "Original" : level == 2160 ? "4K" : "\(level)p" }
    static func path(id: String, height: Int) -> URL {
        Storage.root.appendingPathComponent("VideoQuality").appendingPathComponent("\(UUID(uuidString: id) != nil ? id : "invalid")-\(levels.contains(height) ? height : 0).mov")
    }
    static func playbackURL(_ item: Wallpaper, quality: Int) -> URL? {
        guard let filename = item.filename else { return nil }
        let source = Storage.media.appendingPathComponent(filename)
        guard quality > 0, let w = item.pixelWidth, let h = item.pixelHeight, quality < min(w, h) else { return source }
        let copy = path(id: item.id, height: quality)
        return FileManager.default.fileExists(atPath: copy.path) ? copy : source
    }
    static func needsCopy(_ item: Wallpaper, quality: Int) -> Bool {
        guard UUID(uuidString: item.id) != nil, levels.contains(quality), let w = item.pixelWidth, let h = item.pixelHeight else { return false }
        return quality < min(w, h) && !FileManager.default.fileExists(atPath: path(id: item.id, height: quality).path)
    }
    static func dimensions(_ url: URL) async throws -> (Int, Int) {
        guard let track = try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first else { return (0, 0) }
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let rect = CGRect(origin: .zero, size: size).applying(transform)
        return (Int(abs(rect.width).rounded()), Int(abs(rect.height).rounded()))
    }
}

/// One encoder at a time, completed files only, 512 MiB per copy and 2 GiB total.
/// Originals live in Media and are never included in cache cleanup.
actor VideoQualityCache {
    static let shared = VideoQualityCache()
    static let maximumFileBytes: Int64 = 512 * 1024 * 1024
    static let maximumBytes: Int64 = 2 * 1024 * 1024 * 1024
    private var encoding = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private func acquire() async {
        if encoding { await withCheckedContinuation { waiters.append($0) } }
        else { encoding = true }
    }
    private func release() {
        if waiters.isEmpty { encoding = false }
        else { waiters.removeFirst().resume() }
    }
    func prepare(_ item: Wallpaper, height: Int, protected: Set<String>) async throws {
        await acquire()
        defer { release() }
        try Task.checkCancellation()
        guard UUID(uuidString: item.id) != nil, let filename = item.filename,
              filename == (filename as NSString).lastPathComponent,
              VideoQuality.options(width: item.pixelWidth ?? 0, height: item.pixelHeight ?? 0).contains(height),
              VideoQuality.needsCopy(item, quality: height) else { return }
        let fm = FileManager.default, destination = VideoQuality.path(id: item.id, height: height)
        let root = destination.deletingLastPathComponent()
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        for stale in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] where stale.lastPathComponent.hasSuffix(".tmp.mov") { try? fm.removeItem(at: stale) }
        let temporary = root.appendingPathComponent(UUID().uuidString + ".tmp.mov")
        defer { try? fm.removeItem(at: temporary) }
        let source = Storage.media.appendingPathComponent(filename)
        let worker = Task.detached(priority: .utility) {
            try await NativeMovieEncoder.transcode(source, to: temporary, shortEdge: height, maximumBytes: Self.maximumFileBytes)
        }
        try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        try Task.checkCancellation()
        let size = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= Self.maximumFileBytes else { throw LockScreenFailure.unavailable("The quality copy exceeds the 512 MB limit. Use Original quality for this video.") }
        var copies = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])
            .filter { $0.pathExtension == "mov" && !$0.lastPathComponent.contains(".tmp.") }
        func bytes(_ file: URL) -> Int64 { Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        var total = copies.reduce(Int64(size)) { $0 + bytes($1) }
        copies.sort { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) < ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
        var protectedFiles = protected
        if let saved = try? Storage.load() {
            for id in saved.assignments.values {
                if let quality = saved.videoQuality[id], quality > 0 { protectedFiles.insert(VideoQuality.path(id: id, height: quality).lastPathComponent) }
            }
        }
        for file in copies where total > Self.maximumBytes && !protectedFiles.contains(file.lastPathComponent) {
            let old = bytes(file); try fm.removeItem(at: file); total -= old
        }
        guard total <= Self.maximumBytes else { throw LockScreenFailure.unavailable("The 2 GB quality cache is in use. Stop another wallpaper or use Original quality.") }
        try fm.moveItem(at: temporary, to: destination)
    }
}

@MainActor extension Library {
    var selectedQualityOptions: [Int] {
        VideoQuality.options(width: selected.pixelWidth ?? 0, height: selected.pixelHeight ?? 0)
    }
    var selectedQuality: Int {
        let saved = state.videoQuality[selected.id] ?? 0
        return selectedQualityOptions.contains(saved) ? saved : selectedQualityOptions.last ?? 0
    }
    func refreshVideoDimensions() async {
        for item in state.videos where item.pixelWidth == nil || item.pixelHeight == nil {
            guard let filename = item.filename,
                  let size = try? await VideoQuality.dimensions(Storage.media.appendingPathComponent(filename)),
                  size.0 > 0, size.1 > 0,
                  let index = state.videos.firstIndex(where: { $0.id == item.id }) else { continue }
            state.videos[index].pixelWidth = size.0; state.videos[index].pixelHeight = size.1
        }
        save()
        for screen in NSScreen.screens {
            if let id = state.assignments[screen.wallpaperID], let item = state.videos.first(where: { $0.id == id }) {
                prepareQualityIfNeeded(item)
            }
        }
    }
    func applyToScreen(_ item: Wallpaper, screen: NSScreen) {
        engine?.apply(item, to: screen, paused: paused, speed: state.speed, motionFPS: state.motionFPS,
                      videoURL: VideoQuality.playbackURL(item, quality: state.videoQuality[item.id] ?? 0))
        prepareQualityIfNeeded(item)
    }
    func setVideoQuality(_ height: Int) {
        let item = selected
        guard item.isVideo, selectedQualityOptions.contains(height) else { return }
        qualityJobs[item.id]?.cancel(); qualityJobs[item.id] = nil
        qualityTokens.removeValue(forKey: item.id); qualityBusy.remove(item.id)
        state.videoQuality[item.id] = height
        save()
        if VideoQuality.needsCopy(item, quality: height) { prepareQualityIfNeeded(item) }
        else { refreshQualityPlayback(item) }
    }
    private func refreshQualityPlayback(_ item: Wallpaper) {
        for screen in NSScreen.screens where state.assignments[screen.wallpaperID] == item.id {
            applyToScreen(item, screen: screen)
        }
    }
    private func prepareQualityIfNeeded(_ item: Wallpaper) {
        let height = state.videoQuality[item.id] ?? 0
        guard qualityJobs[item.id] == nil, VideoQuality.needsCopy(item, quality: height) else { return }
        let token = UUID(); qualityTokens[item.id] = token; qualityBusy.insert(item.id)
        let protected = Set(state.assignments.values.compactMap { id -> String? in
            guard let quality = state.videoQuality[id], quality > 0 else { return nil }
            return VideoQuality.path(id: id, height: quality).lastPathComponent
        })
        qualityJobs[item.id] = Task { [weak self] in
            do {
                try await VideoQualityCache.shared.prepare(item, height: height, protected: protected)
                guard !Task.isCancelled, let self, self.qualityTokens[item.id] == token else { return }
                self.qualityJobs[item.id] = nil; self.qualityTokens.removeValue(forKey: item.id); self.qualityBusy.remove(item.id)
                self.refreshQualityPlayback(item)
            } catch {
                guard let self, self.qualityTokens[item.id] == token else { return }
                self.qualityJobs[item.id] = nil; self.qualityTokens.removeValue(forKey: item.id); self.qualityBusy.remove(item.id)
                if !Task.isCancelled {
                    self.state.videoQuality[item.id] = 0; self.save()
                    self.notice = "Could not prepare \(VideoQuality.title(height)): \(error.localizedDescription) Original quality is available."
                }
            }
        }
    }
}
