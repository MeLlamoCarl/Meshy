//
//  FluidViewModel.swift
//  Meshy
//
//  Created by Ethan Lipnik on 8/3/22.
//

import AppKit
import CoreGraphics
import Foundation
import MeshKit
import SwiftUI

/// What a screen's fluid wallpaper is set to. Persisted per screen by `WallpaperService`.
enum FluidSelection: Equatable {
    /// Cycle through random presets on every palette-change interval.
    case random
    /// A single preset; the timer regenerates within this hue only.
    case hue(Hue)
    /// A saved custom wallpaper; the timer never overrides it.
    case custom(UUID)

    init(storageValue: String) {
        if storageValue.hasPrefix("hue:"),
           let hue = Hue.presetCases.first(where: { $0.displayTitle == storageValue.dropFirst(4) }) {
            self = .hue(hue)
        } else if storageValue.hasPrefix("custom:"),
                  let id = UUID(uuidString: String(storageValue.dropFirst(7))) {
            self = .custom(id)
        } else {
            self = .random
        }
    }

    var storageValue: String {
        switch self {
        case .random: return "random"
        case let .hue(hue): return "hue:\(hue.displayTitle)"
        case let .custom(id): return "custom:\(id.uuidString)"
        }
    }

    var hue: Hue? {
        if case let .hue(hue) = self { return hue }
        return nil
    }

    var customID: UUID? {
        if case let .custom(id) = self { return id }
        return nil
    }
}

extension Hue {
    /// Hues offered as wallpaper presets (Monochrome is intentionally excluded).
    static var presetCases: [Hue] {
        allCases.filter { $0 != .monochrome }
    }
}

class FluidViewModel: ObservableObject {
    @Published
    var meshRandomizer: MeshRandomizer
    @Published
    var colors: MeshColorGrid
    @Published
    var timer: Timer?
    @Published
    var currentPalette: Hue?
    @Published
    var meshPreviewID: UUID = UUID()
    @Published
    var isPaused: Bool = false
    /// What this screen is set to. The timer and appearance changes respect it.
    private(set) var selection: FluidSelection = .random
    /// Render settings (grain, subdivisions, speed) that override the global ones for this
    /// screen only — set by custom wallpapers and by the Fluid Editor's Apply.
    @Published
    var settingsOverride: CustomWallpaperConfig?
    /// `NSScreen.uuidString` of the screen this view model renders on.
    var screenID: String?

    private var gameModeObservers: [Any] = []
    var shouldUpdateDesktopPicture: Bool = false
    /// Pending desktop picture update; a newer palette cancels it so it can't overwrite the
    /// newer colors (that left the menu bar tinted with the previous theme).
    private var desktopPictureTask: Task<Void, Never>?

    var allowedPalettes: [Hue] {
        Hue.presetCases
            .filter {
                !UserDefaults.standard.bool(forKey: "isWallpaperPalette-\($0.displayTitle)Disabled")
            }
    }

    init() {
        let colors = MeshKit.generate(palette: .monochrome, luminosity: .dark)
        self.colors = colors
        meshRandomizer = .withMeshColors(colors)
    }

    deinit {
        timer?.invalidate()
        timer = nil
    }

    func destroy() {
        timer?.invalidate()
        timer = nil
        desktopPictureTask?.cancel()
        desktopPictureTask = nil
        stopGameModeMonitoring()
    }

    // MARK: - Game Mode monitoring

