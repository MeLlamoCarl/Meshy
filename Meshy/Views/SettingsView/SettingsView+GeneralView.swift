//
//  SettingsView+GeneralView.swift
//  Meshy
//
//  Created by Ethan Lipnik on 8/6/22.
//

import SwiftUI

extension SettingsView {
    struct GeneralView: View {
        @AppStorage("colorSpace")
        var colorSpace: ColorSpace = .sRGB
        @State
        var launchAtLogin: Bool = LaunchAtLogin.isEnabled

        var body: some View {
            SectionView {
                Toggle(isOn: $launchAtLogin) {
                    Text("Launch Meshy on system startup")
                }
                .onChange(of: launchAtLogin) { newValue in
                    // Same mechanism as the menu bar toggle, so both always agree.
                    guard newValue != LaunchAtLogin.isEnabled else { return }
                    if newValue {
                        LaunchAtLogin.enable()
                    } else {
                        LaunchAtLogin.disable()
                    }
                }
                .onAppear {
                    launchAtLogin = LaunchAtLogin.isEnabled
                }

                Picker("Color Space", selection: $colorSpace) {
                    ForEach(ColorSpace.allCases, id: \.rawValue) { colorSpace in
                        Text(colorSpace.displayName)
                            .tag(colorSpace)
                    }
                }
            } header: {
                Label {
                    Text("General")
                } icon: {
                    Image(systemName: "gearshape.fill")
                        .foregroundColor(.accentColor)
                }
            }
        }
    }
}

struct SettingsView_StartupView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView.GeneralView()
    }
}
