//
//  PlacePicker.swift
//  stcp-app
//
//  Created by Nuno Rios on 21/10/2026.
//

import SwiftUI
import MapKit

/// Addresses and points of interest around Porto, from MapKit.
@MainActor
enum PlaceSearch {
    private static let porto = CLLocationCoordinate2D(latitude: 41.1579, longitude: -8.6291)

    static func search(_ query: String) async -> [Place] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.address, .pointOfInterest]
        request.region = MKCoordinateRegion(center: porto, latitudinalMeters: 40_000, longitudinalMeters: 40_000)
        request.regionPriority = .required

        guard let response = try? await MKLocalSearch(request: request).start() else {
            return []
        }
        return response.mapItems.prefix(8).map { $0.place(fallbackName: query) }
    }
}

struct PlacePicker: View {
    let title: String
    let onPick: (TravelModel.Endpoint) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var favorites = FavoritesStore.shared
    @State private var query = ""
    @State private var places: [Place] = []

    private static let allStops = DataStore.getBusStops()
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

    private var trimmed: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        NavigationStack {
            List {
                if trimmed.isEmpty {
                    suggestions
                } else {
                    results
                }
            }
            .searchable(text: $query,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search places or stops")
            .autocorrectionDisabled()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task(id: trimmed) {
                guard !trimmed.isEmpty else {
                    places = []
                    return
                }
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                places = await PlaceSearch.search(trimmed)
            }
        }
    }

    private func pick(_ endpoint: TravelModel.Endpoint) {
        onPick(endpoint)
        dismiss()
    }

    @ViewBuilder
    private var suggestions: some View {
        Section {
            Button { pick(.currentLocation) } label: {
                PlaceRow(title: "My Location", icon: "location.circle.fill", tint: .blue)
            }
        }
        let favoriteStops = favorites.getFavoriteStops
        if !favoriteStops.isEmpty {
            Section("Favorite Stops") {
                ForEach(favoriteStops, id: \.id) { stopButton($0) }
            }
        }
    }

    @ViewBuilder
    private var results: some View {
        let stops = Self.allStops.lazy
            .filter { $0.name.localizedStandardContains(trimmed) || $0.id.localizedStandardContains(trimmed) }
            .prefix(4)
        if !stops.isEmpty {
            Section("Stops") {
                ForEach(Array(stops), id: \.id) { stopButton($0) }
            }
        }
        if !places.isEmpty {
            Section("Places") {
                ForEach(places, id: \.self) { place in
                    Button { pick(.place(place)) } label: {
                        PlaceRow(title: place.name, subtitle: place.detail, icon: "mappin.circle.fill", tint: .red)
                    }
                }
            }
        }
    }

    private func stopButton(_ stop: BusStop) -> some View {
        let alias = favorites.getStopAlias(for: stop.id)
        return Button {
            pick(.place(Place(name: alias ?? stop.name, stopId: stop.id, location: stop.location)))
        } label: {
            HStack {
                PlaceRow(title: alias ?? stop.name,
                         subtitle: alias == nil ? nil : stop.name,
                         icon: "bus.fill",
                         tint: .accentColor)
                Spacer(minLength: 12)
                StopBadge(id: stop.id, scale: 0.8)
            }
        }
    }
}

private struct PlaceRow: View {
    let title: String
    var subtitle: String? = nil
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}
