//
//  PixabayAPIKey.swift
//  Meshy
//

import PixabayKit
import SwiftUI

/// The user's Pixabay API key, stored in this Mac's preferences (never in the source code), and
/// whether it currently works. Shared by the Manage Videos window, Settings → Video and the menu.
@MainActor
final class PixabayAPIKeyStore: ObservableObject {
    static let shared = PixabayAPIKeyStore()
    static let storageKey = "pixabayAPIKey"

    enum Status: Equatable {
        case missing
        /// Saved but not checked yet, or couldn't be checked (offline).
        case unverified
        case checking
        case valid
        /// Pixabay rejected it: regenerated key, deleted account or typo.
        case invalid
    }

    @Published
    private(set) var key: String
    @Published
    private(set) var status: Status
    /// Shows the key editor sheet in the Manage Videos window.
    @Published
    var isEditorPresented = false

    var kit: PixabayKit { PixabayKit(key) }

    /// The editor replaces the video grid, so a new key has to be entered before searching.
    var needsKey: Bool { status == .missing || status == .invalid }

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.storageKey) ?? ""
        key = stored
        status = stored.isEmpty ? .missing : .unverified
    }

    /// Checks the saved key against Pixabay.
    func verify() async {
        guard !key.isEmpty, status != .checking else { return }
        let checkedKey = key
        status = .checking
        let result = await Self.check(checkedKey)
        guard checkedKey == key else { return }  // replaced meanwhile
        status = result
    }

    /// Verifies `newKey` and saves it unless Pixabay rejects it. Returns the resulting status.
    @discardableResult
    func save(_ newKey: String) async -> Status {
        let trimmed = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .missing }

        let result = await Self.check(trimmed)
        if result != .invalid {
            key = trimmed
            status = result
            UserDefaults.standard.set(trimmed, forKey: Self.storageKey)
        }
        return result
    }

    func remove() {
        key = ""
        status = .missing
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
    }

    /// Called when a search is rejected because of the key.
    func markInvalid() {
        if !key.isEmpty { status = .invalid }
    }

    private static func check(_ key: String) async -> Status {
        do {
            return try await PixabayKit(key).validateAPIKey() ? .valid : .invalid
        } catch {
            return .unverified
        }
    }
}

/// Shows the current key (visible, so it can be checked against pixabay.com), its status, and
/// lets the user replace or remove it.
struct PixabayAPIKeyEditor: View {
    @ObservedObject
    private var store = PixabayAPIKeyStore.shared

    @State
    private var draft = ""
    @State
    private var isSaving = false
    @State
    private var rejectedDraft: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !store.key.isEmpty {
                LabeledContent("Current key") {
                    Text(store.key)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                statusLabel
            }

            HStack {
                TextField(
                    store.key.isEmpty ? "API Key" : "New API Key",
                    text: $draft,
                    prompt: Text(store.key.isEmpty ? "Paste your Pixabay API key" : "Paste a new key to replace it")
                )
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)

                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                }
                Button(store.key.isEmpty ? "Save" : "Replace", action: save)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
            }

            if let rejectedDraft, rejectedDraft == draft {
                Label("Pixabay rejected this key. Check it and try again.", systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
            }

            HStack {
                Self.helpText
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                if !store.key.isEmpty {
                    Button("Remove Key", role: .destructive) {
                        store.remove()
                    }
                }
            }
        }
        .task {
            if store.status == .unverified {
                await store.verify()
            }
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch store.status {
        case .valid:
            Label("Working", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .invalid:
            Label(
                "This key no longer works. It may have been regenerated or its account deleted. Enter a new one.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .foregroundStyle(.orange)
        case .checking:
            Label("Checking…", systemImage: "hourglass")
                .foregroundStyle(.secondary)
        case .unverified:
            HStack {
                Label("Couldn't check the key (are you online?)", systemImage: "wifi.exclamationmark")
                    .foregroundStyle(.secondary)
                Button("Check Again") {
                    Task { await store.verify() }
                }
            }
        case .missing:
            EmptyView()
        }
    }

    private func save() {
        let candidate = draft
        guard !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !isSaving else { return }
        isSaving = true
        Task {
            let result = await store.save(candidate)
            isSaving = false
            if result == .invalid {
                rejectedDraft = candidate
            } else {
                draft = ""
                rejectedDraft = nil
            }
        }
    }

    static var helpText: some View {
        Text("Get a free key at ") + Text("[pixabay.com/api/docs](https://pixabay.com/api/docs/)")
            + Text(" (sign in, then see “Parameters” → key).")
    }
}
