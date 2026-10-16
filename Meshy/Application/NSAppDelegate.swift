//
//  NSAppDelegate.swift
//  Meshy
//
//  Created by Ethan Lipnik on 7/31/22.
//

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var statusBar: StatusBarController?
    private var aboutBoxWindowController: NSWindowController?

    func applicationWillFinishLaunching(_: Notification) {
        // Never run two copies (e.g. a duplicate login item, or opening the app twice).
        if isDuplicateInstance() {
            exit(0)
        }
        // Before any wallpaper starts: keep settings from previous builds valid.
        SettingsMigration.run()
    }

    /// True when an older Meshy instance is already running. Comparing launch order means
    /// that if two start at once (login), exactly one survives.
    private func isDuplicateInstance() -> Bool {
        let current = NSRunningApplication.current
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .contains { other in
                guard other != current, !other.isTerminated else { return false }
                if let otherDate = other.launchDate, let currentDate = current.launchDate,
                   otherDate != currentDate {
                    return otherDate < currentDate
                }
                return other.processIdentifier < current.processIdentifier
            }
    }

    func applicationDidFinishLaunching(_: Notification) {
        NSApplication.shared.windows.forEach { $0.close() }

        Self.statusBar = StatusBarController()
        Self.statusBar?.appDelegate = self

        NSApp.setActivationPolicy(.accessory)

        if !UserDefaults.standard.bool(forKey: "didShowOnboarding") {
            showOnboarding()
        }
    }

    @MainActor
    func applicationWillTerminate(_: Notification) {
        WallpaperService.shared.revertDesktopPicture()
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        false
    }

    func showAboutPanel() {
        if aboutBoxWindowController == nil {
            let styleMask: NSWindow.StyleMask = [.closable, .titled, .fullSizeContentView]
            let window = NSWindow()
            window.styleMask = styleMask
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.contentView = NSHostingView(rootView: AboutView().frame(width: 300, height: 580))
            aboutBoxWindowController = NSWindowController(window: window)
        }

        // Centre it on the screen the user is on (the window started at the bottom-left corner).
        if let window = aboutBoxWindowController?.window {
            window.setContentSize(NSSize(width: 300, height: 580))
            let mouse = NSEvent.mouseLocation
            if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main {
                let visible = screen.visibleFrame
                window.setFrameOrigin(NSPoint(
                    x: visible.midX - window.frame.width / 2,
                    y: visible.midY - window.frame.height / 2
                ))
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        aboutBoxWindowController?.showWindow(aboutBoxWindowController?.window)
        aboutBoxWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    func showOnboarding() {
        let onboardingWindow = OnboardingWindow()
        let onboardingController = NSWindowController(window: onboardingWindow)
        onboardingController.showWindow(onboardingWindow)
        onboardingWindow.makeKeyAndOrderFront(onboardingController)
        onboardingWindow.center()
    }
}
