//
//  JourneyView.swift
//  stcp-app
//
//  Created by Nuno Rios on 21/10/2026.
//

import SwiftUI

struct JourneyView: View {
    let model: TravelModel
    let journeyId: String

    @Environment(\.scenePhase) private var scenePhase
    private let liveInterval: Duration = .seconds(20)

    var body: some View {
        Group {
            if let journey = model.journey(id: journeyId) {
                content(journey)
            } else {
                ContentUnavailableView("Route no longer available",
                                       systemImage: "bus",
                                       description: Text("Go back to see updated routes"))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await model.refreshLive()
                try? await Task.sleep(for: liveInterval)
            }
        }
    }

    private func content(_ journey: Journey) -> some View {
        List {
            CollapsibleSection("Map", storageKey: "journey.map") {
                TransitMapRepresentable(shape: RouteShape(journey: journey),
                                        buses: journey.rides.compactMap { model.buses[$0.tripId] })
                    .frame(height: 280)
                    .listRowInsets(EdgeInsets())
            }

            Section {
                JourneyRow(journey: journey)
            }

            CollapsibleSection("Steps", storageKey: "journey.steps", forceExpanded: true) {
                EndpointStepRow(icon: "location.circle.fill", tint: .blue,
                                title: journey.from.name, time: journey.departure)
                ForEach(journey.steps) { StepRow(step: $0) }
                EndpointStepRow(icon: "mappin.circle.fill", tint: .red,
                                title: journey.to.name, time: journey.arrival)
            }
        }
        .environment(\.defaultMinListHeaderHeight, 0)
        .navigationTitle("To \(journey.to.name)")
    }
}

private struct EndpointStepRow: View {
    let icon: String
    let tint: Color
    let title: String
    let time: Date

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(minWidth: 36)
            Text(title)
                .font(.system(.body, design: .rounded))
                .fontWeight(.medium)
                .lineLimit(2)
            Spacer(minLength: 8)
            Text(DateUtil.clockText(for: time))
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}

private struct StepRow: View {
    let step: Journey.Step

    @State private var showStops = false
    private let dotSize: CGFloat = 12

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            icon
                .frame(minWidth: 36)
            VStack(alignment: .leading, spacing: 4) {
                switch step.leg {
                case .walk(let walk): walkDetails(walk)
                case .ride(let ride): rideDetails(ride)
                }
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var icon: some View {
        switch step.leg {
        case .walk:
            Image(systemName: "figure.walk")
                .font(.title3)
                .foregroundStyle(.secondary)
        case .ride(let ride):
            if let line = DataStore.getBusLine(id: ride.lineId) {
                LineBadge(busLine: line, scale: 0.6)
            }
        }
    }

    @ViewBuilder
    private func walkDetails(_ walk: Journey.Walk) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Walk to \(walk.to.name)")
                .font(.system(.body, design: .rounded))
            Spacer(minLength: 8)
            Text(DateUtil.clockText(for: step.start))
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        // "~" until MapKit has measured the real walking route
        Text("\(walk.path == nil ? "~" : "")\(walk.minutes) min · \(Journey.distanceText(walk.meters))")
            .font(.system(.footnote, design: .rounded))
            .foregroundStyle(.secondary)
        if step.isTight {
            warning("Leave now to make it")
        }
    }

    @ViewBuilder
    private func rideDetails(_ ride: Journey.Ride) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Towards")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
            Text(ride.headsign)
                .font(.system(.body, design: .rounded))
                .fontWeight(.semibold)
        }
        .padding(.bottom, 8)

        VStack(alignment: .leading, spacing: 0) {
            timelineStop(caption: "Board at", name: ride.from.name) {
                LiveClock(scheduled: ride.departure, live: ride.live)
            }
            if step.isTight {
                warning("Tight connection")
                    .padding(.leading, dotSize + 10)
                    .padding(.top, 4)
            }

            HStack(alignment: .top, spacing: 10) {
                Rectangle()
                    .fill(.quaternary)
                    .frame(width: 2)
                    .frame(width: dotSize)
                intermediateStops(ride)
                    .padding(.vertical, 10)
            }

            timelineStop(caption: "Get off at", name: ride.to.name) {
                Text(DateUtil.clockText(for: ride.liveArrival))
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func timelineStop(caption: String, name: String,
                              @ViewBuilder time: () -> some View) -> some View {
        HStack(spacing: 10) {
            Circle()
                .strokeBorder(.secondary, lineWidth: 2)
                .frame(width: dotSize, height: dotSize)
            VStack(alignment: .leading, spacing: 1) {
                Text(caption)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(name)
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.medium)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            time()
        }
    }

    @ViewBuilder
    private func intermediateStops(_ ride: Journey.Ride) -> some View {
        let middle = Array(ride.stops.dropFirst().dropLast())
        let count = ride.stops.count - 1
        let summary = "\(count) stop\(count == 1 ? "" : "s") · \(ride.minutes) min"

        if middle.isEmpty {
            Text(summary)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.snappy) { showStops.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text(summary)
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.bold))
                            .rotationEffect(.degrees(showStops ? 180 : 0))
                    }
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showStops ? "Hide stops" : "Show \(middle.count) intermediate stops")

                if showStops {
                    ForEach(Array(middle.enumerated()), id: \.offset) { _, stop in
                        Text(stop.name)
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 5)
                    }
                }
            }
        }
    }

    private func warning(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.system(.footnote, design: .rounded))
            .foregroundStyle(.orange)
    }
}
