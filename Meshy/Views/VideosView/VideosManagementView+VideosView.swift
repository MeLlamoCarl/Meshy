//
//  VideosManagementView+VideosView.swift
//  Meshy
//
//  Created by Ethan Lipnik on 8/5/22.
//

import PixabayKit
import SwiftUI

extension VideosManagementView {
    struct VideosView: View {
        @StateObject
        var debounceObject = DebounceObject()
        @StateObject
        var downloadService = VideoDownloadService()

        @AppStorage("VWSearchItemLimit")
        var searchItemLimit: Int = 200
        @AppStorage("shouldEnableVWSafeSearch")
        var shouldEnableSafeSearch: Bool = true

        @State
        var videos: [Video] = []
        @State
        var shouldShowDownloadingVideos: Bool = false
        @State
        var sort: String = "popular"
        @State
        var editorsChoice: Bool = true
        @State
        var selectedVideo: Video?
        @State
        var filter4k: Bool = true
        @State
        var didFailToLoad: Bool = false

        @ObservedObject
        var keyStore = PixabayAPIKeyStore.shared

        @Binding
        var category: SearchCategory?

        var body: some View {
            HStack(spacing: 0) {
                if keyStore.needsKey {
                    VStack(spacing: 16) {
                        Text(keyStore.status == .invalid ? "Pixabay API key not working" : "Pixabay API key needed")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                        PixabayAPIKeyEditor()
                            .frame(maxWidth: 440)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
                } else if didFailToLoad {
                    VStack {
                        Text("Failed to load videos")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                        Text("Check that you're online.")
                            .foregroundStyle(.secondary)
                        Button("Retry") {
                            didFailToLoad = false
                            Task(priority: .high) {
                                await search()
                            }
                        }
                    }
                    .transition(.opacity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [.init(.adaptive(minimum: 150, maximum: 250))]) {
                            ForEach(videos) { video in
                                Button {
                                    selectedVideo = video
                                } label: {
                                    VideoItemView(video: video)
                                        .overlay(
                                            selectedVideo == video ? RoundedRectangle(
                                                cornerRadius: 10,
                                                style: .continuous
                                            ).stroke(Color.accentColor, lineWidth: 4) : nil
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                    .shadow(radius: 8, y: 4)
                    .background(Color("Background"))
                    // Pixabay API terms: show where results come from, with a link to Pixabay.
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        HStack(spacing: 4) {
                            Text("Videos provided by")
                            Link("Pixabay", destination: URL(string: "https://pixabay.com/videos/")!)
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(.bar)
                        .overlay(Divider(), alignment: .top)
                    }
                    .frame(maxWidth: .infinity)
                    .onTapGesture {
                        selectedVideo = nil
                    }
                }

                HStack {
                    Divider()
                    VideosManagementView.SelectedItemView(video: selectedVideo)
                        .environmentObject(downloadService)
                        .onChange(of: selectedVideo) { newValue in
                            guard let newValue else { return }
                            downloadService.getVideoIsDownloaded(newValue)
                        }
                }.frame(width: 350)
            }
            .animation(.easeInOut, value: videos)
            .animation(.easeInOut, value: didFailToLoad)
            .animation(.easeInOut, value: keyStore.needsKey)
            .sheet(isPresented: $keyStore.isEditorPresented) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Pixabay API Key")
                        .font(.title2.bold())
                    PixabayAPIKeyEditor()
                    HStack {
                        Spacer()
                        Button("Done") {
                            keyStore.isEditorPresented = false
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(20)
                .frame(width: 480)
            }
            .navigationTitle("Meshy – Manage Videos")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        keyStore.isEditorPresented = true
                    } label: {
                        Label("Pixabay API Key", systemImage: "key")
                    }
                    .help("Pixabay API Key")

                    Toggle(isOn: $editorsChoice) {
                        Label(
                            "Editors Choice",
                            systemImage: "bookmark.circle" + (editorsChoice ? ".fill" : "")
                        )
                        .animation(.easeInOut(duration: 0.1), value: editorsChoice)
                    }
                    .onChange(of: editorsChoice) { _ in
                        Task(priority: .high) {
                            await search()
                        }
                    }

                    Toggle(isOn: $filter4k) {
                        Label("4K Only", systemImage: "4k.tv")
                    }
                    .onChange(of: filter4k) { _ in
                        Task(priority: .high) {
                            await search()
                        }
                    }

                    Button {
                        shouldShowDownloadingVideos.toggle()
                    } label: {
                        Label(
                            "Downloads",
                            systemImage: "arrow.down.circle" + ((downloadService.downloadingVideos
                                    .contains(where: { $0.value != .done() })) ? ".fill" : "")
                        )
                        .animation(
                            .easeInOut(duration: 0.1),
                            value: downloadService.downloadingVideos
                        )
                    }
                    .popover(isPresented: $shouldShowDownloadingVideos) {
                        downloadsView
                    }

                    Picker(selection: $sort) {
                        Text("Popular")
                            .tag("popular")

                        Text("Latest")
                            .tag("latest")
                    } label: {
                        Label("Sort", systemImage: "line.2.horizontal.decrease.circle")
                    }
                    .pickerStyle(.menu)
                    .onChange(of: sort) { _ in
                        Task(priority: .high) {
                            await search()
                        }
                    }
                }
            }
            .searchable(text: $debounceObject.text, prompt: "Search Pixabay", suggestions: {
                Text("🔁 Looping")
                    .searchCompletion("Looping")
                Text("🍃 Nature")
                    .searchCompletion("Nature")
                Text("🦍 Gorilla")
                    .searchCompletion("Gorilla")
            })
            .onChange(of: debounceObject.debouncedText) { _ in
                Task(priority: .high) {
                    await search()
                }
            }
            .task {
                await keyStore.verify()
                await search()
            }
            // The window may stay alive while hidden; check again whenever it comes back.
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                Task { await keyStore.verify() }
            }
            .onChange(of: category) { _ in
                Task(priority: .high) {
                    await search()
                }
            }
            .onChange(of: keyStore.key) { _ in
                didFailToLoad = false
                Task(priority: .high) {
                    await search()
                }
            }
        }

        var downloadsView: some View {
            ScrollView {
                LazyVStack(spacing: 10) {
                    if downloadService.downloadingVideos.isEmpty {
                        Text("No downloads")
                            .font(.title3.bold())
                            .foregroundStyle(.secondary)
                    }
                    ForEach(
                        downloadService.downloadingVideos.sorted(by: { $0.key.id > $1.key.id }),
                        id: \.key
                    ) { video, state in
                        HStack {
                            VideoItemView(video: video)
                                .shadow(radius: 8, y: 4)
                            switch state {
                            case let .downloading(progress, _):
                                ProgressView(value: progress, total: .init(1))
                                    .progressViewStyle(.linear)
                            case .processing, .notStarted:
                                ProgressView()
                                    .progressViewStyle(.linear)
                            case .done:
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.accentColor)
                            case let .failed(error):
                                Text("Failed to download. " + error.localizedDescription)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        Divider()
                    }
                }
                .padding()
            }
            .frame(width: 300, height: 400)
        }

        func search() async {
            guard !keyStore.needsKey else { return }
            let category = category ?? .all
            do {
                let cacheName = "videos" + "-\(sort)-" + "-safeSearch \(shouldEnableSafeSearch)-" +
                    "-limit \(searchItemLimit)-" + "-editorsChoice \(editorsChoice)-" +
                    "-category \(category.rawValue)-" + "-width \(filter4k ? 3000 : 0)" +
                    debounceObject.debouncedText
                if let videos: [Video] = ResponseCache.shared.value(forKey: cacheName) {
                    self.videos = videos
                    return
                }

                let videos = try await keyStore.kit.searchVideos(
                    debounceObject.debouncedText,
                    safeSearch: shouldEnableSafeSearch,
                    order: sort,
                    type: .all,
                    editorsChoice: editorsChoice,
                    category: category,
                    minWidth: filter4k ? 3000 : 0,
                    count: searchItemLimit
                )
                self.videos = videos

                ResponseCache.shared.setValue(videos, forKey: cacheName, expiresIn: 24 * 60 * 60)
            } catch PixabayError.invalidAPIKey {
                keyStore.markInvalid()
            } catch {
                print(error)
                didFailToLoad = true
            }
        }
    }
}
