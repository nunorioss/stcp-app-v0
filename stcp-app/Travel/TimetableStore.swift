//
//  TimetableStore.swift
//  stcp-app
//
//  Created by Nuno Rios on 21/10/2026.
//

import Foundation

/// Hands out one `Timetable` per service type: from memory, then the disk cache,
/// and only builds it from SwiftData when the bundled store changed.
@MainActor
enum TimetableStore {
    /// Stops closer than this are linked by a walking transfer.
    private static let transferRadius = 400.0

    private static var tasks: [Int: Task<Timetable, Never>] = [:]

    static func timetable(for serviceType: Int) async -> Timetable {
        if let task = tasks[serviceType] {
            return await task.value
        }
        let version = SwiftDataManager.storeVersion
        let task = Task {
            let cached = await Task.detached(priority: .userInitiated) {
                Timetable.load(storeVersion: version, serviceType: serviceType)
            }.value
            if let cached {
                return cached
            }
            let built = await build(serviceType: serviceType)
            Task.detached(priority: .utility) { built.save(storeVersion: version) }
            return built
        }
        tasks[serviceType] = task
        return await task.value
    }

    /// Groups each route's trips into patterns (same stop sequence, no overtaking).
    /// Runs on the main actor because the models live there, yielding after every route.
    private static func build(serviceType: Int) async -> Timetable {
        let stops = DataStore.getBusStops()
        var index: [String: Int32] = [:]
        for (i, stop) in stops.enumerated() { index[stop.id] = Int32(i) }

        var patterns: [Timetable.Pattern] = []

        for line in DataStore.getBusLines() {
            for route in line.storedRoutes {
                var rows: [(id: String, stops: [Int32], times: [Int32])] = []
                for trip in route.trips where trip.serviceType.rawValue == serviceType {
                    let tripStops = trip.tripStops
                    let ids = tripStops.compactMap { index[$0.stop.id] }
                    guard ids.count == tripStops.count, ids.count > 1 else { continue }
                    rows.append((trip.id, ids, tripStops.map { Int32($0.etaNumeric) }))
                }
                rows.sort { $0.times[0] < $1.times[0] }

                var byStops: [[Int32]: [Int]] = [:]
                for row in rows {
                    // a trip that overtakes the previous one goes into a separate pattern,
                    // so binary search on departures stays valid
                    let fit = byStops[row.stops]?.first { p in
                        let last = patterns[p].tripCount - 1
                        return row.times.indices.allSatisfy { patterns[p].time(trip: last, at: $0) <= row.times[$0] }
                    }
                    let p = fit ?? patterns.count
                    if fit == nil {
                        patterns.append(Timetable.Pattern(lineId: line.id,
                                                          direction: route.direction,
                                                          routeSortIndex: route.sortIndex,
                                                          headsign: route.headsign,
                                                          stops: row.stops))
                        byStops[row.stops, default: []].append(p)
                    }
                    patterns[p].tripIds.append(row.id)
                    patterns[p].times += row.times
                }
                await Task.yield()
            }
        }

        var stopPatterns = [[Timetable.StopPattern]](repeating: [], count: stops.count)
        for (p, pattern) in patterns.enumerated() {
            for (position, stop) in pattern.stops.enumerated() {
                stopPatterns[Int(stop)].append(.init(pattern: Int32(p), position: Int32(position)))
            }
        }

        let coords = stops.map(\.location)
        return Timetable(serviceType: serviceType,
                         stopIds: stops.map(\.id),
                         stopNames: stops.map(\.name),
                         coords: coords,
                         patterns: patterns,
                         stopPatterns: stopPatterns,
                         transfers: Timetable.transfers(between: coords, within: transferRadius))
    }
}
