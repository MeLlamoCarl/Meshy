//
//  AppPaths.swift
//  Meshy
//

import Foundation

/// Folders Meshy keeps its data in.
enum AppPaths {
    static let folderName = "Meshy"

    /// `~/Movies/Meshy/Videos`: downloaded and imported video wallpapers.
    static var videos: URL {
        directory(.moviesDirectory).appendingPathComponent("Videos", isDirectory: true)
    }

    /// `~/Library/Application Support/Meshy`
    static var applicationSupport: URL {
        directory(.applicationSupportDirectory)
    }

    /// `~/Library/Caches/Meshy`
    static var caches: URL {
        directory(.cachesDirectory)
    }

    static func directory(_ base: FileManager.SearchPathDirectory) -> URL {
        FileManager.default.urls(for: base, in: .userDomainMask)[0]
            .appendingPathComponent(folderName, isDirectory: true)
    }
}
