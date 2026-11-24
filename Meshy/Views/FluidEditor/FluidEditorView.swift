//
//  FluidEditorView.swift
//  Meshy
//

import MeshKit
import RandomColor
import SwiftUI

/// What the Fluid Editor opens with: a new Fluid (from what the targeted screen shows) or an
/// existing custom. Set before opening the window; an open editor picks up the change.
@MainActor
final class FluidEditorState: ObservableObject {
    static let shared = FluidEditorState()

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

struct FluidEditorView: View {
    @ObservedObject
    private var state = FluidEditorState.shared


    // MARK: - Preview state
    @State private var colors: MeshColorGrid = MeshKit.generate(palette: .blue, luminosity: .dark)
    @State private var meshRandomizer: MeshRandomizer?
    @State private var shouldAnimate: Bool = true
    /// A mesh view keeps the colors, grain and pace it started with: a new ID starts a new one.
    @State private var meshPreviewID: UUID = UUID()
    /// The preview is created once the window is on screen: an MTKView made while its window
    /// is still being set up never starts drawing (blank preview).
    @State private var showsPreview: Bool = false
    @State private var restartTask: Task<Void, Never>?
    /// The custom being edited (nil for a new one).
    @State private var editingID: UUID?
    @State private var editingName: String = ""

    // MARK: - Color settings
    @State private var selectedHueNames: Set<String> = ["Blue"]
    @State private var luminosity: LuminosityOption = .dark

    // MARK: - Mesh settings
    @State private var meshSize: Int = 5
    @State private var grainAlpha: Float = 0.05
    @State private var subdivisions: Float = 18
    @State private var animationSpeed: Double = 4.0

    // MARK: - Popover state
    @State private var showColorPicker: Bool = false
    @State private var showSettings: Bool = false

    // MARK: - Save dialog
    @State private var showSaveDialog: Bool = false
    @State private var saveName: String = ""

    // MARK: - Applied feedback
    @State private var showAppliedBadge: Bool = false
    @State private var badgeText: String = ""
    @State private var showExport: Bool = false

    @AppStorage("colorSpace") private var colorSpace: ColorSpace = .sRGB

    // MARK: - Enums

    enum LuminosityOption: String, CaseIterable {
        case light = "Light"
        case dark = "Dark"
        case vibrant = "Vibrant"

