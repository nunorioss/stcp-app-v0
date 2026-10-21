//
//  TravelView.swift
//  stcp-app
//
//  Created by Nuno Rios on 21/10/2026.
//

import SwiftUI
import CoreLocation

struct JourneyLink: Hashable {
    let id: String
}

struct TravelView: View {
    @State private var model = TravelModel()
    @State private var picking: Field?
    @AppStorage("travel.sort") private var sort: JourneySort = .best
    @AppStorage("travel.liveOnly") private var liveOnly = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    private let iconWidth: CGFloat = 28
    private let locationProvider = LocationProvider.shared

    private let liveInterval: Duration = .seconds(20)

    enum Field: Identifiable {
        case origin, destination
        var id: Self { self }
    }

    private struct TaskKey: Equatable {
        let search: TravelModel.SearchKey
        let isActive: Bool
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 0) {
                    endpoints
                    Divider()
                        .padding(.leading, iconWidth + 12)
                    departureRow
                        .padding(.vertical, 10)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            results
        }
        .environment(\.defaultMinListHeaderHeight, 0)
        .navigationTitle("Travel")
        .navigationDestination(for: JourneyLink.self) {
            JourneyView(model: model, journeyId: $0.id)
        }
        .sheet(item: $picking) { field in
            PlacePicker(title: field == .origin ? "From" : "To") { endpoint in
                if field == .origin {
                    model.origin = endpoint
                } else {
                    model.destination = endpoint
                }
            }
        }
        .refreshable {
            await model.search(force: true)
        }
        .onAppear {
            if locationProvider.authorizationStatus == .notDetermined {
                locationProvider.requestPermission()
            }
            locationProvider.startTracking()
        }
        .onDisappear {
            locationProvider.stopTracking()
        }
        .task(id: TaskKey(search: model.searchKey, isActive: scenePhase == .active)) {
            // debounce while the user is still scrolling the time picker
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, scenePhase == .active else { return }
            await model.search()
            while !Task.isCancelled {
                try? await Task.sleep(for: liveInterval)
                await model.refreshLive()
            }
        }
    }

    // MARK: - From / To

    private var endpoints: some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                endpointButton(.origin, icon: "location.circle.fill", tint: .blue,
                               label: "From", value: model.name(of: model.origin))
                Divider()
                    .padding(.leading, iconWidth + 12)
                endpointButton(.destination, icon: "mappin.circle.fill", tint: .red,
                               label: "To", value: model.destination.map { model.name(of: $0) })
            }

            Button {
                withAnimation { model.swap() }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .background(Color(.tertiarySystemFill), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(model.destination == nil)
            .accessibilityLabel("Swap start and destination")
        }
    }

    private func endpointButton(_ field: Field, icon: String, tint: Color,
                                label: String, value: String?) -> some View {
        Button {
            picking = field
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(tint)
                    .frame(width: iconWidth)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(value ?? "Choose destination")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(value == nil ? .secondary : .primary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var departureRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock")
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: iconWidth)
            Text("Depart")
                .font(.system(.body, design: .rounded))
            Spacer(minLength: 0)
            if model.departure != nil {
                Button("Now") { model.departure = nil }
                    .buttonStyle(.borderless)
            }
            DatePicker("Depart",
                       selection: Binding(get: { model.departure ?? .now },
                                          set: { model.departure = $0 }),
                       displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
        }
    }

    // MARK: - Results

    @ViewBuilder
    private var results: some View {
        if model.destination == nil {
            message("Where to?", systemImage: "map",
                    description: "Choose a destination to see\nthe best ways to get there")
        } else if model.place(for: model.origin) == nil {
            message("Finding your location", systemImage: "location",
                    description: "Allow location access or\nchoose a starting point")
        } else {
            let walk = model.walkEstimate
            if let walk {
                Section {
                    walkRow(meters: walk.meters, minutes: walk.minutes)
                }
            }

            if model.journeys.isEmpty {
                if model.isSearching {
                    Section {
                        ProgressView("Finding routes…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                            .listRowBackground(Color.clear)
                    }
                } else if walk == nil {
                    message("No routes found", systemImage: "bus",
                            description: "Try another time or destination")
                }
            } else {
                let shown = sort.sorted(model.journeys).filter { !liveOnly || $0.isLive }
                CollapsibleSection("Routes", storageKey: "travel.routes", forceExpanded: true) {
                    if shown.isEmpty {
                        Text("No routes with live times right now")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    } else {
                        ForEach(shown) { journey in
                            NavigationLink(value: JourneyLink(id: journey.id)) {
                                JourneyRow(journey: journey)
                            }
                        }
                    }
                } accessory: {
                    HStack(spacing: 12) {
                        liveToggle
                        sortMenu
                    }
                }
            }
        }
    }

    private func walkRow(meters: Double, minutes: Int) -> some View {
        Button {
            openWalkingDirections()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "figure.walk")
                    .font(.title2)
                    .foregroundStyle(.green)
                    .frame(width: iconWidth)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Walk there")
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                    Text("It's only about \(Journey.distanceText(meters)) away")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(minutes)")
                        .font(.system(.title2, design: .rounded))
                        .fontWeight(.semibold)
                    Text("min")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "arrow.up.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens walking directions in Maps")
    }

    private func openWalkingDirections() {
        guard let from = model.place(for: model.origin)?.location,
              let to = model.place(for: model.destination)?.location,
              let url = URL(string: "maps://?saddr=\(from.latitude),\(from.longitude)&daddr=\(to.latitude),\(to.longitude)&dirflg=w")
        else { return }
        openURL(url)
    }

    private var liveToggle: some View {
        Button {
            withAnimation(.snappy) { liveOnly.toggle() }
        } label: {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundStyle(liveOnly ? Color.green : Color.secondary)
                .frame(width: 36, height: 36)
                .background(liveOnly ? Color.green.opacity(0.15) : Color.clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Only routes with live times")
        .accessibilityAddTraits(liveOnly ? .isSelected : [])
    }

    private func message(_ title: String, systemImage: String, description: String) -> some View {
        Section {
            ContentUnavailableView(title, systemImage: systemImage, description: Text(description))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort by", selection: $sort) {
                ForEach(JourneySort.allCases) { option in
                    Label(option.title, systemImage: option.systemImage).tag(option)
                }
            }
        } label: {
            Image(systemName: sort.systemImage)
                .font(.title3)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
        }
        .tint(.secondary)
        .accessibilityLabel("Sort routes")
    }
}

#Preview {
    NavigationStack {
        TravelView()
    }
}
