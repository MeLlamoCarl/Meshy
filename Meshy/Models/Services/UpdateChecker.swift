//
//  UpdateChecker.swift
//  Meshy
//

import AppKit
import Foundation

/// Looks up the latest Meshy release on GitHub and offers to open its page when it's newer
/// than the running version. Meshy isn't notarized, so updating means downloading the DMG from
/// the release page; nothing is downloaded or installed here.
@MainActor
enum UpdateChecker {
    static let checksAtLaunchKey = "checkForUpdatesAtLaunch"
    static let skippedVersionKey = "skippedUpdateVersion"

    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/MeLlamoCarl/Meshy/releases/latest")!
    private static let releasesPageURL = URL(string: "https://github.com/MeLlamoCarl/Meshy/releases/latest")!

    struct Release: Decodable {
        let tagName: String
        let htmlURL: URL
        let name: String?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case name
        }

        /// "v2.0.0" → "2.0.0".
        var version: String {
            tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        }
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private static var isChecking = false

    /// At launch: quietly checks (when enabled) and only speaks up about a new, unskipped version.
    static func checkAtLaunch() {
        UserDefaults.standard.register(defaults: [checksAtLaunchKey: true])
        guard UserDefaults.standard.bool(forKey: checksAtLaunchKey) else { return }
        check(userInitiated: false)
    }

    /// From Settings: also reports being up to date or a failed check, and ignores a skipped version.
    static func checkNow() {
        check(userInitiated: true)
    }

    private static func check(userInitiated: Bool) {
        guard !isChecking else { return }
        isChecking = true
        Task {
            defer { isChecking = false }
            do {
                let release = try await fetchLatestRelease()
                if isVersion(release.version, newerThan: currentVersion) {
                    if userInitiated || UserDefaults.standard.string(forKey: skippedVersionKey) != release.version {
                        showUpdateAlert(for: release)
                    }
                } else if userInitiated {
                    showAlert(
                        title: "Meshy is up to date",
                        message: "Version \(currentVersion) is the latest release."
                    )
                }
            } catch {
                print("Update check failed:", error)
                if userInitiated {
                    showAlert(
                        title: "Couldn't check for updates",
                        message: "Check your internet connection and try again.\n\n\(error.localizedDescription)"
                    )
                }
            }
        }
    }

    private static func fetchLatestRelease() async throws -> Release {
        var request = URLRequest(url: latestReleaseURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Meshy/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(Release.self, from: data)
    }

    /// Compares dotted version numbers ("2.0.10" > "2.0.9"); missing parts count as 0.
    static func isVersion(_ version: String, newerThan other: String) -> Bool {
        func parts(_ string: String) -> [Int] {
            string.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        }
        let lhs = parts(version), rhs = parts(other)
        for index in 0 ..< max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    // MARK: - Alerts

    private static func showUpdateAlert(for release: Release) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Meshy \(release.version) is available"
        alert.informativeText = "You have version \(currentVersion). Download the new version from its release page on GitHub."
        alert.addButton(withTitle: "View Release")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Skip This Version")

        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(release.htmlURL.host == "github.com" ? release.htmlURL : releasesPageURL)
        case .alertThirdButtonReturn:
            UserDefaults.standard.set(release.version, forKey: skippedVersionKey)
        default:
            break
        }
    }

    private static func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
