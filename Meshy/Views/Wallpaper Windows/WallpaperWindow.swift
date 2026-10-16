//
//  WallpaperWindow.swift
//  Meshy
//
//  Created by Ethan Lipnik on 7/31/22.
//

import Foundation
import MeshKit

import AppKit
import SwiftUI

class WallpaperWindow: NSWindow {
    var wallpaperType: WallpaperType? { nil }

    /// `NSScreen.uuidString` of the screen this window covers.
    let screenID: String

    var targetScreen: NSScreen? {
        NSScreen.screens.first { $0.uuidString == screenID }
    }

    init(screen: NSScreen) {
        screenID = screen.uuidString
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isReleasedWhenClosed = true
        level = .init(Int(CGWindowLevelForKey(.desktopWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        ignoresMouseEvents = true
        isOpaque = false
        hasShadow = false
        backgroundColor = .clear
        identifier = .init("wallpaperWindow")

        updateScreenSize()
        // Screen changes, and opening the menu bar popover (a cheap moment to pick up a changed
        // "Show menu bar background" setting, which posts no notification).
        for name in [NSApplication.didChangeScreenParametersNotification, Notification.Name("didOpenStatusBarItem")] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.updateScreenSize()
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.isOpaque = true
            self?.backgroundColor = .black
        }
    }

    override func constrainFrameRect(_ frameRect: NSRect, to _: NSScreen?) -> NSRect {
        frameRect
    }

    /// "Show menu bar background" (System Settings → Menu Bar).
    static var showsMenuBarBackground: Bool {
        UserDefaults.standard.bool(forKey: "SLSMenuBarUseBlurredAppearance")
    }

    /// macOS draws the menu bar background from the desktop picture behind it, and stops updating
    /// it while a window covers the whole picture (the tint got stuck on an old theme). With that
    /// background shown, leave the menu bar strip uncovered: the desktop picture there is Meshy's
    /// snapshot of the current theme, so the tint follows it. With a transparent or auto-hiding menu
    /// bar, cover the whole screen so no static strip shows.
    func updateScreenSize() {
        guard let screen = targetScreen else { return }
        var frame = screen.frame
        if Self.showsMenuBarBackground {
            frame.size.height -= max(0, screen.frame.maxY - screen.visibleFrame.maxY)
        }
        if frame != self.frame {
            setFrame(frame, display: true)
        }
    }

    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}
