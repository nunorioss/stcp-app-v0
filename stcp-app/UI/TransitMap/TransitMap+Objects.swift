//
//  TransitMap+Objects.swift
//  stcp-app
//
//  Created by Nuno Rios on 20/09/2026.
//

import MapKit
import SwiftUI
 
//MARK: Overlays
// the shape and its border
 
final class BorderPolyline: MKPolyline {
    var opacity: Double = 1
}
final class StyledPolyline: MKPolyline {
    var style: SegmentStyle = .solid(.white)
}
 
//MARK: Annotations
// arrows, stop dots and live buses
 
final class ArrowAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    let angle: Double
    let level: Int
    let walking: Bool
    
    init(coordinate: CLLocationCoordinate2D, angle: Double, level: Int, walking: Bool = false) {
        self.coordinate = coordinate
        self.angle = angle
        self.level = level
        self.walking = walking
    }
    
    convenience init(_ arrow: RouteArrow) {
        self.init(coordinate: arrow.coordinate,
                  angle: arrow.angle,
                  level: arrow.level,
                  walking: arrow.walking)
    }
}

final class StopAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    let style: SegmentStyle
    /// First or last stop of its segment (route ends, or where to board and alight), drawn bigger.
    let isEndpoint: Bool
    
    init(coordinate: CLLocationCoordinate2D, style: SegmentStyle, isEndpoint: Bool = false) {
        self.coordinate = coordinate
        self.style = style
        self.isEndpoint = isEndpoint
    }
}

final class BusAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    private(set) var bus: Bus
    
    init(bus: Bus) {
        self.bus = bus
        self.coordinate = bus.location.coordinate
    }
    
    func update(to bus: Bus) {
        self.bus = bus
        coordinate = bus.location.coordinate
    }
}
