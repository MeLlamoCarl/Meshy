//
//  VideosManagementView.swift
//  Meshy
//
//  Created by Ethan Lipnik on 8/5/22.
//

import AVKit
import PixabayKit
import SDWebImage
import SwiftUI

struct VideosManagementView: View {
    @State
    private var selectedCategory: SearchCategory? = .backgrounds

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedCategory: $selectedCategory)
        } detail: {
            VideosView(category: $selectedCategory)
        }
        .navigationTitle("Videos")
        .onAppear(perform: VideoItemView.limitMemoryCache)
        // The previews aren't needed once the window closes (they stay in the disk cache).
        .onDisappear { SDImageCache.shared.clearMemory() }
    }
}

struct VideosManagementView_Previews: PreviewProvider {
    static var previews: some View {
        VideosManagementView()
    }
}
