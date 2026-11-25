//
//  FlowViewModel.swift
//  Meshy
//

import AppKit
import FlowKit
import Foundation

/// What a screen's Flow wallpaper is set to. Persisted per screen by `WallpaperService`.
enum FlowSelection: Equatable {
    /// Cycle through the allowed presets on every palette-change interval.
    case random
    /// A single preset, by its stable name.
    case preset(String)
    /// A saved custom Flow.
    case custom(UUID)

    init(storageValue: String) {
        if storageValue.hasPrefix("preset:"), FlowPreset.named(String(storageValue.dropFirst(7))) != nil {
            self = .preset(String(storageValue.dropFirst(7)))
        } else if storageValue.hasPrefix("custom:"), let id = UUID(uuidString: String(storageValue.dropFirst(7))) {
            self = .custom(id)
        } else {
            self = .random
        }
    }

    var storageValue: String {
        switch self {
        case .random: return "random"
        case let .preset(name): return "preset:\(name)"
        case let .custom(id): return "custom:\(id.uuidString)"
        }
    }

    var presetName: String? {
        if case let .preset(name) = self { return name }
        return nil
    }

    var customID: UUID? {
        if case let .custom(id) = self { return id }
        return nil
    }
}

extension FlowPreset {
    /// Presets the 🎲 rotation may pick (Settings can turn some off).
    static var allowed: [FlowPreset] {
        let enabled = all.filter { !UserDefaults.standard.bool(forKey: disabledKey(for: $0.name)) }
        return enabled.isEmpty ? all : enabled
    }

    static func disabledKey(for name: String) -> String {
        "isFlowPreset-\(name)Disabled"
    }
}

/// One screen's Flow: what it shows, whether it's paused, and its desktop picture.
@MainActor
final class FlowViewModel: ObservableObject {
    @Published
    private(set) var palette: FlowPalette = FlowPreset.all[0].palette
    @Published
    private(set) var settings: FlowSettings = .default
    /// Set by the window's `WallpaperActivity`.
    @Published
    var isPaused: Bool = false
    @Published
    var maxFramesPerSecond: Int = 60
    /// The preset shown by the 🎲 rotation or a preset selection.
    private(set) var currentPreset: FlowPreset?
    private(set) var selection: FlowSelection = .random
    /// `NSScreen.uuidString` of the screen this view model renders on.
    let screenID: String

    /// The Flow Editor's applied, unsaved colors.
    private var unsavedConfig: FlowCustomConfig?
    private var timer: Timer?
    private var desktopPictureTask: Task<Void, Never>?

    init(screenID: String) {
        self.screenID = screenID
    }

    func destroy() {
        timer?.invalidate()
        timer = nil
        desktopPictureTask?.cancel()
        desktopPictureTask = nil
    }

    // MARK: - Selection

    /// Applies a selection to this screen. Unknown customs (e.g. deleted) fall back to random.
    func apply(_ selection: FlowSelection) {
        switch selection {
        case .random:
            show(nextRandomPreset(), as: .random)
        case let .preset(name):
            show(FlowPreset.named(name) ?? FlowPreset.all[0], as: selection)
        case let .custom(id):
            if let config = FlowCustomConfig.loadAll().first(where: { $0.id == id })
                ?? unsavedConfig.flatMap({ $0.id == id ? $0 : nil }) {
                apply(config)
            } else {
                show(nextRandomPreset(), as: .random)
            }
        }
        setTimer()
    }

    /// Shows a custom (or the Flow Editor's unsaved colors) on this screen.
    func apply(_ config: FlowCustomConfig) {
        currentPreset = nil
        selection = .custom(config.id)
        if !FlowCustomConfig.loadAll().contains(where: { $0.id == config.id }) {
            unsavedConfig = config
        }
        show(palette: config.palette, settings: config.settings, snapshotKey: config.snapshotKey)
        setTimer()
    }

    private func show(_ preset: FlowPreset, as selection: FlowSelection) {
        currentPreset = preset
        self.selection = selection
        show(palette: preset.palette, settings: Self.presetSettings, snapshotKey: "preset-\(preset.name)")
    }

    private func show(palette: FlowPalette, settings: FlowSettings, snapshotKey: String) {
        self.palette = palette
        self.settings = settings
        scheduleDesktopPictureUpdate(key: snapshotKey)
    }

    /// Presets use the default drops at the speed chosen in Settings.
    static var presetSettings: FlowSettings {
        var settings = FlowSettings.default
        if let speed = UserDefaults.standard.object(forKey: "FlowSpeed") as? Double {
            settings.speed = speed
        }
        return settings.validated
    }

    private func nextRandomPreset() -> FlowPreset {
        let choices = FlowPreset.allowed.filter { $0 != currentPreset }
        return choices.randomElement() ?? FlowPreset.allowed[0]
    }

    /// Re-applies the selection (Settings changed).
    func refresh() {
        switch selection {
        case .random:
            if let currentPreset { show(currentPreset, as: .random) } else { apply(.random) }
        default:
            apply(selection)
        }
    }

    // MARK: - Rotation

    func setTimer() {
        timer?.invalidate()
        timer = nil
        guard selection == .random else { return }
        timer = Timer.scheduledTimer(withTimeInterval: FluidViewModel.getDefaultChangeInterval(), repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.selection == .random, !self.isPaused else { return }
                self.show(self.nextRandomPreset(), as: .random)
            }
        }
    }

    // MARK: - Desktop picture

    /// Shows a still of the Flow as the desktop picture (menu bar tint, lock screen, Mission
    /// Control). Stills are rendered once per palette and screen size and kept in the caches:
    /// macOS's wallpaper agent keeps a bitmap of every picture it's given (keyed by file and
    /// modification date) and never deletes them, so reusing the file costs nothing new.
    private func scheduleDesktopPictureUpdate(key: String) {
        desktopPictureTask?.cancel()
        let palette = palette, settings = settings, screenID = screenID
        desktopPictureTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                try await DesktopSnapshot.setFlowStill(key: key, for: screenID) { url, size in
                    let colorMatch = (UserDefaults.standard.object(forKey: "shouldColorMatchFWMenuBar") as? Bool) ?? true
                    let image: CGImage? = colorMatch
                        ? await Task.detached(priority: .utility) {
                            FlowRenderer.still(palette: palette, settings: settings,
                                               width: Int(size.width), height: Int(size.height))
                        }.value
                        : nil
                    try Task.checkCancellation()
                    if let image {
                        try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
                    } else {
                        try NSImage(color: .black, size: NSSize(width: 10, height: 10)).pngData?.write(to: url)
                    }
                }
            } catch is CancellationError {
            } catch {
                print(error)
            }
        }
    }
}
