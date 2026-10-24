//
//  Estimator+Inference.swift
//  stcp-app
//
//  Created by Nuno Rios on 10/10/2026.
//

import Foundation

nonisolated extension Estimator {
    private static let maxInferenceHops = 3

    // A bus further behind than 1h is not trusted
    // to project its delay onto later trips
    private static let maxInferableLateness: TimeInterval = 60 * 60

    /// Infers the delay of the next trips of every live bus (same block, same physical bus),
    /// keyed by trip id. Callers pick the trips they care about.
    static func inferLiveFromPreviousTrips(live: LiveData,
                                           now: Date,
                                           nowSeconds: Int)
    -> [String: (bus: Bus, delay: TimeInterval)] {
        guard !live.byTripId.isEmpty else {
            return [:]
        }
        
        var projected: [String: (bus: Bus, delay: TimeInterval)] = [:]

        for bus in live.byTripId.values {
            guard let busTrip = bus.trip,
                  var freeAt = freeAt(of: busTrip,
                                      bus: bus,
                                      now: now,
                                      nowSeconds: nowSeconds),
                  // lateness at the end of the current trip
                  freeAt - TimeInterval(busTrip.lastEtaNumeric) <= maxInferableLateness else {
                continue
            }

            var current = busTrip

            for _ in 0..<maxInferenceHops {
                guard let nextId = current.nextTripId,
                      let next = DataStore.getTrip(id: nextId) else {
                    // no next trip, nothing else to infer for this bus
                    break
                }

                // early arrival doesn't help;
                // the next trip still leaves at its scheduled time
                let delay = max(freeAt - TimeInterval(next.firstEtaNumeric), 0)
                projected[next.id] = (bus, delay)

                freeAt = TimeInterval(next.lastEtaNumeric) + delay
                current = next
            }
        }
        return projected
    }

    /// When the bus is expected to reach the end of its current trip, in seconds
    /// of the trip's service day. nil if the bus can't be placed on its trip.
    private static func freeAt(of busTrip: Trip,
                               bus: Bus,
                               now: Date,
                               nowSeconds: Int) -> TimeInterval? {
        guard let progress = bus.tripProgress else {
            return nil
        }

        let stops = busTrip.route.stops
        guard progress.lastStopIndex < stops.count else {
            return nil
        }
                
        guard progress.lastStopIndex + 1 < stops.count else {
            // bus already at the last stop
            let clock = busTrip.liveClock(at: nowSeconds, scheduledAt: busTrip.lastEtaNumeric)
            return TimeInterval(clock)
        }

        let lastId = stops[progress.lastStopIndex].id
        let nextId = stops[progress.lastStopIndex + 1].id
        let etas = busTrip.etas(for: [lastId, nextId])

        guard let etaLast = etas[lastId],
              let etaNext = etas[nextId] else {
            return nil
        }
        
        // live time to reach the last stop.
        //nil: it most likely already got there
        let remaining = timeToReach(progress: progress.progress,
                                    busTimestamp: bus.timestamp,
                                    etaLastStop: etaLast,
                                    etaNextStop: etaNext,
                                    etaTarget: busTrip.lastEtaNumeric,
                                    now: now) ?? 0
        
        let clock = busTrip.liveClock(at: nowSeconds, scheduledAt: etaLast)
        return TimeInterval(clock) + remaining
    }
}
