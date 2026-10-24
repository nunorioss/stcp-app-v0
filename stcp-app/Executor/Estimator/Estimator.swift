//
//  Estimator.swift
//  stcp-app
//
//  Created by Nuno Rios on 08/10/2026.
//

import Foundation
import SwiftData

nonisolated enum Estimator {
    struct LiveData {
        // buses that serve the desired stop (line + direction)
        var buses: [Bus] = []
        // all buses eligible for inference
        var byTripId: [String: Bus] = [:]
    }

    static let updateFrequency: TimeInterval = 2 * 60
    
    /// Seconds until a bus reaches a target stop, based on the trip schedule.
    /// Returns nil if bus already passed the stop and its data is stale.
    static func timeToReach(progress: Double,
                                    busTimestamp: Date,
                                    etaLastStop: Int,
                                    etaNextStop: Int?,
                                    etaTarget: Int,
                                    now: Date = .now) -> TimeInterval? {
        guard etaTarget > etaLastStop else {
            return nil
        }

        // scheduled "time to reach"
        let scheduled = Double(etaTarget - etaLastStop)

        // share of the lastStop -> nextStop segment already covered,
        // scaled by that segment's scheduled duration
        var alpha = 0.0
        if let etaNextStop, etaNextStop > etaLastStop {
            alpha = progress * Double(etaNextStop - etaLastStop)
        }

        // take into account bus location age
        let sinceUpdate = max(now.timeIntervalSince(busTimestamp), 0)

        let remaining = scheduled - alpha - sinceUpdate
        if remaining < 0 && sinceUpdate > updateFrequency {
            return nil
        }
        return max(remaining, 0)
    }
    
    
    /// Builds the Arrival of one trip at a given stop.
    /// Returns nil if the bus already passed the stop or the schedule has no ETA for it
    static func makeArrival(of trip: Trip,
                                at stop: BusStop,
                                stopIndex: Int,
                                bus: Bus?,
                                now: Date,
                                nowSeconds: Int) -> Arrival? {
        let stops = trip.route.stops
        let progress = bus?.tripProgress

        if let progress, progress.lastStopIndex >= stopIndex {
            // bus already passed the stop
            return nil
        }

        // get scheduled ETA for last, next and target stops
        var ids = [stop.id]
        if let idx = progress?.lastStopIndex {
            ids.append(stops[idx].id)
            ids.append(stops[idx + 1].id)
        }
        let etas = trip.etas(for: ids)

        guard let etaTarget = etas[stop.id] else {
            // target stop's ETA not available ??
            return nil
        }

        let lastEta = progress.flatMap { etas[stops[$0.lastStopIndex].id] }
        let clock = lastEta.map { trip.liveClock(at: nowSeconds, scheduledAt: $0) }
            ?? trip.serviceClock(at: nowSeconds)
        let scheduledEta = now.addingTimeInterval(TimeInterval(etaTarget - clock))

        var live: Arrival.Live?
        if let bus, let progress,
           let etaLast = etas[stops[progress.lastStopIndex].id] {
            guard let remaining = timeToReach(progress: progress.progress,
                                              busTimestamp: bus.timestamp,
                                              etaLastStop: etaLast,
                                              etaNextStop: etas[stops[progress.lastStopIndex + 1].id],
                                              etaTarget: etaTarget,
                                              now: now) else {
                // bus already passed the stop
                return nil
            }
            live = Arrival.Live(eta: now.addingTimeInterval(remaining), busId: bus.id)
        }

        let route = trip.route
        return Arrival(tripId: trip.id,
                       lineId: route.line.id,
                       routeId: route.persistentModelID,
                       routeSortIndex: route.sortIndex,
                       scheduledEta: scheduledEta,
                       live: live)
    }
    
    
    /// Builds Arrivals of a tracked bus' trip at every stop ahead of it.
    static func makeLiveArrivals(of trip: Trip, bus: Bus, now: Date, nowSeconds: Int)
        -> [(stopId: String, arrival: Arrival)] {
        let tripStops = trip.tripStops
        guard let progress = bus.tripProgress,
              progress.lastStopIndex + 1 < tripStops.count else {
            return []
        }

        let start = progress.lastStopIndex + 1
        let etaLast = tripStops[progress.lastStopIndex].etaNumeric
        let etaNext = tripStops[start].etaNumeric
            
        let clock = trip.liveClock(at: nowSeconds, scheduledAt: etaLast)
            
        let route = trip.route

        return tripStops[start...].compactMap { ts in
            let scheduledEta = now.addingTimeInterval(TimeInterval(ts.etaNumeric - clock))
            
            guard let remaining = timeToReach(progress: progress.progress,
                                              busTimestamp: bus.timestamp,
                                              etaLastStop: etaLast,
                                              etaNextStop: etaNext,
                                              etaTarget: ts.etaNumeric,
                                              now: now) else {
                // bus already passed the stop
                return nil
            }
            let live = Arrival.Live(eta: now.addingTimeInterval(remaining), busId: bus.id)
            
            return (
                ts.stop.id,
                Arrival(tripId: trip.id,
                        lineId: route.line.id,
                        routeId: route.persistentModelID,
                        routeSortIndex: route.sortIndex,
                        scheduledEta: scheduledEta,
                        live: live)
            )
        }
    }
    
    
    /// Upcoming scheduled arrivals at a single stop.
    static func estimate(for stop: BusStop, within: Int = 60) -> [Arrival] {
        let now = Date()
        let nowSeconds = DateUtil.secondsSinceMidnight()

        return DataStore.getScheduledTrips(for: stop, within: within).compactMap { trip in
            guard let stopIndex = trip.route.stops
                .firstIndex(where: { $0.persistentModelID == stop.persistentModelID }) else {
                return nil
            }
            return makeArrival(of: trip, at: stop, stopIndex: stopIndex,
                               bus: nil, now: now, nowSeconds: nowSeconds)
        }
    }
    
    
    /// Upcoming scheduled arrivals at every stop of a line/direction combination, keyed by stop id.
    static func estimate(line: BusLine, direction: Bool, within: Int = 60) -> [String: [Arrival]] {
        let now = Date()
        let nowSeconds = DateUtil.secondsSinceMidnight()

        var result: [String: [Arrival]] = [:]
        for trip in DataStore.getScheduledTrips(line: line, direction: direction, within: within) {
            let clock = trip.serviceClock(at: nowSeconds)
            let window = clock...(clock + within * 60)
            
            let route = trip.route
            
            for ts in trip.tripStops where window.contains(ts.etaNumeric) {
                let scheduledEta = now.addingTimeInterval(TimeInterval(ts.etaNumeric - clock))
                result[ts.stop.id, default: []].append(
                    Arrival(tripId: trip.id,
                            lineId: route.line.id,
                            routeId: route.persistentModelID,
                            routeSortIndex: route.sortIndex,
                            scheduledEta: scheduledEta,
                            live: nil)
                )
            }
        }
        return result
    }
}
