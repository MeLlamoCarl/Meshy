//
//  FlowWindow.swift
//  Meshy
//

import Cocoa
import FlowKit
import SwiftUI

final class FlowWindow: WallpaperWindow {
    private(set) var viewModel: FlowViewModel?

    override var wallpaperType: WallpaperType? { .flow }

    init(screen: NSScreen, selection: FlowSelection) {
        super.init(screen: screen)

        let viewModel = FlowViewModel(screenID: screenID)
        // Read the latest stored selection: the user may have changed it while starting.
        viewModel.apply(WallpaperService.storedFlowSelection(for: screen.uuidString) ?? selection)
        contentView = NSHostingView(rootView: FlowWallpaperView().environmentObject(viewModel))
        self.viewModel = viewModel
        activity.onChange = { [weak viewModel] state in
            viewModel?.isPaused = state.isPaused
            viewModel?.maxFramesPerSecond = state.maxFramesPerSecond
        }
    }

    override func close() {
        contentView = nil
        viewModel?.destroy()
        viewModel = nil
        super.close()
    }
}

/// The live Flow filling a wallpaper window.
struct FlowWallpaperView: View {
    @EnvironmentObject
    var viewModel: FlowViewModel
    @AppStorage("FlowFramerate")
    private var framerate: Int = 30

    var body: some View {
        FlowView(
            palette: viewModel.palette,
            settings: viewModel.settings,
            isAnimating: !viewModel.isPaused,
            framesPerSecond: min(max(framerate, 1), viewModel.maxFramesPerSecond),
            grain: 0.012
        )
        .ignoresSafeArea()
    }
}
