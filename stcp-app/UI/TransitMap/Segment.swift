//
//  Segment.swift
//  stcp-app
//
//  Created by Nuno Rios on 24/09/2026.
//

import SwiftUI
import MapKit

struct Segment: Equatable {
    let points: [CLLocationCoordinate2D]
    let stops: [CLLocationCoordinate2D]
    
    /// Meters from the start of the reference path to `points[0]`.
    ///
    /// Arrows are placed relative to the line's shape, so a route and its
    /// subset are arrows in the exact same spots.
    var startDistance: CLLocationDistance = 0

    let style: SegmentStyle
 
    static func ==(lhs: Segment, rhs: Segment) -> Bool {
        lhs.style == rhs.style
        && lhs.startDistance == rhs.startDistance
        && sameCoordinates(lhs.points, rhs.points)
        && sameCoordinates(lhs.stops, rhs.stops)
    }
    
    private static func sameCoordinates(_ lhs: [CLLocationCoordinate2D], _ rhs: [CLLocationCoordinate2D]) -> Bool {
        guard lhs.count == rhs.count else {
            return false
        }
        
        return zip(lhs, rhs).allSatisfy {
            $0.latitude == $1.latitude && $0.longitude == $1.longitude
        }
    }
}
