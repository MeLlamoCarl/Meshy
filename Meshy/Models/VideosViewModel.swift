//
//  VideoViewModel.swift
//  Meshy
//
//  Created by Ethan Lipnik on 8/8/22.
//

import AppKit
import AVKit
import Foundation
import SwiftUI

@MainActor
class VideosViewModel: ObservableObject {
    @Published
    var videos: [VideoItem] = []

    let folder: URL
    /// Thumbnails already made, by file path and modification date: the popover reloads the list
    /// every time it opens, and decoding a frame of every (4K) video each time was slow.
    private var thumbnailCache: [String: NSImage] = [:]
    private let thumbnailLock = NSLock()

    struct VideoItem: Identifiable, Hashable {
        var fileUrl: URL
        var id: String

        var thumbnail: NSImage?
    }

    init() {
        folder = AppPaths.videos

        do {
            if !FileManager.default.fileExists(atPath: folder.path) {
                try FileManager.default.createDirectory(
                    at: folder,
                    withIntermediateDirectories: true
                )
            }

            Task(priority: .userInitiated) { [weak self] in
                do {
                    try await self?.getVideos()
                } catch {
                    print(error)
                }
            }
        } catch {
            print(error)
        }
    }

    func getVideos() async throws {
        let contents = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .map { folder.appendingPathComponent($0) }
            .filter { fileUrl in
                let type = UTType(filenameExtension: fileUrl.pathExtension)
                let isVideo = type?.isSubtype(of: .movie) ?? false
                return isVideo
            }
            .compactMap { url -> (URL, String)? in
                let id = url.deletingPathExtension().lastPathComponent
                return (url, id)
            }

        let videos = try await contents
            .concurrentMap { [weak self] video in
                // One unreadable file shouldn't hide every other video.
                let thumbnail = await self?.thumbnail(for: video.0)
                return VideoItem(
                    fileUrl: video.0,
                    id: video.1,
                    thumbnail: thumbnail
                )
            }

        withAnimation { [weak self] in
            self?.videos = videos.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
        }
    }

    @MainActor
    func delete(_ video: VideoItem) throws {
        if let index = videos.firstIndex(of: video) {
            videos.remove(at: index)
        }

        try FileManager.default.trashItem(at: video.fileUrl, resultingItemURL: nil)
        try? FileManager.default.removeItem(at: DesktopSnapshot.videoFrameURL(for: video.fileUrl))
        NotificationCenter.default.post(name: .videosChanged, object: nil)
    }

    func updateWallpaper() {
        Task {
            do {
                try await WallpaperService.shared.start(.video)
            } catch {
                print(error)
            }
        }
    }

    private func thumbnail(for url: URL) async -> NSImage? {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let key = url.path + "|" + String(modified?.timeIntervalSinceReferenceDate ?? 0)
        if let cached = thumbnailLock.withLock({ thumbnailCache[key] }) { return cached }
        guard let image = try? await generateThumbnail(url) else { return nil }
        thumbnailLock.withLock { thumbnailCache[key] = image }
        return image
    }

    private func generateThumbnail(_ url: URL) async throws -> NSImage? {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let asset = AVURLAsset(url: url)

                let assetIG = AVAssetImageGenerator(asset: asset)
                assetIG.appliesPreferredTrackTransform = true
                assetIG.apertureMode = AVAssetImageGenerator.ApertureMode.encodedPixels
                // Shown small: a full-size frame of a 4K video is ~33 MB decoded, and Core
                // Animation keeps another copy while it's on screen (12 videos used ~600 MB).
                assetIG.maximumSize = CGSize(width: 640, height: 640)

                let cmTime = CMTime(seconds: 2, preferredTimescale: 60)
                let thumbnailImageRef: CGImage
                do {
                    thumbnailImageRef = try assetIG.copyCGImage(at: cmTime, actualTime: nil)
                } catch {
                    print("Error: \(error)")
                    continuation.resume(throwing: error)
                    return
                }

                continuation
                    .resume(returning: NSImage(cgImage: thumbnailImageRef, size: .zero))
            }
        }
    }
}

extension Sequence {
    func asyncMap<T>(
        _ transform: (Element) async throws -> T
    ) async rethrows -> [T] {
        var values = [T]()

        for element in self {
            try await values.append(transform(element))
        }

        return values
    }

    func concurrentMap<T>(
        _ transform: @escaping (Element) async throws -> T
    ) async throws -> [T] {
        let tasks = map { element in
            Task {
                try await transform(element)
            }
        }

        return try await tasks.asyncMap { task in
            try await task.value
        }
    }

    func concurrentForEach(
        _ operation: @escaping (Element) async throws -> Void
    ) async throws {
        // A task group automatically waits for all of its
        // sub-tasks to complete, while also performing those
        // tasks in parallel:
        await withThrowingTaskGroup(of: Void.self) { group in
            for element in self {
                group.addTask {
                    try await operation(element)
                }
            }
        }
    }
}
