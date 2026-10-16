//
//  ContentView+OptionsView.swift
//  Meshy
//
//  Created by Ethan Lipnik on 8/8/22.
//

import MeshKit
import SwiftUI

extension ContentView {
    struct OptionsView: View {
        @Binding
        var selectedWallpaper: WallpaperType?
        @EnvironmentObject
        var wallpaperService: WallpaperService
        @StateObject
        var videosViewModel = VideosViewModel()
        @AppStorage("currentBackgroundVideoFile")
        var currentBackgroundVideoFile: String = ""
        @ObservedObject
        private var mouseMonitor = MouseMonitor.shared
        @ObservedObject
        private var importService = VideoImportService.shared
        @State
        private var isHoldingRandomizeButton: Bool = false
        @State
        private var customWallpapers: [CustomWallpaperConfig] = []

        var selectedHue: Hue? { wallpaperService.targetSelection.hue }
        var selectedCustomID: UUID? { wallpaperService.targetSelection.customID }
        var isRandomSelected: Bool { isFluid && wallpaperService.targetSelection == .random }
        /// Mouse wheels can't scroll sideways: with a mouse, reveal the native scroll bar on hover.
        var revealsScroller: Bool { mouseMonitor.isExternalMouseConnected }

        let popoverNotification = NotificationCenter.default
            .publisher(for: NSNotification.Name("didOpenStatusBarItem"))
        let customWallpapersChanged = NotificationCenter.default
            .publisher(for: .customWallpapersChanged)

        var isFluid: Bool {
            selectedWallpaper == .fluid
        }

        var body: some View {
            VStack(spacing: 0) {
                // Presets section header
                HStack {
                    Text("Presets")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    if isFluid && wallpaperService.screens.count > 1 {
                        screenPicker
                    }
                }
                .padding(.horizontal)
                .padding(.top, 6)
                .background { Color.black.opacity(0.5).blendMode(.overlay) }

                // Main presets row
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .center) {
                        randomizeButton

                        switch selectedWallpaper {
                        case .fluid:
                            ForEach(Hue.presetCases, id: \.self) { hue in
                                PalettePresetItem(hue: hue, isSelected: selectedHue == hue)
                                    .onTapGesture {
                                        guard !wallpaperService.isLoading else { return }
                                        wallpaperService.selectForTarget(.hue(hue))
                                    }
                            }

                        case .video:
                            ForEach(videosViewModel.videos) { video in
                                videoThumbnail(video)
                                        .aspectRatio(16 / 10, contentMode: .fit)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        .overlay(
                                            currentBackgroundVideoFile == video.fileUrl.lastPathComponent
                                                ? RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                    .stroke(Color.accentColor, lineWidth: 4)
                                                : nil
                                        )
                                        .contextMenu {
                                            Button(role: .destructive) {
                                                withAnimation {
                                                    try? videosViewModel.delete(video)
                                                    if currentBackgroundVideoFile == video.fileUrl.lastPathComponent {
                                                        currentBackgroundVideoFile = videosViewModel.videos.first?.fileUrl.lastPathComponent ?? ""
                                                        videosViewModel.updateWallpaper()
                                                    }
                                                }
                                            } label: {
                                                Label("Move to Trash", systemImage: "trash")
                                            }
                                        }
                                        .shadow(radius: 8, y: 8)
                                        .onTapGesture {
                                            currentBackgroundVideoFile = video.fileUrl.lastPathComponent
                                            videosViewModel.updateWallpaper()
                                        }
                            }
                            importVideoButton
                        case .none:
                            EmptyView()
                        }
                    }
                    .padding()
                    .horizontalWheelScrolling(revealsScroller: revealsScroller)
                }
                .frame(height: 86)
                .background { Color.black.opacity(0.5).blendMode(.overlay) }

