//
//  JourneyRow.swift
//  stcp-app
//
//  Created by Nuno Rios on 21/10/2026.
//

import SwiftUI

struct JourneyRow: View {
    let journey: Journey

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                JourneyStrip(journey: journey)
                Text("\(DateUtil.clockText(for: journey.departure)) – \(DateUtil.clockText(for: journey.arrival))")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.secondary)
                details
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(journey.minutes)")
                        .font(.system(.title2, design: .rounded))
                        .bold()
                    Text("min")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                leaveText
            }
        }
        .padding(.vertical, 4)
    }

    private var details: some View {
        HStack(spacing: 10) {
            if journey.walkMeters > 0 {
                Label(Journey.distanceText(journey.walkMeters), systemImage: "figure.walk")
            }
            if journey.transfers > 0 {
                Label("\(journey.transfers) transfer\(journey.transfers == 1 ? "" : "s")",
                      systemImage: "arrow.triangle.swap")
            }
            if journey.isTight {
                Label("Tight", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
        .font(.system(.caption, design: .rounded))
        .foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
    }

    private var leaveText: some View {
        let minutes = Int((journey.departure.timeIntervalSinceNow / 60).rounded(.down))
        return HStack(spacing: 3) {
            if journey.isLive {
                Image(systemName: "dot.radiowaves.up.forward")
                    .imageScale(.small)
                    .accessibilityLabel("Live")
            }
            Text(minutes <= 0 ? "Leave now" : "in \(DateUtil.formatInterval(minutes))")
        }
        .font(.system(.caption, design: .rounded))
        .fontWeight(.medium)
        .foregroundStyle(journey.isTight ? Color.orange : journey.isLive ? Color.green : Color.secondary)
    }
}

/// Walk › 205 › walk › 500: drops the walks when space is tight.
struct JourneyStrip: View {
    let journey: Journey

    var body: some View {
        ViewThatFits(in: .horizontal) {
            strip(showingWalks: true)
            strip(showingWalks: false)
        }
    }

    private func strip(showingWalks: Bool) -> some View {
        let legs = journey.legs.filter {
            if case .ride = $0 { true } else { showingWalks }
        }
        return HStack(spacing: 4) {
            ForEach(Array(legs.enumerated()), id: \.offset) { i, leg in
                if i > 0 {
                    Image(systemName: "chevron.compact.right")
                        .foregroundStyle(.tertiary)
                }
                switch leg {
                case .walk(let walk):
                    HStack(spacing: 1) {
                        Image(systemName: "figure.walk")
                        Text("\(walk.minutes)")
                            .font(.caption2.monospacedDigit())
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Walk \(walk.minutes) minutes")
                case .ride(let ride):
                    if let line = DataStore.getBusLine(id: ride.lineId) {
                        LineBadge(busLine: line, scale: 0.55)
                    }
                }
            }
        }
    }
}

/// Clock time, live-colored like `ArrivalTime` when there's a live ETA.
struct LiveClock: View {
    let scheduled: Date
    let live: Date?

    var body: some View {
        HStack(spacing: 3) {
            if live != nil {
                Image(systemName: "dot.radiowaves.up.forward")
                    .imageScale(.small)
                    .accessibilityLabel("Live")
            }
            Text(DateUtil.clockText(for: live ?? scheduled))
        }
        .font(.system(.subheadline, design: .monospaced))
        .fontWeight(live == nil ? .regular : .semibold)
        .foregroundStyle(color)
        .fixedSize()
    }

    private var color: Color {
        guard let live else { return .secondary }
        let delayMinutes = live.timeIntervalSince(scheduled) / 60
        if delayMinutes > 10 { return .red }
        if delayMinutes > 3 { return .orange }
        return .green
    }
}
