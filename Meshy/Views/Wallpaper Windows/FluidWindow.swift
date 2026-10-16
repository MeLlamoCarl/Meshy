//
//  FluidWindow.swift
//  Meshy
//
//  Created by Ethan Lipnik on 8/4/22.
//

import Cocoa
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

        viewModel.startGameModeMonitoring()

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard self?.viewModel != nil else { return }
            // Read the latest stored selection — the user may have changed it during startup.
            viewModel.apply(WallpaperService.storedSelection(for: screen.uuidString) ?? selection)
            viewModel.setTimer()
        }
    }

    override func close() {
        contentView = nil
        viewModel?.destroy()
        viewModel = nil
        super.close()
    }
}
