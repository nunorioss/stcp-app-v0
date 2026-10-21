//
//  ArrivalRow.swift
//  stcp-app
//
//  Created by Nuno Rios on 13/10/2026.
//

import SwiftUI
import SwiftData
 
struct ArrivalRow: View {
    let arrivals: [Arrival]
    let maxArrivals: Int
    
    //a single arrival still gets the height of two
    let doubledMinHeight: Bool
    
    @State private var showClock = false

    // all arrivals must be non-empty and belong to the same route
    init(arrivals: [Arrival], maxArrivals: Int = 4, doubledMinHeight: Bool = false) {
        precondition(!arrivals.isEmpty, "ArrivalRow needs at least one arrival")
        let route = arrivals[0].routeId
        precondition(arrivals.allSatisfy { $0.routeId == route },
                     "ArrivalRow arrivals must all be from the same route")
        
        self.arrivals = arrivals.sorted { $0.eta < $1.eta }
        self.maxArrivals = maxArrivals
        self.doubledMinHeight = doubledMinHeight
    }
    
    init(arrival: Arrival) {
        self.init(arrivals: [arrival])
    }
    
    var first: Arrival {
        arrivals[0]
    }
    
    var body: some View {
        let isFarAndNotToday = arrivals.count == 1
        && first.isFar && !first.isToday
        
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                LineBadge(busLine: first.line, scale: 0.8)
                    .padding(.trailing, 2)
     
                Text(first.route.headsign)
                    .font(.system(.body, design: .rounded))
     
                Spacer(minLength: 10)
     
                if !isFarAndNotToday {
                    ZStack(alignment: .trailing) {
                        if doubledMinHeight {
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(" ")
                                Text(" ")
                            }
                            .hidden()
                        }

                        VStack(alignment: .trailing, spacing: 3) {
                            ForEach(Array(arrivals.prefix(maxArrivals).enumerated()), id: \.offset) { _, arrival in
                                ArrivalTime(arrival: arrival, showClock: $showClock)
                            }
                        }
                    }
                    .font(.system(.subheadline, design: .monospaced))
                }
            }
            
            // show in a separate line from badge and route name
            if isFarAndNotToday {
                FarawayArrivalTime(arrival: first)
            }
        }
    }
}
