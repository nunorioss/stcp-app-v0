//
//  Timetable.swift
//  stcp-app
//
//  Created by Nuno Rios on 21/10/2026.
//

import Foundation

/// One service type's whole schedule, flattened into plain arrays so RAPTOR can scan it
/// without touching SwiftData. Built once by `TimetableStore` and cached on disk.
nonisolated struct Timetable: Codable, Sendable {
    /// Bump when the layout changes so stale caches get rebuilt.
    static let formatVersion = 1

    /// Every trip that visits exactly the same stop sequence: RAPTOR's notion of a "route".
    struct Pattern: Codable, Sendable {
        let lineId: String
        let direction: Bool
        let routeSortIndex: Int
        let headsign: String
        /// Stop indices, in travel order.
        let stops: [Int32]
        /// Sorted by departure from `stops[0]`.
        var tripIds: [String] = []
        /// `tripIds.count × stops.count` times, seconds since service-day midnight.
        var times: [Int32] = []

        var tripCount: Int {
            tripIds.count
        }

        @inline(__always)
        func time(trip: Int, at position: Int) -> Int32 {
            times[trip * stops.count + position]
        }

        /// Earliest trip leaving `stops[position]` at or after `time`. Assumes trips don't overtake.
        func earliestTrip(at position: Int, departingAfter time: Int32) -> Int? {
            var lo = 0, hi = tripCount
            while lo < hi {
                let mid = (lo + hi) / 2
                if self.time(trip: mid, at: position) < time { lo = mid + 1 } else { hi = mid }
            }
            return lo < tripCount ? lo : nil
        }
    }

    struct StopPattern: Codable, Sendable {
        let pattern: Int32
        let position: Int32
    }

    /// A short walk between two nearby stops.
    struct Transfer: Codable, Sendable {
        let to: Int32
        let meters: Float
    }

    let serviceType: Int
    let stopIds: [String]
    let stopNames: [String]
    let coords: [GeoPoint]
    let patterns: [Pattern]
    let stopPatterns: [[StopPattern]]
    let transfers: [[Transfer]]

    var stopCount: Int {
        stopIds.count
    }

    func place(_ stop: Int) -> Place {
        Place(name: stopNames[stop], stopId: stopIds[stop], location: coords[stop])
    }

    /// Stops within `radius` meters of a point, with their straight-line distance.
    func stops(near point: GeoPoint, within radius: Double) -> [(stop: Int, meters: Double)] {
        var result: [(stop: Int, meters: Double)] = []
        for i in 0..<stopCount {
            let d = Self.meters(coords[i], point)
            if d <= radius { result.append((i, d)) }
        }
        return result
    }

    /// Equirectangular distance: plenty accurate at city scale, and much cheaper than CLLocation.
    static func meters(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        let dy = (b.latitude - a.latitude) * 111_320
        let dx = (b.longitude - a.longitude) * 111_320 * cos((a.latitude + b.latitude) * .pi / 360)
        return (dx * dx + dy * dy).squareRoot()
    }
}

// MARK: - Disk cache

extension Timetable {
    private static func cacheURL(storeVersion: Int, serviceType: Int) -> URL {
        URL.cachesDirectory.appending(path: "timetable-v\(formatVersion)-\(storeVersion)-\(serviceType).plist")
    }

    static func load(storeVersion: Int, serviceType: Int) -> Timetable? {
        let url = cacheURL(storeVersion: storeVersion, serviceType: serviceType)
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? PropertyListDecoder().decode(Timetable.self, from: data)
    }

    func save(storeVersion: Int) {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let url = Self.cacheURL(storeVersion: storeVersion, serviceType: serviceType)
        try? encoder.encode(self).write(to: url, options: .atomic)
    }
}
