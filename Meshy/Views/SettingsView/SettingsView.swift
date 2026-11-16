//
//  SettingsView.swift
//  Meshy
//
//  Created by Ethan Lipnik on 8/1/22.
//

import SwiftUI

struct SettingsView: View {
    @State
    var selection: Int = 0

    var body: some View {
        TabView(selection: $selection) {
            FormView {
                GeneralView()
            }
            .tabItem {
                Label("General", systemImage: "gearshape.fill")
            }
            .tag(0)

            FormView {
                FluidWallpaperView()
            }
            .tabItem {
                Label("Fluid", systemImage: "square.stack.3d.down.right.fill")
            }
            .tag(1)

            FormView {
                VideoWallpaperView()
            }
            .tabItem {
                Label("Video", systemImage: "play.rectangle.fill")
            }
            .tag(2)

            FormView {
                FlowWallpaperView()
            }
            .tabItem {
                Label("Flow", systemImage: "drop.fill")
            }
            .tag(3)
        }
    }

    /// A grouped form as tall as its contents when the tab opens (so the window fits each tab,
    /// with no empty space or rubber-band scrolling), up to the screen's height. Sections that
    /// expand later (e.g. "All Presets") scroll inside that height instead of resizing the window.
    struct FormView<Content: View>: View {
        @ViewBuilder
        let content: () -> Content
        @State
        private var contentHeight: CGFloat?

        var body: some View {
            Form {
                content()
            }
            .formStyle(.grouped)
            .background(FormContentHeightReader(height: $contentHeight))
            .frame(height: contentHeight.map { min($0, Self.maxHeight) } ?? 300)
        }

        static var maxHeight: CGFloat {
            max((NSScreen.main?.visibleFrame.height ?? 800) - 120, 300)
        }
    }

    /// Reads the height of the form's contents when it appears. SwiftUI's grouped `Form` is an
    /// `NSScrollView` with no API for its content size on macOS 13, so this finds it in the view
    /// hierarchy and reads its document view's height while the form settles, then stops.
    private struct FormContentHeightReader: NSViewRepresentable {
        @Binding
        var height: CGFloat?

        func makeNSView(context: Context) -> ReaderView {
            let view = ReaderView()
            view.onHeightChange = { newHeight in
                if height.map({ abs($0 - newHeight) >= 1 }) ?? true {
                    height = newHeight
                }
            }
            return view
        }

        func updateNSView(_ nsView: ReaderView, context: Context) {
            nsView.attach()
        }

        final class ReaderView: NSView {
            var onHeightChange: ((CGFloat) -> Void)?
            private weak var scrollView: NSScrollView?
            private var observer: NSObjectProtocol?

            /// How long after the form appears its height is followed (first layout passes).
            private static let settleTime: TimeInterval = 0.5

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                DispatchQueue.main.async { [weak self] in self?.attach() }
            }

            func attach() {
                guard window != nil, scrollView == nil, let found = findScrollView(),
                      let documentView = found.documentView else { return }
                scrollView = found
                documentView.postsFrameChangedNotifications = true
                observer = NotificationCenter.default.addObserver(
                    forName: NSView.frameDidChangeNotification, object: documentView, queue: .main
                ) { [weak self] _ in self?.report() }
                report()
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleTime) { [weak self] in
                    self?.stopObserving()
                }
            }

            /// The form's scroll view: the largest one under the nearest ancestor that has any.
            private func findScrollView() -> NSScrollView? {
                var ancestor = superview
                while let view = ancestor {
                    let found = Self.scrollViews(in: view)
                    if let largest = found.max(by: { $0.frame.height < $1.frame.height }) {
                        return largest
                    }
                    ancestor = view.superview
                }
                return nil
            }

            private static func scrollViews(in view: NSView) -> [NSScrollView] {
                view.subviews.flatMap { subview -> [NSScrollView] in
                    if let scrollView = subview as? NSScrollView { return [scrollView] }
                    return scrollViews(in: subview)
                }
            }

            private func report() {
                guard let scrollView, let documentView = scrollView.documentView else { return }
                // The scroll view runs under the toolbar (its top inset), which the window already
                // accounts for: only the document itself and the bottom inset count.
                let height = documentView.frame.height + scrollView.contentInsets.bottom
                guard height > 1 else { return }
                onHeightChange?(ceil(height))
            }

            private func stopObserving() {
                if let observer { NotificationCenter.default.removeObserver(observer) }
                observer = nil
            }

            deinit {
                stopObserving()
            }
        }
    }

    struct SectionView<Content: View, Header: View>: View {
        let contentView: Content
        let headerView: Header
        let footerView: AnyView?

        init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header) {
            contentView = content()
            headerView = header()
            footerView = nil
        }

        init(
            @ViewBuilder content: () -> Content,
            @ViewBuilder header: () -> Header,
            @ViewBuilder footer: () -> some View
        ) {
            contentView = content()
            headerView = header()
            footerView = AnyView(footer())
        }

        var body: some View {
            Group {
                if let footerView {
                    Section {
                        contentView
                    } header: {
                        headerView
                    } footer: {
                        footerView
                    }
                } else {
                    Section {
                        contentView
                    } header: {
                        headerView
                    }
                }
            }
        }
    }
}

struct MacSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
