//
//  StopArrivals.swift
//  stcp-app
//

import Foundation
import SwiftData

/// Builds a stop's arrivals off the main thread, on its own model context.
/// Only plain values go in and out (ids, reports, arrivals), never models.
@ModelActor
actor StopArrivals {
    static let shared = StopArrivals(modelContainer: SwiftDataManager.container)

    /// Scheduled arrivals only. On top of what the estimator returns, adds the next
    /// scheduled arrival of every master route serving the stop (possibly hours or days
    /// away), so lines with nothing due soon still show up. Those are returned in `far`.
    func scheduled(stopId: String) -> (arrivals: [Arrival], far: Set<String>) {
        onContext {
            guard let stop = DataStore.getBusStop(id: stopId) else {
                return ([], [])
            }
            var arrivals = Estimator.estimate(for: stop, within: 75)
            var tripIds = Set(arrivals.map(\.tripId))
            var far: Set<String> = []

            for route in stop.routes where route.isMasterRoute && !route.ends(at: stop) {
                guard let (tripId, eta) = DataStore.getNextScheduledArrival(at: stop,
                                                                            line: route.line,
                                                                            direction: route.direction),
                      tripIds.insert(tripId).inserted,   // skip if the estimator already has it
                      let trip = DataStore.getTrip(id: tripId),
                      !trip.route.ends(at: stop)
                else { continue }

                far.insert(tripId)

                arrivals.append(Arrival(
                    tripId: tripId,
                    lineId: route.line.id,
                    routeId: route.persistentModelID,
                    routeSortIndex: route.sortIndex,
                    scheduledEta: eta,
                    live: nil)
                )
            }
            return (arrivals, far)
        }
    }

    /// Schedule, then Porto Digital (with inference), then STCP.
    func merge(stopId: String,
               scheduled: [Arrival],
               reports: [BusReport],
               stcpETAs: [String: Date]) -> [Arrival] {
        onContext {
            guard let stop = DataStore.getBusStop(id: stopId) else {
                return scheduled
            }
            let live = Estimator.liveData(from: reports, for: stop)
            let withLive = Estimator.applyLiveDataFromPortoDigital(live, to: scheduled, for: stop)
            let merged = Estimator.applyETAsFromSTCP(stcpETAs, to: withLive, for: stop, live: live)

            let pd = withLive.filter { $0.live?.inferred == false }.count
            let inferred = withLive.filter { $0.live?.inferred == true }.count
            let stcp = merged.filter { $0.live?.source == .stcp }.count
            print("[\(stopId)] \(scheduled.count) scheduled | porto digital: \(pd) live, \(inferred) inferred "
                  + "| stcp: \(stcpETAs.count) received, \(stcp) applied")
            return merged
        }
    }

    /// Runs `work` with every `DataStore` query on this actor's context.
    private func onContext<T>(_ work: () -> T) -> T {
        DataStore.$taskContext.withValue(.init(context: modelContext), operation: work)
    }
}
