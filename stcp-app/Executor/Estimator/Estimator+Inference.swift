//
//  Estimator+Inference.swift
//  stcp-app
//
//  Created by Nuno Rios on 10/10/2026.
//

import Foundation

extension Estimator {
    private static let maxInferenceHops = 3

    // A bus further behind than 1h is not trusted
    // to project its delay onto later trips
    private static let maxInferableLateness: TimeInterval = 60 * 60

    //TODO: Simplify formula?: let it simply be
    //TODO: "scheduledTimeToStart(N) - timeToReach(end of N)"
    
    /// For scheduled trips with no live bus, infers a live ETA from a bus
    /// running an earlier trip of the same block (same physical bus).
    static func inferLiveFromPreviousTrips(for tripIds: [String],
                                           live: LiveData,
                                           now: Date,
                                           nowSeconds: Int)
    -> [String: (bus: Bus, delay: TimeInterval)] {
        guard !tripIds.isEmpty, !live.byTripId.isEmpty else {
            return [:]
        }
        
        var projected: [String: (bus: Bus, delay: TimeInterval)] = [:]

        for bus in live.byTripId.values {
            guard let busTrip = bus.trip,
                  let lateness = latenessAtEnd(of: busTrip,
                                               bus: bus,
                                               now: now,
                                               nowSeconds: nowSeconds),
                  lateness <= maxInferableLateness else {
                continue
            }

            // early arrival doesn't help;
            // the next trip still leaves at its scheduled time
            var delay = max(lateness, 0)
            var current = busTrip

            for _ in 0..<maxInferenceHops {
                guard let nextId = current.nextTripId,
                      let next = DataStore.getTrip(id: nextId) else {
                    // no next trip, nothing else to infer for this bus
                    break
                }

                // the layover absorbs part of the delay
                // layover-> time between end of current trip and start of next trip
                let slack = TimeInterval(next.firstEtaNumeric - current.lastEtaNumeric)
                delay = max(delay - slack, 0)

                projected[next.id] = (bus, delay)
                current = next
            }
        }

        var result: [String: (bus: Bus, delay: TimeInterval)] = [:]
            for id in tripIds {
                if let inferred = projected[id] {
                    result[id] = inferred
                }
            }
        return result
    }

    /// How early or late a bus is expected to be when it reaches
    /// the end of its current trip. nil if the bus can't be placed on its trip.
    private static func latenessAtEnd(of busTrip: Trip,
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
            
            // formula is liveRemaining - scheduledRemaining
            // = 0 - scheduledRemaining
            let clock = busTrip.liveClock(at: nowSeconds, scheduledAt: busTrip.lastEtaNumeric)
            return TimeInterval(clock - busTrip.lastEtaNumeric)
        }

        let lastId = stops[progress.lastStopIndex].id
        let nextId = stops[progress.lastStopIndex + 1].id
        let etas = busTrip.etas(for: [lastId, nextId])

        // live time to reach the last stop
        guard let etaLast = etas[lastId],
              let etaNext = etas[nextId],
              let remaining = timeToReach(progress: progress.progress,
                                          busTimestamp: bus.timestamp,
                                          etaLastStop: etaLast,
                                          etaNextStop: etaNext,
                                          etaTarget: busTrip.lastEtaNumeric,
                                          now: now) else {
            return nil
        }
        
        let clock = busTrip.liveClock(at: nowSeconds, scheduledAt: etaLast)
        let scheduledRemaining = TimeInterval(busTrip.lastEtaNumeric - clock)

        return remaining - scheduledRemaining
    }
}
