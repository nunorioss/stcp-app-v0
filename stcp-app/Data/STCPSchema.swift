//
//  STCPSchema.swift
//  stcp-app
//
//  Created by Nuno Rios on 16/09/2026.
//

import SwiftData

public enum STCPSchema {
    
    public static let storeName = "stcp.store"
    
    public static let schema = Schema([
        BusLine.self,
        BusStop.self,
        Route.self,
        RouteStop.self,
        Trip.self,
        TripStop.self,
        ServiceDate.self,
        TripConfig.self
    ])
}
