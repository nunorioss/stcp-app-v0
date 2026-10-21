//
//  JourneyLive.swift
//  stcp-app
//
//  Created by Nuno Rios on 21/10/2026.
//

import Foundation
import MapKit

/// Puts live departures on every ride: PortoDigital bus position first, then delay
/// inferred from the bus's previous trip, then STCP's own ETA at the first boarding stop.
@MainActor
enum JourneyLive {
    /// Live ETAs further than this from the schedule are ignored.
    private static let maxDeviation: TimeInterval = 30 * 60

    static func apply(to journeys: [Journey]) async -> (journeys: [Journey], buses: [String: Bus]) {
        let rides = journeys.flatMap(\.rides)
        guard !rides.isEmpty else {
            return (journeys, [:])
        }

        let lineIds = Set(rides.flatMap { [$0.lineId] + (DataStore.getBusLine(id: $0.lineId)?.sisterLineIds ?? []) })
        var live = Estimator.LiveData()
        for bus in await BusTracker.shared.getLiveBuses(forLines: Array(lineIds)) {
            if let trip = bus.trip { live.byTripId[trip.id] = bus }
        }
        let stcp = await stcpETAs(for: Set(journeys.compactMap { $0.rides.first?.from.stopId }))

        let now = Date(), nowSeconds = DateUtil.secondsSinceMidnight()
        let inferred = Estimator.inferLiveFromPreviousTrips(for: Array(Set(rides.map(\.tripId))),
                                                            live: live, now: now, nowSeconds: nowSeconds)

        let updated = journeys.map { journey in
            var journey = journey
            journey.legs = journey.legs.map { leg in
                guard case .ride(var ride) = leg else { return leg }
                let eta = tracked(ride, bus: live.byTripId[ride.tripId], now: now, nowSeconds: nowSeconds)
                    ?? inferred[ride.tripId].map { ride.departure.addingTimeInterval($0.delay) }
                    ?? ride.from.stopId.flatMap { stcp[$0]?[ride.tripId] }
                ride.live = eta.flatMap { abs($0.timeIntervalSince(ride.departure)) <= maxDeviation ? $0 : nil }
                return .ride(ride)
            }
            return journey
        }
        return (updated, live.byTripId)
    }

    private static func tracked(_ ride: Journey.Ride, bus: Bus?, now: Date, nowSeconds: Int) -> Date? {
        guard let bus, let trip = bus.trip, bus.tripProgress != nil,
              let stopId = ride.from.stopId,
              let stop = DataStore.getBusStop(id: stopId),
              let index = trip.route.stops.firstIndex(where: { $0.id == stopId }) else {
            return nil
        }
        return Estimator.makeArrival(of: trip, at: stop, stopIndex: index,
                                     bus: bus, now: now, nowSeconds: nowSeconds)?.live?.eta
    }

    private static func stcpETAs(for stopIds: Set<String>) async -> [String: [String: Date]] {
        await withTaskGroup(of: (String, [String: Date]).self) { group in
            for id in stopIds {
                group.addTask { (id, (try? await STCPFetcher.getLiveETAs(for: id)) ?? [:]) }
            }
            var result: [String: [String: Date]] = [:]
            for await (id, etas) in group { result[id] = etas }
            return result
        }
    }
}

/// Replaces estimated walks with MapKit walking directions: real distance, time and path.
@MainActor
enum WalkRouter {
    nonisolated struct Route: Sendable {
        let meters: Double
        let seconds: Int
        let path: [GeoPoint]
    }

    /// MapKit throttles directions, so cap how many are requested per search.
    private static let maxRequests = 24
    private static var cache: [String: Route] = [:]

    private static func key(_ a: GeoPoint, _ b: GeoPoint) -> String {
        String(format: "%.5f,%.5f>%.5f,%.5f", a.latitude, a.longitude, b.latitude, b.longitude)
    }

    static func refine(_ journeys: [Journey]) async -> [Journey] {
        var pending: [String: (GeoPoint, GeoPoint)] = [:]
        for walk in journeys.flatMap(\.walks) where pending.count < maxRequests {
            let k = key(walk.from.location, walk.to.location)
            if cache[k] == nil { pending[k] = (walk.from.location, walk.to.location) }
        }

        await withTaskGroup(of: (String, Route?).self) { group in
            for (k, (a, b)) in pending {
                group.addTask { (k, await directions(from: a, to: b)) }
            }
            for await (k, route) in group {
                if let route { cache[k] = route }
            }
        }

        return journeys.map { journey in
            var journey = journey
            journey.legs = journey.legs.map { leg in
                guard case .walk(var walk) = leg,
                      let route = cache[key(walk.from.location, walk.to.location)] else { return leg }
                walk.meters = route.meters
                walk.seconds = route.seconds
                walk.path = route.path
                return .walk(walk)
            }
            return journey
        }
    }

    private static func directions(from a: GeoPoint, to b: GeoPoint) async -> Route? {
        let request = MKDirections.Request()
        request.source = .at(a)
        request.destination = .at(b)
        request.transportType = .walking

        guard let route = try? await MKDirections(request: request).calculate().routes.first else {
            return nil
        }
        let line = route.polyline
        var coords = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: line.pointCount)
        line.getCoordinates(&coords, range: NSRange(location: 0, length: line.pointCount))

        return Route(meters: route.distance,
                     seconds: Int(route.expectedTravelTime.rounded(.up)),
                     path: coords.map { GeoPoint(latitude: $0.latitude, longitude: $0.longitude) })
    }
}

extension MKMapItem {
    static func at(_ point: GeoPoint) -> MKMapItem {
        if #available(iOS 26, *) {
            return MKMapItem(location: point.clLocation, address: nil)
        }
        return MKMapItem(placemark: MKPlacemark(coordinate: point.coordinate))
    }

    func place(fallbackName: String) -> Place {
        let coordinate: CLLocationCoordinate2D
        let detail: String?
        if #available(iOS 26, *) {
            coordinate = location.coordinate
            detail = address?.shortAddress
        } else {
            coordinate = placemark.coordinate
            detail = placemark.title
        }
        return Place(name: name ?? fallbackName,
                     detail: detail,
                     location: GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude))
    }
}
