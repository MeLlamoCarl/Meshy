//
//  SettingsView+FlowWallpaperView.swift
//  Meshy
//

import FlowKit
import SwiftUI

extension SettingsView {
    struct FlowWallpaperView: View {
        struct PresetToggle: Hashable {
            let name: String
            var isOn: Bool {
                didSet { UserDefaults.standard.set(!isOn, forKey: FlowPreset.disabledKey(for: name)) }
            }

            init(_ preset: FlowPreset) {
                name = preset.name
                isOn = !UserDefaults.standard.bool(forKey: FlowPreset.disabledKey(for: preset.name))
            }
        }

        @State
        private var presets: [PresetToggle] = FlowPreset.all.map(PresetToggle.init)
        @State
        private var isShowingPresets: Bool = false
        @AppStorage("FlowSpeed")
        private var speed: Double = FlowSettings.default.speed
        @AppStorage("FlowFramerate")
        private var framerate: Int = 60
        @AppStorage("FWPaletteChangeInterval")
        private var paletteChangeInterval: Double = FluidWallpaperView.PaletteChangeInterval.oneMin.rawValue
        @AppStorage("shouldColorMatchFWMenuBar")
        private var colorMatchingMenuBar: Bool = true

        var body: some View {
            Group {
                SectionView {
                    LabeledContent("Speed") {
                        Slider(value: $speed, in: 0.4 ... 1.6) {
                            EmptyView()
                        } minimumValueLabel: {
                            Image(systemName: "tortoise.fill")
                        } maximumValueLabel: {
                            Image(systemName: "hare.fill")
                        }
                        .onChange(of: speed) { _ in refreshFlows() }
                    }

                    Picker("Framerate", selection: $framerate) {
                        Text("30 FPS").tag(30)
                        Text("60 FPS").tag(60)
                        Text("120 FPS").tag(120)
                    }
                    .pickerStyle(.menu)
                } header: {
                    Label {
                        Text("Drops")
                    } icon: {
                        Image(systemName: "drop.fill")
                            .symbolRenderingMode(.multicolor)
                    }
                } footer: {
                    Text("Flow shows glowing drops of color that drift, merge and dissolve over a soft gradient. Speed applies to the presets; custom Flows keep their own.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                SectionView {
                    Toggle("Color Match Menu Bar", isOn: $colorMatchingMenuBar)
                        .onChange(of: colorMatchingMenuBar) { _ in refreshFlows() }

                    Picker(selection: $paletteChangeInterval) {
                        ForEach(FluidWallpaperView.PaletteChangeInterval.allCases, id: \.rawValue) {
                            Text($0.displayTitle).tag($0.rawValue)
                        }
                    } label: {
                        Text("Transition Interval")
                        Text("How often 🎲 changes the preset")
                    }
                    .pickerStyle(.menu)
                    .onChange(of: paletteChangeInterval) { _ in
                        WallpaperService.shared.flowViewModels.forEach { $0.setTimer() }
                    }

                    DisclosureGroup(isExpanded: $isShowingPresets) {
                        ForEach(presets.indices, id: \.self) { index in
                            Toggle(presets[index].name, isOn: $presets[index].isOn)
                        }
                    } label: {
                        Toggle("All Presets", sources: $presets, isOn: \.isOn)
                    }
                } header: {
                    Label {
                        Text("Presets")
                    } icon: {
                        Image(systemName: "paintpalette.fill")
                            .symbolRenderingMode(.multicolor)
                    }
                }
            }
        }

        private func refreshFlows() {
            WallpaperService.shared.flowViewModels.forEach { $0.refresh() }
        }
    }
}
