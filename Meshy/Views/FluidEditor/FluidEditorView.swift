//
//  FluidEditorView.swift
//  Meshy
//

import MeshKit
import RandomColor
import SwiftUI

struct FluidEditorView: View {

    // MARK: - Preview state
    @State private var colors: MeshColorGrid
    @State private var meshRandomizer: MeshRandomizer?
    @State private var shouldAnimate: Bool = true
    @State private var meshPreviewID: UUID = UUID()

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

    // MARK: - Init

    init() {
        // Edit the screen the menu bar popover is targeting.
        let viewModel = WallpaperService.shared.targetFluidViewModel
        let override = viewModel?.settingsOverride
        let meshDimension = {
            let stored = UserDefaults.standard.integer(forKey: "FWMeshSize")
            return stored > 0 ? stored : 5
        }()
        let initialColors = viewModel?.colors
            ?? MeshKit.generate(
                palette: [Hue.blue],
                luminosity: .dark,
                size: MeshSize(width: meshDimension, height: meshDimension),
                withRandomizedLocations: true
            )
        _colors = .init(initialValue: initialColors)

        if let override, !override.hueNames.isEmpty {
            _selectedHueNames = .init(initialValue: Set(override.hueNames))
            _luminosity = .init(initialValue: override.luminosityName == "light" ? .light
                : override.luminosityName == "dark" ? .dark : .vibrant)
        } else if let currentPalette = viewModel?.currentPalette {
            _selectedHueNames = .init(initialValue: [currentPalette.displayTitle])
        }

        let storedSize = UserDefaults.standard.integer(forKey: "FWMeshSize")
        _meshSize = .init(initialValue: override?.meshSize ?? (storedSize > 0 ? storedSize : 5))

        let storedGrain = UserDefaults.standard.object(forKey: "FWGrainAlpha") as? Double ?? 0.05
        _grainAlpha = .init(initialValue: override?.grainAlpha ?? Float(storedGrain))

        let storedSubs = UserDefaults.standard.integer(forKey: "FWSubdivisions")
        _subdivisions = .init(initialValue: override?.subdivisions ?? Float(storedSubs > 0 ? storedSubs : 18))

        let storedSpeed = UserDefaults.standard.object(forKey: "FWCustomSpeed") as? Double ?? 4.0
        _animationSpeed = .init(initialValue: override?.animationSpeed ?? storedSpeed)
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Full-screen mesh preview
            Group {
                if shouldAnimate, let randomizer = meshRandomizer {
                    Mesh(
                        colors: colors,
                        animatorConfiguration: .init(
                            framesPerSecond: 30,
                            animationSpeedRange: animationSpeed ... animationSpeed * 1.5,
                            meshRandomizer: randomizer
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

            // Applied badge
            if showAppliedBadge {
                Label("Applied to Desktop", systemImage: "checkmark.circle.fill")
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
                .onChange(of: shouldAnimate) { value in
                    if value {
                        meshRandomizer = .withMeshColors(colors)
                    } else {
                        meshRandomizer = nil
                    }
                }
            }

            // Color picker popover
            ToolbarItem(id: "colors") {
                Button {
                    showColorPicker.toggle()
                } label: {
                    Label("Colors", systemImage: "paintpalette.fill")
                }
                .popover(isPresented: $showColorPicker) {
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
                .popover(isPresented: $showSettings) {
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
            ToolbarItem(id: "save", placement: .primaryAction) {
                Button {
                    saveName = ""
                    showSaveDialog = true
                } label: {
                    Label("Save Custom...", systemImage: "square.and.arrow.down")
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
            if shouldAnimate {
                meshRandomizer = .withMeshColors(colors)
            }
        }
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
                            Text(hue.displayTitle)
                                .font(.caption.bold())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
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
                HStack(spacing: 4) {
                    ForEach([3, 4, 5, 6, 7, 8], id: \.self) { size in
                        Button("\(size)×\(size)") {
                            meshSize = size
                            regeneratePreview()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .tint(meshSize == size ? .accentColor : .secondary)
                    }
                }
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
                    value: Binding(get: { Double(subdivisions) }, set: { subdivisions = Float($0) }),
                    range: 2 ... 32,
                    format: "%.0f",
                    step: 1
                )
                sliderRow(
                    label: "Speed",
                    icon: "speedometer",
                    value: $animationSpeed,
                    range: 1 ... 20,
                    format: "%.0fs",
                    onChange: {
                        if shouldAnimate {
                            meshPreviewID = UUID()
                        }
                    }
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
        format: String,
        step: Double? = nil,
        onChange: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: 6) {
            Label(label, systemImage: icon)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            if let step = step {
                Slider(value: value, in: range, step: step)
                    .onChange(of: value.wrappedValue) { _ in onChange?() }
            } else {
                Slider(value: value, in: range)
                    .onChange(of: value.wrappedValue) { _ in onChange?() }
            }
            Text(String(format: format, value.wrappedValue))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
    }

    // MARK: - Actions

    func regeneratePreview() {
        let hues = selectedHueNames.compactMap { name in
            Hue.allCases.first { $0.displayTitle == name }
        }
        let effectiveHues = hues.isEmpty ? [Hue.blue] : hues

        colors = MeshKit.generate(
            palette: effectiveHues,
            luminosity: luminosity.luminosity,
            size: MeshSize(width: meshSize, height: meshSize),
            withRandomizedLocations: true
        )

        if shouldAnimate {
            meshRandomizer = .withMeshColors(colors)
            meshPreviewID = UUID()
        }
    }

    func applyToWallpaper() {
        guard let viewModel = WallpaperService.shared.targetFluidViewModel else { return }

        // Settings apply to the targeted screen only, not globally.
        viewModel.settingsOverride = CustomWallpaperConfig(
            name: "Fluid Editor",
            hueNames: Array(selectedHueNames),
            luminosityName: luminosity == .light ? "light" : luminosity == .dark ? "dark" : "vibrant",
            meshSize: meshSize,
            grainAlpha: grainAlpha,
            subdivisions: subdivisions,
            animationSpeed: animationSpeed
        )
        viewModel.applyColors(colors)

        withAnimation {
            showAppliedBadge = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showAppliedBadge = false
            }
        }
    }

    func saveCustomWallpaper() {
        guard !saveName.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        let config = CustomWallpaperConfig(
            name: saveName.trimmingCharacters(in: .whitespaces),
            hueNames: Array(selectedHueNames),
            luminosityName: luminosity == .light ? "light" : luminosity == .dark ? "dark" : "vibrant",
            meshSize: meshSize,
            grainAlpha: grainAlpha,
            subdivisions: subdivisions,
            animationSpeed: animationSpeed
        )
        CustomWallpaperConfig.save(config)
        NotificationCenter.default.post(name: .customWallpapersChanged, object: nil)
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