    func startGameModeMonitoring() {
        // Register default so the feature is ON out of the box
        UserDefaults.standard.register(defaults: ["pauseOnGameMode": true])

        let nc = NSWorkspace.shared.notificationCenter
        let names: [NSNotification.Name] = [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didDeactivateApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
        ]
        gameModeObservers = names.map { name in
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.updatePauseState()
            }
        }
    }

    func stopGameModeMonitoring() {
        let nc = NSWorkspace.shared.notificationCenter
        gameModeObservers.forEach { nc.removeObserver($0) }
        gameModeObservers = []
    }

    func updatePauseState() {
        guard UserDefaults.standard.bool(forKey: "pauseOnGameMode") else {
            if isPaused { isPaused = false }
            return
        }
        isPaused = isOtherAppFullScreen()
    }

    private func isOtherAppFullScreen() -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.uuidString == screenID }) ?? NSScreen.main,
              let primaryScreen = NSScreen.screens.first else { return false }
        // CGWindow bounds use a top-left origin relative to the primary screen.
        let screenRect = CGRect(
            x: screen.frame.minX,
            y: primaryScreen.frame.maxY - screen.frame.maxY,
            width: screen.frame.width,
            height: screen.frame.height
        )
        let ownPID = ProcessInfo.processInfo.processIdentifier

        let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []

        for window in windowList {
            guard
                let pid = window[kCGWindowOwnerPID as String] as? Int32,
                pid != ownPID,
                let boundsDict = window[kCGWindowBounds as String] as? [String: CGFloat],
                let layer = window[kCGWindowLayer as String] as? Int,
                layer == 0  // normal window layer (not system overlays)
            else { continue }

            let windowRect = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )
            if windowRect.insetBy(dx: -1, dy: -1).contains(screenRect) {
                return true
            }
        }
        return false
    }

    func applyColors(_ newColors: MeshColorGrid) {
        colors = newColors
        meshRandomizer = .withMeshColors(newColors)
    }

    /// Applies a selection to this screen. Unknown customs (e.g. deleted) fall back to random.
    func apply(_ selection: FluidSelection) {
        switch selection {
        case .random:
            newPalette()
        case let .hue(hue):
            newPalette(hue)
        case let .custom(id):
            if let config = CustomWallpaperConfig.loadAll().first(where: { $0.id == id }) {
                applyConfig(config)
            } else {
                newPalette()
            }
        }
    }

    /// Regenerates colors within the current selection (timer tick, appearance change).
    func regenerate() {
        switch selection {
        case .random:
            newPalette()
        case let .hue(hue):
            newPalette(hue)
        case .custom:
            break  // the meshRandomizer already animates a custom palette continuously
        }
    }

    private func applyConfig(_ config: CustomWallpaperConfig) {
        let hues = config.hues.isEmpty ? [Hue.blue] : config.hues
        colors = MeshKit.generate(
            palette: hues,
            luminosity: config.luminosity,
            size: MeshSize(width: config.meshSize, height: config.meshSize),
            withRandomizedLocations: true
        )
        meshRandomizer = .withMeshColors(colors)
        currentPalette = hues.count == 1 ? hues.first : nil
        selection = .custom(config.id)
        settingsOverride = config
        scheduleDesktopPictureUpdate()
    }

    private func newPalette(_ palette: Hue? = nil, luminosityOverride: Luminosity? = nil) {
        let luminosity: Luminosity = {
            if let override = luminosityOverride {
                return override
            }
            let interfaceStyle = InterfaceStyle()
            let wallpaperColorScheme = WallpaperColorScheme(
                rawValue: UserDefaults.standard
                    .string(forKey: "FWColorScheme") ?? "system"
            )
            switch wallpaperColorScheme {
            case .light:
                return .light
            case .dark:
                return .dark
            case .system:
                return interfaceStyle == .Light ? .light : .dark
            default:
                return .bright
            }
        }()

        let meshDimension: Int = {
            let stored = UserDefaults.standard.integer(forKey: "FWMeshSize")
            return stored > 0 ? stored : 5
        }()

        let newPalette = palette ?? allowedPalettes.randomElement() ?? .blue

        colors = MeshKit.generate(
            palette: newPalette,
            luminosity: luminosity,
            size: MeshSize(width: meshDimension, height: meshDimension),
            withRandomizedLocations: true
        )
        meshRandomizer = .withMeshColors(colors)

        currentPalette = newPalette
        selection = palette.map { .hue($0) } ?? .random
        settingsOverride = nil
        scheduleDesktopPictureUpdate()
    }

    /// Updates the desktop picture (and with it the menu bar tint) shortly after the colors
    /// change. The short delay coalesces quick successive changes.
    private func scheduleDesktopPictureUpdate() {
        guard shouldUpdateDesktopPicture else { return }
        desktopPictureTask?.cancel()
        desktopPictureTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                try await self?.updateDesktopPicture()
            } catch is CancellationError {
            } catch {
                print(error)
            }
        }
    }

    func setTimer(_ interval: Double = FluidViewModel.getDefaultChangeInterval()) {
        timer?.invalidate()
        timer = nil

        timer = Timer.scheduledTimer(
            timeInterval: interval,
            target: self,
            selector: #selector(generateNewPalette),
            userInfo: nil,
            repeats: true
        )
    }

    @objc
    private func generateNewPalette() {
        regenerate()
    }

    static func getDefaultChangeInterval() -> Double {
        if UserDefaults.standard.object(forKey: "FWPaletteChangeInterval") != nil {
            return UserDefaults.standard.double(forKey: "FWPaletteChangeInterval")
        }

        return 60
    }

    @MainActor
    func updateDesktopPicture() async throws {
        guard shouldUpdateDesktopPicture, let screenID else { return }
        let colors = colors
        try Task.checkCancellation()

        try await DesktopSnapshot.set(for: screenID) { url in
            if (UserDefaults.standard.object(forKey: "shouldColorMatchFWMenuBar") as? Bool) ?? true {
                _ = try await colors.export(to: url)
            } else {
                let image = NSImage(color: NSColor.black, size: NSSize(width: 10, height: 10))
                try image.pngData?.write(to: url)
            }
            // A newer palette arrived while exporting: don't show these colors.
            try Task.checkCancellation()
        }
    }

    enum InterfaceStyle: String {
        case Dark, Light

        init() {
            let type = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") ?? "Light"
            self = InterfaceStyle(rawValue: type)!
        }
    }
}

extension NSImage {
    convenience init(color: NSColor, size: NSSize) {
        self.init(size: size)
        lockFocus()
        color.drawSwatch(in: NSRect(origin: .zero, size: size))
        unlockFocus()
    }

    var pngData: Data? {
        guard let tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffRepresentation) else { return nil }
        return bitmapImage.representation(using: .png, properties: [:])
    }

    func pngWrite(to url: URL, options: Data.WritingOptions = .atomic) throws {
        try pngData?.write(to: url, options: options)
    }
}
