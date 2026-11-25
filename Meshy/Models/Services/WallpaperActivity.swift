//
//  WallpaperActivity.swift
//  Meshy
//

import AppKit

/// Decides, for one wallpaper window, whether it should be drawing and how often. One place for
/// every reason to stop (another app full screen, the window fully covered, the displays asleep)
/// and to slow down (the screen's refresh rate, Low Power Mode, a hot Mac), so Fluid, Flow and
/// videos behave the same and low-end Macs don't spend their GPU on a wallpaper nobody sees.
@MainActor
final class WallpaperActivity {
    struct State: Equatable {
        var isPaused = false
        /// Upper limit for the wallpaper's frame rate; the user's setting applies below it.
        var maxFramesPerSecond = 60
    }

    /// Frame rate cap in Low Power Mode or when the Mac is hot.
    static let reducedFramesPerSecond = 20
    /// The window must stay covered this long before pausing: occlusion flickers while windows
    /// animate over the desktop.
    private static let occlusionDelay: TimeInterval = 1

    private(set) var state = State()
    var onChange: ((State) -> Void)? {
        didSet { onChange?(state) }
    }

    private weak var window: NSWindow?
    private let screenID: String
    private var isOccluded = false
    private var screensAsleep = false
    private var occlusionWork: DispatchWorkItem?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init(window: NSWindow, screenID: String) {
        self.window = window
        self.screenID = screenID
        UserDefaults.standard.register(defaults: ["pauseOnGameMode": true])

        let workspace = NSWorkspace.shared.notificationCenter
        // Another app going (or leaving) full screen.
        observe(workspace, [NSWorkspace.didActivateApplicationNotification,
                            NSWorkspace.didDeactivateApplicationNotification,
                            NSWorkspace.activeSpaceDidChangeNotification]) { $0.update() }
        observe(workspace, [NSWorkspace.screensDidSleepNotification]) { $0.screensAsleep = true; $0.update() }
        observe(workspace, [NSWorkspace.screensDidWakeNotification]) { $0.screensAsleep = false; $0.update() }
        observe(NotificationCenter.default, [NSWindow.didChangeOcclusionStateNotification]) { $0.occlusionDidChange() }
        observe(NotificationCenter.default, [NSApplication.didChangeScreenParametersNotification,
                                             .NSProcessInfoPowerStateDidChange,
                                             ProcessInfo.thermalStateDidChangeNotification]) { $0.update() }
        update()
    }

    func invalidate() {
        observers.forEach { center, token in center.removeObserver(token) }
        observers = []
        occlusionWork?.cancel()
        onChange = nil
    }

    /// Re-evaluates everything (also called when the "pause in full screen" setting changes).
    func update() {
        let pauseOnGameMode = UserDefaults.standard.bool(forKey: "pauseOnGameMode")
        var next = State()
        next.isPaused = screensAsleep || isOccluded
            || (pauseOnGameMode && GameMode.isOtherAppFullScreen(on: screenID))
        next.maxFramesPerSecond = Self.maxFramesPerSecond(on: screen)
        guard next != state else { return }
        state = next
        onChange?(next)
    }

    private var screen: NSScreen? {
        NSScreen.screens.first { $0.uuidString == screenID }
    }

    /// The screen's refresh rate (no point drawing 120 fps on a 60 Hz display), lowered in Low
    /// Power Mode or when macOS reports the Mac running hot.
    static func maxFramesPerSecond(on screen: NSScreen?) -> Int {
        let refreshRate = max(screen?.maximumFramesPerSecond ?? 60, 1)
        let info = ProcessInfo.processInfo
        if info.isLowPowerModeEnabled || info.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue {
            return min(refreshRate, reducedFramesPerSecond)
        }
        return refreshRate
    }

    /// Whether any connected screen refreshes faster than 60 Hz (Settings only offers 120 fps then).
    static var anyScreenAbove60Hz: Bool {
        NSScreen.screens.contains { $0.maximumFramesPerSecond > 60 }
    }

    /// Pauses only once the window has stayed covered for a moment; resumes right away.
    private func occlusionDidChange() {
        guard let window else { return }
        let visible = window.occlusionState.contains(.visible)
        occlusionWork?.cancel()
        if visible {
            isOccluded = false
            update()
        } else {
            let work = DispatchWorkItem { [weak self] in
                guard let self, let window = self.window, !window.occlusionState.contains(.visible) else { return }
                self.isOccluded = true
                self.update()
            }
            occlusionWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.occlusionDelay, execute: work)
        }
    }

    private func observe(_ center: NotificationCenter, _ names: [Notification.Name],
                         _ handler: @escaping @MainActor (WallpaperActivity) -> Void) {
        for name in names {
            let object: AnyObject? = name == NSWindow.didChangeOcclusionStateNotification ? window : nil
            let token = center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    handler(self)
                }
            }
            observers.append((center, token))
        }
    }
}

/// Detects another app covering a whole screen (games, full-screen video).
enum GameMode {
    static func isOtherAppFullScreen(on screenID: String?) -> Bool {
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
        let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []

        for window in windowList {
            guard let pid = window[kCGWindowOwnerPID as String] as? Int32, pid != ownPID,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let layer = window[kCGWindowLayer as String] as? Int, layer == 0 // normal windows only
            else { continue }
            let windowRect = CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0,
                                    width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0)
            if windowRect.insetBy(dx: -1, dy: -1).contains(screenRect) {
                return true
            }
        }
        return false
    }
}
