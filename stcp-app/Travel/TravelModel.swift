//
//  TravelModel.swift
//  stcp-app
//
//  Created by Nuno Rios on 21/10/2026.
//

import Foundation
import CoreLocation
import Observation

/// Picks the service days to search (yesterday's too, right after midnight) and runs RAPTOR off the main actor.
@MainActor
enum Planner {
    static func plan(from: Place, to: Place, at date: Date) async -> [Journey] {
        let calendar = DateUtil.portoCalendar
        let today = calendar.startOfDay(for: date)
        let seconds = Int32(DateUtil.secondsSinceMidnight(at: date))

        var days: [(start: Date, t: Int32)] = [(today, seconds)]
        if seconds < 3 * 3600, let yesterday = calendar.date(byAdding: .day, value: -1, to: today) {
            days.append((yesterday, seconds + Int32(DateUtil.secondsPerDay)))
        }

        var all: [Journey] = []
        for (start, t) in days {
            let timetable = await TimetableStore.timetable(for: DataStore.getServiceType(on: start).rawValue)
            all += await Task.detached(priority: .userInitiated) {
                Raptor.search(timetable, from: from, to: to, at: t, dayStart: start)
            }.value
        }
        return Journey.prune(all)
    }
}

@Observable
final class TravelModel {
    enum Endpoint: Hashable {
        case currentLocation
        case place(Place)
    }

    struct SearchKey: Hashable {
        let from: GeoPoint?
        let to: GeoPoint?
        let departure: Date?
    }

    var origin: Endpoint = .currentLocation
    var destination: Endpoint?
    /// nil = leave now
    var departure: Date?

    private(set) var journeys: [Journey] = []
    /// Live buses by trip id, for the map.
    private(set) var buses: [String: Bus] = [:]
    private(set) var isSearching = false

    private var planned: [Journey] = []
    private var lastSearch: (key: SearchKey, at: Date)?

    func name(of endpoint: Endpoint) -> String {
        switch endpoint {
        case .currentLocation: "My Location"
        case .place(let place): place.name
        }
    }

    func place(for endpoint: Endpoint?) -> Place? {
        switch endpoint {
        case .currentLocation:
            LocationProvider.shared.location.map {
                Place(name: "My Location",
                      location: GeoPoint(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude))
            }
        case .place(let place): place
        case nil: nil
        }
    }

    /// Rounded to ~100 m, so walking around doesn't trigger a new search.
    var searchKey: SearchKey {
        SearchKey(from: place(for: origin)?.location.rounded,
                  to: place(for: destination)?.location.rounded,
                  departure: departure)
    }

    /// Set when the trip is short enough that walking is a sensible alternative.
    var walkEstimate: (meters: Double, minutes: Int)? {
        guard let from = place(for: origin), let to = place(for: destination) else { return nil }
        let straight = from.location.distance(to: to.location)
        guard straight < 500 else { return nil }
        let minutes = Int((Double(Journey.walkSeconds(straight: straight)) / 60).rounded(.up))
        return (straight * Journey.detour, max(minutes, 1))
    }

    func journey(id: String) -> Journey? {
        journeys.first { $0.id == id }
    }

    func swap() {
        guard let destination else { return }
        (origin, self.destination) = (destination, origin)
    }

    func search(force: Bool = false) async {
        let key = searchKey
        guard let from = place(for: origin), let to = place(for: destination) else {
            planned = []
            journeys = []
            return
        }
        if !force, let last = lastSearch, last.key == key, Date.now.timeIntervalSince(last.at) < 120 {
            await refreshLive()
            return
        }

        isSearching = true
        defer { isSearching = false }

        let found = await Planner.plan(from: from, to: to, at: departure ?? .now)
        guard !Task.isCancelled else { return }
        planned = found
        journeys = found
        lastSearch = (key, .now)

        let refined = await WalkRouter.refine(found)
        guard !Task.isCancelled else { return }
        planned = refined
        journeys = refined
        await refreshLive()
    }

    func refreshLive() async {
        guard !planned.isEmpty, (departure ?? .now).timeIntervalSinceNow < 2 * 3600 else { return }
        let (updated, live) = await JourneyLive.apply(to: planned)
        guard !Task.isCancelled else { return }
        journeys = updated
        buses = live
    }
}

private extension GeoPoint {
    var rounded: GeoPoint {
        GeoPoint(latitude: (latitude * 1000).rounded() / 1000,
                 longitude: (longitude * 1000).rounded() / 1000)
    }
}
