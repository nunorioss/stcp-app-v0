//
//  Journey.swift
//  stcp-app
//
//  Created by Nuno Rios on 21/10/2026.
//

import Foundation

/// A point the user can travel from or to: a stop, an address or their location.
nonisolated struct Place: Hashable, Sendable {
    let name: String
    var stopId: String? = nil
    var detail: String? = nil
    /// What it is, for search results: "Restaurant", "University", "Address"...
    var kind: String? = nil
    let location: GeoPoint
}

nonisolated struct Journey: Identifiable, Sendable {
    /// Walking speed in m/s, and how much longer streets are than a straight line.
    static let walkSpeed = 1.25
    static let detour = 1.3
    /// Walks shorter than this are dropped.
    static let minWalk = 25.0
    /// Seconds to be at the stop before the bus is due.
    static let boardBuffer: TimeInterval = 60

    static func walkSeconds(straight meters: Double) -> Int {
        Int((meters * detour / walkSpeed).rounded(.up))
    }

    nonisolated struct Walk: Sendable {
        let from: Place
        let to: Place
        var meters: Double
        var seconds: Int
        /// Street path from MapKit; nil while only estimated.
        var path: [GeoPoint]?

        init?(from: Place, to: Place) {
            let straight = Timetable.meters(from.location, to.location)
            guard straight >= Journey.minWalk else { return nil }
            self.from = from
            self.to = to
            meters = straight * Journey.detour
            seconds = Journey.walkSeconds(straight: straight)
        }

        var minutes: Int { max(1, Int((Double(seconds) / 60).rounded(.up))) }
    }

    nonisolated struct Ride: Sendable {
        let tripId: String
        let lineId: String
        let direction: Bool
        let headsign: String
        /// From the boarding stop to the alighting stop, inclusive.
        let stops: [Place]
        let departure: Date
        let arrival: Date
        /// Live ETA at the boarding stop.
        var live: Date?

        var from: Place { stops[0] }
        var to: Place { stops[stops.count - 1] }
        var delay: TimeInterval { live.map { $0.timeIntervalSince(departure) } ?? 0 }
        var liveDeparture: Date { live ?? departure }
        /// Assumes the delay at boarding carries through the ride.
        var liveArrival: Date { arrival.addingTimeInterval(delay) }
        var minutes: Int { max(1, Int((arrival.timeIntervalSince(departure) / 60).rounded())) }
    }

    nonisolated enum Leg: Sendable {
        case walk(Walk)
        case ride(Ride)
    }

    nonisolated struct Step: Identifiable, Sendable {
        let id: Int
        let leg: Leg
        let start: Date
        let end: Date
        /// Previous step ends after this one starts.
        let isTight: Bool
    }

    let from: Place
    let to: Place
    var legs: [Leg]
    /// When the search starts: the earliest the user can leave.
    var earliest: Date

    var id: String {
        let rides = rides.map { "\($0.tripId)@\($0.from.stopId ?? "")" }
        return rides.isEmpty ? "walk" : rides.joined(separator: ">")
    }

    var rides: [Ride] {
        legs.compactMap { leg -> Ride? in
            if case .ride(let ride) = leg { return ride }
            return nil
        }
    }

    var walks: [Walk] {
        legs.compactMap { leg -> Walk? in
            if case .walk(let walk) = leg { return walk }
            return nil
        }
    }

    /// The access walk is timed backwards from the first bus, so the user leaves just in time.
    var steps: [Step] {
        var result: [Step] = []
        var clock = earliest
        for (i, leg) in legs.enumerated() {
            switch leg {
            case .walk(let walk):
                var start = clock
                // only a walk to catch a bus can be late
                var catchesBus = false
                if i == 0, legs.count > 1, case .ride(let next) = legs[1] {
                    start = next.liveDeparture.addingTimeInterval(-Double(walk.seconds) - Self.boardBuffer)
                    catchesBus = true
                }
                let end = start.addingTimeInterval(Double(walk.seconds))
                result.append(Step(id: i, leg: leg, start: start, end: end,
                                   isTight: catchesBus && start < .now.addingTimeInterval(-30)))
                clock = end
            case .ride(let ride):
                result.append(Step(id: i, leg: leg, start: ride.liveDeparture, end: ride.liveArrival,
                                   isTight: i > 0 && clock > ride.liveDeparture))
                clock = ride.liveArrival
            }
        }
        return result
    }

    var departure: Date { steps.first?.start ?? earliest }
    var arrival: Date { steps.last?.end ?? earliest }
    var minutes: Int { max(1, Int((arrival.timeIntervalSince(departure) / 60).rounded())) }
    var transfers: Int { max(rides.count - 1, 0) }
    var walkMeters: Double { walks.reduce(0) { $0 + $1.meters } }
    var walkSeconds: Int { walks.reduce(0) { $0 + $1.seconds } }
    var isTight: Bool { steps.contains(where: \.isTight) }
    /// Have to leave right away to catch the first bus.
    var isTightStart: Bool {
        steps.contains { if case .walk = $0.leg { $0.isTight } else { false } }
    }
    /// Little or no time to change between buses.
    var isTightTransfer: Bool {
        steps.contains { if case .ride = $0.leg { $0.isTight } else { false } }
    }
    var isLive: Bool { rides.first?.live != nil }

    /// Lower is better: door-to-door time, plus a bit for waiting, walking and transferring.
    var score: Double {
        let travel = arrival.timeIntervalSince(departure)
        let wait = max(departure.timeIntervalSince(earliest), 0)
        return travel + 0.4 * wait + 0.6 * Double(walkSeconds) + 300 * Double(transfers)
    }

    /// A bus route that walking straight there beats: it walks at least as far, or it's
    /// slower and only saves a little walking. Catches detours like riding away from the
    /// destination and walking back from a stop farther than where you started.
    var isPointless: Bool {
        guard !rides.isEmpty else { return false }
        let straight = Timetable.meters(from.location, to.location)
        let walkThere = straight * Self.detour
        if walkMeters >= walkThere { return true }
        let slower = arrival.timeIntervalSince(departure) >= TimeInterval(Self.walkSeconds(straight: straight))
        return slower && walkMeters > walkThere / 2
    }

    /// Drops bus routes that walk at least as long as just walking there. Meant for after the
    /// walks are measured on real streets: a stop that looks close in a straight line can be
    /// a long way round (a motorway in between), which `isPointless` can't see.
    static func dropWalkingMoreThanWalking(_ journeys: [Journey]) -> [Journey] {
        guard let direct = journeys.first(where: { $0.rides.isEmpty }) else { return journeys }
        return journeys.filter { $0.rides.isEmpty || $0.walkSeconds < direct.walkSeconds }
    }

    /// No worse on anything, strictly better on something. Leaving later is better.
    func dominates(_ other: Journey) -> Bool {
        let noWorse = departure >= other.departure && arrival <= other.arrival
            && transfers <= other.transfers && walkMeters <= other.walkMeters
        let better = departure > other.departure || arrival < other.arrival
            || transfers < other.transfers || walkMeters < other.walkMeters
        return noWorse && better
    }

    /// Dedupes, drops pointless, dominated and much slower journeys, and keeps the best few.
    /// With `arriveBy`, the window is measured back from the latest departure instead.
    static func prune(_ journeys: [Journey], arriveBy: Bool = false, limit: Int = 8) -> [Journey] {
        var unique: [String: Journey] = [:]
        for j in journeys where !j.isPointless && unique[j.id].map({ j.score < $0.score }) ?? true {
            unique[j.id] = j
        }
        let all = Array(unique.values)
        let buses = all.filter { !$0.rides.isEmpty }
        // measured against buses only: walking there can arrive well before the next bus
        // even comes, and shouldn't push every bus route out
        let tooLate: (Journey) -> Bool
        if arriveBy {
            guard let latest = buses.map(\.departure).max() else { return all }
            tooLate = { latest.timeIntervalSince($0.departure) > 45 * 60 }
        } else {
            guard let fastest = buses.map(\.arrival).min() ?? all.map(\.arrival).min() else { return [] }
            tooLate = { $0.arrival.timeIntervalSince(fastest) > 45 * 60 }
        }

        let kept = all.filter { b in
            b.rides.isEmpty || !tooLate(b)
            && !all.contains { a in a.id != b.id && a.dominates(b) }
        }
        return Array(JourneySort.best.sorted(kept).prefix(limit))
    }

    static func distanceText(_ meters: Double) -> String {
        // round first, so 996 m reads "1.0 km" rather than "1000 m"
        let rounded = Int((meters / 10).rounded()) * 10
        return rounded < 1000
            ? "\(rounded) m"
            : String(format: "%.1f km", meters / 1000)
    }
}

nonisolated enum JourneySort: String, CaseIterable, Identifiable, Sendable {
    case best, fastest, leastWalking, fewestTransfers

    var id: Self { self }

    var title: String {
        switch self {
        case .best: "Best"
        case .fastest: "Fastest"
        case .leastWalking: "Less walking"
        case .fewestTransfers: "Fewer transfers"
        }
    }

    var systemImage: String {
        switch self {
        case .best: "sparkles"
        case .fastest: "hare"
        case .leastWalking: "figure.walk"
        case .fewestTransfers: "arrow.triangle.swap"
        }
    }

    func sorted(_ journeys: [Journey]) -> [Journey] {
        switch self {
        case .best: journeys.sorted { $0.score < $1.score }
        case .fastest: journeys.sorted { ($0.arrival, $0.score) < ($1.arrival, $1.score) }
        case .leastWalking: journeys.sorted { ($0.walkMeters, $0.arrival) < ($1.walkMeters, $1.arrival) }
        case .fewestTransfers: journeys.sorted { ($0.transfers, $0.arrival) < ($1.transfers, $1.arrival) }
        }
    }
}
