//
//  LineArrivalList.swift
//  stcp-app
//
//  Created by Nuno Rios on 13/10/2026.
//

import SwiftUI
import SwiftData

// one section per line, one row per route
struct LineArrivalList: View {
    let groups: [LineArrivalGroup]
 
    init(groups: [LineArrivalGroup]) {
        self.groups = groups
    }
 
    init(arrivals: [Arrival]) {
        self.groups = arrivals.groupedByLine()
    }
 
    var body: some View {
        let needsDoubledHeight = groups.contains { group in
            group.routeArrivals.contains { $0.arrivals.count > 1 }
        }
        
        // List {} created by caller
        ForEach(groups, id: \.line.id) { group in
            Section {
                ForEach(group.routeArrivals, id: \.route.persistentModelID) { routeGroup in
                    ArrivalRow(arrivals: routeGroup.arrivals,
                               doubledMinHeight: needsDoubledHeight)
                }
            }
        }
    }
}
