//
//  StatusBarController.swift
//  Meshy
//
//  Created by Ethan Lipnik on 8/1/22.
//

import AppKit
import SwiftUI

final class StatusBarController {
    private var statusBar: NSStatusBar
    var statusItem: NSStatusItem

    weak var appDelegate: AppDelegate?
    var popover: NSPopover!
    /// Closes the popover on clicks in other apps — `.transient` only reacts to clicks
    /// inside Meshy, which as a menu bar (accessory) app is usually not active.
    private var outsideClickMonitor: Any?
    private var popoverCloseObserver: Any?

    init() {
        statusBar = NSStatusBar.system
        // Creating a status bar item having a fixed length
        statusItem = statusBar.statusItem(withLength: NSStatusItem.squareLength)

        if let statusBarButton = statusItem.button {
            statusBarButton.image = NSImage(named: "Menubar")
            statusBarButton.image?.size = NSSize(width: 18.0, height: 18.0)
            statusBarButton.image?.isTemplate = true
            statusBarButton.target = self
            statusBarButton.action = #selector(togglePopover(_:))

            let contentView = ContentView { [weak self] in
                self?.appDelegate?.showAboutPanel()
            } openOnboarding: { [weak self] in
                self?.appDelegate?.showOnboarding()
            }.frame(width: 300)

            let viewController = NSHostingController(rootView: contentView)
            let popover = NSPopover()
            popover.contentViewController = viewController
            popover.contentSize = NSSize(width: 300, height: 300)
            popover.behavior = .transient
            popover.setValue(true, forKeyPath: "shouldHideAnchor")
            popover.show(
                relativeTo: statusBarButton.bounds,
                of: statusBarButton,
                preferredEdge: .minY
            )
            popover.contentViewController?.view.window?.makeKey()
            self.popover = popover

            popoverCloseObserver = NotificationCenter.default.addObserver(
                forName: NSPopover.didCloseNotification,
                object: popover,
                queue: .main
            ) { [weak self] _ in
                self?.stopOutsideClickMonitor()
            }
            startOutsideClickMonitor()
        }
    }

    @MainActor
    @objc
    func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }

        // Edit the screen whose menu bar was clicked (each display has its own menu bar).
        let mouseLocation = NSEvent.mouseLocation
        let clickedScreen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? sender.window?.screen
        WallpaperService.shared.targetScreenID = clickedScreen?.uuidString

        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        startOutsideClickMonitor()

        NotificationCenter.default.post(name: .init("didOpenStatusBarItem"), object: nil)
    }

    private func startOutsideClickMonitor() {
        stopOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            guard let popover = self?.popover, popover.isShown else { return }
            popover.performClose(nil)
        }
    }

    private func stopOutsideClickMonitor() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
        outsideClickMonitor = nil
    }

    @objc
    func openAbout() {
        appDelegate?.showAboutPanel()
    }
}
