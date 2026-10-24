//
//  Estimator+Live.swift
//  stcp-app
//
//  Created by Nuno Rios on 11/10/2026.
//

import Foundation
import SwiftData

nonisolated extension Estimator {
    /// Lines whose buses matter to a bus stop: the ones it serves + their sister lines.
    static func liveLineIds(for stop: BusStop) -> [String] {
        Array(Set(stop.routes.flatMap { [$0.line.id] + $0.line.sisterLineIds }))
    }

    /// Live data for a bus stop, from the PortoDigital reports of `liveLineIds(for:)`.
    static func liveData(from reports: [BusReport], for stop: BusStop) -> LiveData {
        struct LineDirection: Hashable, Sendable {
            let lineId: String
            let direction: Bool
        }
        
        let pairs = Set(stop.routes.map {
            LineDirection(lineId: $0.line.id, direction: $0.direction) }
        )
        let all = reports.map(Bus.init(report:))

        // separate into: line+direction that serves the stop vs. others
        var data = LiveData()
        for bus in all {
            guard let trip = bus.trip else {
                // not useful if we can't get the trip
                continue
            }
            data.byTripId[trip.id] = bus
            if pairs.contains(LineDirection(lineId: bus.lineId, direction: bus.direction)) {
                data.buses.append(bus)
            }
        }
        return data
    }
    
    
    /// Fetches live data for a bus line from PortoDigital.
    static func fetchLiveDataFromPortoDigital(for line: BusLine, direction: Bool) async -> LiveData {
        let all = await BusTracker.shared.getLiveBuses(forLines: [line.id] + line.sisterLineIds)
        var data = LiveData()
        
        for bus in all {
            guard let trip = bus.trip else {
                // not useful if we can't get the trip
                continue
            }
            data.byTripId[trip.id] = bus
            if bus.lineId == line.id, bus.direction == direction {
                data.buses.append(bus)
            }
        }
        return data
    }
    
    
    /// Merges PortoDigital live data for a bus stop with scheduled Arrivals.
    static func applyLiveDataFromPortoDigital(_ live: LiveData,
                                          to arrivals: [Arrival],
                                          for stop: BusStop) -> [Arrival] {
        let now = Date()
        let nowSeconds = DateUtil.secondsSinceMidnight()
        var byTrip = Dictionary(arrivals.map { ($0.tripId, $0) }, uniquingKeysWith: { a, _ in a })
        
        // live buses: rebuild their arrival. this also adds live trips outside the schedule
        // window, and drops trips whose bus already passed the stop
        for bus in live.buses {
            guard let trip = bus.trip,
                  let stopIndex = trip.route.stops
                .firstIndex(where: { $0.persistentModelID == stop.persistentModelID }) else {
                continue
            }
            
            byTrip[trip.id] = makeArrival(of: trip, at: stop, stopIndex: stopIndex,
                                       bus: bus, now: now, nowSeconds: nowSeconds)
        }
        
        // inference fallback
        let tracked = Set(live.buses.compactMap { $0.trip?.id })
        let inferred = inferLiveFromPreviousTrips(live: live, now: now, nowSeconds: nowSeconds)
        
        for (tripId, inf) in inferred where !tracked.contains(tripId) {
            let a: Arrival
            
            if let scheduled = byTrip[tripId] {
                a = scheduled
            } else {
                // we don't yet have the scheduled trip,
                //fetch it + make arrival
                guard let trip = DataStore.getTrip(id: tripId),
                      let stopIndex = trip.route.stops
                    .firstIndex(where: { $0.persistentModelID == stop.persistentModelID }),
                      let scheduled = makeArrival(of: trip, at: stop, stopIndex: stopIndex,
                                                  bus: nil, now: now, nowSeconds: nowSeconds),
                      scheduled.scheduledEta < now else {
                    // later trips get picked up by the schedule once they're in its window
                    //TODO: Why not allow it either way even if scheduled.scheduledEta >= now?
                    continue
                }
                a = scheduled
            }
            
            let eta = a.scheduledEta.addingTimeInterval(inf.delay)
            guard eta >= now else {
                continue
            }
            
            byTrip[tripId] = a.with(live: .init(eta: eta, busId: inf.bus.id, inferred: true))
        }
        
        return Array(byTrip.values)
    }
    
    /// Merges PortoDigital live data with scheduled Arrivals of a line/direction keyed by stop id.
    static func applyPortoDigitalLiveData(_ live: LiveData,
                                          to arrivals: [String: [Arrival]],
                                          line: BusLine,
                                          direction: Bool) -> [String: [Arrival]] {
        let now = Date()
        let nowSeconds = DateUtil.secondsSinceMidnight()

        // for buses we can place on their trip, their scheduled arrivals get rebuilt
        let tracked = live.buses.filter { $0.trip != nil && $0.tripProgress != nil }
        let liveTrips = Set(tracked.compactMap { $0.trip?.id })
        
        var result = arrivals.mapValues { list in list.filter { !liveTrips.contains($0.tripId) } }
        for bus in tracked {
            for (stopId, arrival) in makeLiveArrivals(of: bus.trip!, bus: bus, now: now, nowSeconds: nowSeconds) {
                result[stopId, default: []].append(arrival)
            }
        }

        // inference fallback
        let inferred = inferLiveFromPreviousTrips(live: live, now: now, nowSeconds: nowSeconds)
            .filter { !liveTrips.contains($0.key) }
        
        result = result.mapValues { list in
            list.map { a in
                guard !a.isLive, let inf = inferred[a.tripId] else {
                    return a
                }
                return a.with(live: .init(eta: a.scheduledEta.addingTimeInterval(inf.delay),
                                          busId: inf.bus.id,
                                          inferred: true))
            }
        }
        
        // inference also covers stops outside the schedule window
        // e.g. a late trip's stops whose scheduled time already passed
        for (tripId, inf) in inferred {
            guard let trip = DataStore.getTrip(id: tripId),
                  trip.route.line.id == line.id,
                  trip.route.direction == direction else {
                continue
            }
            let clock = trip.serviceClock(at: nowSeconds)
            let route = trip.route
            
            for ts in trip.tripStops where ts.etaNumeric < clock {
                let scheduledEta = now.addingTimeInterval(TimeInterval(ts.etaNumeric - clock))
                let eta = scheduledEta.addingTimeInterval(inf.delay)
                guard eta >= now else {
                    continue
                }
                
                result[ts.stop.id, default: []].append(
                    Arrival(tripId: trip.id,
                            lineId: route.line.id,
                            routeId: route.persistentModelID,
                            routeSortIndex: route.sortIndex,
                            scheduledEta: scheduledEta,
                            live: .init(eta: eta, busId: inf.bus.id, inferred: true))
                )
            }
        }
        return result
    }
    
    /// Merges STCP API ETAs for a stop with its arrivals.
    static func applyETAsFromSTCP(_ etas: [String: Date],
                                  to arrivals: [Arrival],
                                  for stop: BusStop,
                                  live: LiveData) -> [Arrival] {
        let now = Date()
        let nowSeconds = DateUtil.secondsSinceMidnight()
        
        let tracked = Set(live.buses.compactMap { $0.trip?.id }) // already tracked by PortoDigital
        var byTrip = Dictionary(arrivals.map { ($0.tripId, $0) }, uniquingKeysWith: { a, _ in a })
        
        for (tripId, eta) in etas where eta > now && !tracked.contains(tripId) {
            let a: Arrival
            if let existing = byTrip[tripId] {
                // only trips without live data get the new ETA
                guard !existing.isLive else {
                    continue
                }
                a = existing
                
            } else {
                // hadn't fetched the trip yet, likely late
                guard let trip = DataStore.getTrip(id: tripId),
                      let stopIndex = trip.route.stops
                    .firstIndex(where: { $0.persistentModelID == stop.persistentModelID }),
                      let scheduled = makeArrival(of: trip, at: stop, stopIndex: stopIndex,
                                                  bus: nil, now: now, nowSeconds: nowSeconds) else {
                    continue
                }
                a = scheduled
            }
            byTrip[tripId] = a.with(live: .init(eta: eta, busId: nil, source: .stcp))
        }
        return Array(byTrip.values)
    }
}
