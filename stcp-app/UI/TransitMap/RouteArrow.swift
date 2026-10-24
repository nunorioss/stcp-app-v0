//
//  RouteArrow.swift
//  stcp-app
//
//  Created by Nuno Rios on 24/09/2026.
//

import MapKit

struct RouteArrow {
    let coordinate: CLLocationCoordinate2D
    let angle: Double // radians, clockwise from north
    
    /// The zoom level from which this arrow is shown.
    let level: Int

    /// Walking arrows are drawn on their own instead of on top of a line.
    var walking = false
    
    // finest spacing
    static let spacing: CLLocationDistance = 125
    static let walkingSpacing: CLLocationDistance = 30
    
    private static func level(ofIndex k: Int) -> Int {
        if k % 8 == 0 { return 1 }
        if k % 4 == 0 { return 2 }
        if k % 2 == 0 { return 3 }
        return 4
    }

    static func along(
        _ coordinates: [CLLocationCoordinate2D],
        startDistance: CLLocationDistance = 0,
        walking: Bool = false
    ) -> [RouteArrow] {
        let spacing = walking ? Self.walkingSpacing : Self.spacing
        guard coordinates.count > 1 else {
            return []
        }

        // first arrow at or after this slice's start
        var k = max(0, Int(ceil((startDistance - spacing / 2) / spacing)))
        var nextArrow = spacing / 2 + Double(k) * spacing
        var result: [RouteArrow] = []
        var travelled = startDistance
        var a = MKMapPoint(coordinates[0])

        for coordinate in coordinates.dropFirst() {
            let b = MKMapPoint(coordinate)
            let length = a.distance(to: b)
            let end = travelled + length
            defer {
                a = b
                travelled = end
            }

            guard length > 0, nextArrow < end else {
                continue
            }

            let dx = b.x - a.x, dy = b.y - a.y
            let angle = atan2(dx, -dy)

            while nextArrow < end {
                let t = (nextArrow - travelled) / length
                let point = MKMapPoint(x: a.x + dx * t, y: a.y + dy * t)
                result.append(
                    RouteArrow(coordinate: point.coordinate, angle: angle, level: level(ofIndex: k), walking: walking)
                )
                k += 1
                nextArrow = spacing / 2 + Double(k) * spacing
            }
        }
        return result
    }
    
    /// Length in meters of the polyline through `coordinates`.
    static func length(of coordinates: some Collection<CLLocationCoordinate2D>) -> CLLocationDistance {
        var total = 0.0
        var previous: MKMapPoint?
        
        for coordinate in coordinates {
            let point = MKMapPoint(coordinate)
            if let previous {
                total += previous.distance(to: point)
            }
            previous = point
        }
        return total
    }
}
