//
//  BusTracker.swift
//  stcp-app
//
//  Created by Nuno Rios on 15/10/2026.
//

//
//  BusTracker.swift
//  stcp-app
//
//  The access point for live buses.
//
//  - Cold cache: the request goes straight to PortoDigital, for just the lines asked
//    for, while tracking of ALL buses starts in the background.
//  - Warm cache: requests are answered from the cache, with no network.
//  - Tracking stops after `idleTimeout` without requests.
//  - The cache lives on disk too, so it survives restarts.
//

import Foundation

@MainActor
final class BusTracker {
    static let shared = BusTracker()

    // MARK: - Tuning

    /// How often the full feed is refreshed while tracking. PortoDigital itself only
    /// updates a bus about every 75s, so this just keeps the cache from lagging behind.
    private let pollInterval: Duration = .seconds(15)
    /// Tracking stops after this long without requests.
    private let idleTimeout: TimeInterval = 60
    /// The cache is "cold" if the full feed hasn't been fetched for this long.
    private let maxCacheAge: TimeInterval = 45
    /// A bus is trusted for ~3 PortoDigital update cycles...
    private let maxStaleness: TimeInterval = 4 * 60
    /// ...or much longer if it went silent at the end of its trip.
    private let maxLayoverStaleness: TimeInterval = 20 * 60

    // MARK: - State

    private var reports: [String: BusReport] = [:]   // bus id -> latest report
    private var lastFullFetch = Date.distantPast
    private var lastRequest = Date.distantPast
    private var tracking: Task<Void, Never>?

    private init() {
        reports = Self.load()
    }

    // MARK: - API
    
    /// Live buses of one line, in one direction.
    func getLiveBuses(line: String, direction: Bool) async -> [Bus] {
        await getLiveBuses(forLines: [line]).filter { $0.direction == direction }
    }

    /// Live buses serving `lineIds`.
    func getLiveBuses(forLines lineIds: [String]) async -> [Bus] {
        await refreshIfCold(lines: lineIds)
        let lines = Set(lineIds)
        return usableBuses { lines.contains($0.lineId) }
    }

    /// One live bus by id. `lineId` is an optional hint that makes a cold-cache
    /// request cheaper (only that line is fetched instead of the full feed).
    func getLiveBus(id: String, lineId: String? = nil) async -> Bus? {
        await getLiveBuses(ids: [id], lineIds: lineId.map { [$0] }).first
    }

    /// Live buses by id. Ids with no recent usable report are left out.
    func getLiveBuses(ids: Set<String>, lineIds: Set<String>? = nil) async -> [Bus] {
        await refreshIfCold(lines: lineIds.map(Array.init))
        return usableBuses { ids.contains($0.id) }
    }

    // MARK: - Helpers

    /// Registers the request, and if the cache is cold fetches either just
    /// `lines` (when known) or the full feed.
    private func refreshIfCold(lines lineIds: [String]?) async {
        lastRequest = .now
        startTracking()

        guard Date().timeIntervalSince(lastFullFetch) > maxCacheAge else { return }

        let fresh: [BusReport]?
        if let lineIds {
            fresh = try? await PortoDigitalFetcher.getLiveBuses(forLines: lineIds)
        } else {
            fresh = try? await PortoDigitalFetcher.getLiveBuses()
        }
        if let fresh { ingest(fresh) }
    }

    private func usableBuses(where matches: (BusReport) -> Bool) -> [Bus] {
        let now = Date()
        return reports.values
            .filter { matches($0) && now.timeIntervalSince($0.timestamp) <= maxLayoverStaleness }
            .map(Bus.init(report:))
            .filter { isUsable($0, now: now) }
    }

    // MARK: - Tracking

    private func startTracking() {
        guard tracking == nil else {
            return
        }
        tracking = Task {
            while Date().timeIntervalSince(self.lastRequest) < self.idleTimeout {
                if let all = try? await PortoDigitalFetcher.getLiveBuses() {
                    self.ingest(all)
                    self.lastFullFetch = .now
                }
                try? await Task.sleep(for: self.pollInterval)
            }
            self.tracking = nil
        }
    }

    private func ingest(_ incoming: [BusReport]) {
        for report in incoming where report.timestamp >= reports[report.id]?.timestamp ?? .distantPast {
            reports[report.id] = report
        }
        let cutoff = Date().addingTimeInterval(-maxLayoverStaleness)
        reports = reports.filter { $0.value.timestamp >= cutoff }
        save()
    }

    // MARK: - Staleness

    /// Recent reports are trusted. Older ones only if the bus was last seen at (or just before)
    /// the end of its trip: it most likely switched its tracker off while waiting for the next trip.
    private func isUsable(_ bus: Bus, now: Date) -> Bool {
        if now.timeIntervalSince(bus.timestamp) <= maxStaleness {
            return true
        }
        guard let stopCount = bus.trip?.route.stops.count,
              let progress = bus.tripProgress else {
            return false
        }
        return progress.lastStopIndex >= stopCount - 2
    }

    // MARK: - Disk cache

    private static let fileURL = URL.cachesDirectory.appending(path: "bus-reports.json")

    private func save() {
        let snapshot = Array(reports.values)
        let url = Self.fileURL
        Task.detached(priority: .utility) {
            try? JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
        }
    }

    private static func load() -> [String: BusReport] {
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? JSONDecoder().decode([BusReport].self, from: data) else {
            return [:]
        }
        return Dictionary(saved.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }
}
