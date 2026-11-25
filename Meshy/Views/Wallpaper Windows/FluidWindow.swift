//
//  FluidWindow.swift
//  Meshy
//
//  Created by Ethan Lipnik on 8/4/22.
//

import Cocoa
import Combine
import SwiftUI

final class FluidWindow: WallpaperWindow {
    lazy var viewModel: FluidViewModel? = nil

    override var wallpaperType: WallpaperType? { .fluid }

    init(screen: NSScreen, selection: FluidSelection) {
        super.init(screen: screen)

        let viewModel = FluidViewModel()
        viewModel.screenID = screenID
        viewModel.shouldUpdateDesktopPicture = true
        let screenSaverView = ScreenSaverView().environmentObject(viewModel)
        contentView = NSHostingView(rootView: screenSaverView)

        self.viewModel = viewModel

        activity.onChange = { [weak viewModel] state in
            viewModel?.isPaused = state.isPaused
            viewModel?.maxFramesPerSecond = state.maxFramesPerSecond
        }

        // New Metal views appear when the mesh restarts (pause, frame rate, editor colors).
        renderScaleObserver = viewModel.objectWillChange.sink { [weak self] _ in
            self?.scheduleRenderScale()
        }
        for name in [NSWindow.didResizeNotification, NSWindow.didChangeBackingPropertiesNotification] {
            NotificationCenter.default.addObserver(forName: name, object: self, queue: .main) { [weak self] _ in
                self?.scheduleRenderScale()
            }
        }
        scheduleRenderScale()

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard self?.viewModel != nil else { return }
            // Read the latest stored selection — the user may have changed it during startup.
            // Colors applied from the Fluid Editor meanwhile stay.
            if !viewModel.hasEditorColors {
                viewModel.apply(WallpaperService.storedSelection(for: screen.uuidString) ?? selection)
            }
            viewModel.setTimer()
        }
    }

    /// Hidden setting `FluidRenderScale` (0.25–1, default 1): draws Fluid at that fraction of the
    /// screen's pixels and lets the compositor scale it up. Measured on an M1 Pro it saved no GPU
    /// (Fluid's cost is per frame, not per pixel) and 0.5 makes the grain blotchy, so it's off
    /// by default; kept to try on slow Intel GPUs. MeshGradient's view doesn't offer it, so the
    /// drawable size is set on its MTKViews here.
    static var renderScale: CGFloat {
        let stored = UserDefaults.standard.double(forKey: "FluidRenderScale")
        return stored > 0 ? min(max(stored, 0.25), 1) : 1
    }
    private var renderScaleObserver: AnyCancellable?

    private func scheduleRenderScale() {
        for delay in [0.05, 0.6] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.applyRenderScale()
            }
        }
    }

    private func applyRenderScale() {
        guard let contentView, Self.renderScale < 1 else { return }
        let scale = backingScaleFactor * Self.renderScale
        for view in Self.metalViews(in: contentView) where view.bounds.width > 0 && view.bounds.height > 0 {
            view.autoResizeDrawable = false
            let size = CGSize(width: (view.bounds.width * scale).rounded(), height: (view.bounds.height * scale).rounded())
            if view.drawableSize != size { view.drawableSize = size }
        }
    }

    override func close() {
        renderScaleObserver = nil
        contentView = nil
        viewModel?.destroy()
        viewModel = nil
        super.close()
    }
}
