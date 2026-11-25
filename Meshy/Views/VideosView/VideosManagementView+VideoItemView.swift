//
//  VideosManagementView+VideoItemView.swift
//  Meshy
//
//  Created by Ethan Lipnik on 8/5/22.
//

import PixabayKit
import SDWebImage
import SDWebImageSwiftUI
import SwiftUI

extension VideosManagementView {
    struct VideoItemView: View {
        let video: Video

        /// Pixabay's preview images are as big as the video size they belong to (2560×1440 for
        /// "medium", ~15 MB each once decoded, and the grid shows dozens: ~425 MB that stayed in
        /// memory). Take the smallest one and decode it at the size it's shown (the selected
        /// video's preview is the largest, ~380 pt wide).
        static let thumbnailPixelSize = CGSize(width: 768, height: 432)

        /// Decoded images SDWebImage keeps in memory; the disk cache keeps the rest.
        static func limitMemoryCache() {
            SDImageCache.shared.config.maxMemoryCost = 64 * 1024 * 1024
        }

        private var thumbnailURL: URL? {
            video.items[.tiny]?.thumbnail ?? video.thumbnailURL
        }

        var body: some View {
            WebImage(
                url: thumbnailURL,
                options: [.scaleDownLargeImages],
                context: [.imageThumbnailPixelSize: Self.thumbnailPixelSize]
            )
            .resizable()
            .background(Color.secondary)
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}
