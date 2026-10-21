//
//  ArrivalTime.swift
//  stcp-app
//
//  Created by Nuno Rios on 14/10/2026.
//

import SwiftUI

// Faraway arrivals get their own line in the UI
struct FarawayArrivalTime: View {
    let arrival: Arrival
    
    var body: some View {
        Text(DateUtil.formatUpcomingDate(for: arrival.eta))
            .font(.system(.subheadline, design: .monospaced))
            .foregroundStyle(.secondary)
            .fixedSize()
    }
}

// Arrivals within 3h show inline with the line
// badge and route name
struct ArrivalTime: View {
    let arrival: Arrival
    @Binding var showClock: Bool

    var body: some View {
        HStack(spacing: 4) {
            if arrival.isLive {
                Image(systemName: "dot.radiowaves.up.forward")
                    .imageScale(.small)
                    .accessibilityLabel("Live")
            }
            Text(timeText)
        }
        .font(.system(.subheadline, design: .monospaced))
        .fontWeight(arrival.isLive ? .semibold : .regular)
        .foregroundStyle(color)
        .fixedSize()
        .contentShape(Rectangle())
        .onTapGesture {
            showClock.toggle()
        }
    }
    
    private var timeText: String {
        arrival.isFar || showClock
        ? DateUtil.clockText(for: arrival.eta)
            : DateUtil.formatInterval(arrival.minutesTilArrival)
    }
 
    private var color: Color {
        guard arrival.isLive else { return .secondary }
        let delayMinutes = arrival.delay / 60
        if delayMinutes > 10 { return .red }
        if delayMinutes > 3 { return .orange }
        return .green
    }
}
