//
//  MeshyShortcuts.swift
//  Meshy
//
//  Created by Ethan Lipnik on 9/18/22.
//

import AppIntents
import Foundation

@available(iOS 16.0, macOS 13.0, *)
struct MeshyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GenerateMeshIntent(),
            phrases: [
                "Generate a \(.applicationName) mesh",
                "Generate a \(.applicationName) \(\.$palette) mesh"
            ],
            shortTitle: "Generate a mesh",
            systemImageName: "square.stack.3d.down.right.fill"
        )
    }
}
