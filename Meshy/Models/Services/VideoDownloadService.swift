//
//  VideoDownloadService.swift
//  Meshy
//
//  Created by Ethan Lipnik on 8/5/22.
//

import AVKit
import Foundation
import PixabayKit
import VideoToolbox

final class VideoDownloadService: ObservableObject {
    @Published
    var downloadingVideos: [Video: State] = [:]

    enum State: Equatable {
        case notStarted(URL? = nil)
        case downloading(Double, URL)
        case processing
        case done(URL? = nil)
        case failed(Error)

        static func == (lhs: VideoDownloadService.State, rhs: VideoDownloadService.State) -> Bool {
            switch (lhs, rhs) {
            case (.notStarted, .notStarted):
                return true
            case (.downloading, .downloading):
                return true
            case (.processing, .processing):
                return true
            case (.done, .done):
                return true
            case (.failed, .failed):
                return true

            default:
                return false
            }
        }
    }

    let folder: URL

    init() {
        folder = AppPaths.videos

        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
    }

    @discardableResult
    func getVideoIsDownloaded(_ video: Video?) -> Bool {
        guard let video,
              !downloadingVideos.contains(where: { $0.key.id == video.id }) else { return false }

        let file = folder.appendingPathComponent("\(video.id).mp4")
        let exists = FileManager.default.fileExists(atPath: file.path)

//        if exists {
//            downloadingVideos[video] = .done(file)
//        }
        return exists
    }

    func delete(_ video: Video) throws {
        downloadingVideos.removeValue(forKey: video)
        let file = folder.appendingPathComponent("\(video.id).mp4")
        try FileManager.default.trashItem(at: file, resultingItemURL: nil)
        try? FileManager.default.removeItem(at: DesktopSnapshot.videoFrameURL(for: file))
        NotificationCenter.default.post(name: .videosChanged, object: nil)
    }

    /// Pixabay's 4K ("large") only where a screen is more than 2560 px across: on smaller screens
    /// a 1920 px video looks the same and is several times cheaper to decode and scale.
    @MainActor
    static func preferredItem(of video: Video) -> Video.Item.VideoItem? {
        let widest = NSScreen.screens.map { $0.frame.width * $0.backingScaleFactor }.max() ?? 0
        let order: [Video.Item] = widest > 2560 ? [.large, .medium] : [.medium, .large]
        return order.lazy.compactMap { video.items[$0] }.first { $0.width > 0 }
    }

    /// Whether this Mac decodes HEVC in hardware (Intel Macs before 2017 do it on the CPU).
    static var decodesHEVCInHardware: Bool {
        VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)
    }

    func download(_ video: Video) async throws {
        guard let url = await Self.preferredItem(of: video)?.url else { throw URLError(.badURL) }

        func updateState(_ state: State) {
            DispatchQueue.main.async { [weak self] in
                self?.downloadingVideos[video] = state
            }
        }

        updateState(.notStarted(url))

        do {
            var downloadRequest = URLRequest(url: url)
            downloadRequest.cachePolicy = .reloadIgnoringCacheData

            // A download task writes to disk as it goes (reading the bytes one by one kept a CPU
            // core busy and the whole video in memory).
            let progress = DownloadProgress { updateState(.downloading($0, url)) }
            let (downloadedFile, _) = try await URLSession.shared.download(for: downloadRequest, delegate: progress)

            let videoFile = FileManager.default.temporaryDirectory
                .appendingPathComponent("video-download-\(video.id).mp4")
            let destinationUrl = folder.appendingPathComponent("\(video.id).mp4")

            if FileManager.default.fileExists(atPath: videoFile.path) {
                try FileManager.default.removeItem(at: videoFile)
            }

            if FileManager.default.fileExists(atPath: destinationUrl.path) {
                try FileManager.default.removeItem(at: destinationUrl)
            }

            try FileManager.default.moveItem(at: downloadedFile, to: videoFile)
            print("Downloaded video", videoFile.path)

            updateState(.processing)

            let convertedFile: URL
            if !UserDefaults.standard.bool(forKey: "shouldEnableVWCompression") {
                convertedFile = videoFile
            } else {
                do {
                    convertedFile = try await convert(videoFile)
                    print("Converted video", convertedFile.path)
                } catch {
                    print(error)
                    convertedFile = videoFile
                }
            }

            try FileManager.default.moveItem(at: convertedFile, to: destinationUrl)

            // Clean up
            try? FileManager.default.removeItem(at: convertedFile)
            try? FileManager.default.removeItem(at: videoFile)

            updateState(.done(destinationUrl))
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .videosChanged, object: nil)
            }
        } catch {
            updateState(.failed(error))
            throw error
        }
    }

    func convert(_ url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)

        let outputUrl = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "output-\(Int(Date().timeIntervalSinceReferenceDate))-\(UUID().uuidString).mp4"
            )

        // HEVC decoded on the CPU costs more than the space it saves.
        guard Self.decodesHEVCInHardware else { return url }
        let preset = AVAssetExportPresetHEVCHighestQuality
        let outFileType = AVFileType.m4v

        let isCompatible = await withCheckedContinuation { continuation in
            AVAssetExportSession.determineCompatibility(
                ofExportPreset: preset,
                with: asset,
                outputFileType: outFileType
            ) { bool in
                continuation.resume(returning: bool)
            }
        }

        guard isCompatible else { return url }

        guard let exporter = AVAssetExportSession(asset: asset, presetName: preset) else {
            print("Unable to create AVAssetExportSession...")

            throw AVError(.sessionNotRunning)
        }

        exporter.shouldOptimizeForNetworkUse = true
        exporter.canPerformMultiplePassesOverSourceMediaData = true
        exporter.outputFileType = outFileType
        exporter.outputURL = outputUrl

        if let track = try await asset.loadTracks(withMediaType: AVMediaType.video).first {
            let bps = try await track.load(.estimatedDataRate)

            let duration = try await asset.load(.duration).seconds

            let fileSize = Double(bps) * duration / 8

            let fileLimit = UserDefaults.standard.integer(forKey: "VWFileLimit")

            if fileLimit != -1 {
                var desiredFileSize = Int64(fileSize)

                if fileLimit > 0 {
                    desiredFileSize = Int64(fileLimit)
                }

                exporter.fileLengthLimit = desiredFileSize
            }
        }

        await exporter.export()

        return outputUrl
    }
}

/// Reports a download task's progress in whole percents.
private final class DownloadProgress: NSObject, URLSessionTaskDelegate {
    private let onProgress: (Double) -> Void
    private var observation: NSKeyValueObservation?
    private var lastPercent = -1

    init(_ onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_: URLSession, didCreateTask task: URLSessionTask) {
        observation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            guard let self else { return }
            let percent = Int(progress.fractionCompleted * 100)
            guard percent != self.lastPercent else { return }
            self.lastPercent = percent
            self.onProgress(progress.fractionCompleted)
        }
    }
}
