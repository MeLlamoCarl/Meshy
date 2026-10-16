//
//  SettingsMigration.swift
//  Meshy
//

import AppKit
import Foundation
import ServiceManagement

/// Runs once per launch, before any wallpaper starts, so settings written by older builds keep
/// working (and invalid values fall back to defaults) after updating or switching versions.
enum SettingsMigration {
    static func run() {
        LaunchAtLogin.migrate()
        validateFluidSelections()
        validateStoredSettings()

        let info = Bundle.main.infoDictionary
        let version = "\(info?["CFBundleShortVersionString"] ?? "?") (\(info?["CFBundleVersion"] ?? "?"))"
        UserDefaults.standard.set(version, forKey: "lastLaunchedVersion")
    }

    /// Drops per-screen selections pointing at deleted customs or removed presets (e.g. Monochrome).
    private static func validateFluidSelections() {
        let defaults = UserDefaults.standard
        let customIDs = Set(CustomWallpaperConfig.loadAll().map(\.id))

        if let stored = defaults.dictionary(forKey: "FWScreenSelections") as? [String: String] {
            let validated = stored.mapValues { value -> String in
                let selection = FluidSelection(storageValue: value)
                if let id = selection.customID, !customIDs.contains(id) {
                    return FluidSelection.random.storageValue
                }
                return selection.storageValue
            }
            if validated != stored {
                defaults.set(validated, forKey: "FWScreenSelections")
            }
        }
    }

    /// Removes out-of-range or unknown values so the app falls back to its defaults.
    private static func validateStoredSettings() {
        let defaults = UserDefaults.standard

        func validateNumber(_ key: String, _ isValid: (Double) -> Bool) {
            guard let object = defaults.object(forKey: key) else { return }
            if let number = (object as? NSNumber)?.doubleValue, isValid(number) { return }
            defaults.removeObject(forKey: key)
        }

        func validateRawValue(_ key: String, _ isValid: (String) -> Bool) {
            guard defaults.object(forKey: key) != nil else { return }
            if let raw = defaults.string(forKey: key), isValid(raw) { return }
            defaults.removeObject(forKey: key)
        }

        validateNumber("FWMeshSize") { (3 ... 8).contains($0) }
        validateNumber("FWSubdivisions") { $0 > 0 }
        validateNumber("FWGrainAlpha") { (0 ... 1).contains($0) }
        validateNumber("FWCustomSpeed") { $0 >= 0 }
        validateNumber("FWFramerate") { $0 > 0 }
        validateNumber("FWPaletteChangeInterval") { $0 >= 5 }

        validateRawValue("FWAnimationSpeed") { AnimationSpeed(rawValue: $0) != nil }
        validateRawValue("FWColorScheme") { WallpaperColorScheme(rawValue: $0) != nil }
        validateRawValue("colorSpace") { ColorSpace(rawValue: $0) != nil }
        validateRawValue("lastWallpaperType") { WallpaperType(rawValue: $0) != nil }
    }
}

// MARK: - Launch at Login

/// Launch at login via a LaunchAgent plist (works without code signing).
///
/// Older builds used `SMAppService.mainApp` (Settings → General) while the menu used the
/// LaunchAgent; having both launches two instances. `migrate()` consolidates onto the agent.
enum LaunchAtLogin {
    private static var label: String { Bundle.main.bundleIdentifier ?? "com.mellamocarl.Meshy" }
    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool {
        agentExecutablePath != nil || SMAppService.mainApp.status == .enabled
    }

    static func enable() {
        writeAgent()
        unregisterLoginItem()
    }

    static func disable() {
        run("/bin/launchctl", args: ["bootout", "gui/\(getuid())", plistURL.path])
        try? FileManager.default.removeItem(at: plistURL)
        unregisterLoginItem()
    }

    /// Keeps whichever mechanism was enabled working, on the agent, pointing at this build.
    static func migrate() {
        let loginItemEnabled = SMAppService.mainApp.status == .enabled
        let agentPath = agentExecutablePath
        guard loginItemEnabled || agentPath != nil else { return }

        if agentPath != Bundle.main.executablePath {
            writeAgent()
        }
        if loginItemEnabled {
            unregisterLoginItem()
        }
    }

    private static var agentExecutablePath: String? {
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let arguments = plist["ProgramArguments"] as? [String]
        else { return nil }
        return arguments.first
    }

    /// Writes the agent without loading it: launchd picks it up at next login. Loading it now
    /// (`launchctl bootstrap` + `RunAtLoad`) would start a second instance immediately.
    private static func writeAgent() {
        guard let executablePath = Bundle.main.executablePath else { return }
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            "KeepAlive": false
        ]
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: plistURL)
        } catch {
            print("LaunchAtLogin enable failed: \(error)")
        }
    }

    private static func unregisterLoginItem() {
        guard SMAppService.mainApp.status == .enabled else { return }
        do {
            try SMAppService.mainApp.unregister()
        } catch {
            print("LaunchAtLogin login item unregister failed: \(error)")
        }
    }

    private static func run(_ path: String, args: [String]) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        try? task.run()
        task.waitUntilExit()
    }
}
