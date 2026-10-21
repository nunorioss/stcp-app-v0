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
    @Environment(\.scenePhase) private var scenePhase
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
                endpoints
                departureRow
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
                    .padding(.leading, 40)
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
                VStack(alignment: .leading, spacing: 1) {
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
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var departureRow: some View {
        HStack {
            Label("Depart", systemImage: "clock")
                .font(.system(.body, design: .rounded))
            Spacer()
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
        } else if model.journeys.isEmpty {
            if model.isSearching {
                Section {
                    ProgressView("Finding routes…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .listRowBackground(Color.clear)
                }
            } else {
                message("No routes found", systemImage: "bus",
                        description: "Try another time or destination")
            }
        } else {
            CollapsibleSection("Routes", storageKey: "travel.routes", forceExpanded: true) {
                ForEach(sort.sorted(model.journeys)) { journey in
                    NavigationLink(value: JourneyLink(id: journey.id)) {
                        JourneyRow(journey: journey)
                    }
                }
            } accessory: {
                sortMenu
            }
        }
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
