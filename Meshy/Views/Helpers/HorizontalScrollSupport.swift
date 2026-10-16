//
//  HorizontalScrollSupport.swift
//  Meshy
//

import AppKit
import IOKit
import IOKit.hid
import SwiftUI

// MARK: - External mouse detection

/// Tracks whether an external mouse is connected, via the IORegistry (no Input Monitoring
/// permission needed). Built-in and external trackpads don't count — they scroll sideways.
final class MouseMonitor: ObservableObject {
    static let shared = MouseMonitor()

    @Published
    private(set) var isExternalMouseConnected = false

    private var notifyPort: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []

    private init() {
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        notifyPort = port
        IONotificationPortSetDispatchQueue(port, .main)

        let context = Unmanaged.passUnretained(self).toOpaque()
        for notificationType in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            let result = IOServiceAddMatchingNotification(
                port,
                notificationType,
                Self.mouseMatching(),
                { context, iterator in
                    MouseMonitor.drain(iterator)
                    guard let context else { return }
                    let monitor = Unmanaged<MouseMonitor>.fromOpaque(context).takeUnretainedValue()
                    monitor.update()
                    // A terminating device can still be listed for a moment; check again.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { monitor.update() }
                },
                context,
                &iterator
            )
            if result == KERN_SUCCESS {
                Self.drain(iterator)  // arms the notification
                iterators.append(iterator)
            }
        }
        update()
    }

    private func update() {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, Self.mouseMatching(), &iterator) == KERN_SUCCESS
        else { return }
        defer { IOObjectRelease(iterator) }

        var found = false
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if Self.isExternalMouse(service) {
                found = true
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }

        if isExternalMouseConnected != found {
            isExternalMouseConnected = found
        }
    }

    private static func isExternalMouse(_ service: io_service_t) -> Bool {
        func property(_ key: String) -> Any? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue()
        }
        let product = property(kIOHIDProductKey) as? String ?? ""
        let transport = property(kIOHIDTransportKey) as? String ?? ""
        let builtIn = property("Built-In") as? Bool ?? false

        return !builtIn
            && transport != "SPI"  // internal keyboard/trackpad
            && !product.localizedCaseInsensitiveContains("trackpad")
            && !product.localizedCaseInsensitiveContains("internal")
    }

    private static func mouseMatching() -> CFMutableDictionary {
        let matching = IOServiceMatching(kIOHIDDeviceKey) as NSMutableDictionary
        matching[kIOHIDPrimaryUsagePageKey] = kHIDPage_GenericDesktop
        matching[kIOHIDPrimaryUsageKey] = kHIDUsage_GD_Mouse
        return matching as CFMutableDictionary
    }

    private static func drain(_ iterator: io_iterator_t) {
        var service = IOIteratorNext(iterator)
        while service != 0 {
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
    }
}

// MARK: - Horizontal scroll view support

extension View {
    /// Apply to the content of a horizontal `ScrollView`. With a mouse (`revealsScroller`), the
    /// native overlay scroll bar is shown while the pointer is over the row, and the vertical
    /// wheel scrolls it sideways (which also shows the scroll bar, as a trackpad swipe does).
    func horizontalWheelScrolling(revealsScroller: Bool) -> some View {
        background(HorizontalScrollSupport(revealsScroller: revealsScroller))
    }
}

private struct HorizontalScrollSupport: NSViewRepresentable {
    let revealsScroller: Bool

    func makeNSView(context _: Context) -> ScrollConfiguratorView {
        ScrollConfiguratorView()
    }

    func updateNSView(_ view: ScrollConfiguratorView, context _: Context) {
        view.revealsScroller = revealsScroller
    }
}

private final class ScrollConfiguratorView: NSView {
    var revealsScroller = false {
        didSet { if !revealsScroller { stopRevealing() } }
    }

    private var wheelMonitor: Any?
    private var trackingArea: NSTrackingArea?
    private weak var trackedScrollView: NSScrollView?
    private var revealTimer: Timer?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            removeObservers()
        } else {
            installObservers()
            // SwiftUI may finish building the enclosing scroll view after this view moves in.
            DispatchQueue.main.async { [weak self] in self?.installTrackingArea() }
        }
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil  // never intercept clicks on the presets
    }

    private func installTrackingArea() {
        guard let scrollView = enclosingScrollView, scrollView !== trackedScrollView else { return }
        removeTrackingArea()
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        scrollView.addTrackingArea(area)
        trackingArea = area
        trackedScrollView = scrollView
    }

    private func removeTrackingArea() {
        if let trackingArea {
            trackedScrollView?.removeTrackingArea(trackingArea)
        }
        trackingArea = nil
        trackedScrollView = nil
    }

    override func mouseEntered(with _: NSEvent) {
        guard revealsScroller else { return }
        // Overlay scroll bars fade out after a moment; keep flashing them while hovering.
        trackedScrollView?.flashScrollers()
        revealTimer?.invalidate()
        revealTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.trackedScrollView?.flashScrollers()
        }
    }

    override func mouseExited(with _: NSEvent) {
        stopRevealing()
    }

    private func stopRevealing() {
        revealTimer?.invalidate()
        revealTimer = nil
    }

    private func installObservers() {
        guard wheelMonitor == nil else { return }
        wheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.convertVerticalWheel(event) ?? event
        }
    }

    private func removeObservers() {
        if let wheelMonitor {
            NSEvent.removeMonitor(wheelMonitor)
        }
        wheelMonitor = nil
        stopRevealing()
        removeTrackingArea()
    }

    /// Turns a mouse wheel's vertical scroll over this scroll view into a horizontal one,
    /// the same way holding Shift does. Trackpads (precise deltas) are left alone.
    private func convertVerticalWheel(_ event: NSEvent) -> NSEvent? {
        guard !event.hasPreciseScrollingDeltas,
              event.scrollingDeltaX == 0, event.scrollingDeltaY != 0,
              let scrollView = enclosingScrollView,
              event.window === scrollView.window,
              scrollView.bounds.contains(scrollView.convert(event.locationInWindow, from: nil)),
              let cgEvent = event.cgEvent?.copy()
        else { return nil }

        let integerFields: [(CGEventField, CGEventField)] = [
            (.scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2),
            (.scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2),
        ]
        for (vertical, horizontal) in integerFields {
            cgEvent.setIntegerValueField(horizontal, value: cgEvent.getIntegerValueField(vertical))
            cgEvent.setIntegerValueField(vertical, value: 0)
        }
        let fixed = (CGEventField.scrollWheelEventFixedPtDeltaAxis1, CGEventField.scrollWheelEventFixedPtDeltaAxis2)
        cgEvent.setDoubleValueField(fixed.1, value: cgEvent.getDoubleValueField(fixed.0))
        cgEvent.setDoubleValueField(fixed.0, value: 0)

        return NSEvent(cgEvent: cgEvent)
    }

    deinit {
        if let wheelMonitor {
            NSEvent.removeMonitor(wheelMonitor)
        }
        revealTimer?.invalidate()
    }
}
