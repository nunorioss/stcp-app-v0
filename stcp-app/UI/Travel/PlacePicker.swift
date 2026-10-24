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
    static let porto = CLLocationCoordinate2D(latitude: 41.1579, longitude: -8.6291)

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
    @ObservedObject private var favoritePlaces = FavoritePlacesStore.shared
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
                try? await Task.sleep(for: .milliseconds(75))
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
            NavigationLink {
                MapPointPicker(name: pinName) { location in
                    pick(.place(Place(name: pinName(location), location: location)))
                }
            } label: {
                PlaceRow(title: "Choose on Map", icon: "map.circle.fill", tint: .green)
            }
        }
        if !favoritePlaces.places.isEmpty {
            Section("Favorite Places") {
                ForEach(favoritePlaces.places) { place in
                    FavoritePlaceRow(place: place) {
                        pick(.place(Place(name: place.displayName, location: place.location)))
                    }
                }
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
                    let isFavorite = favoritePlaces.isFavorite(at: place.location)
                    Button { pick(.place(place)) } label: {
                        PlaceRow(title: place.name,
                                 subtitle: [place.kind, area(of: place)].compactMap { $0 }.joined(separator: " · "),
                                 caption: place.detail,
                                 icon: isFavorite ? "star.circle.fill" : "mappin.circle.fill",
                                 tint: isFavorite ? .yellow : .red)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            withAnimation { favoritePlaces.toggleFavorite(name: place.name, location: place.location) }
                        } label: {
                            Label(isFavorite ? "Unfavorite" : "Favorite",
                                  systemImage: isFavorite ? "star.slash.fill" : "star.fill")
                        }
                        .tint(isFavorite ? .gray : .yellow)
                    }
                }
            }
        }
    }

    /// MapKit's areas are whole parish unions, so the closest stop's name ("São Bento",
    /// "Bolhão"...) says better which one of several places with the same name this is.
    private func area(of place: Place) -> String? {
        nearestStop(to: place.location).map { "near \($0.name)" }
    }

    /// A map pin is named after its closest stop.
    private func pinName(_ location: GeoPoint) -> String {
        nearestStop(to: location).map { "Pin near \($0.name)" } ?? "Dropped Pin"
    }

    private func nearestStop(to location: GeoPoint) -> BusStop? {
        Self.allStops.min { Timetable.meters($0.location, location) < Timetable.meters($1.location, location) }
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
    var caption: String? = nil
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
                if let caption {
                    Text(caption)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
    }
}
