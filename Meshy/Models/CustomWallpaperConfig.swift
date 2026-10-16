//
//  CustomWallpaperConfig.swift
//  Meshy
//

import Foundation
import MeshKit
import RandomColor

struct CustomWallpaperConfig: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var hueNames: [String]
    var luminosityName: String
    var meshSize: Int
    var grainAlpha: Float
    var subdivisions: Float
    var animationSpeed: Double

    var hues: [Hue] {
        hueNames.compactMap { name in
            Hue.allCases.first { $0.displayTitle == name }
        }
    }

    var luminosity: Luminosity {
        switch luminosityName {
        case "light": return .light
        case "dark": return .dark
        default: return .bright
        }
    }

    static var storageURL: URL {
        let dir = AppPaths.applicationSupport.appendingPathComponent("CustomWallpapers")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("wallpapers.json")
    }

    static func loadAll() -> [CustomWallpaperConfig] {
        guard let data = try? Data(contentsOf: storageURL),
              let configs = try? JSONDecoder().decode([CustomWallpaperConfig].self, from: data)
        else { return [] }
        return configs
    }

    static func save(_ config: CustomWallpaperConfig) {
        var configs = loadAll()
        configs.append(config)
        if let data = try? JSONEncoder().encode(configs) {
            try? data.write(to: storageURL)
        }
    }

    static func delete(id: UUID) {
        var configs = loadAll()
        configs.removeAll { $0.id == id }
        if let data = try? JSONEncoder().encode(configs) {
            try? data.write(to: storageURL)
        }
    }

    static func rename(id: UUID, newName: String) {
        var configs = loadAll()
        if let idx = configs.firstIndex(where: { $0.id == id }) {
            configs[idx].name = newName
            if let data = try? JSONEncoder().encode(configs) {
                try? data.write(to: storageURL)
            }
        }
    }
}

extension Notification.Name {
    static let customWallpapersChanged = Notification.Name("customWallpapersChanged")
}