                // Customs row (fluid only, when customs exist)
                if isFluid && !customWallpapers.isEmpty {
                    Divider()
                    customsRow
                }
            }
            .onReceive(popoverNotification) { _ in
                loadCustomWallpapers()
                Task(priority: .userInitiated) {
                    do {
                        try await videosViewModel.getVideos()
                    } catch {
                        print(error)
                    }
                }
            }
            .onReceive(customWallpapersChanged) { _ in
                loadCustomWallpapers()
            }
            .onReceive(NotificationCenter.default.publisher(for: .videosChanged)) { _ in
                Task(priority: .userInitiated) {
                    try? await videosViewModel.getVideos()
                }
            }
            .onAppear {
                loadCustomWallpapers()
            }
        }

        // MARK: - Screen picker

        var screenPicker: some View {
            Menu {
                ForEach(wallpaperService.screens, id: \.uuidString) { screen in
                    Button {
                        wallpaperService.targetScreenID = screen.uuidString
                    } label: {
                        if screen.uuidString == wallpaperService.targetScreen?.uuidString {
                            Label(wallpaperService.displayName(for: screen), systemImage: "checkmark")
                        } else {
                            Text(wallpaperService.displayName(for: screen))
                        }
                    }
                }
            } label: {
                Label(
                    wallpaperService.targetScreen.map(wallpaperService.displayName(for:)) ?? "Display",
                    systemImage: "display"
                )
                .font(.caption.bold())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Display to change the theme on")
        }

        // MARK: - Customs row

        var customsRow: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Customs")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .padding(.top, 6)
                    Spacer()
                }
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .center) {
                        ForEach(customWallpapers) { config in
                            CustomPresetItem(config: config, isSelected: selectedCustomID == config.id)
                                .frame(height: 54)
                                .onTapGesture {
                                    guard !wallpaperService.isLoading else { return }
                                    wallpaperService.selectForTarget(.custom(config.id))
                                }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .horizontalWheelScrolling(revealsScroller: revealsScroller)
                }
                .frame(height: 70)
            }
            .background { Color.black.opacity(0.3).blendMode(.overlay) }
        }

        // MARK: - Randomize button

        var randomizeButton: some View {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.5).blendMode(.overlay))
                .aspectRatio(16 / 10, contentMode: .fit)
                .overlay(
                    Image(systemName: "dice.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding()
                        .foregroundStyle(.secondary)
                )
                .overlay(
                    isRandomSelected
                        ? RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.accentColor, lineWidth: 4)
                        : nil
                )
                .scaleEffect(isHoldingRandomizeButton ? 0.9 : 1)
                .animation(.spring(), value: isHoldingRandomizeButton)
                .onTapGesture {
                    isHoldingRandomizeButton = false
                    guard !wallpaperService.isLoading else { return }
                    switch selectedWallpaper {
                    case .fluid:
                        wallpaperService.selectForTarget(.random)
                    case .video:
                        currentBackgroundVideoFile = videosViewModel.videos.randomElement()?.fileUrl.lastPathComponent ?? ""
                        videosViewModel.updateWallpaper()
                    case .none:
                        break
                    }
                }
                .onLongPressGesture(perform: {
                    isHoldingRandomizeButton = true
                }, onPressingChanged: { bool in
                    isHoldingRandomizeButton = bool
                })
        }

        // MARK: - Videos

        @ViewBuilder
        func videoThumbnail(_ video: VideosViewModel.VideoItem) -> some View {
            if let image = video.thumbnail {
                Image(nsImage: image)
                    .resizable()
            } else {
                Color.black.opacity(0.5)
                    .overlay(Image(systemName: "film").foregroundStyle(.secondary))
            }
        }

        /// Imports the user's own videos (copied into ~/Movies/Meshy/Videos as MP4).
        var importVideoButton: some View {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.5).blendMode(.overlay))
                .aspectRatio(16 / 10, contentMode: .fit)
                .overlay {
                    if importService.isImporting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "plus")
                            .font(.title2.bold())
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
                .help("Import your own video")
                .onTapGesture {
                    guard !importService.isImporting else { return }
                    importService.presentImportPanel()
                }
        }

        // MARK: - Helpers

        func loadCustomWallpapers() {
            customWallpapers = CustomWallpaperConfig.loadAll()
        }
    }
}

// MARK: - Palette preset item

private struct PalettePresetItem: View {
    let hue: Hue
    let isSelected: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(gradient)
            .aspectRatio(16 / 10, contentMode: .fit)
            .overlay(
                // scrim so the label is always readable
                LinearGradient(
                    colors: [.clear, .black.opacity(0.45)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            )
            .overlay(
                isSelected
                    ? RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(SwiftUI.Color.accentColor, lineWidth: 4)
                    : nil
            )
            .overlay(
                Text(hue.displayTitle)
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(6),
                alignment: .bottomLeading
            )
            .shadow(radius: 8, y: 8)
    }

    var gradient: LinearGradient {
        LinearGradient(colors: hue.previewColors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Custom preset item

private struct CustomPresetItem: View {
    let config: CustomWallpaperConfig
    let isSelected: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(gradient)
            .aspectRatio(16 / 10, contentMode: .fit)
            .overlay(
                // scrim so the label is always readable
                LinearGradient(
                    colors: [.clear, .black.opacity(0.45)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            )
            .overlay(
                isSelected
                    ? RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(SwiftUI.Color.accentColor, lineWidth: 4)
                    : nil
            )
            .overlay(
                Text(config.name)
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(6),
                alignment: .bottomLeading
            )
            .shadow(radius: 6, y: 6)
    }

    var gradient: LinearGradient {
        let colors: [SwiftUI.Color] = config.hues.isEmpty
            ? [.blue, .purple]
            : config.hues.flatMap(\.previewColors)
        return LinearGradient(
            colors: colors.isEmpty ? [.blue, .purple] : colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct ContentView_OptionsView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView.OptionsView(selectedWallpaper: .constant(nil))
    }
}
