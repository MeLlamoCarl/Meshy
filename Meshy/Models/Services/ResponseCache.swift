//
//  ResponseCache.swift
//  Meshy
//

import CryptoKit
import Foundation

/// Small on-disk cache for `Codable` values with an expiration date, stored as JSON in
/// `~/Library/Caches/Meshy/ResponseCache/`. Used to avoid repeating Pixabay searches.
final class ResponseCache {
    static let shared = ResponseCache()

    private struct Entry<Value: Codable>: Codable {
        let expiration: Date
        let value: Value
    }

    private let directory: URL
    private let memory = NSCache<NSString, AnyObject>()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(directory: URL = AppPaths.caches.appendingPathComponent("ResponseCache", isDirectory: true)) {
        self.directory = directory
    }

    /// The cached value for `key`, or nil if missing, expired or unreadable.
    func value<Value: Codable>(forKey key: String) -> Value? {
        let entry = memory.object(forKey: key as NSString) as? Entry<Value>
            ?? (try? Data(contentsOf: fileURL(for: key))).flatMap { try? decoder.decode(Entry<Value>.self, from: $0) }

        guard let entry, entry.expiration > Date() else {
            removeValue(forKey: key)
            return nil
        }
        memory.setObject(entry as AnyObject, forKey: key as NSString)
        return entry.value
    }

    func setValue<Value: Codable>(_ value: Value, forKey key: String, expiresIn interval: TimeInterval) {
        let entry = Entry(expiration: Date().addingTimeInterval(interval), value: value)
        memory.setObject(entry as AnyObject, forKey: key as NSString)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try encoder.encode(entry).write(to: fileURL(for: key), options: .atomic)
        } catch {
            print("ResponseCache save failed: \(error)")
        }
    }

    func removeValue(forKey key: String) {
        memory.removeObject(forKey: key as NSString)
        try? FileManager.default.removeItem(at: fileURL(for: key))
    }

    /// Keys can contain any search text (including "/"), so files are named by their hash.
    private func fileURL(for key: String) -> URL {
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash).appendingPathExtension("json")
    }
}
