//
//  MeshyApp.swift
//  Meshy
//
//  Created by Ethan Lipnik on 7/28/22.
//

import MeshKit
import SwiftUI

@main
struct MeshyApp: App {
    @Environment(\.openURL)
    var openUrl
    @NSApplicationDelegateAdaptor
    var appDelegate: AppDelegate
    @State
    private var isImportingVideo: Bool = false

    var body: some Scene {
        WindowGroup {
            VideosManagementView()
                .frame(minWidth: 700, minHeight: 500)
                .fileImporter(
                    isPresented: $isImportingVideo,
                    allowedContentTypes: [.video, .movie],
                    allowsMultipleSelection: true,
                    onCompletion: { result in
                        switch result {
                        case let .success(fileUrls):
                            Task { await VideoImportService.shared.importVideos(fileUrls) }
                        case let .failure(error):
                            print(error)
                        }
                    }
                )
                .onDisappear {
                    if NSApp.windows.compactMap(\.identifier)
                        .filter({
                            $0.rawValue.hasPrefix("SwiftUI") || $0.rawValue.hasPrefix("Meshy") })
                        .count == 0
                    {
                        NSApp.setActivationPolicy(.accessory)
                    }
                }
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                }
        }
        .commands {
            ToolbarCommands()
            SidebarCommands()

            CommandGroup(after: .newItem) {
                Button("Import Video...") {
                    isImportingVideo.toggle()
                }
                .keyboardShortcut("i")
            }

            CommandGroup(replacing: .appInfo) {
                Button(action: {
                    appDelegate.showAboutPanel()
                }) {
                    Text("About Meshy")
                }
            }

            CommandGroup(replacing: .help) {
                Button("Meshy Help") {
                    appDelegate.showAboutPanel()
                }
            }
        }
        .handlesExternalEvents(matching: Set(arrayLiteral: WindowManager.Videos.rawValue))

        Settings {
            SettingsView()
                .frame(width: 400)
        }

        meshCreatorWindow
        fluidEditorWindow
    }

    var meshCreatorWindow: some Scene {
        WindowGroup("Mesh Creator") {
            DeepLinkMeshCreatorView()
                .navigationTitle("Meshy – Mesh Creator")
                .frame(minWidth: 400, minHeight: 400)
                .onDisappear {
                    if NSApp.windows.compactMap(\.identifier)
                        .filter({
                            $0.rawValue.hasPrefix("SwiftUI") || $0.rawValue.hasPrefix("Meshy") })
                        .count == 0
                    {
                        NSApp.setActivationPolicy(.accessory)
                    }
                }
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                }
        }
        .handlesExternalEvents(matching: Set(arrayLiteral: WindowManager.MeshCreator.rawValue))
        .windowToolbarStyle(.unifiedCompact)
    }

    struct DeepLinkMeshCreatorView: View {
        @State
        private var size: MeshSize?

        var body: some View {
            Group {
                if let size {
                    MeshCreatorView(size: size)
                } else {
                    ProgressView()
                        .onOpenURL { url in
                            let urlComponents = URLComponents(
                                url: url,
                                resolvingAgainstBaseURL: true
                            )
                            if let sizeStr = urlComponents?.queryItems?
                                .first(where: { $0.name == "size" })?.value,
                                let size = Int(sizeStr)
                            {
                                self.size = MeshSize(width: size, height: size)
                            }
                        }
                }
            }
        }
    }

    var fluidEditorWindow: some Scene {
        WindowGroup("Fluid Editor") {
            FluidEditorView()
                .navigationTitle("Meshy – Fluid Editor")
                .onDisappear {
                    if NSApp.windows.compactMap(\.identifier)
                        .filter({
                            $0.rawValue.hasPrefix("SwiftUI") || $0.rawValue.hasPrefix("Meshy") })
                        .count == 0
                    {
                        NSApp.setActivationPolicy(.accessory)
                    }
                }
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                }
        }
        .handlesExternalEvents(matching: Set(arrayLiteral: WindowManager.FluidEditor.rawValue))
        .windowToolbarStyle(.unifiedCompact)
    }
}

enum WindowManager: String, CaseIterable {
    case Main = "MainView"
    case MeshCreator = "MeshCreatorView"
    case Videos = "VideosView"
    case FluidEditor = "FluidEditorView"

    func open(query: URLQueryItem...) {
        var urlComponents = URLComponents(string: urlStr)
        urlComponents?.queryItems = query
        if let url = urlComponents?.url {
            NSWorkspace.shared.open(url)
        }
    }

    func open() {
        if let url = URL(string: urlStr) {
            NSWorkspace.shared.open(url)
        }
    }

    var urlStr: String {
        "meshy://\(rawValue)"
    }
}
