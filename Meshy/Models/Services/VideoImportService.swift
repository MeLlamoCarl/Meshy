//
//  VideoImportService.swift
//  Meshy
//

import AppKit
import AVFoundation
import UniformTypeIdentifiers

extension Notification.Name {
    /// Posted when the videos folder changed (import, download, delete).
    static let videosChanged = Notification.Name("videosChanged")
}

/// Imports the user's own videos as wallpapers. Every video ends up as MP4 with H.264 or HEVC
/// video, like Pixabay's downloads, so playback stays hardware-decoded and efficient:
/// MP4/M4V in those codecs is copied as is, MOV in those codecs is re-wrapped without
/// re-encoding, anything else AVFoundation can read is converted to H.264 MP4.
/// The original file is never moved or modified.
@MainActor
final class VideoImportService: ObservableObject {
    static let shared = VideoImportService()

    @Published
    private(set) var isImporting = false

    enum ImportError: LocalizedError {
        case unreadable(String)
        case noVideoTrack(String)
        case conversionFailed(String, String?)

        var errorDescription: String? {
            switch self {
            case let .unreadable(name):
                return "“\(name)” can't be played by macOS."
            case let .noVideoTrack(name):
                return "“\(name)” has no video."
            case let .conversionFailed(name, reason):
                return "“\(name)” couldn't be converted to MP4." + (reason.map { " \($0)" } ?? "")
            }
        }
    }

    private let folder: URL = AppPaths.videos

    /// Shows an open panel and imports the chosen videos; the first one becomes the wallpaper.
    func presentImportPanel() {
        let panel = NSOpenPanel()
        panel.title = "Import Videos"
        panel.prompt = "Import"
        panel.allowedContentTypes = [.movie]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            let urls = panel.urls
            Task { @MainActor in await self?.importVideos(urls) }
        }
    }

    /// Imports the videos, reports failures, and sets the first imported one as the wallpaper.
    func importVideos(_ urls: [URL], setAsWallpaper: Bool = true) async {
        guard !urls.isEmpty else { return }
        isImporting = true
        defer { isImporting = false }

        var imported: [URL] = []
        var errors: [Error] = []
        for url in urls {
            do {
                imported.append(try await importVideo(url))
            } catch {
                errors.append(error)
            }
        }

        if !imported.isEmpty {
            NotificationCenter.default.post(name: .videosChanged, object: nil)
        }
        if setAsWallpaper, let first = imported.first {
            UserDefaults.standard.set(first.lastPathComponent, forKey: "currentBackgroundVideoFile")
            try? await WallpaperService.shared.start(.video)
        }
        if !errors.isEmpty {
            showErrors(errors)
        }
    }

    /// Imports one video and returns its URL in the videos folder.
    func importVideo(_ url: URL) async throws -> URL {
        let name = url.lastPathComponent
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let asset = AVURLAsset(url: url)
        guard (try? await asset.load(.isPlayable)) == true else { throw ImportError.unreadable(name) }
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw ImportError.noVideoTrack(name)
        }

        let codec = try await track.load(.formatDescriptions).first.map(CMFormatDescriptionGetMediaSubType)
        let isEfficientCodec = codec == kCMVideoCodecType_H264 || codec == kCMVideoCodecType_HEVC
        let isMP4 = ["mp4", "m4v"].contains(url.pathExtension.lowercased())

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = uniqueDestination(for: url.deletingPathExtension().lastPathComponent)

        if UserDefaults.standard.bool(forKey: "shouldEnableVWCompression") {
            // Settings → Video → Download Compression: same HEVC conversion as Pixabay downloads.
            let converted = try await VideoDownloadService().convert(url)
            if converted == url {
                try FileManager.default.copyItem(at: url, to: destination)
            } else {
                try FileManager.default.moveItem(at: converted, to: destination)
            }
        } else if isMP4 && isEfficientCodec {
            try FileManager.default.copyItem(at: url, to: destination)
        } else {
            let preset = isEfficientCodec ? AVAssetExportPresetPassthrough : AVAssetExportPresetHighestQuality
            try await export(asset, preset: preset, to: destination, name: name)
        }
        return destination
    }

    private func export(_ asset: AVURLAsset, preset: String, to destination: URL, name: String) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw ImportError.conversionFailed(name, nil)
        }
        session.outputURL = destination
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true

        await withCheckedContinuation { continuation in
            session.exportAsynchronously { continuation.resume() }
        }
        guard session.status == .completed else {
            try? FileManager.default.removeItem(at: destination)
            throw ImportError.conversionFailed(name, session.error?.localizedDescription)
        }
    }

    /// "<name>.mp4", or "<name> 2.mp4", "<name> 3.mp4"… if taken.
    private func uniqueDestination(for baseName: String) -> URL {
        var candidate = folder.appendingPathComponent(baseName).appendingPathExtension("mp4")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(baseName) \(counter)").appendingPathExtension("mp4")
            counter += 1
        }
        return candidate
    }

    private func showErrors(_ errors: [Error]) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = errors.count == 1 ? "Couldn't import the video" : "Couldn't import \(errors.count) videos"
        alert.informativeText = errors.map(\.localizedDescription).joined(separator: "\n")
        alert.alertStyle = .warning
        alert.runModal()
    }
}
