//
//  RouteShape+Journey.swift
//  stcp-app
//
//  Created by Nuno Rios on 21/10/2026.
//

import MapKit

extension RouteShape {
    /// Dotted walks and solid, line-colored rides that follow the line's shape.
    init(journey: Journey) {
        var segments: [Segment] = []
        var arrows: [RouteArrow] = []

        for leg in journey.legs {
            switch leg {
            case .walk(let walk):
                let points = (walk.path ?? [walk.from.location, walk.to.location]).map(\.coordinate)
                segments.append(Segment(points: points,
                                        stops: [walk.from.location.coordinate, walk.to.location.coordinate],
                                        style: .walking))
            case .ride(let ride):
                guard let line = DataStore.getBusLine(id: ride.lineId) else { continue }
                let points = Self.slice(line.shape(ride.direction), from: ride.from.location, to: ride.to.location)
                    ?? ride.stops.map(\.location.coordinate)
                segments.append(Segment(points: points,
                                        stops: ride.stops.map(\.location.coordinate),
                                        style: .solid(line.backgroundColor)))
                arrows += RouteArrow.along(points)
            }
        }
        self.init(segments: segments, arrows: arrows)
    }

    /// The part of a line's shape between two stops, or nil if the stops are off the shape.
    private static func slice(_ shape: [GeoPoint], from a: GeoPoint, to b: GeoPoint) -> [CLLocationCoordinate2D]? {
        guard shape.count > 1 else { return nil }

        func nearest(_ p: GeoPoint, in range: Range<Int>) -> (index: Int, meters: Double)? {
            range.map { (index: $0, meters: Timetable.meters(shape[$0], p)) }.min { $0.meters < $1.meters }
        }

        guard let start = nearest(a, in: 0..<(shape.count - 1)), start.meters < 150,
              let end = nearest(b, in: (start.index + 1)..<shape.count), end.meters < 150 else {
            return nil
        }
        return shape[start.index...end.index].map(\.coordinate)
    }
}
