//
// RouteUtil.swift
// stcp-app
//
// Created by Nuno Rios on 22/09/2026.
//

import Foundation


nonisolated enum RouteUtil {

    static func tripProgress(busLocation: GeoPoint, along stops: [BusStop]) -> TripProgress? {
        guard stops.count > 1 else {
            return nil
        }

        var best: (index: Int, progress: Double, distance: Double)?

        for i in 0..<(stops.count - 1) {
            let a = stops[i].location
            let b = stops[i + 1].location

            // flat map in meters around "a"
            let metersPerLat = 111_320.0
            let metersPerLon = metersPerLat * cos(a.latitude * .pi / 180)

            let abx = (b.longitude - a.longitude) * metersPerLon
            let aby = (b.latitude - a.latitude) * metersPerLat
            let apx = (busLocation.longitude - a.longitude) * metersPerLon
            let apy = (busLocation.latitude - a.latitude) * metersPerLat

            let length2 = abx * abx + aby * aby
            let t = length2 == 0 ? 0 : min(max((apx * abx + apy * aby) / length2, 0), 1)
            let distance = hypot(apx - t * abx, apy - t * aby)

            if distance < (best?.distance ?? .infinity) {
                best = (i, t, distance)
            }
        }

        guard let best, best.distance <= 250 else {
            // best estimate is too far away from the route
            return nil
        }

        return TripProgress(lastStopIndex: best.index, progress: best.progress)
    }

    /// Estimated time for a live bus to reach a stop further along its route, based on its
    /// own trip's *scheduled* segment durations rather than a constant-speed assumption.
    ///
    /// - `busIndex` / `progress` come from `stopProgress`: the bus is currently `progress`
    ///   of the way between `stops[busIndex]` and `stops[busIndex + 1]`.
    /// - `stops` must be in the same stop sequence as the bus's trip (i.e. the route's own
    ///   `RouteStop`s), so each one can be matched to the trip's scheduled ETA at that stop.
    /// - `targetIndex` is the stop we want the ETA for; it must be strictly after `busIndex`.
    ///
    /// Returns `nil` if the bus has no matching trip, the target isn't ahead of the bus, or
    /// the trip's schedule doesn't cover one of the stops involved.
    static func travelTime(of bus: Bus,
                            fromIndex busIndex: Int,
                            progress: Double,
                            along stops: [RouteStop],
                            toIndex targetIndex: Int) -> TimeInterval? {
        guard let trip = bus.trip,
              targetIndex > busIndex,
              stops.indices.contains(busIndex + 1),
              stops.indices.contains(targetIndex) else {
            return nil
        }

        let etaByStopId = Dictionary(uniqueKeysWithValues: trip.tripStops.map { ($0.stop.id, $0.etaNumeric) })

        guard let etaAtBus = etaByStopId[stops[busIndex].stop.id],
              let etaAtNext = etaByStopId[stops[busIndex + 1].stop.id],
              let etaAtTarget = etaByStopId[stops[targetIndex].stop.id] else {
            return nil
        }

        // How far into the current segment the bus already is, in seconds, scaled by that
        // segment's own scheduled duration (segments aren't all the same length/speed).
        let segmentDuration = Double(etaAtNext - etaAtBus)
        let elapsedInSegment = progress * segmentDuration

        let remaining = Double(etaAtTarget - etaAtBus) - elapsedInSegment
        return max(remaining, 0)
    }
    
    /// Estimated seconds until `bus` reaches `target`, using the bus's own trip schedule.
    ///
    /// estimate = ETA(target) − ETA(lastStop) − alpha − timeSinceUpdate
    ///
    /// - `lastStop`: the last stop the bus passed (`stops[index]` from `stopProgress`).
    /// - `nextStop` + `progress`: optional; used for alpha, the share of the
    ///   lastStop → nextStop segment the bus has already covered.
    /// - Returns `nil` if the trip has no schedule for the stops involved, or the
    ///   target isn't ahead of `lastStop`.
    static func timeToReach(_ target: BusStop,
                            by bus: Bus,
                            on trip: Trip,
                            lastStop: BusStop,
                            nextStop: BusStop? = nil,
                            progress: Double = 0,
                            now: Date = Date()) -> TimeInterval? {
        timeToReach(target, by: bus, eta: etaTable(for: trip), lastStop: lastStop,
                    nextStop: nextStop, progress: progress, now: now)
    }

    /// Scheduled ETA (seconds since midnight) of every stop on `trip`, by stop id.
    /// Walks all of the trip's stops, so build it once per trip and reuse it.
    static func etaTable(for trip: Trip) -> [String: Int] {
        // uniquingKeysWith: a stop can appear twice on a looping trip, and
        // uniqueKeysWithValues would crash on that.
        Dictionary(trip.tripStops.map { ($0.stop.id, $0.etaNumeric) },
                   uniquingKeysWith: { first, _ in first })
    }

    /// Same estimate as `timeToReach(_:by:on:...)`, but takes the trip's precomputed
    /// `etaTable(for:)`, so calling it once per row doesn't rebuild the table each time.
    static func timeToReach(_ target: BusStop,
                            by bus: Bus,
                            eta: [String: Int],
                            lastStop: BusStop,
                            nextStop: BusStop? = nil,
                            progress: Double = 0,
                            now: Date = Date()) -> TimeInterval? {

        guard let etaTarget = eta[target.id],
              let etaLast = eta[lastStop.id],
              etaTarget > etaLast else {
            return nil
        }

        let scheduled = Double(etaTarget - etaLast)

        // Alpha: how much of the current segment the bus had already covered
        // when its position was captured, scaled by that segment's scheduled duration.
        var alpha = 0.0
        if let nextStop, let etaNext = eta[nextStop.id], etaNext > etaLast {
            alpha = progress * Double(etaNext - etaLast)
        }

        // The fix is already a few seconds old, so the bus has moved on since.
        let sinceUpdate = max(now.timeIntervalSince(bus.timestamp), 0)

        return max(scheduled - alpha - sinceUpdate, 0)
    }
    
}
