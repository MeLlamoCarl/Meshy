//
//  WallpaperService.swift
//  Meshy
//
//  Created by Ethan Lipnik on 8/4/22.
//

import AppKit
import Foundation

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    /// Stable identifier for this display that survives reboots and reconnects.
    var uuidString: String {
        guard let displayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue()
        else { return localizedName }
        return CFUUIDCreateString(nil, uuid) as String
    }
}

/// Desktop pictures Meshy sets as snapshots of the live wallpaper. macOS derives the menu bar
/// tint (with "Show menu bar background") and Mission Control's picture from them.
@MainActor
enum DesktopSnapshot {
    static var folder: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Meshy Desktop Pictures", isDirectory: true)
    }

    /// Writes a snapshot under a new, unique name, makes it the screen's desktop picture and only
    /// then deletes the older ones. Deleting the shown file first (or reusing its name) could
    /// leave the menu bar tinted with the previous colors.
    static func set(for screenID: String, write: (URL) async throws -> Void) async throws {
        guard let screen = NSScreen.screens.first(where: { $0.uuidString == screenID }) else { return }
        let screenFolder = folder.appendingPathComponent(screenID, isDirectory: true)
        try FileManager.default.createDirectory(at: screenFolder, withIntermediateDirectories: true)

        let url = screenFolder.appendingPathComponent("Meshy \(UUID().uuidString).png")
        try await write(url)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try NSWorkspace.shared.setDesktopImageURL(url, for: screen)

        removeSnapshots(in: screenFolder, except: url)
    }

    /// Video frames are kept at full size under a fixed name per video and written only once.
    /// macOS's wallpaper agent keeps a bitmap of every desktop picture (keyed by file and
    /// modification date) and never deletes them, so reusing the same file means each video
    /// costs one cached bitmap instead of a new one (up to ~33 MB at 4K) every time it starts.
    nonisolated static var videoFramesFolder: URL {
        AppPaths.caches.appendingPathComponent("Video Frames", isDirectory: true)
    }

    nonisolated static func videoFrameURL(for videoFile: URL) -> URL {
        videoFramesFolder.appendingPathComponent(videoFile.lastPathComponent + ".png")
    }

    /// Shows the video's saved frame, writing it first if it doesn't exist yet.
    static func setVideoFrame(of videoFile: URL, for screenID: String, write: (URL) async throws -> Void) async throws {
        guard let screen = NSScreen.screens.first(where: { $0.uuidString == screenID }) else { return }
        let url = videoFrameURL(for: videoFile)
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: videoFramesFolder, withIntermediateDirectories: true)
            try await write(url)
            guard FileManager.default.fileExists(atPath: url.path) else { return }
        }
        try NSWorkspace.shared.setDesktopImageURL(url, for: screen)
        removeSnapshots(in: folder.appendingPathComponent(screenID, isDirectory: true), except: nil)
    }

    /// Flow stills, rendered once per palette and screen size (see `FlowViewModel`).
    nonisolated static var flowStillsFolder: URL {
        AppPaths.caches.appendingPathComponent("Flow Stills", isDirectory: true)
    }

    /// Shows the still named `key` at the screen's size, rendering it first if it doesn't exist.
    /// Older stills of the same custom (edited since) are deleted.
    static func setFlowStill(key: String, for screenID: String, write: (URL, CGSize) async throws -> Void) async throws {
        guard let screen = NSScreen.screens.first(where: { $0.uuidString == screenID }) else { return }
        // macOS's wallpaper agent caches each picture as a bitmap at its own size (~30 MB at
        // 3456 px); Flow is soft gradients, so 1280 px wide looks the same scaled up.
        let width = min(screen.frame.width * screen.backingScaleFactor, 1280)
        let size = CGSize(width: width.rounded(), height: (width * screen.frame.height / max(screen.frame.width, 1)).rounded())
        let url = flowStillsFolder.appendingPathComponent("\(key)-\(Int(size.width))x\(Int(size.height)).png")
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: flowStillsFolder, withIntermediateDirectories: true)
            try await write(url, size)
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            if key.hasPrefix("custom-") {
                let custom = String(key.prefix("custom-".count + 36)) // custom-<UUID>
                removeFlowStills(prefix: custom, keeping: key)
            }
        }
        try NSWorkspace.shared.setDesktopImageURL(url, for: screen)
        removeSnapshots(in: folder.appendingPathComponent(screenID, isDirectory: true), except: nil)
    }

    /// Deletes Flow stills whose name starts with `prefix`, except those of `kept`.
    nonisolated static func removeFlowStills(prefix: String, keeping kept: String? = nil) {
        let files = (try? FileManager.default.contentsOfDirectory(at: flowStillsFolder, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent.hasPrefix(prefix) {
            if let kept, file.lastPathComponent.hasPrefix(kept + "-") { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }

    private static func removeSnapshots(in screenFolder: URL, except kept: URL?) {
        let older = (try? FileManager.default.contentsOfDirectory(at: screenFolder, includingPropertiesForKeys: nil)) ?? []
        for file in older where file.lastPathComponent != kept?.lastPathComponent {
            try? FileManager.default.removeItem(at: file)
        }
    }
}

@MainActor
class WallpaperService: ObservableObject {
    static let shared = WallpaperService()

    nonisolated private static let selectionsKey = "FWScreenSelections"
    nonisolated static let flowSelectionsKey = "FlowScreenSelections"
    private static let originalPicturesKey = "originalDesktopPictures"

    /// One wallpaper window per connected screen, keyed by `NSScreen.uuidString`.
    private var windowControllers: [String: NSWindowController] = [:]
    /// Each screen's desktop picture from before Meshy took over, for reverting. Persisted, so
    /// a relaunch (when the desktop already shows one of Meshy's own snapshots) keeps the real one.
    private var originalDesktopPictures: [String: URL] = [:] {
        didSet {
            UserDefaults.standard.set(
                originalDesktopPictures.mapValues(\.path),
                forKey: Self.originalPicturesKey
            )
        }
    }
    private var screenObserver: Any?
    /// Increments per start/stop so only the latest one clears `isLoading`.
    private var loadingGeneration = 0

    @Published
    var selectedWallpaper: WallpaperType?
    @Published
    var isLoading: Bool = false
    /// Fluid selection per screen (`NSScreen.uuidString` → selection).
    @Published
    private(set) var selections: [String: FluidSelection] = [:]
    /// Flow selection per screen.
    @Published
    private(set) var flowSelections: [String: FlowSelection] = [:]
    /// Screen the menu bar popover is currently editing.
    @Published
    var targetScreenID: String?
    @Published
    private(set) var screens: [NSScreen] = NSScreen.screens

    var isUsingWallpaper: Bool {
        !windowControllers.isEmpty || selectedWallpaper != nil
    }

    var targetScreen: NSScreen? {
        screens.first { $0.uuidString == targetScreenID } ?? NSScreen.main ?? screens.first
    }

    var targetSelection: FluidSelection {
        targetScreen.map { selection(for: $0.uuidString) } ?? .random
    }

    var targetFluidViewModel: FluidViewModel? {
        targetScreen.flatMap { fluidWindow(for: $0.uuidString)?.viewModel }
    }

    var fluidViewModels: [FluidViewModel] {
        windowControllers.values.compactMap { ($0.window as? FluidWindow)?.viewModel }
    }

    var targetFlowSelection: FlowSelection {
        targetScreen.map { flowSelection(for: $0.uuidString) } ?? .random
    }

    var targetFlowViewModel: FlowViewModel? {
        targetScreen.flatMap { (windowControllers[$0.uuidString]?.window as? FlowWindow)?.viewModel }
    }

    var flowViewModels: [FlowViewModel] {
        windowControllers.values.compactMap { ($0.window as? FlowWindow)?.viewModel }
    }

    /// Re-checks every wallpaper's "pause when an app is full screen" state.
    func updatePauseStates() {
        fluidViewModels.forEach { $0.updatePauseState() }
        flowViewModels.forEach { $0.updatePauseState() }
    }

    init() {
        let stored = UserDefaults.standard.dictionary(forKey: Self.selectionsKey) as? [String: String] ?? [:]
        selections = stored.mapValues(FluidSelection.init(storageValue:))
        let storedFlow = UserDefaults.standard.dictionary(forKey: Self.flowSelectionsKey) as? [String: String] ?? [:]
        flowSelections = storedFlow.mapValues(FlowSelection.init(storageValue:))

        let storedPictures = UserDefaults.standard.dictionary(forKey: Self.originalPicturesKey) as? [String: String] ?? [:]
        originalDesktopPictures = storedPictures.mapValues { URL(fileURLWithPath: $0) }
        NSScreen.screens.forEach(rememberDesktopPicture)

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.screensDidChange() }
        }

        let lastTypeRaw = UserDefaults.standard.string(forKey: "lastWallpaperType")
        if let lastTypeRaw, let lastType = WallpaperType(rawValue: lastTypeRaw) {
            Task {
                do {
                    try await start(lastType)
                } catch {
                    print(error)
                }
            }
        } else if UserDefaults.standard.bool(forKey: "shouldStartFWOnLaunch") {
            Task {
                do {
                    try await start(.fluid)
                } catch {
                    print(error)
                }
            }
        }
    }

    /// Screen name for menus; numbered when several screens share the same model name.
    func displayName(for screen: NSScreen) -> String {
        let sameName = screens.filter { $0.localizedName == screen.localizedName }
        guard sameName.count > 1,
              let index = sameName.firstIndex(where: { $0.uuidString == screen.uuidString })
        else { return screen.localizedName }
        return "\(screen.localizedName) (\(index + 1))"
    }

    // MARK: - Selections

    /// Stored selection for a screen, or nil if it was never set.
    nonisolated static func storedSelection(for screenID: String) -> FluidSelection? {
        let stored = UserDefaults.standard.dictionary(forKey: selectionsKey) as? [String: String]
        return stored?[screenID].map(FluidSelection.init(storageValue:))
    }

    func selection(for screenID: String) -> FluidSelection {
        selections[screenID] ?? .random
    }

    /// Sets and applies a selection on the screen the popover is targeting.
    func selectForTarget(_ selection: FluidSelection) {
        guard let screenID = targetScreen?.uuidString else { return }
        select(selection, for: screenID)
    }

    func select(_ selection: FluidSelection, for screenID: String) {
        selections[screenID] = selection
        persistSelections()
        fluidWindow(for: screenID)?.viewModel?.apply(selection)
    }

    /// Screens showing a deleted custom wallpaper fall back to random.
    func customWallpaperDeleted(_ id: UUID) {
        for screen in screens where selection(for: screen.uuidString) == .custom(id) {
            select(.random, for: screen.uuidString)
        }
    }

    private func persistSelections() {
        UserDefaults.standard.set(selections.mapValues(\.storageValue), forKey: Self.selectionsKey)
    }

    // MARK: - Flow selections

    nonisolated static func storedFlowSelection(for screenID: String) -> FlowSelection? {
        let stored = UserDefaults.standard.dictionary(forKey: flowSelectionsKey) as? [String: String]
        return stored?[screenID].map(FlowSelection.init(storageValue:))
    }

    func flowSelection(for screenID: String) -> FlowSelection {
        flowSelections[screenID] ?? .random
    }

    /// Sets and applies a Flow selection on the screen the popover is targeting.
    func selectFlowForTarget(_ selection: FlowSelection) {
        guard let screenID = targetScreen?.uuidString else { return }
        selectFlow(selection, for: screenID)
    }

    func selectFlow(_ selection: FlowSelection, for screenID: String) {
        flowSelections[screenID] = selection
        UserDefaults.standard.set(flowSelections.mapValues(\.storageValue), forKey: Self.flowSelectionsKey)
        (windowControllers[screenID]?.window as? FlowWindow)?.viewModel?.apply(selection)
    }

    /// Screens showing a deleted custom Flow fall back to random.
    func customFlowDeleted(_ id: UUID) {
        for screen in screens where flowSelection(for: screen.uuidString) == .custom(id) {
            selectFlow(.random, for: screen.uuidString)
        }
    }

    /// Screens showing an edited custom Flow pick up the change.
    func customFlowChanged(_ id: UUID) {
        for viewModel in flowViewModels where viewModel.selection == .custom(id) {
            viewModel.apply(.custom(id))
        }
    }

    // MARK: - Windows

    func fluidWindow(for screenID: String) -> FluidWindow? {
        windowControllers[screenID]?.window as? FluidWindow
    }

    private func makeWindow(_ wallpaper: WallpaperType, for screen: NSScreen) {
        let window: WallpaperWindow
        switch wallpaper {
        case .fluid:
            window = FluidWindow(screen: screen, selection: selection(for: screen.uuidString))
        case .video:
            window = VideoWindow(screen: screen)
        case .flow:
            window = FlowWindow(screen: screen, selection: flowSelection(for: screen.uuidString))
        }
        let controller = NSWindowController(window: window)
        windowControllers[screen.uuidString] = controller
        controller.showWindow(nil)
    }

    private func screensDidChange() {
        let current = NSScreen.screens
        screens = current
        let currentIDs = Set(current.map(\.uuidString))

        if targetScreenID.map({ !currentIDs.contains($0) }) ?? false {
            targetScreenID = nil
        }

        guard let wallpaper = selectedWallpaper, !isLoading else { return }

        // Close windows of disconnected screens.
        for (id, controller) in windowControllers where !currentIDs.contains(id) {
            controller.close()
            windowControllers[id] = nil
        }

        // Add windows for newly connected screens.
        for screen in current where windowControllers[screen.uuidString] == nil {
            rememberDesktopPicture(screen)
            makeWindow(wallpaper, for: screen)
        }
    }

    // MARK: - Start / stop

    @discardableResult
    func toggle(_ wallpaper: WallpaperType) async throws -> Bool {
        let isUsingWallpaper = isUsingWallpaper

        if isUsingWallpaper {
            try await stop()
            return false
        } else {
            try await start(wallpaper)
            return true
        }
    }

    func start(_ wallpaper: WallpaperType) async throws {
        // The latest request wins (rejecting taps while loading made Start seem unresponsive),
        // and the flag is always cleared: a stuck `isLoading` used to block every later Start.
        loadingGeneration += 1
        let generation = loadingGeneration
        isLoading = true
        defer { if generation == loadingGeneration { isLoading = false } }

        // Switching wallpapers: the new one replaces the desktop picture right away, so don't
        // revert to the original in between.
        closeWindows()

        screens = NSScreen.screens
        for screen in screens {
            rememberDesktopPicture(screen)
            makeWindow(wallpaper, for: screen)
        }

        selectedWallpaper = wallpaper
        UserDefaults.standard.set(wallpaper.rawValue, forKey: "lastWallpaperType")

        try? await Task.sleep(nanoseconds: 1_000_000_000)
    }

    func stop() async throws {
        loadingGeneration += 1
        isLoading = false

        let isUsingWallpaper = isUsingWallpaper
        closeWindows()
        UserDefaults.standard.removeObject(forKey: "lastWallpaperType")

        if isUsingWallpaper {
            revertDesktopPicture()
        }
    }

    private func closeWindows() {
        windowControllers.values.forEach { $0.close() }
        windowControllers = [:]
        selectedWallpaper = nil
    }

    /// Files Meshy writes as desktop pictures (snapshots of the live wallpaper) live in the
    /// temporary directory or, for video frames and Flow stills, in Meshy's caches; they are never the user's
    /// own picture.
    private static func isMeshySnapshot(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        return [FileManager.default.temporaryDirectory, DesktopSnapshot.videoFramesFolder, DesktopSnapshot.flowStillsFolder]
            .contains { path.hasPrefix($0.resolvingSymlinksInPath().path) }
    }

    private func rememberDesktopPicture(_ screen: NSScreen) {
        guard let current = NSWorkspace.shared.desktopImageURL(for: screen),
              !Self.isMeshySnapshot(current) else { return }
        originalDesktopPictures[screen.uuidString] = current
    }

    func refresh() {
        for viewModel in fluidViewModels {
            viewModel.regenerate()
            viewModel.setTimer()
        }
        for viewModel in flowViewModels {
            viewModel.refresh()
            viewModel.setTimer()
        }
    }

    /// Puts back each screen's original picture. Screens whose original no longer exists keep
    /// Meshy's last snapshot; one failing screen doesn't stop the others.
    func revertDesktopPicture() {
        let workspace = NSWorkspace.shared
        for screen in NSScreen.screens {
            guard let original = originalDesktopPictures[screen.uuidString],
                  original != workspace.desktopImageURL(for: screen),
                  FileManager.default.fileExists(atPath: original.path) else { continue }
            do {
                try workspace.setDesktopImageURL(original, for: screen)
            } catch {
                print("Couldn't restore desktop picture for \(screen.localizedName): \(error)")
            }
        }
    }
}
