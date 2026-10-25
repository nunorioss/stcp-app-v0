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

    // MARK: - Tuning

    /// Tracking stops after this long without requests or subscribers
    /// (so leaving a view and coming back soon doesn't restart it).
    private let idleTimeout: TimeInterval = 30

    /// Nothing fetched for this long: a request waits for STCP instead of answering from the cache.
    let maxCacheAge: TimeInterval = 45

    /// Reports older than this are dropped.
    let maxStaleness: TimeInterval = 5 * 60

    /// Reports dated further ahead than this are bogus (a feed's clock or time zone
    /// slipping, e.g. on a DST change).
    private let maxClockSkew: TimeInterval = 60

    // MARK: - State

    /// Goes up whenever the live buses change, so views can refresh right away
    /// instead of on their own timers (see `onBusUpdate`). The only observed property.
    private(set) var revision = 0

    @ObservationIgnored private(set) var reports: [String: BusReport] = [:]   // trip id -> latest report
    @ObservationIgnored private(set) var lastFetch = Date.distantPast
    @ObservationIgnored var lastRequest = Date.distantPast
    @ObservationIgnored private var tracking: Task<Void, Never>?
    // views on screen that want live buses kept current (see `track`)
    @ObservationIgnored var subscribers = 0

    // STCP's last snapshot (trip id -> vehicle), to tell when the feed refreshed
    @ObservationIgnored private var stcpVehicles: [String: STCPFetcher.Vehicle] = [:]

    private init() {}

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

    /// STCP's feed has no timestamps, but it refreshes every bus at once: if any bus moved,
    /// appeared or disappeared, the whole feed refreshed and every bus gets this response's
    /// time. If nothing changed, nothing is stored, so they keep the time of the last refresh.
    /// Returns whether it refreshed.
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
}
