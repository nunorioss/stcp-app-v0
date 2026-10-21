//
//  BusOverlay.swift
//  stcp-app
//

import SwiftUI

/// Shown as a map callout when a bus is tapped. MapKit anchors callouts
/// to their annotation view, so this automatically stays pinned to the
/// bus as it moves — no manual position tracking needed.
///
/// Tapping the card crossfades between two faces: the front shows the
/// line/route and the next stop, the back shows bus id, speed and
/// last-update details.
struct BusOverlay: View {
    let bus: Bus

    @State private var showingBack = false

    /// Fixed width for the whole card. An exact value (not a maxWidth)
    /// so MapKit — which sizes the callout bubble itself — has no room
    /// to give the accessory view extra space and center it oddly.
    private static let cardWidth: CGFloat = 250

    var body: some View {
        // Both faces stay mounted; only their opacity toggles. That keeps
        // the card's size constant regardless of which face is showing.
        ZStack(alignment: .topLeading) {
            front.opacity(showingBack ? 0 : 1)
            back.opacity(showingBack ? 1 : 0)
        }
        .padding(5)
        .frame(maxWidth: Self.cardWidth, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.25)) {
                showingBack.toggle()
            }
        }
    }

    // MARK: - Faces

    private var front: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if let progress {
                journey(progress)
            }
        }
    }

    private var back: some View {
        VStack(alignment: .leading, spacing: 6) {
            footerRow(systemImage: "bus.fill", text: bus.id)
            footerRow(systemImage: "speedometer", text: "\(Int(bus.speed.rounded()))km/h")

            // Only tick the live clock while this face is actually visible.
            if showingBack {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    footerRow(systemImage: "clock", text: Self.compactAge(from: bus.timestamp, to: context.date))
                }
            } else {
                footerRow(systemImage: "clock", text: Self.compactAge(from: bus.timestamp, to: .now))
            }
        }
        .font(.caption2.monospaced())
        .foregroundStyle(.secondary)
        // Expand to fill the card, then center the block within that
        // space (front stays leading-aligned; only back centers).
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: - Front content

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            LineBadge(busLine: bus.line, scale: 0.7)
            Text(route?.headsign ?? "Unknown route")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .lineLimit(2)
                // Without this, the text can truncate with an ellipsis
                // instead of wrapping to a second line.
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.bottom, 4)
    }

    private func journey(_ info: (last: BusStop, next: BusStop, fraction: Double)) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("NEXT STOP")
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(lineColor)
            HStack(alignment: .top, spacing: 6) {
                Text(info.next.name)
                    .font(.footnote)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                StopBadge(id: info.next.id, scale: 0.6)
            }
        }
    }

    private func footerRow(systemImage: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .frame(width: 12, alignment: .center)
            Text(text)
        }
    }

    // MARK: - Derived data

    private var route: Route? {
        bus.trip?.route
    }

    private var lineColor: Color {
        bus.line.backgroundColor
    }

    /// The stop the bus most recently passed, the stop it's heading to
    /// next, and how far along that segment it currently is (0...1).
    private var progress: (last: BusStop, next: BusStop, fraction: Double)? {
        guard let route else { return nil }
        let stops = route.stops
        guard let hit = bus.tripProgress else {
            return nil
        }
        return (stops[hit.lastStopIndex], stops[hit.lastStopIndex + 1], hit.progress)
    }

    /// "10s ago", "5m ago", "2h ago", "3d ago" — recomputed every second by
    /// the TimelineView above while the back face is visible.
    private static func compactAge(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        switch seconds {
        case 0..<60:
            return "\(seconds)s ago"
        case 60:
            return "1min ago"
        case 61..<3600:
            return "\(seconds / 60)min \(seconds % 60)s ago"
        case 3600..<86_400:
            return "\(seconds / 3600)h ago"
        default:
            return "\(seconds / 86_400)d ago"
        }
    }
}
