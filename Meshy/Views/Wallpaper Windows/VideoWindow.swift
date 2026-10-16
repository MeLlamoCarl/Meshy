//
//  VideoWindow.swift
//  Meshy
//
//  Created by Ethan Lipnik on 8/4/22.
//

import AppKit
import AVKit
import PixabayKit

class VideoWindow: WallpaperWindow {
    override var wallpaperType: WallpaperType? { .video }

    private lazy var videoFile: URL? = {
        guard let currentBackgroundVideoFile = UserDefaults.standard
            .string(forKey: "currentBackgroundVideoFile") else { return nil }

        return AppPaths.videos.appendingPathComponent(currentBackgroundVideoFile)
    }()

    private lazy var playerItem: AVPlayerItem? = {
        guard let videoFile else { return nil }

        let asset = AVURLAsset(url: videoFile)
        let playerItem = AVPlayerItem(asset: asset)

        return playerItem
    }()

    private lazy var player: AVQueuePlayer = {
        let player = AVQueuePlayer(playerItem: playerItem)

        player.automaticallyWaitsToMinimizeStalling = true
        player.volume = 0

        return player
    }()

    private lazy var playerLayer: AVPlayerLayer = {
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.frame = contentView?.bounds ?? .zero
        return playerLayer
    }()

    private var playerLooper: AVPlayerLooper!

    override init(screen: NSScreen) {
        super.init(screen: screen)

        contentView?.layer = playerLayer
        player.play()

        if let playerItem {
            playerLooper = AVPlayerLooper(player: player, templateItem: playerItem)
        }

        if let videoFile {
            let screenID = screenID
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let image = self?.imageFromVideo(url: videoFile, at: 2) else { return }
                Task { @MainActor [weak self] in
                    // Skip if this window was already replaced by another wallpaper.
                    guard let self, self.isVisible else { return }
                    do {
                        try await DesktopSnapshot.set(for: screenID) { url in
                            try image.pngWrite(to: url)
                        }
                    } catch {
                        print(error)
                    }
                }
            }
        }
    }

    func imageFromVideo(url: URL, at time: TimeInterval) -> NSImage? {
        let asset = AVURLAsset(url: url)

        let assetIG = AVAssetImageGenerator(asset: asset)
        assetIG.appliesPreferredTrackTransform = true
        assetIG.apertureMode = AVAssetImageGenerator.ApertureMode.encodedPixels

        let cmTime = CMTime(seconds: time, preferredTimescale: 60)
        let thumbnailImageRef: CGImage
        do {
            thumbnailImageRef = try assetIG.copyCGImage(at: cmTime, actualTime: nil)
        } catch {
            print(error, url.path)
            return nil
        }

        return NSImage(cgImage: thumbnailImageRef, size: NSSize(width: 640, height: 480))
    }
}
