//
//  ArrivalGroup.swift
//  stcp-app
//
//  Created by Nuno Rios on 09/10/2026.
//

import Foundation
import SwiftData

// Arrivals grouped by route
nonisolated struct RouteArrivalGroup {
    public let lineId: String
    public let routeId: PersistentIdentifier
    public let routeSortIndex: Int
    public let arrivals: [Arrival]
}

// Arrivals grouped by line AND route
nonisolated struct LineArrivalGroup {
    public let lineId: String
    public let routeArrivals: [RouteArrivalGroup]
}

extension [Arrival] {
    nonisolated func groupedByRoute() -> [RouteArrivalGroup] {
        Dictionary(grouping: self, by: { $0.routeId })
            .map { _, arrivals in
                let first = arrivals[0]
                // sort between arrivals by eta
                return RouteArrivalGroup(lineId: first.lineId,
                                         routeId: first.routeId,
                                         routeSortIndex: first.routeSortIndex,
                                         arrivals: arrivals.sorted { $0.eta < $1.eta })
            }
    }

    nonisolated func groupedByLine() -> [LineArrivalGroup] {
        groupedByRoute().groupedByLine()
    }
}

extension [RouteArrivalGroup] {
    nonisolated func groupedByLine() -> [LineArrivalGroup] {
        Dictionary(grouping: self, by: { $0.lineId })
            .map { lineId, routes in
                // sort between routes by sort index
                let sortedRoutes = routes.sorted { $0.routeSortIndex < $1.routeSortIndex }
                return LineArrivalGroup(lineId: lineId, routeArrivals: sortedRoutes)
            }
            // then sort between lines by soonest arrival
            .sorted { a, b in
                let ea = a.routeArrivals[0].arrivals[0].eta
                let eb = b.routeArrivals[0].arrivals[0].eta
                // line id as tiebreaker so order is stable
                return ea != eb ? ea < eb : a.lineId < b.lineId
            }
    }
}
