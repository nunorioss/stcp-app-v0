//
//  StopArrivals.swift
//  stcp-app
//
//  Created by Nuno Rios on 25/10/2026.
//

import Foundation
import SwiftData

@Observable
final class StopArrivals {
    let stop: BusStop

    private(set) var arrivals: [Arrival] = []
    
    //to hide behind the chevron
    private(set) var farTripIds: Set<String> = []
    
    private(set) var buses: [Bus] = [] //live buses

    @ObservationIgnored
    private var scheduled: [Arrival] = []
    
    private struct LineDirection: Hashable {
        let lineId: String
        let direction: Bool
    }
    
    // kept between refreshes
    //a far arrival stays valid until it's due
    @ObservationIgnored
    private var far: [LineDirection: Arrival] = [:]
    
    @ObservationIgnored
    private var live = Estimator.LiveData()
    
    // failsafe, in case live buses aren't working
    @ObservationIgnored
    private var stcpETAs: [String: Date] = [:]

    init(stop: BusStop) {
        self.stop = stop
    }

    /// Refresh cheduled arrivals within the next 1h15min.
    /// Master routes with none get their next one, fetched only when they had none yet or it's already due.
    func refreshSchedule() {
        scheduled = Estimator.estimate(for: stop, within: 75)
        
        // line+direction combos that have arrivals
        let served = Set(scheduled.map {
            LineDirection(lineId: $0.lineId, direction: $0.route.direction)
        })
        
        let now = Date()

        for route in stop.routes where route.isMasterRoute {
            let key = LineDirection(lineId: route.line.id, direction: route.direction)
            
            if served.contains(key) {
                far[key] = nil
            } else if far[key].map({ $0.scheduledEta <= now }) ?? true {
                far[key] = nextArrival(of: route)
            }
        }
        merge()
    }

    //TODO: Only refresh when BusTracker detects a data change?
    func refreshLive() async {
        live = await Estimator.fetchLiveDataFromPortoDigital(for: stop)
        merge()
    }

    /// Refresh STCP's own ETAs for the stop.
    func refreshStcpETAs() async {
        // keep the previous ETAs if the request fails
        guard let etas = try? await STCPFetcher.getLiveETAs(for: stop.id) else {
            return
        }
        stcpETAs = etas
        merge()
    }

    private func nextArrival(of route: Route) -> Arrival? {
        guard let (tripId, eta) = DataStore.getNextScheduledArrival(at: stop,
                                                                    line: route.line,
                                                                    direction: route.direction),
              let trip = DataStore.getTrip(id: tripId) else {
            return nil
        }
        return Arrival(tripId: tripId,
                       lineId: route.line.id,
                       routeId: trip.route.persistentModelID,
                       routeSortIndex: trip.route.sortIndex,
                       scheduledEta: eta, live: nil)
    }

    private func merge() {
        // Scheduled, + the live buses
        let withLive = Estimator.applyLiveDataFromPortoDigital(live,
                                                               to: scheduled + far.values,
                                                               for: stop)
        // + STCP's ETAs
        arrivals = Estimator.applyETAsFromSTCP(stcpETAs, to: withLive, for: stop, live: live)
        
        farTripIds = Set(far.values.map(\.tripId))
        
        let busIds = Set(arrivals.compactMap { $0.live?.busId })
        buses = live.byTripId.values.filter { busIds.contains($0.id) }
    }
}
