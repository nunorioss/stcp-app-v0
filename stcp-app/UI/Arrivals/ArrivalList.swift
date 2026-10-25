//
//  ArrivalsView.swift
//  stcp-app
//
//  Created by Nuno Rios on 13/10/2026.
//

import SwiftUI
 
struct ArrivalList: View {
    let arrivals: [Arrival]
 
    private var sortedArrivals: [Arrival] {
        arrivals.sorted { $0.eta < $1.eta }
    }
 
    var body: some View {
        // List {} created by caller
        // one row per arrival (no line or route grouping)
        ForEach(Array(sortedArrivals.enumerated()), id: \.offset) { _, arrival in
            ArrivalRow(arrival: arrival)
        }
    }
}
