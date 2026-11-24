//
//  FlowEditorView.swift
//  Meshy
//

import FlowKit
import SwiftUI

/// What the Flow Editor opens with: a new Flow (from the targeted screen's current preset) or
/// an existing custom. Set before opening the window; an open editor picks up the change.
@MainActor
final class FlowEditorState: ObservableObject {
    static let shared = FlowEditorState()

    enum Request: Equatable {
        case new
        case edit(UUID)
    }

    @Published
    private(set) var request: Request = .new
    /// Changes on every request, so asking again for the same one still reloads the editor.
    @Published
    private(set) var token = UUID()

    func prepareNew() {
        request = .new
        token = UUID()
    }

    func prepareEditing(_ id: UUID) {
        request = .edit(id)
        token = UUID()
    }
}

struct FlowEditorView: View {
    @ObservedObject
    private var state = FlowEditorState.shared

    // MARK: - What's being edited

    @State private var palette: FlowPalette = FlowPreset.all[0].palette
    @State private var settings: FlowSettings = .default
    @State private var basePreset: String? = FlowPreset.all[0].name
    /// The custom being edited (nil for a new one).
    @State private var editingID: UUID?
    @State private var editingName: String = ""
    /// The background liquid follows the background color until it's picked by hand.
    @State private var isLiquidAutomatic: Bool = true

    // MARK: - UI state

    @State private var showColors: Bool = false
    @State private var showDrops: Bool = false
    @State private var showSaveDialog: Bool = false
    @State private var saveName: String = ""
    @State private var showAppliedBadge: Bool = false
    @State private var badgeText: String = ""
    @State private var showExport: Bool = false
    @State private var previewID = UUID()
    /// The preview is created once the window is on screen: an MTKView made while its window
    /// is still being set up never starts drawing (blank preview until Restart).
    @State private var showsPreview: Bool = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if showsPreview {
                FlowView(palette: palette, settings: settings, framesPerSecond: 60)
                    .id(previewID)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }

            if showAppliedBadge {
                Label(badgeText, systemImage: "checkmark.circle.fill")
                    .font(.caption.bold())
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding()
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                presetMenu
            }

            ToolbarItem(placement: .navigation) {
                Button {
                    previewID = UUID()
                } label: {
                    Label("Restart", systemImage: "arrow.counterclockwise")
                }
                .help("Start over with new motion")
            }

            ToolbarItem(id: "colors") {
                Button {
                    showColors.toggle()
                } label: {
                    Label("Colors", systemImage: "paintpalette.fill")
                }
                .popover(isPresented: $showColors, arrowEdge: .bottom) {
                    colorsPopover
                }
            }

            ToolbarItem(id: "drops") {
                Button {
                    showDrops.toggle()
                } label: {
                    Label("Drops", systemImage: "drop.fill")
                }
                .popover(isPresented: $showDrops, arrowEdge: .bottom) {
                    dropsPopover
                }
            }

            ToolbarItem(id: "apply", placement: .primaryAction) {
                Button {
                    applyToWallpaper()
                } label: {
                    Label("Apply to Wallpaper", systemImage: "rectangle.on.rectangle")
                }
                .buttonStyle(.borderedProminent)
            }

            ToolbarItem(id: "export", placement: .primaryAction) {
                Button {
                    showExport.toggle()
                } label: {
                    Label("Export Image...", systemImage: "photo")
                }
                .help("Export Image…")
                .popover(isPresented: $showExport, arrowEdge: .bottom) {
                    ImageExportView(defaultName: "Meshy Flow", canShuffle: true, render: renderImage) {
                        showBadge("Image Saved")
                    }
                }
            }

