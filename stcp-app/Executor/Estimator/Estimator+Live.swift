//
//  Estimator+Live.swift
//  stcp-app
//
//  Created by Nuno Rios on 11/10/2026.
//

import Foundation
import SwiftData

extension Estimator {
    /// Fetches live data for a bus stop from PortoDigital.
    static func fetchLiveDataFromPortoDigital(for stop: BusStop) async -> LiveData {
        struct LineDirection: Hashable, Sendable {
            let lineId: String
            let direction: Bool
        }
        
        // get buses for lines that the stop serves + their sister lines

        let routes = stop.routes
        let pairs = Set(routes.map {
            LineDirection(lineId: $0.line.id, direction: $0.direction) }
        )
        let lineIds = Set(routes.flatMap { [$0.line.id] + $0.line.sisterLineIds })
        
        let all = await BusTracker.shared.getLiveBuses(forLines: Array(lineIds))

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
        let notLive = byTrip.values.filter { !$0.isLive }.map(\.tripId)
        let inferred = inferLiveFromPreviousTrips(for: notLive, live: live,
                                                      now: now, nowSeconds: nowSeconds)
        
        for (tripId, inf) in inferred {
            guard let a = byTrip[tripId] else {
                continue
            }
            byTrip[tripId] = a.with(live: .init(eta: a.scheduledEta.addingTimeInterval(inf.delay),
                                                busId: inf.bus.id,
                                                inferred: true))
        }
        return Array(byTrip.values)
    }
    
    /// Merges PortoDigital live data with scheduled Arrivals keyed by stop id.
    static func applyPortoDigitalLiveData(_ live: LiveData,
                                          to arrivals: [String: [Arrival]]) -> [String: [Arrival]] {
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
        let notLive = Set(arrivals.values.flatMap { $0 }.map(\.tripId)).subtracting(liveTrips)
        let inferred = inferLiveFromPreviousTrips(for: Array(notLive), live: live,
                                                      now: now, nowSeconds: nowSeconds)
        
        return result.mapValues { list in
            list.map { a in
                guard !a.isLive, let inf = inferred[a.tripId] else {
                    return a
                }
                return a.with(live: .init(eta: a.scheduledEta.addingTimeInterval(inf.delay),
                                          busId: inf.bus.id,
                                          inferred: true))
            }
        }
    }
    
    /// Merges STCP API ETAs with a list of arrivals.
    static func applyETAsFromSTCP(_ etas: [String: Date], to arrivals: [Arrival]) -> [Arrival] {
        arrivals.map { arrival in
            // only trips without live data get the new ETA
            guard !arrival.isLive, let eta = etas[arrival.tripId], eta > .now else {
                return arrival
            }
            return arrival.with(live: .init(eta: eta, busId: nil, source: .stcp))
        }
    }
}
