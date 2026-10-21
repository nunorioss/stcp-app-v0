//
//  Arrival+Model.swift
//  stcp-app
//
//  Created by Nuno Rios on 20/10/2026.
//

import SwiftData

@MainActor
extension Arrival {
    var line: BusLine {
        guard let line = DataStore.getBusLine(id: lineId) else {
            preconditionFailure("Arrival \(tripId) is on line \(lineId), which is not stored")
        }
        return line
    }

    var route: Route {
        SwiftDataManager.context.model(for: routeId) as! Route
    }
}

@MainActor
extension LineArrivalGroup {
    var line: BusLine {
        guard let line = DataStore.getBusLine(id: lineId) else {
            preconditionFailure("Line \(lineId) is not stored")
        }
        return line
    }
}

@MainActor
extension RouteArrivalGroup {
    var route: Route {
        SwiftDataManager.context.model(for: routeId) as! Route
    }
}