        var luminosity: Luminosity {
            switch self {
            case .light: return .light
            case .dark: return .dark
            case .vibrant: return .bright
            }
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Full-screen mesh preview
            if showsPreview {
                Group {
                    if shouldAnimate, let meshRandomizer {
                        Mesh(
                            colors: colors,
                            animatorConfiguration: .init(
                                framesPerSecond: 30,
                                animationSpeedRange: animationSpeed ... animationSpeed * 1.5,
                                meshRandomizer: meshRandomizer
                            ),
                            grainAlpha: grainAlpha,
                            subdivisions: Int(subdivisions),
                            colorSpace: colorSpace.cgColorSpace
                        )
                    } else {
                        Mesh(
                            colors: colors,
                            grainAlpha: grainAlpha,
                            subdivisions: Int(subdivisions),
                            colorSpace: colorSpace.cgColorSpace
                        )
                    }
                }
                .id(meshPreviewID)
                .edgesIgnoringSafeArea(.all)
                .transition(.opacity)
            }

            // Applied badge
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
            // Regenerate
            ToolbarItem(placement: .navigation) {
                Button {
                    regeneratePreview()
                } label: {
                    Label("Regenerate", systemImage: "arrow.triangle.2.circlepath")
                }
            }

            // Animate toggle
            ToolbarItem(placement: .navigation) {
                Toggle(isOn: $shouldAnimate) {
                    Label("Animate", systemImage: "play.fill")
                }
                .help(shouldAnimate ? "Pause the preview" : "Animate the preview")
            }

            // Color picker popover
            ToolbarItem(id: "colors") {
                Button {
                    showColorPicker.toggle()
                } label: {
                    Label("Colors", systemImage: "paintpalette.fill")
                }
                .popover(isPresented: $showColorPicker, arrowEdge: .bottom) {
                    colorPickerPopover
                }
            }

            // Settings popover
            ToolbarItem(id: "settings") {
                Button {
                    showSettings.toggle()
                } label: {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
                .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                    settingsPopover
                }
            }

            // Apply button
            ToolbarItem(id: "apply", placement: .primaryAction) {
                Button {
                    applyToWallpaper()
                } label: {
                    Label("Apply to Wallpaper", systemImage: "rectangle.on.rectangle")
                }
                .buttonStyle(.borderedProminent)
            }

            // Save button
            ToolbarItem(id: "export", placement: .primaryAction) {
                Button {
                    showExport.toggle()
                } label: {
                    Label("Export Image...", systemImage: "photo")
                }
                .help("Export Image…")
                .popover(isPresented: $showExport, arrowEdge: .bottom) {
                    ImageExportView(defaultName: "Meshy Fluid", canShuffle: false, render: renderImage) {
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
        .alert("Save Custom Wallpaper", isPresented: $showSaveDialog) {
            TextField("Name", text: $saveName)
            Button("Save") { saveCustomWallpaper() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a name for this custom wallpaper preset.")
        }
        .onAppear {
            load()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                withAnimation(.easeOut(duration: 0.3)) { showsPreview = true }
            }
        }
        .onDisappear { restartTask?.cancel() }
        .onChange(of: state.token) { _ in load() }
        // The renderer makes its grain texture once, and the animation keeps its pace until each
        // point arrives: both need a new preview.
        .onChange(of: grainAlpha) { _ in restartPreviewSoon() }
        .onChange(of: animationSpeed) { _ in restartPreviewSoon() }
        .frame(minWidth: 500, minHeight: 350)
    }

    // MARK: - Color Picker Popover

    var colorPickerPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Colors")
                .font(.headline)

            Text("Select one or more palettes to combine")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [.init(.adaptive(minimum: 80), spacing: 6)], spacing: 6) {
                ForEach(Hue.presetCases, id: \.displayTitle) { hue in
                    let isSelected = selectedHueNames.contains(hue.displayTitle)
                    Button {
                        if isSelected && selectedHueNames.count > 1 {
                            selectedHueNames.remove(hue.displayTitle)
                        } else {
                            selectedHueNames.insert(hue.displayTitle)
                        }
                        regeneratePreview()
                    } label: {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(hue.representativeColor)
                                .frame(width: 10, height: 10)
                            Text(hue.presetTitle)
                                .font(.caption.bold())
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.caption2.bold())
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isSelected ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            Text("Luminosity")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("", selection: $luminosity) {
                ForEach(LuminosityOption.allCases, id: \.rawValue) {
                    Text($0.rawValue).tag($0)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: luminosity) { _ in regeneratePreview() }
        }
        .padding()
        .frame(width: 260)
    }

    // MARK: - Settings Popover

    var settingsPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .font(.headline)

            // Mesh size
            VStack(alignment: .leading, spacing: 4) {
                Label("Mesh Size", systemImage: "grid")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: Binding(get: { meshSize }, set: { size in
                    meshSize = size
                    regeneratePreview()
                })) {
                    ForEach(3 ... 8, id: \.self) { Text("\($0)×\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Divider()

            // Sliders
            VStack(spacing: 8) {
                sliderRow(
                    label: "Grain",
                    icon: "camera.filters",
                    value: Binding(get: { Double(grainAlpha) }, set: { grainAlpha = Float($0) }),
                    range: 0.01 ... 0.25,
                    format: "%.2f"
                )
                sliderRow(
                    label: "Subdivisions",
                    icon: "cube",
                    value: Binding(get: { Double(subdivisions) }, set: { subdivisions = Float($0.rounded()) }),
                    range: 2 ... 32,
                    format: "%.0f"
                )
                sliderRow(
                    label: "Speed",
                    icon: "speedometer",
                    value: $animationSpeed,
                    range: 1 ... 20,
                    format: "%.0fs"
                )
            }
        }
        .padding()
        .frame(width: 340)
    }

    @ViewBuilder
    func sliderRow(
        label: String,
        icon: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: String
    ) -> some View {
        HStack(spacing: 6) {
            Label(label, systemImage: icon)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Slider(value: value, in: range)
            Text(String(format: format, value.wrappedValue))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
    }

    // MARK: - Actions

    private func load() {
        let defaults = UserDefaults.standard
        switch state.request {
        case let .edit(id):
            if let config = CustomWallpaperConfig.loadAll().first(where: { $0.id == id }) {
                load(config)
                editingID = config.id
                editingName = config.name
                let viewModel = WallpaperService.shared.targetFluidViewModel
                if let viewModel, viewModel.selection == .custom(id) {
                    show(viewModel.colors)
                } else {
                    regeneratePreview()
                }
                return
            }
            fallthrough
        case .new:
            // Start from what the targeted screen shows.
            editingID = nil
            editingName = ""
            let viewModel = WallpaperService.shared.targetFluidViewModel
            if let config = viewModel?.settingsOverride {
                load(config)
            } else {
                selectedHueNames = [(viewModel?.currentPalette ?? .blue).displayTitle]
                luminosity = Self.currentLuminosity
                let size = defaults.integer(forKey: "FWMeshSize")
                meshSize = size > 0 ? min(max(size, 3), 8) : 5
                grainAlpha = Float(defaults.object(forKey: "FWGrainAlpha") as? Double ?? 0.05)
                let subs = defaults.integer(forKey: "FWSubdivisions")
                subdivisions = Float(subs > 0 ? subs : 18)
                let speed = defaults.double(forKey: "FWCustomSpeed")
                animationSpeed = speed > 0 ? speed : 4
            }
            if let viewModel {
                show(viewModel.colors)
            } else {
                regeneratePreview()
            }
        }
    }

    private func load(_ config: CustomWallpaperConfig) {
        selectedHueNames = config.hueNames.isEmpty ? ["Blue"] : Set(config.hueNames)
        luminosity = config.luminosityName == "light" ? .light : config.luminosityName == "dark" ? .dark : .vibrant
        meshSize = config.meshSize
        grainAlpha = config.grainAlpha
        subdivisions = config.subdivisions
        animationSpeed = config.animationSpeed > 0 ? config.animationSpeed : 4
    }

    /// The luminosity presets use right now (as in `FluidViewModel`).
    private static var currentLuminosity: LuminosityOption {
        switch WallpaperColorScheme(rawValue: UserDefaults.standard.string(forKey: "FWColorScheme") ?? "system") {
        case .light: return .light
        case .dark: return .dark
        case .system: return FluidViewModel.InterfaceStyle() == .Light ? .light : .dark
        default: return .vibrant
        }
    }

    func regeneratePreview() {
        let hues = selectedHueNames.compactMap { name in
            Hue.allCases.first { $0.displayTitle == name }
        }
        show(MeshKit.generate(
            palette: hues.isEmpty ? [Hue.blue] : hues,
            luminosity: luminosity.luminosity,
            size: MeshSize(width: meshSize, height: meshSize),
            withRandomizedLocations: true
        ))
    }

    private func show(_ newColors: MeshColorGrid) {
        restartTask?.cancel()
        colors = newColors
        meshRandomizer = .withMeshColors(newColors)
        meshPreviewID = UUID()
    }

    /// Restarts the preview once a slider pauses, not on every step of it.
    private func restartPreviewSoon() {
        restartTask?.cancel()
        restartTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            meshPreviewID = UUID()
        }
    }

    private func config(id: UUID, name: String) -> CustomWallpaperConfig {
        CustomWallpaperConfig(
            id: id,
            name: name,
            hueNames: Array(selectedHueNames),
            luminosityName: luminosity == .light ? "light" : luminosity == .dark ? "dark" : "vibrant",
            meshSize: meshSize,
            grainAlpha: grainAlpha,
            subdivisions: subdivisions,
            animationSpeed: animationSpeed
        )
    }

    func applyToWallpaper() {
        let config = config(id: editingID ?? UUID(), name: editingName.isEmpty ? "Fluid Editor" : editingName)
        let colors = colors
        let service = WallpaperService.shared
        Task { @MainActor in
            if service.selectedWallpaper != .fluid {
                try? await service.start(.fluid)
            }
            guard let viewModel = service.targetFluidViewModel else { return }
            // Applies to the targeted screen only, not globally.
            viewModel.apply(config, colors: colors)
            showBadge("Applied to Desktop")
        }
    }

    private func renderImage(width: Int, height: Int, seed _: UInt64) async -> CGImage? {
        // The grain is drawn in 8×8 blocks: draw whole ones and crop.
        let size = MeshSize(width: (width + 7) / 8 * 8, height: (height + 7) / 8 * 8)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            _ = try await colors.export(to: url, size: size, subdivisions: Int(subdivisions),
                                        grainAlpha: grainAlpha, colorSpace: colorSpace.cgColorSpace)
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
            else { return nil }
            return image.cropping(to: CGRect(x: 0, y: 0, width: width, height: height))
        } catch {
            print(error)
            return nil
        }
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
        CustomWallpaperConfig.save(config(id: editingID, name: editingName))
        NotificationCenter.default.post(name: .customWallpapersChanged, object: nil)
        WallpaperService.shared.customWallpaperChanged(editingID)
    }

    func saveCustomWallpaper() {
        let name = saveName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let config = config(id: UUID(), name: name)
        CustomWallpaperConfig.save(config)
        NotificationCenter.default.post(name: .customWallpapersChanged, object: nil)
        editingID = config.id
        editingName = name
        saveName = ""
    }
}

// MARK: - Hue helpers

extension Hue {
    var representativeColor: SwiftUI.Color {
        switch self {
        case .blue: return .blue
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .pink: return .pink
        case .purple: return .purple
        case .red: return .red
        case .monochrome: return .gray
        case .random: return .cyan
        default: return .gray
        }
    }

    var previewColors: [SwiftUI.Color] {
        switch self {
        case .blue:
            return [SwiftUI.Color(red: 0.23, green: 0.49, blue: 1.0), SwiftUI.Color(red: 0.10, green: 0.24, blue: 0.71)]
        case .orange:
            return [SwiftUI.Color(red: 1.0, green: 0.55, blue: 0.16), SwiftUI.Color(red: 0.91, green: 0.36, blue: 0.0)]
        case .yellow:
            return [SwiftUI.Color(red: 1.0, green: 0.83, blue: 0.15), SwiftUI.Color(red: 0.91, green: 0.67, blue: 0.0)]
        case .green:
            return [SwiftUI.Color(red: 0.18, green: 0.80, blue: 0.44), SwiftUI.Color(red: 0.10, green: 0.48, blue: 0.27)]
        case .pink:
            return [SwiftUI.Color(red: 1.0, green: 0.37, blue: 0.63), SwiftUI.Color(red: 0.80, green: 0.13, blue: 0.40)]
        case .purple:
            return [SwiftUI.Color(red: 0.55, green: 0.18, blue: 0.91), SwiftUI.Color(red: 0.35, green: 0.10, blue: 0.60)]
        case .red:
            return [SwiftUI.Color(red: 0.91, green: 0.19, blue: 0.19), SwiftUI.Color(red: 0.60, green: 0.10, blue: 0.10)]
        case .monochrome:
            return [SwiftUI.Color(white: 0.75), SwiftUI.Color(white: 0.25)]
        case .random:
            return [SwiftUI.Color(red: 1.0, green: 0.37, blue: 0.63), SwiftUI.Color(red: 0.23, green: 0.49, blue: 1.0), SwiftUI.Color(red: 0.18, green: 0.80, blue: 0.44)]
        default:
            return [SwiftUI.Color.gray, SwiftUI.Color.black]
        }
    }
}
