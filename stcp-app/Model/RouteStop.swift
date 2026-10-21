//
//  RouteStop.swift
//  stcp-app
//
//  Created by Nuno Rios on 16/09/2026.
//

import SwiftData

@Model
public final class RouteStop {
    
    @Relationship(inverse: \Route.storedRouteStops)
    public private(set) var route: Route
    
    @Relationship(inverse: \BusStop.routeStops)
    public private(set) var stop: BusStop
    
    public private(set) var sequenceNo: Int
    
    public init(route: Route, stop: BusStop, sequenceNo: Int) {
        self.route = route
        self.stop = stop
        self.sequenceNo = sequenceNo
    }
}
