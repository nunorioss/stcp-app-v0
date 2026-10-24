//
//  JourneyRow.swift
//  stcp-app
//
//  Created by Nuno Rios on 21/10/2026.
//

import SwiftUI

struct JourneyRow: View {
    let journey: Journey

    /// Walking only has no bus to catch, so leave whenever; a year or more out isn't useful.
    private var showsLeave: Bool {
        !journey.rides.isEmpty && journey.departure.timeIntervalSinceNow < Self.year
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                JourneyStrip(journey: journey)
                    .padding(.bottom, 4)
                Text("\(DateUtil.clockText(for: journey.departure)) – \(DateUtil.clockText(for: journey.arrival))")
                    .font(.system(.subheadline, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 2)
                details
            }

            Spacer(minLength: 8)

            if showsLeave {
                VStack(alignment: .trailing, spacing: 15) {
                    tripTime
                    leaveColumn
                }
            } else if journey.minutes < 60 {
                bigNumber("\(journey.minutes)", unit: "min")
            } else {
                bigNumber(DateUtil.formatInterval(journey.minutes))
            }
        }
        .padding(.vertical, 4)
    }

    /// Door-to-door duration, above the (bigger) leave time.
    private var tripTime: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            // 1h, 1h30min, ... past an hour, like the leave time
            Text(journey.minutes < 60 ? "\(journey.minutes)" : DateUtil.formatInterval(journey.minutes))
                .font(.system(.callout, design: .rounded))
                .fontWeight(.medium)
            if journey.minutes < 60 {
                Text("min")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 5) {
            if journey.walkMeters > 0 {
                Label(Journey.distanceText(journey.walkMeters), systemImage: "figure.walk")
            }
            if journey.transfers > 0 {
                Label("\(journey.transfers) transfer\(journey.transfers == 1 ? "" : "s")",
                      systemImage: "arrow.triangle.swap")
            }
            if journey.isTightStart {
                Label("Tight", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            if journey.isTightTransfer {
                Label("Tight transfer", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
        .font(.system(.caption, design: .rounded))
        .foregroundStyle(.secondary)
        .labelStyle(TightLabelStyle())
    }

    private static let minute = 60.0, hour = 3600.0, day = 86_400.0
    private static let week = 7 * day, month = 30 * day, year = 365 * day

    /// The two largest units left, e.g. 12min, 2h5min, 1d20h. A week or more is one unit
    /// in full (1 week, 3 months). Minutes stand alone, and a zero second unit is dropped.
    static func leaveParts(_ seconds: TimeInterval) -> [(value: Int, unit: String)] {
        let units: [(TimeInterval, String)] = [(month, "m"), (week, "w"), (day, "d"),
                                               (hour, "h"), (minute, "min")]
        let s = max(seconds, 0)
        guard let i = units.firstIndex(where: { s >= $0.0 }) else { return [] }
        let (size, unit) = units[i]
        if size >= week {
            let value = Int(s / size)
            let word = size == month ? "month" : "week"
            return [(value, value == 1 ? word : word + "s")]
        }
        var parts = [(value: Int(s / size), unit: unit)]
        if i + 1 < units.count {
            let (smaller, smallerUnit) = units[i + 1]
            let rest = Int(s.truncatingRemainder(dividingBy: size) / smaller)
            if rest > 0 { parts.append((rest, smallerUnit)) }
        }
        return parts
    }

    /// When to leave, big. Ticks on its own so it counts down between live refreshes.
    private var leaveColumn: some View {
        let tint = journey.isTightStart ? Color.orange : journey.isLive ? Color.green : Color.primary

        return TimelineView(.periodic(from: .now, by: 10)) { context in
            // under a minute left counts as now
            let seconds = journey.departure.timeIntervalSince(context.date) < Self.minute
                ? 0 : journey.departure.timeIntervalSince(context.date)

            VStack(alignment: .trailing, spacing: 1) {
                Text(seconds <= 0 ? "Leave" : "Leave in")
                    .font(.system(.caption2, design: .rounded))
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    if journey.isLive {
                        Image(systemName: "dot.radiowaves.up.forward")
                            .font(.caption)
                            .accessibilityLabel("Live")
                    }
                    if seconds <= 0 {
                        bigNumber("now")
                    } else {
                        ForEach(Array(Self.leaveParts(seconds).enumerated()), id: \.offset) { _, part in
                            bigNumber("\(part.value)", unit: part.unit)
                        }
                    }
                }
                .foregroundStyle(tint)
            }
        }
    }

    private func bigNumber(_ value: String, unit: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(value)
                .font(.system(.title2, design: .rounded))
                .bold()
            if let unit {
                Text(unit)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Walk › 205 › walk › 500: drops the walk minutes, then the walks, when space is tight.
struct JourneyStrip: View {
    let journey: Journey

    var body: some View {
        ViewThatFits(in: .horizontal) {
            strip(showingWalks: true, showingWalkMinutes: true)
            strip(showingWalks: true, showingWalkMinutes: false)
            strip(showingWalks: false, showingWalkMinutes: false)
        }
    }

    private func strip(showingWalks: Bool, showingWalkMinutes: Bool) -> some View {
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
                        if showingWalkMinutes {
                            Text("\(walk.minutes)")
                                .font(.caption2.monospacedDigit())
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Walk \(walk.minutes) minutes")
                case .ride(let ride):
                    if let line = DataStore.getBusLine(id: ride.lineId) {
                        HStack(spacing: 2) {
                            if ride.live != nil {
                                Image(systemName: "dot.radiowaves.up.forward")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.green)
                                    .accessibilityLabel("Live")
                            }
                            LineBadge(busLine: line, scale: 0.55)
                        }
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

/// Icon + title with minimal gap, for compact metadata rows.
private struct TightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 2) {
            configuration.icon
            configuration.title
        }
    }
}
