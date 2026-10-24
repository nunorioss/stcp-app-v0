//
//  SwiftDataManager.swift
//  stcp-app
//
//  Created by Nuno Rios on 16/09/2026.
//

import Foundation
import SwiftData

nonisolated enum SwiftDataManager {
    static let storeName = STCPSchema.storeName
    static let schema = STCPSchema.schema

    private static let bundledFileName = "\(storeName).zlib"
    private static let bundledVersionFileName = "\(storeName).version"
    
    // for retrieving the version number of the installed store
    private static let installedVersionKey = "SwiftDataManager.installedStoreVersion"

    static let container: ModelContainer = {
        do {
            let url = try installBundledStoreIfNeeded()
            let configuration = ModelConfiguration(schema: schema, url: url)
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    @MainActor
    static var context: ModelContext {
        container.mainContext
    }

    /// Version of the installed store, for keying caches derived from it.
    static var storeVersion: Int {
        UserDefaults.standard.integer(forKey: installedVersionKey)
    }

    /// Get the epoch seconds at which the bundled store was generated.
    private static var bundledVersion: Int {
        guard let url = Bundle.main.url(forResource: bundledVersionFileName, withExtension: nil),
              let text = try? String(contentsOf: url, encoding: .utf8),
              let version = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            fatalError("\(bundledVersionFileName) is missing or invalid in the app bundle")
        }
        return version
    }

    /// Install the bundled store if there is none installed or if its version is newer
    /// than the one currently installed, otherwise return the URL to open.
    private static func installBundledStoreIfNeeded() throws -> URL {
        let fm = FileManager.default
        let directory = try fm.url(for: .applicationSupportDirectory,
                                    in: .userDomainMask,
                                    appropriateFor: nil,
                                    create: true)
        let destination = directory.appendingPathComponent(storeName)
        
        let installedVersion = UserDefaults.standard.integer(forKey: installedVersionKey)
        let bundled = bundledVersion

        if fm.fileExists(atPath: destination.path), bundled <= installedVersion {
            return destination
        }

        guard let archiveURL = Bundle.main.url(forResource: bundledFileName, withExtension: nil) else {
            fatalError("\(bundledFileName) is missing from the app bundle")
        }

        let compressed = try Data(contentsOf: archiveURL)
        let decompressed = try (compressed as NSData).decompressed(using: .zlib) as Data

        // first write to a scratch location, then move to Application Support
        let scratch = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try decompressed.write(to: scratch, options: .atomic)
        defer { try? fm.removeItem(at: scratch) }

        for suffix in ["", "-wal", "-shm"] {
            let path = destination.path + suffix
            if fm.fileExists(atPath: path) {
                try fm.removeItem(atPath: path)
            }
        }

        try fm.moveItem(at: scratch, to: destination)

        UserDefaults.standard.set(bundled, forKey: installedVersionKey)
        return destination
    }
}
