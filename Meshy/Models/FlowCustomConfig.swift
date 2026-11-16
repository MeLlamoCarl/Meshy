//
//  FlowCustomConfig.swift
//  Meshy
//

import FlowKit
import Foundation

/// A saved custom Flow: colors (started from a preset) and drop settings.
struct FlowCustomConfig: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    /// Preset it was started from (shown in the editor).
    var basePreset: String?
    var palette: FlowPalette
    var settings: FlowSettings

    /// Changes whenever the colors or settings do: names the cached desktop picture.
    var snapshotKey: String {
        let data = (try? Self.encoder.encode([palette.hashableValues, settings.hashableValues])) ?? Data()
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325 // FNV-1a: stable across launches, unlike Hasher
        for byte in data {
            hash = (hash ^ UInt64(byte)) &* 0x0100_0000_01B3
        }
        return "custom-\(id.uuidString)-\(String(hash, radix: 16))"
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()

    static var storageURL: URL {
        let dir = AppPaths.applicationSupport.appendingPathComponent("CustomWallpapers")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("flows.json")
    }

    static func loadAll() -> [FlowCustomConfig] {
        guard let data = try? Data(contentsOf: storageURL),
              let configs = try? JSONDecoder().decode([FlowCustomConfig].self, from: data)
        else { return [] }
        return configs.map { config in
            var config = config
            config.settings = config.settings.validated
            return config
        }
    }

    private static func write(_ configs: [FlowCustomConfig]) {
        if let data = try? JSONEncoder().encode(configs) {
            try? data.write(to: storageURL, options: .atomic)
        }
        NotificationCenter.default.post(name: .customWallpapersChanged, object: nil)
    }

    /// Adds a new custom, or replaces the one with the same ID.
    static func save(_ config: FlowCustomConfig) {
        var configs = loadAll()
        if let index = configs.firstIndex(where: { $0.id == config.id }) {
            configs[index] = config
        } else {
            configs.append(config)
        }
        write(configs)
    }

    static func delete(id: UUID) {
        write(loadAll().filter { $0.id != id })
        DesktopSnapshot.removeFlowStills(prefix: "custom-\(id.uuidString)")
    }

    static func rename(id: UUID, newName: String) {
        var configs = loadAll()
        guard let index = configs.firstIndex(where: { $0.id == id }) else { return }
        configs[index].name = newName
        write(configs)
    }
}

private extension FlowPalette {
    var hashableValues: [Double] {
        ([background, liquid, halo] + drops).flatMap { [$0.red, $0.green, $0.blue] }
    }
}

private extension FlowSettings {
    var hashableValues: [Double] {
        [Double(dropCount), minSize, maxSize, speed]
    }
}
