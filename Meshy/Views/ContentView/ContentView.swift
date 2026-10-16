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
        VStack(spacing: 0) {
            LazyVGrid(columns: [.init(.adaptive(minimum: 100), spacing: 15)], spacing: 15) {
                ForEach([WallpaperType.fluid, WallpaperType.video], id: \.rawValue) { wallpaper in
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
                                    withAnimation {
                                        selectedWallpaper = nil
                                    }
                                    try await wallpaperService.stop()
                                } else {
                                    withAnimation {
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
            }
            .padding()

            Spacer()

            Group {
                if selectedWallpaper != nil {
                    Divider()

                    OptionsView(selectedWallpaper: $selectedWallpaper)
                        .environmentObject(wallpaperService)
                } else {
                    Text("Select a wallpaper type")
                        .font(.title3.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .transition(.opacity)

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
        wallpaperService.targetSelection.customID
    }

    var isFluid: Bool {
        selectedWallpaper == .fluid
    }

    var hasSelectedCustom: Bool {
        selectedCustomID != nil && isFluid
    }

    var selectedCustomConfig: CustomWallpaperConfig? {
        guard let id = selectedCustomID else { return nil }
        return CustomWallpaperConfig.loadAll().first { $0.id == id }
    }

    var footer: some View {
        HStack {
            // + menu: create / import
            Menu {
                Menu("Create Mesh") {
                    Button("3x3") {
                        let query = URLQueryItem(name: "size", value: "3")
                        WindowManager.MeshCreator.open(query: query)
                    }
                    Button("4x4") {
                        let query = URLQueryItem(name: "size", value: "4")
                        WindowManager.MeshCreator.open(query: query)
                    }
                    Button("5x5") {
                        let query = URLQueryItem(name: "size", value: "5")
                        WindowManager.MeshCreator.open(query: query)
                    }
                    Button("6x6") {
                        let query = URLQueryItem(name: "size", value: "6")
                        WindowManager.MeshCreator.open(query: query)
                    }
                    Button("7x7") {
                        let query = URLQueryItem(name: "size", value: "7")
                        WindowManager.MeshCreator.open(query: query)
                    }
                    Button("8x8") {
                        let query = URLQueryItem(name: "size", value: "8")
                        WindowManager.MeshCreator.open(query: query)
                    }
                }

                Button("Create Custom...") {
                    WindowManager.FluidEditor.open()
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
                    WindowManager.FluidEditor.open()
                }

                Button("Rename") {
                    renameText = selectedCustomConfig?.name ?? ""
                    showRenameAlert = true
                }

                Divider()

                Button("Delete", role: .destructive) {
                    if let id = selectedCustomID {
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
                        wallpaperService.fluidViewModels.forEach { $0.updatePauseState() }
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
                    CustomWallpaperConfig.rename(id: id, newName: trimmed)
                    NotificationCenter.default.post(name: .customWallpapersChanged, object: nil)
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
