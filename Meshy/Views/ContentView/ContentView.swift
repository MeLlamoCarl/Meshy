//
//  ContentView.swift
//  Meshy
//
//  Created by Ethan Lipnik on 8/7/22.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State
    private var selectedWallpaper: WallpaperType?
    @State
    private var showRenameAlert: Bool = false
    @State
    private var renameText: String = ""
    @AppStorage("pauseOnGameMode")
    private var pauseOnGameMode: Bool = true
    @State
    private var launchAtLogin: Bool = LaunchAtLogin.isEnabled

    let openAbout: () -> Void
    let openOnboarding: () -> Void
    @StateObject
    var wallpaperService: WallpaperService = .shared
    @State
    var canStartVideo: Bool = false
    @ObservedObject
    private var mouseMonitor = MouseMonitor.shared

    let popoverNotification = NotificationCenter.default
        .publisher(for: NSNotification.Name("didOpenStatusBarItem"))

    init(openAbout: @escaping () -> Void, openOnboarding: @escaping () -> Void) {
        self.openAbout = openAbout
        self.openOnboarding = openOnboarding

        let wallpaperService = WallpaperService.shared
        _wallpaperService = .init(wrappedValue: wallpaperService)

        // Read last active wallpaper directly from UserDefaults — the service starts async
        // so wallpaperService.selectedWallpaper is still nil at this point.
        let lastType = UserDefaults.standard.string(forKey: "lastWallpaperType")
            .flatMap { WallpaperType(rawValue: $0) }
        _selectedWallpaper = .init(initialValue: lastType ?? wallpaperService.selectedWallpaper)

    }

    var body: some View {
        // The popover takes this content's ideal height and animates to it (NSPopover's own
        // resize). While it does, the rows stay anchored to the top, clipped by the moving edge,
        // and the footer rides the bottom edge: nothing jumps or recenters mid-animation.
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                wallpaperCarousel

                Group {
                    if selectedWallpaper != nil {
                        Divider()

                        OptionsView(selectedWallpaper: $selectedWallpaper)
                            .environmentObject(wallpaperService)
                    } else {
                        Text("Select a wallpaper type")
                            .font(.title3.bold())
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 24)
                    }
                }
                .transition(.opacity)
            }
            .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
            .clipped()

            footer
        }
        .onAppear {
            updateCanStartVideo()
        }
        .onReceive(popoverNotification) { _ in
            selectedWallpaper = wallpaperService.selectedWallpaper
            launchAtLogin = LaunchAtLogin.isEnabled
            updateCanStartVideo()
        }
        .onReceive(NotificationCenter.default.publisher(for: .videosChanged)) { _ in
            selectedWallpaper = wallpaperService.selectedWallpaper
            updateCanStartVideo()
        }
    }

    /// Matches the popover's own resize animation, so the rows fade while its edge moves.
    static let resizeAnimation = Animation.easeInOut(duration: 0.25)

    /// Fluid, Flow and Video in a horizontally scrolling row.
    var wallpaperCarousel: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach([WallpaperType.fluid, WallpaperType.flow, WallpaperType.video], id: \.rawValue) { wallpaper in
                        wallpaperItem(wallpaper)
                            .frame(width: 122)
                            .id(wallpaper)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 14) // room for the tiles' shadows
                .horizontalWheelScrolling(revealsScroller: mouseMonitor.isExternalMouseConnected)
            }
            // Keep its full height: otherwise the row gets squeezed (cutting the tiles) when the
            // options below grow, e.g. the Customs row, instead of the popover growing.
            .fixedSize(horizontal: false, vertical: true)
            .onAppear { scrollToSelected(proxy, animated: false) }
            .onReceive(popoverNotification) { _ in scrollToSelected(proxy, animated: false) }
        }
    }

    private func scrollToSelected(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let wallpaper = wallpaperService.selectedWallpaper ?? selectedWallpaper else { return }
        DispatchQueue.main.async {
            if animated {
                withAnimation { proxy.scrollTo(wallpaper, anchor: .center) }
            } else {
                proxy.scrollTo(wallpaper, anchor: .center)
            }
        }
    }

    @ViewBuilder
    func wallpaperItem(_ wallpaper: WallpaperType) -> some View {
        let actions: [WallpaperItem.Action] = {
            switch wallpaper {
            case .video:
                return [("Manage", {
                    WindowManager.Videos.open()
                })]
            default:
                return []
            }
        }()

        WallpaperItem(
            wallpaper: wallpaper,
            selectedWallpaper: $selectedWallpaper,
            canStart: wallpaper == .video ? canStartVideo : true,
            actions: actions
        ) {
            Task {
                do {
                    if selectedWallpaper == wallpaper {
                        withAnimation(Self.resizeAnimation) {
                            selectedWallpaper = nil
                        }
                        try await wallpaperService.stop()
                    } else {
                        withAnimation(Self.resizeAnimation) {
                            selectedWallpaper = wallpaper
                        }
                        try await wallpaperService.start(wallpaper)
                    }
                } catch {
                    print(error)
                }
                // Show what's actually running, even if starting failed.
                selectedWallpaper = wallpaperService.selectedWallpaper
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedWallpaper)
        .environmentObject(wallpaperService)
    }

    func updateCanStartVideo() {
        let folder = AppPaths.videos

        do {
            let contents = try FileManager.default.contentsOfDirectory(atPath: folder.path)
                .map { folder.appending(path: $0) }
                .compactMap { UTType(filenameExtension: $0.pathExtension) }
                .filter { $0.isSubtype(of: .movie) }
            canStartVideo = !contents.isEmpty
        } catch {
            print(error)
        }
    }

    var selectedCustomID: UUID? {
        switch selectedWallpaper {
        case .fluid: return wallpaperService.targetSelection.customID
        case .flow: return wallpaperService.targetFlowSelection.customID
        default: return nil
        }
    }

    var isFluid: Bool {
        selectedWallpaper == .fluid
    }

    var isFlow: Bool {
        selectedWallpaper == .flow
    }

    var hasSelectedCustom: Bool {
        selectedCustomID != nil && (isFluid || isFlow)
    }

    /// Name of the selected custom (Fluid or Flow), for renaming.
    var selectedCustomName: String? {
        guard let id = selectedCustomID else { return nil }
        return isFlow
            ? FlowCustomConfig.loadAll().first { $0.id == id }?.name
            : CustomWallpaperConfig.loadAll().first { $0.id == id }?.name
    }

    var footer: some View {
        HStack {
            // + menu: create / import
            Menu {
                Button("Create Custom Fluid...") {
                    FluidEditorState.shared.prepareNew()
                    WindowManager.FluidEditor.open()
                }

                Button("Create Custom Flow...") {
                    FlowEditorState.shared.prepareNew()
                    WindowManager.FlowEditor.open()
                }

                Divider()

                Button("Import video...") {
                    VideoImportService.shared.presentImportPanel()
                }
            } label: {
                Image(systemName: "plus.circle.fill")
            }
            .buttonStyle(.plain)

            Spacer()

            // Custom wallpaper management button — always a Menu, disabled when nothing selected
            Menu {
                Button("Edit") {
                    if isFlow, let id = selectedCustomID {
                        FlowEditorState.shared.prepareEditing(id)
                        WindowManager.FlowEditor.open()
                    } else {
                        if let id = selectedCustomID {
                            FluidEditorState.shared.prepareEditing(id)
                        } else {
                            FluidEditorState.shared.prepareNew()
                        }
                        WindowManager.FluidEditor.open()
                    }
                }

                Button("Rename") {
                    renameText = selectedCustomName ?? ""
                    showRenameAlert = true
                }

                Divider()

                Button("Delete", role: .destructive) {
                    guard let id = selectedCustomID else { return }
                    if isFlow {
                        FlowCustomConfig.delete(id: id)
                        wallpaperService.customFlowDeleted(id)
                    } else {
                        CustomWallpaperConfig.delete(id: id)
                        wallpaperService.customWallpaperDeleted(id)
                        NotificationCenter.default.post(name: .customWallpapersChanged, object: nil)
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .foregroundStyle(hasSelectedCustom ? Color.primary : Color.secondary.opacity(0.4))
            }
            .buttonStyle(.plain)
            .disabled(!hasSelectedCustom)

            // ⚙️ menu: about, onboarding, quit + game mode toggle
            Menu {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        guard newValue != LaunchAtLogin.isEnabled else { return }
                        if newValue {
                            LaunchAtLogin.enable()
                        } else {
                            LaunchAtLogin.disable()
                        }
                    }

                Toggle("Pause when app is fullscreen", isOn: $pauseOnGameMode)
                    .onChange(of: pauseOnGameMode) { _ in
                        wallpaperService.updatePauseStates()
                    }

                Button {
                    PixabayAPIKeyStore.shared.isEditorPresented = true
                    WindowManager.Videos.open()
                } label: {
                    Label("Pixabay API Key…", systemImage: "key")
                }

                Divider()

                Button(action: openAbout) {
                    Label("About", systemImage: "info")
                }
                if #available(macOS 14, *) {
                    OpenSettingsButton()
                } else {
                    Button {
                        AppDelegate.statusBar?.popover.performClose(nil)
                        NSApp.activate(ignoringOtherApps: true)
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    } label: {
                        Label("Settings…", systemImage: "gearshape")
                    }
                }
                Button(action: openOnboarding) {
                    Label("Onboarding", systemImage: "circle.circle.fill")
                }
                Divider()
                Button {
                    NSApplication.shared.terminate(self)
                } label: {
                    Label("Quit", systemImage: "xmark")
                }
            } label: {
                Image(systemName: "gearshape.fill")
            }
            .buttonStyle(.plain)
        }
        .padding()
        .overlay(Divider(), alignment: .top)
        .alert("Rename", isPresented: $showRenameAlert) {
            TextField("Name", text: $renameText)
            Button("Save") {
                let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                if let id = selectedCustomID, !trimmed.isEmpty {
                    if isFlow {
                        FlowCustomConfig.rename(id: id, newName: trimmed)
                    } else {
                        CustomWallpaperConfig.rename(id: id, newName: trimmed)
                        NotificationCenter.default.post(name: .customWallpapersChanged, object: nil)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a new name for this custom wallpaper.")
        }
    }

    struct WallpaperItem: View {
        @EnvironmentObject
        var wallpaperService: WallpaperService
        let wallpaper: WallpaperType

        typealias Action = (String, () -> Void)

        @Binding
        var selectedWallpaper: WallpaperType?
        var canStart: Bool = true
        var actions: [Action] = []
        let updateWallpaper: () -> Void

        @State
        private var isHolding: Bool = false
        @State
        private var isHovering: Bool = false

        var body: some View {
            VStack {
                Image(wallpaper.rawValue.capitalized + "Thumbnail")
                    .resizable()
                    .aspectRatio(16 / 10, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        selectedWallpaper == wallpaper ? RoundedRectangle(
                            cornerRadius: 10,
                            style: .continuous
                        )
                        .stroke(Color.accentColor, lineWidth: 4) : nil
                    )
                    .overlay(
                        selectedWallpaper == wallpaper && wallpaperService
                            .isLoading ? ProgressView() : nil
                    )
                    .overlay(
                        isHovering ? ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.black)
                                .opacity(0.5)
                            VStack {
                                Button(selectedWallpaper == wallpaper ? "Stop" : "Start") {
                                    guard canStart else { return }
                                    updateWallpaper()
                                }.disabled(!canStart)

                                ForEach(actions, id: \.0) { action in
                                    Button(action: action.1) {
                                        Text(action.0)
                                    }
                                }
                            }
                        } : nil
                    )
                    .shadow(radius: isHolding ? 4 : 8, y: isHolding ? 4 : 8)
                    .scaleEffect(isHolding ? 0.9 : 1)
                    .animation(.spring(), value: isHolding)
                    .onHover { isHovering in
                        withAnimation(.easeInOut) {
                            self.isHovering = isHovering
                        }
                    }
                    .onTapGesture {
                        isHolding = false

                        guard canStart else { return }

                        updateWallpaper()
                    }
                    .onLongPressGesture {} onPressingChanged: { isHolding in
                        self.isHolding = isHolding
                    }

                Text(wallpaper.displayTitle)
                    .font(.headline)
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(openAbout: {}, openOnboarding: {})
    }
}

/// Opens the Settings window (macOS 14 no longer lets apps send `showSettingsWindow:`).
@available(macOS 14, *)
private struct OpenSettingsButton: View {
    @Environment(\.openSettings)
    private var openSettings

    var body: some View {
        Button {
            // Meshy is a menu bar app: bring it forward so the window opens in front.
            AppDelegate.statusBar?.popover.performClose(nil)
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        } label: {
            Label("Settings…", systemImage: "gearshape")
        }
    }
}
