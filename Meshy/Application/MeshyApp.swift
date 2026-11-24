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

        fluidEditorWindow
        flowEditorWindow
    }

    var fluidEditorWindow: some Scene {
        WindowGroup("Fluid Editor") {
            FluidEditorView()
                .navigationTitle("Meshy – Fluid Editor")
                // Opening the editor again reuses its window.
                .handlesExternalEvents(preferring: [WindowManager.FluidEditor.rawValue],
                                       allowing: [WindowManager.FluidEditor.rawValue])
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

    var flowEditorWindow: some Scene {
        WindowGroup("Flow Editor") {
            FlowEditorView()
                .navigationTitle("Meshy – Flow Editor")
                // Opening the editor again reuses its window.
                .handlesExternalEvents(preferring: [WindowManager.FlowEditor.rawValue],
                                       allowing: [WindowManager.FlowEditor.rawValue])
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
        .handlesExternalEvents(matching: Set(arrayLiteral: WindowManager.FlowEditor.rawValue))
        .windowToolbarStyle(.unifiedCompact)
    }
}

enum WindowManager: String, CaseIterable {
    case Main = "MainView"
    case Videos = "VideosView"
    case FluidEditor = "FluidEditorView"
    case FlowEditor = "FlowEditorView"

    func open() {
        if let url = URL(string: urlStr) {
            NSWorkspace.shared.open(url)
        }
    }

    var urlStr: String {
        "meshy://\(rawValue)"
    }
}
