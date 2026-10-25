import AppKit
import AVFoundation

enum VideoQualityTests {
    @MainActor static func run() async throws {
        precondition(VideoQuality.options(width: 3840, height: 2160) == [1080,1440,2160])
        precondition(VideoQuality.options(width: 2560, height: 1440) == [1080,1440])
        precondition(VideoQuality.options(width: 2160, height: 3840) == [1080,1440,2160])
        precondition(VideoQuality.options(width: 1920, height: 1080) == [1080])
        precondition(VideoQuality.options(width: 1280, height: 720) == [0])
        let legacy = try JSONDecoder().decode(LibraryState.self, from: Data("{}".utf8))
        precondition(legacy.motionFPS == 60 && legacy.videoQuality.isEmpty)
        let invalid = try JSONDecoder().decode(LibraryState.self, from: Data("{\"motionFPS\":999}".utf8))
        precondition(invalid.motionFPS == 60)
        for fps in [24,60,120] {
            var state = LibraryState(); state.motionFPS = fps; state.videoQuality["fixture"] = 1080
            let copy = try JSONDecoder().decode(LibraryState.self, from: JSONEncoder().encode(state))
            precondition(copy.motionFPS == fps && copy.videoQuality["fixture"] == 1080)
        }
        try Storage.prepare()
        let filename = "quality-fixture.mov", source = Storage.media.appendingPathComponent(filename)
        let writer = try AVAssetWriter(outputURL: source, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 3840, AVVideoHeightKey: 2160])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: 3840, kCVPixelBufferHeightKey as String: 2160])
        writer.add(input); precondition(writer.startWriting()); writer.startSession(atSourceTime: .zero)
        for frame in 0..<6 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var buffer: CVPixelBuffer?
            precondition(CVPixelBufferCreate(kCFAllocatorDefault, 3840, 2160, kCVPixelFormatType_32ARGB, nil, &buffer) == kCVReturnSuccess)
            CVPixelBufferLockBaseAddress(buffer!, [])
            memset(CVPixelBufferGetBaseAddress(buffer!), Int32(30 + frame * 20), CVPixelBufferGetDataSize(buffer!))
            CVPixelBufferUnlockBaseAddress(buffer!, [])
            precondition(adaptor.append(buffer!, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)))
        }
        input.markAsFinished(); await writer.finishWriting(); precondition(writer.status == .completed)
        let item = Wallpaper(id: UUID().uuidString, name: "4K fixture", filename: filename, pixelWidth: 3840, pixelHeight: 2160)
        let original = try Data(contentsOf: source)
        for height in [1080,1440] {
            try await VideoQualityCache.shared.prepare(item, height: height, protected: [])
            let copy = VideoQuality.playbackURL(item, quality: height)!
            precondition(copy != source)
            let size = try await VideoQuality.dimensions(copy)
            precondition(size.0 == height * 16 / 9 && size.1 == height, "Quality copy must have the requested encoded resolution")
            let asset = AVURLAsset(url: copy)
            let playable = try await asset.load(.isPlayable); precondition(playable)
            let audio = try await asset.loadTracks(withMediaType: .audio); precondition(audio.isEmpty)
            let modified = try copy.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            try await VideoQualityCache.shared.prepare(item, height: height, protected: [])
            let reused = try copy.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            precondition(reused == modified)
        }
        precondition(VideoQuality.playbackURL(item, quality: 2160) == source)
        let retained = try Data(contentsOf: source)
        precondition(retained == original)
        print("PASS: 4K fixture produces playable real 1080p/1440p silent copies, reuses cache, preserves source; source-aware options and 24/60/120 persistence/migration")
    }
}
