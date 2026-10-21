//
//  Raptor.swift
//  stcp-app
//
//  Created by Nuno Rios on 21/10/2026.
//

import Foundation

/// Round-based public transit routing (Delling et al.). Round `k` finds the earliest
/// arrival using exactly `k` buses, so one run yields the Pareto set of arrival time
/// vs. number of rides. Everything is flat arrays, no allocations inside the rounds.
nonisolated struct Raptor {
    nonisolated struct Settings: Sendable {
        /// Walking time is multiplied by this while searching only, to prefer less walking.
        var walkPenalty = 1.0
        /// Max straight-line distance between origin/destination and a stop.
        var maxAccess = 900.0
        var maxRides = 4
        var maxDirectWalk = 2500.0
        var boardSlack = Int32(Journey.boardBuffer)

        static let standard = Settings()
        static let lessWalking = Settings(walkPenalty: 2.5, maxAccess: 500)
    }

    let timetable: Timetable
    let settings: Settings

    /// A few complementary runs: fewer walks now, then the next departures.
    static func search(_ timetable: Timetable, from: Place, to: Place,
                       at t0: Int32, dayStart: Date) -> [Journey] {
        var results = Raptor(timetable: timetable, settings: .lessWalking)
            .run(from: from, to: to, at: t0, dayStart: dayStart)

        var t = t0
        for _ in 0..<3 {
            let found = Raptor(timetable: timetable, settings: .standard)
                .run(from: from, to: to, at: t, dayStart: dayStart)
            results += found
            guard let leave = found.filter({ !$0.rides.isEmpty }).map(\.departure).min() else { break }
            t = max(t + 60, Int32(leave.timeIntervalSince(dayStart)) + 60)
        }

        let earliest = dayStart.addingTimeInterval(TimeInterval(t0))
        return results.map { var j = $0; j.earliest = earliest; return j }
    }

    private nonisolated enum Kind: UInt8 { case unset, access, ride, transfer }

    /// How a stop was reached in a round. For rides: pattern, trip, board and alight positions.
    private nonisolated struct Parent {
        var kind = Kind.unset
        var a: Int32 = 0, b: Int32 = 0, c: Int32 = 0, d: Int32 = 0
    }

    private func walk(_ meters: Double) -> Int32 {
        Int32((Double(Journey.walkSeconds(straight: meters)) * settings.walkPenalty).rounded(.up))
    }

    func run(from: Place, to: Place, at t0: Int32, dayStart: Date) -> [Journey] {
        let earliest = dayStart.addingTimeInterval(TimeInterval(t0))
        var journeys: [Journey] = []

        if Timetable.meters(from.location, to.location) <= settings.maxDirectWalk,
           let direct = Journey.Walk(from: from, to: to) {
            journeys.append(Journey(from: from, to: to, legs: [.walk(direct)], earliest: earliest))
        }

        let tt = timetable, n = tt.stopCount, rounds = settings.maxRides
        let never = Int32.max

        var best = [Int32](repeating: never, count: n)
        var arrival = [Int32](repeating: never, count: (rounds + 1) * n)
        var parent = [Parent](repeating: Parent(), count: (rounds + 1) * n)
        var isMarked = [Bool](repeating: false, count: n)
        var marked: [Int] = []
        var patternStart = [Int32](repeating: never, count: tt.patterns.count)
        var queue: [Int] = []
        var targetBest = never
        var targets: [(round: Int, stop: Int)] = []

        func improve(_ slot: Int, _ stop: Int, _ time: Int32, _ p: Parent) {
            arrival[slot] = time
            best[stop] = time
            parent[slot] = p
            if !isMarked[stop] {
                isMarked[stop] = true
                marked.append(stop)
            }
        }

        let egress = tt.stops(near: to.location, within: settings.maxAccess).map { ($0.stop, walk($0.meters)) }

        for (stop, meters) in tt.stops(near: from.location, within: settings.maxAccess) {
            let t = t0 + walk(meters)
            if t < best[stop] { improve(stop, stop, t, Parent(kind: .access)) }
        }

        for k in 1...rounds {
            guard !marked.isEmpty else { break }

            // patterns through improved stops, scanned from the earliest such position
            for stop in marked {
                isMarked[stop] = false
                for sp in tt.stopPatterns[stop] {
                    let p = Int(sp.pattern)
                    if patternStart[p] == never { queue.append(p) }
                    patternStart[p] = min(patternStart[p], sp.position)
                }
            }
            marked.removeAll(keepingCapacity: true)

            let previous = (k - 1) * n, current = k * n

            for p in queue {
                let pattern = tt.patterns[p]
                let start = Int(patternStart[p])
                patternStart[p] = never
                var trip = -1, boardPos = 0

                for pos in start..<pattern.stops.count {
                    let stop = Int(pattern.stops[pos])
                    if trip >= 0 {
                        let t = pattern.time(trip: trip, at: pos)
                        if t < best[stop], t < targetBest {
                            improve(current + stop, stop, t,
                                    Parent(kind: .ride, a: Int32(p), b: Int32(trip), c: Int32(boardPos), d: Int32(pos)))
                        }
                    }
                    let ready = arrival[previous + stop]
                    guard ready != never else { continue }
                    let boardAt = ready + settings.boardSlack
                    if trip < 0 || boardAt <= pattern.time(trip: trip, at: pos),
                       let earlier = pattern.earliestTrip(at: pos, departingAfter: boardAt),
                       trip < 0 || earlier < trip {
                        trip = earlier
                        boardPos = pos
                    }
                }
            }
            queue.removeAll(keepingCapacity: true)

            // footpaths from stops reached by bus this round
            for stop in marked {
                let base = arrival[current + stop]
                for transfer in tt.transfers[stop] {
                    let other = Int(transfer.to)
                    let t = base + walk(Double(transfer.meters))
                    if t < best[other], t < targetBest {
                        improve(current + other, other, t, Parent(kind: .transfer, a: Int32(stop)))
                    }
                }
            }

            var roundBest = never, roundStop = -1
            for (stop, w) in egress where arrival[current + stop] != never {
                let t = arrival[current + stop] + w
                if t < roundBest { roundBest = t; roundStop = stop }
            }
            if roundStop >= 0, roundBest < targetBest {
                targetBest = roundBest
                targets.append((k, roundStop))
            }
        }

        for (round, stop) in targets {
            var rides: [Parent] = []
            var s = stop, r = round, steps = 0
            while r > 0, steps < 64 {
                steps += 1
                let p = parent[r * n + s]
                switch p.kind {
                case .ride:
                    rides.append(p)
                    s = Int(tt.patterns[Int(p.a)].stops[Int(p.c)])
                    r -= 1
                case .transfer:
                    s = Int(p.a)
                default:
                    r = -1
                }
            }
            guard r == 0 else { continue }
            journeys.append(journey(rides.reversed(), from: from, to: to, earliest: earliest, dayStart: dayStart))
        }
        return journeys
    }

    /// Walks are re-derived between consecutive rides, so chained footpaths collapse into one.
    private func journey(_ rides: [Parent], from: Place, to: Place, earliest: Date, dayStart: Date) -> Journey {
        var legs: [Journey.Leg] = []
        var here = from

        for ride in rides {
            let pattern = timetable.patterns[Int(ride.a)]
            let trip = Int(ride.b), board = Int(ride.c), alight = Int(ride.d)
            let stops = (board...alight).map { timetable.place(Int(pattern.stops[$0])) }

            if let walk = Journey.Walk(from: here, to: stops[0]) { legs.append(.walk(walk)) }
            legs.append(.ride(Journey.Ride(
                tripId: pattern.tripIds[trip],
                lineId: pattern.lineId,
                direction: pattern.direction,
                headsign: pattern.headsign,
                stops: stops,
                departure: dayStart.addingTimeInterval(TimeInterval(pattern.time(trip: trip, at: board))),
                arrival: dayStart.addingTimeInterval(TimeInterval(pattern.time(trip: trip, at: alight)))
            )))
            here = stops[stops.count - 1]
        }
        if let walk = Journey.Walk(from: here, to: to) { legs.append(.walk(walk)) }

        return Journey(from: from, to: to, legs: legs, earliest: earliest)
    }
}
