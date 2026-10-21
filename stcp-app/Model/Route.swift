//
//  Route.swift
//  stcp-app
//
//  Created by Nuno Rios on 16/09/2026.
//

import Foundation
import SwiftData

@Model
public final class Route {
    
    @Relationship(inverse: \BusLine.storedRoutes)
    public private(set) var line: BusLine
    
    // Position within BusLine.routes
    // re-ordered at the end of parsing
    // so that main routes come first!
    public internal(set) var sortIndex: Int
    
    public private(set) var direction: Bool
    
    public private(set) var headsign: String
    
    // Subset of the line's shape that the route covers
    public internal(set) var shapeStart: Int = 0
    public internal(set) var shapeEnd: Int = 0
    
    // Master route for that direction of the line
    public internal(set) var isMasterRoute = false
    
    // for accessing stop coordinates without faulting
    // BusStop objects; useful for computing tripProgress()
    public internal(set) var stopCoords: [GeoPoint] = []
    
    @Relationship(deleteRule: .cascade)
    var storedRouteStops: [RouteStop] = []
    
    public var routeStops: [RouteStop] {
        storedRouteStops.sorted { $0.sequenceNo < $1.sequenceNo }
    }
    
    @Relationship(deleteRule: .cascade)
    public internal(set) var trips: [Trip] = []
    
    @Transient private var cachedStops: [BusStop]?
    
    public var stops: [BusStop] {
        if let cachedStops {
            return cachedStops
        }
        let result = routeStops.map(\.stop)
        cachedStops = result
        return result
    }
    
    @Transient private var cachedGeometry: RouteGeometry?
    
    public var geometry: RouteGeometry? {
        if let cachedGeometry {
            return cachedGeometry
        }
        let g = RouteGeometry(coords: stopCoords)
        cachedGeometry = g
        return g
    }
    
    public init(line: BusLine,
                sortIndex: Int,
                direction: Bool,
                headsign: String) {
        self.line = line
        self.sortIndex = sortIndex
        self.direction = direction
        self.headsign = headsign
    }
}
