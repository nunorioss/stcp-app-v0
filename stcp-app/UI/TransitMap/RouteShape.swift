//
//  RouteShape.swift
//  stcp-app
//
//  Created by Nuno Rios on 20/09/2026.
//

import MapKit

struct RouteShape: Equatable {
    let segments: [Segment]
    
    // Direction markers along the route
    let arrows: [RouteArrow]
    
    static var empty: RouteShape {
        RouteShape(segments: [Segment](), arrows: [RouteArrow]())
    }
    
    init(segments: [Segment], arrows: [RouteArrow]) {
        self.segments = segments
        self.arrows = arrows
    }

    init(route: Route) {
        let full = route.direction ? route.line.shape1 : route.line.shape0
        let subset = full[route.shapeStart..<route.shapeEnd]
        
        let segment = Segment(
            points: subset.map(\.coordinate),
            stops: route.routeStops.map { $0.stop.location.coordinate },
            startDistance: RouteArrow.length(of: full[...route.shapeStart].map(\.coordinate)),
            style: SegmentStyle.solid(route.line.backgroundColor)
        )
        
        let arrows = RouteArrow.along(segment.points, startDistance: segment.startDistance)
        
        self.init(segments: [segment], arrows: arrows)
    }
    
    static func ==(lhs: RouteShape, rhs: RouteShape) -> Bool {
        lhs.segments == rhs.segments
    }

    var framingRect: MKMapRect? {
        let coordinates = segments.flatMap(\.points)
        guard !coordinates.isEmpty else {
            return nil
        }
        return MKPolyline(coordinates: coordinates, count: coordinates.count).boundingMapRect
    }
    
    var overlays: [MKOverlay] {
        segments.flatMap { segment -> [MKOverlay] in
            guard segment.points.count > 1 else {
                return []
            }
            let line = StyledPolyline(coordinates: segment.points, count: segment.points.count)
            line.style = segment.style
            
            // walks are drawn as arrows only
            guard !segment.style.dashed else {
                return []
            }
            
            let border = BorderPolyline(coordinates: segment.points, count: segment.points.count)
            border.opacity = segment.style.opacity
            
            return [border, line]
        }
    }
}