            ToolbarItem(id: "save", placement: .primaryAction) {
                if editingID != nil {
                    Menu {
                        Button("Save as New…") {
                            saveName = ""
                            showSaveDialog = true
                        }
                    } label: {
                        Label("Save", systemImage: "square.and.arrow.down")
                    } primaryAction: {
                        saveChanges()
                    }
                    .help("Save changes to “\(editingName)”")
                } else {
                    Button {
                        saveName = ""
                        showSaveDialog = true
                    } label: {
                        Label("Save Custom...", systemImage: "square.and.arrow.down")
                    }
                }
            }
        }
        .alert("Save Custom Flow", isPresented: $showSaveDialog) {
            TextField("Name", text: $saveName)
            Button("Save") { saveAsNew() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a name for this custom Flow.")
        }
        .onAppear {
            load()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                withAnimation(.easeOut(duration: 0.3)) { showsPreview = true }
            }
        }
        .onChange(of: state.token) { _ in load() }
        .frame(minWidth: 500, minHeight: 350)
    }

    // MARK: - Preset

    var presetMenu: some View {
        Menu {
            ForEach(FlowPreset.all) { preset in
                Button(preset.name) {
                    start(from: preset)
                }
            }
        } label: {
            Label(basePreset ?? "Preset", systemImage: "swatchpalette")
                .labelStyle(.titleAndIcon)
        }
        .help("Start from a preset")
    }

    private func start(from preset: FlowPreset) {
        palette = preset.palette
        basePreset = preset.name
        isLiquidAutomatic = true
    }

    // MARK: - Colors

    var colorsPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Colors")
                .font(.headline)

            colorRow("Background", color: Binding(get: { palette.background }, set: { color in
                palette.background = color
                if isLiquidAutomatic { palette.liquid = FlowPalette.defaultLiquid(for: color) }
            }))

            HStack {
                colorRow("Background 2", color: Binding(get: { palette.liquid }, set: { color in
                    palette.liquid = color
                    isLiquidAutomatic = false
                }))
                Button("Auto") {
                    palette.liquid = FlowPalette.defaultLiquid(for: palette.background)
                    isLiquidAutomatic = true
                }
                .controlSize(.small)
                .disabled(isLiquidAutomatic)
                .help("A neighbouring shade of the background")
            }

            colorRow("Halo", color: $palette.halo)

            Divider()

            HStack {
                Text("Drops")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                ForEach(palette.drops.indices, id: \.self) { index in
                    ColorPicker("", selection: cgBinding(Binding(
                        get: { palette.drops[min(index, palette.drops.count - 1)] },
                        set: { palette.drops[index] = $0 }
                    )), supportsOpacity: false)
                    .labelsHidden()
                }
                Button {
                    palette.drops.removeLast()
                } label: {
                    Image(systemName: "minus")
                }
                .disabled(palette.drops.count <= 1)
                Button {
                    palette.drops.append(palette.drops.last ?? palette.halo)
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(palette.drops.count >= FlowSettings.standardDropCount)
            }
            .controlSize(.small)

            Text("With a second color, drops of both colors mix as they meet.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 300)
    }

    func colorRow(_ title: String, color: Binding<FlowColor>) -> some View {
        HStack {
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            ColorPicker("", selection: cgBinding(color), supportsOpacity: false)
                .labelsHidden()
        }
    }

    func cgBinding(_ color: Binding<FlowColor>) -> Binding<CGColor> {
        Binding(
            get: { color.wrappedValue.cgColor },
            set: { if let converted = FlowColor(cgColor: $0) { color.wrappedValue = converted } }
        )
    }

    // MARK: - Drops

    var dropsPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Drops")
                .font(.headline)

            sliderRow("Smallest", icon: "circle.fill", value: Binding(get: { settings.minSize }, set: { size in
                settings.minSize = size
                settings.maxSize = max(settings.maxSize, size)
            }), range: FlowSettings.sizeRange, format: { "\(Int(($0 * 100).rounded()))%" })

            sliderRow("Largest", icon: "circle.circle.fill", value: Binding(get: { settings.maxSize }, set: { size in
                settings.maxSize = size
                settings.minSize = min(settings.minSize, size)
            }), range: FlowSettings.sizeRange, format: { "\(Int(($0 * 100).rounded()))%" })

            sliderRow("Speed", icon: "speedometer", value: $settings.speed, range: FlowSettings.speedRange,
                      format: { String(format: "%.1f×", $0) })

            Text("Sizes are a fraction of the screen's height.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 340)
    }

    func sliderRow(_ title: String, icon: String, value: Binding<Double>, range: ClosedRange<Double>,
                   format: @escaping (Double) -> String) -> some View {
        HStack(spacing: 6) {
            Label(title, systemImage: icon)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            Slider(value: value, in: range)
            Text(format(value.wrappedValue))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
    }

    // MARK: - Loading

    private func load() {
        switch state.request {
        case let .edit(id):
            if let config = FlowCustomConfig.loadAll().first(where: { $0.id == id }) {
                palette = config.palette
                settings = config.settings
                basePreset = config.basePreset
                editingID = config.id
                editingName = config.name
                isLiquidAutomatic = config.palette.liquid == FlowPalette.defaultLiquid(for: config.palette.background)
                return
            }
            fallthrough
        case .new:
            // Start from what the targeted screen shows.
            let viewModel = WallpaperService.shared.targetFlowViewModel
            let preset = viewModel?.currentPreset ?? FlowPreset.all[0]
            palette = viewModel?.palette ?? preset.palette
            settings = viewModel?.settings ?? .default
            basePreset = viewModel?.currentPreset?.name ?? preset.name
            editingID = nil
            editingName = ""
            isLiquidAutomatic = palette.liquid == FlowPalette.defaultLiquid(for: palette.background)
        }
    }

    // MARK: - Actions

    private var currentConfig: FlowCustomConfig {
        FlowCustomConfig(id: editingID ?? UUID(), name: editingName.isEmpty ? "Flow Editor" : editingName,
                         basePreset: basePreset, palette: palette, settings: settings.validated)
    }

    private func applyToWallpaper() {
        let config = currentConfig
        let service = WallpaperService.shared
        Task { @MainActor in
            if service.selectedWallpaper != .flow {
                try? await service.start(.flow)
            }
            service.targetFlowViewModel?.apply(config)
            showBadge("Applied to Desktop")
        }
    }

    private func renderImage(width: Int, height: Int, seed: UInt64) async -> CGImage? {
        let palette = palette, settings = settings
        return await Task.detached(priority: .userInitiated) {
            FlowRenderer.still(palette: palette, settings: settings, width: width, height: height,
                               seed: seed, grain: 0.012)
        }.value
    }

    private func showBadge(_ text: String) {
        badgeText = text
        Task { @MainActor in
            withAnimation { showAppliedBadge = true }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { showAppliedBadge = false }
        }
    }

    private func saveChanges() {
        guard let editingID else { return }
        FlowCustomConfig.save(currentConfig)
        WallpaperService.shared.customFlowChanged(editingID)
    }

    private func saveAsNew() {
        let name = saveName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let config = FlowCustomConfig(name: name, basePreset: basePreset, palette: palette, settings: settings.validated)
        FlowCustomConfig.save(config)
        editingID = config.id
        editingName = name
        saveName = ""
        // Show it right away when Flow is running.
        if WallpaperService.shared.selectedWallpaper == .flow {
            WallpaperService.shared.selectFlowForTarget(.custom(config.id))
        }
    }
}
