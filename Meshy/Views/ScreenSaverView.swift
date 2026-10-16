//
//  ScreenSaverView.swift
//  Meshy
//
//  Created by Ethan Lipnik on 7/28/22.
//

import Combine
import MeshKit
import RandomColor
import SwiftUI

struct ScreenSaverView: View {
    @EnvironmentObject
    var viewModel: FluidViewModel
    @Environment(\.colorScheme)
    var colorScheme
    @AppStorage("FWPaletteChangeInterval")
    private var wallpaperPaletteChangeInterval: Double = 60
    @AppStorage("FWAnimationSpeed")
    private var animationSpeed: AnimationSpeed = .normal
    @AppStorage("FWSubdivisions")
    private var wallpaperSubdivisions: Int = 36
    @AppStorage("FWColorScheme")
    private var wallpaperColorScheme: WallpaperColorScheme = .system
    @AppStorage("FWGrainAlpha")
    private var wallpaperGrainAlpha: Double = .init(
        MeshDefaults
            .grainAlpha
    )
    @AppStorage("FWFramerate")
    private var fwFramerate: Int = 30
    @AppStorage("FWCustomSpeed")
    private var customSpeed: Double = 0
    @AppStorage("colorSpace")
    private var colorSpace: ColorSpace = .sRGB

    @State
    private var isStartingUp: Bool = true

    private var grainAlpha: Float {
        viewModel.settingsOverride?.grainAlpha ?? Float(wallpaperGrainAlpha)
    }

    private var subdivisions: Int {
        viewModel.settingsOverride.map { Int($0.subdivisions) } ?? wallpaperSubdivisions
    }

    var animationSpeedRange: ClosedRange<Double> {
        if let speed = viewModel.settingsOverride?.animationSpeed, speed > 0 {
            return speed ... speed * 1.5
        }
        if customSpeed > 0 {
            return customSpeed ... customSpeed * 1.5
        }
        switch animationSpeed {
        case .slow:
            return 8 ... 16
        case .normal:
            return 4 ... 8
        case .fast:
            return 1 ... 2
        }
    }

    var body: some View {
        ZStack {
            if viewModel.isPaused {
                // Static — no animation loop, minimal GPU/CPU usage
                Mesh(
                    colors: viewModel.colors,
                    grainAlpha: grainAlpha,
                    subdivisions: subdivisions,
                    colorSpace: colorSpace.cgColorSpace
                )
                .transition(.opacity)
                .opacity(isStartingUp ? 0 : 1)
            } else {
                Mesh(
                    colors: viewModel.colors,
                    animatorConfiguration: .init(
                        framesPerSecond: fwFramerate,
                        animationSpeedRange: animationSpeedRange,
                        meshRandomizer: viewModel.meshRandomizer
                    ),
                    grainAlpha: grainAlpha,
                    subdivisions: subdivisions,
                    colorSpace: colorSpace.cgColorSpace
                )
                .id(viewModel.meshPreviewID)
                .transition(.opacity)
                .opacity(isStartingUp ? 0 : 1)
                .onAppear {
                    withAnimation(.easeInOut(duration: 3)) {
                        isStartingUp = false
                    }
                }
            }
        }
        // Crossfade long enough to cover Metal view re-initialization (~300ms),
        // eliminating the black flash between static and animated states.
        .animation(.easeInOut(duration: 1.2), value: viewModel.isPaused)
        .ignoresSafeArea()
        .onChange(of: wallpaperPaletteChangeInterval) { newValue in
            viewModel.setTimer(newValue)
        }
        .onChange(of: colorScheme) { _ in
            viewModel.regenerate()
        }
        .overlay(
            Button("New Color") {
                viewModel.regenerate()
            }
            .keyboardShortcut(.space, modifiers: [])
            .hidden()
        )
    }
}

struct ScreenSaverView_Previews: PreviewProvider {
    static var previews: some View {
        ScreenSaverView()
    }
}
