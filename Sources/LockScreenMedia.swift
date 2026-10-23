import AppKit
import AVFoundation
import CoreImage
import SwiftUI
import VideoToolbox

struct LockScreenMedia: Sendable, Codable {
    let id: String
    let movie: URL
    let poster: URL
}

enum LockScreenFailure: LocalizedError {
    case unavailable(String)
    var errorDescription: String? { if case .unavailable(let reason) = self { return reason }; return nil }
}

@MainActor enum LockScreenRenderer {
    static var root: URL { Storage.root.appendingPathComponent("LockScreen", isDirectory: true) }

    static func poster(for item: Wallpaper) async throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let image: CGImage
        if let filename = item.filename {
            let asset = AVURLAsset(url: Storage.media.appendingPathComponent(filename))
            let duration = try await asset.load(.duration).seconds
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 2560, height: 2560)
            image = try await generator.image(at: CMTime(seconds: min(1, duration * 0.1), preferredTimescale: 600)).image
        } else {
            image = try motionFrame(item.id, time: 1.7, width: 1920, height: 1080)
        }
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
            throw LockScreenFailure.unavailable("Could not create a thumbnail from this wallpaper.")
        }
        let url = root.appendingPathComponent(item.id + "-poster.jpg")
        try data.write(to: url, options: .atomic)
        return url
    }

    static func motionFrame(_ id: String, time: Double, width: Int, height: Int) throws -> CGImage {
        let renderer = ImageRenderer(content: MotionArtwork(preset: id, fixedTime: time).frame(width: CGFloat(width), height: CGFloat(height)))
        renderer.scale = 1
        guard let image = renderer.cgImage else { throw LockScreenFailure.unavailable("Could not render the motion wallpaper.") }
        return image
    }

    static func prepare(_ item: Wallpaper, poster: URL) async throws -> LockScreenMedia {
        // Each prepared wallpaper has a distinct native asset ID; macOS must not
        // reuse an asset ID for different video bytes.
        let id = UUID().uuidString
        let movie = root.appendingPathComponent(id + ".mov")
        do {
            if let filename = item.filename {
                let source = Storage.media.appendingPathComponent(filename)
                let worker = Task.detached(priority: .utility) { try await NativeMovieEncoder.transcode(source, to: movie) }
                try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
            } else {
                try await encodeMotion(item.id, to: movie)
            }
            try Task.checkCancellation()
            return LockScreenMedia(id: id, movie: movie, poster: poster)
        } catch {
            try? FileManager.default.removeItem(at: movie)
            throw error
        }
    }

    private static func encodeMotion(_ preset: String, to url: URL) async throws {
        let width = 1280, height = 720, fps: Int32 = 24
        // The desktop's waves advance by 2π in about 50 seconds. Bake exactly
        // one cycle so the lock-screen loop has no discontinuity.
        let frames = 1206
        let writer = try NativeMovieEncoder.writer(url, width: width, height: height, fps: fps)
        let input = writer.inputs[0]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ])
        guard writer.startWriting() else { throw writer.error ?? LockScreenFailure.unavailable("Video encoder could not start.") }
        writer.startSession(atSourceTime: .zero)
        let context = CIContext(options: [.cacheIntermediates: false])
        do {
            for frame in 0..<frames {
                try Task.checkCancellation()
                if frame % 6 == 0 { await Task.yield() }
                while !input.isReadyForMoreMediaData {
                    if writer.status == .failed { throw writer.error! }
                    try await Task.sleep(for: .milliseconds(5))
                }
                try autoreleasepool {
                    let image = try motionFrame(preset, time: 1.7 + Double(frame) / Double(frames) * 2 * .pi, width: width, height: height)
                    var buffer: CVPixelBuffer?
                    guard let pool = adaptor.pixelBufferPool,
                          CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer) == kCVReturnSuccess, let buffer else {
                        throw LockScreenFailure.unavailable("Could not allocate a video frame.")
                    }
                    context.render(CIImage(cgImage: image), to: buffer)
                    guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: fps)) else {
                        throw writer.error ?? LockScreenFailure.unavailable("Could not encode a video frame.")
                    }
                }
            }
            input.markAsFinished()
            await writer.finishWriting()
            guard writer.status == .completed else { throw writer.error ?? LockScreenFailure.unavailable("Video encoding did not finish.") }
        } catch { writer.cancelWriting(); throw error }
    }
}

enum NativeMovieEncoder {
    static func writer(_ url: URL, width: Int, height: Int, fps: Int32) throws -> AVAssetWriter {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 6_000_000,
                AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel as String,
                AVVideoAllowFrameReorderingKey: false,
                AVVideoMaxKeyFrameIntervalKey: Int(fps), AVVideoMaxKeyFrameIntervalDurationKey: 1.0
            ]
        ])
        guard writer.canAdd(input) else { throw LockScreenFailure.unavailable("HEVC encoding is unavailable on this Mac.") }
        writer.add(input)
        return writer
    }

    static func transcode(_ source: URL, to destination: URL) async throws {
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw LockScreenFailure.unavailable("The wallpaper has no video track.") }
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let rate = try await track.load(.nominalFrameRate)
        let scale = min(1, 1920 / max(size.width, size.height))
        let width = max(2, Int(size.width * scale / 2) * 2), height = max(2, Int(size.height * scale / 2) * 2)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw LockScreenFailure.unavailable("The wallpaper cannot be decoded for the lock screen.") }
        reader.add(output)
        let writer = try writer(destination, width: width, height: height, fps: Int32(max(1, min(rate, 60))))
        let input = writer.inputs[0]
        input.transform = transform
        guard reader.startReading(), writer.startWriting() else { throw writer.error ?? reader.error ?? LockScreenFailure.unavailable("Video processing could not start.") }
        writer.startSession(atSourceTime: .zero)
        do {
            while let sample = output.copyNextSampleBuffer() {
                try Task.checkCancellation()
                while !input.isReadyForMoreMediaData {
                    guard writer.status == .writing else { throw writer.error ?? LockScreenFailure.unavailable("Video encoding stopped.") }
                    try await Task.sleep(for: .milliseconds(5))
                }
                guard input.append(sample) else { throw writer.error ?? LockScreenFailure.unavailable("Could not encode the wallpaper.") }
            }
            guard reader.status == .completed else { throw reader.error ?? LockScreenFailure.unavailable("Video decoding did not finish.") }
            input.markAsFinished(); await writer.finishWriting()
            guard writer.status == .completed else { throw writer.error ?? LockScreenFailure.unavailable("Video encoding did not finish.") }
        } catch { reader.cancelReading(); writer.cancelWriting(); throw error }
    }
}
