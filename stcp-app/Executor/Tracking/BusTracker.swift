//
//  BusTracker.swift
//  stcp-app
//
//  Created by Nuno Rios on 25/10/2026.
//

import Foundation
import Observation

@MainActor
@Observable
final class BusTracker {
    static let shared = BusTracker()

    // Tracking stops after this long without subscribers
    private let idleTimeout: TimeInterval = 30
    
    // Reports older than this are dropped
    let maxStaleness: TimeInterval = 5 * 60
    
    // Reports dated further ahead than this are dropped
    // (likely some weird clock difference)
    private let maxClockSkew: TimeInterval = 60

    // If STCP hasn't answered for this long,
    // we refetch first instead of returning stale data
    let maxCacheAge: TimeInterval = 45
    
    //MARK: - State

    // Goes up whenever live bus data changes
    private(set) var revision = 0

    @ObservationIgnored
    private(set) var reports: [String: BusReport] = [:]
    
    // when STCP last answered
    @ObservationIgnored
    private(set) var lastFetch = Date.distantPast
    
    // when the app last asked for live buses
    @ObservationIgnored
    var lastRequest = Date.distantPast
    
    @ObservationIgnored var subscribers = 0
    @ObservationIgnored private var tracking: Task<Void, Never>?

    // STCP's last snapshot (trip id -> vehicle),
    // to tell when the feed refreshed
    @ObservationIgnored
    private var stcpVehicles: [String: STCPFetcher.Vehicle] = [:]

    private init() {}

    // MARK: - Reports

    /// Applies a feed's `changes`, drops what's stale, and bumps `revision`
    /// if the live buses changed.
    private func update(_ changes: () -> Void) {
        let before = reports
        changes()

        let now = Date()
        lastFetch = now

        // drop stale buses
        reports = reports.filter {
            now.timeIntervalSince($0.value.timestamp) <= maxStaleness
        }

        if reports != before {
            revision += 1
        }
    }

    /// Caches `report` as its bus's latest.
    private func store(_ report: BusReport) {
        guard report.timestamp <= Date().addingTimeInterval(maxClockSkew) else {
            // too far in the future,
            //something's wrong with the clock
            return
        }
        reports[report.id] = report
    }
    
    // MARK: - Tracking

    private var isWanted: Bool {
        subscribers > 0 || Date().timeIntervalSince(lastRequest) < idleTimeout
    }

    func startTracking() {
        guard tracking == nil else {
            // already tracking
            return
        }
        tracking = Task {
            await poll(.stcp) {
                await self.pollSTCP()
            }
            self.tracking = nil
        }
    }

    /// Polls a feed while wanted, each time just after its next refresh.
    /// `fetch` returns whether the feed refreshed since the last poll (nil if it failed).
    private func poll(_ calibrator: PollCalibrator, fetch: @MainActor () async -> Bool?) async {
        var calibrator = calibrator

        while isWanted {
            let sent = ContinuousClock.now
            let changed = await fetch()
            let received = ContinuousClock.now

            try? await Task.sleep(for: calibrator.next(after: changed,
                                                       at: sent + (received - sent) / 2))
        }
    }

    /// Poll STCP's API to get live vehicles.
    /// Returns whether the data refreshed since the last poll, or nil if it failed.
    func pollSTCP() async -> Bool? {
        guard let snapshot = try? await STCPFetcher.getLiveVehicles() else {
            return nil
        }
        // map/index live entries by trip id
        let live = Dictionary(snapshot.vehicles.map { ($0.tripId, $0) },
                              uniquingKeysWith: { a, _ in a })

        let first = stcpVehicles.isEmpty
        let refreshed = !first && live != stcpVehicles

        guard refreshed || (first && !live.isEmpty) else {
            // no new data, stop
            lastFetch = .now
            return false
        }

        // a first snapshot could already be a whole period old (10s),
        //so it's dated that far back
        let period = TimeInterval(PollCalibrator.stcp.period.components.seconds)
        let dataTime = first ? snapshot.timestamp.addingTimeInterval(-period) : snapshot.timestamp

        update {
            for trip in stcpVehicles.keys where live[trip] == nil {
                // bus gone from the feed (trip probably ended)
                //TODO: Though not always... keep it?
                reports[trip] = nil
            }

            for vehicle in snapshot.vehicles {
                store(BusReport(reportedTripId: vehicle.tripId,
                                latitude: vehicle.latitude,
                                longitude: vehicle.longitude,
                                lineId: vehicle.lineId,
                                direction: vehicle.direction,
                                bearing: vehicle.bearing,
                                timestamp: dataTime))
            }
        }
        stcpVehicles = live
        return refreshed
    }
}
