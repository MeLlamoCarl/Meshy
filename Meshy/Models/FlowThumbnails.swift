//
//  FlowThumbnails.swift
//  Meshy
//

import AppKit
import FlowKit

/// Small stills of presets and customs for the menu bar popover, rendered once in the
/// background (one at a time) and kept in memory.
@MainActor
final class FlowThumbnails: ObservableObject {
    static let shared = FlowThumbnails()

    @Published
    private(set) var images: [String: NSImage] = [:]
    private var queued: Set<String> = []
    private var renderTask: Task<Void, Never>?
    private var pending: [(key: String, palette: FlowPalette, settings: FlowSettings)] = []

    /// The thumbnail for `key`, rendering it if it isn't there yet.
    func image(for key: String, palette: FlowPalette, settings: FlowSettings) -> NSImage? {
        if let image = images[key] { return image }
        if !queued.contains(key) {
            queued.insert(key)
            pending.append((key, palette, settings))
            renderNext()
        }
        return nil
    }

    private func renderNext() {
        guard renderTask == nil, !pending.isEmpty else { return }
        let job = pending.removeFirst()
        renderTask = Task { @MainActor in
            let cgImage = await Task.detached(priority: .utility) {
                FlowRenderer.still(palette: job.palette, settings: job.settings, width: 256, height: 160)
            }.value
            if let cgImage {
                images[job.key] = NSImage(cgImage: cgImage, size: NSSize(width: 128, height: 80))
            }
            renderTask = nil
            renderNext()
        }
    }
}
