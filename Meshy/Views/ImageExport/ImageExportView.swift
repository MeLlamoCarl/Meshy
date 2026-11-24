//
//  ImageExportView.swift
//  Meshy
//

import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

enum ImageExportSize: String, CaseIterable, Identifiable {
    case screen = "This Display"
    case fullHD = "1080p"
    case uhd = "4K"
    case fiveK = "5K"
    case square = "Square"
    case phone = "Phone"

    var id: String { rawValue }

    var pixels: CGSize {
        switch self {
        case .screen:
            guard let screen = NSApp.keyWindow?.screen ?? NSScreen.main else { return CGSize(width: 1920, height: 1080) }
            let scale = screen.backingScaleFactor
            return CGSize(width: (screen.frame.width * scale).rounded(), height: (screen.frame.height * scale).rounded())
        case .fullHD: return CGSize(width: 1920, height: 1080)
        case .uhd: return CGSize(width: 3840, height: 2160)
        case .fiveK: return CGSize(width: 5120, height: 2880)
        case .square: return CGSize(width: 2160, height: 2160)
        case .phone: return CGSize(width: 1320, height: 2868)
        }
    }
}

/// The editors' Export Image popover: a preview of the image, its size, and where to save it.
struct ImageExportView: View {
    /// Draws the image at a size in pixels, for a seed that Shuffle changes.
    typealias Render = (_ width: Int, _ height: Int, _ seed: UInt64) async -> CGImage?

    let defaultName: String
    let canShuffle: Bool
    let render: Render
    let onSaved: () -> Void

    @State private var size: ImageExportSize = .screen
    @State private var seed: UInt64 = 3
    @State private var preview: CGImage?
    @State private var isExporting: Bool = false

    private struct PreviewKey: Hashable {
        var size: ImageExportSize
        var seed: UInt64
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export Image")
                .font(.headline)

            ZStack {
                if let preview {
                    Image(decorative: preview, scale: 2)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 160)

            HStack {
                Picker("Size", selection: $size) {
                    ForEach(ImageExportSize.allCases) { Text($0.rawValue).tag($0) }
                }
                Text(verbatim: "\(Int(size.pixels.width))×\(Int(size.pixels.height))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }

            HStack {
                if canShuffle {
                    Button {
                        seed = .random(in: 1 ... .max)
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                    }
                    .help("Another arrangement of the drops")
                }
                Spacer()
                if isExporting {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("Export…", action: export)
                    .buttonStyle(.borderedProminent)
                    .disabled(isExporting)
            }
        }
        .padding()
        .frame(width: 300)
        .task(id: PreviewKey(size: size, seed: seed)) {
            let pixels = size.pixels
            let scale = 560 / max(pixels.width, pixels.height)
            let image = await render(Int(pixels.width * scale), Int(pixels.height * scale), seed)
            if !Task.isCancelled { preview = image }
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = defaultName
        panel.canCreateDirectories = true
        let pixels = size.pixels, seed = seed, render = render, onSaved = onSaved
        isExporting = true
        Task { @MainActor in
            // Not modal: the live wallpaper keeps moving meanwhile.
            NSApp.activate(ignoringOtherApps: true)
            guard await panel.begin() == .OK, let url = panel.url else {
                isExporting = false
                return
            }
            defer { isExporting = false }
            do {
                guard let image = await render(Int(pixels.width), Int(pixels.height), seed) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                try await Task.detached(priority: .userInitiated) { try Self.write(image, to: url) }.value
                onSaved()
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    private static func write(_ image: CGImage, to url: URL) throws {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url, options: .atomic)
    }
}
