//
//  StopList.swift
//  stcp-app
//
//  Created by Nuno Rios on 19/09/2026.
//

import SwiftUI
import CoreLocation

struct StopList: View {
    @ObservedObject private var favorites = FavoritesStore.shared
    private let locationProvider = LocationProvider.shared
    
    @State private var nearbyStops: [BusStop] = []
    @State private var lastQueryLocation: CLLocation?
    @State private var isNearbyCollapsed: Bool = false
    
    private static let maxNearbyResults = 7
    private static let nearbyRadius: CLLocationDistance = 1000  // meters
    private static let minMoveDistance: CLLocationDistance = 5  // meters
    
    @State private var searchText = ""

    private static let allStops: [BusStop] = DataStore.getBusStops().sorted { a, b in
        return a.id.localizedStandardCompare(b.id) == .orderedAscending
    }
    
    private func filtered(_ stops: [BusStop], by query: String) -> [BusStop] {
        guard !query.isEmpty else {
            return stops
        }
 
        // Matches ID or name
        return stops.filter {
            $0.id.localizedStandardContains(query)
            || $0.name.localizedStandardContains(query)
        }
    }
    
    private func refreshNearby() {
        // nothing to compute while collapsed or without a location
        guard !isNearbyCollapsed, let location = locationProvider.location else {
            return
        }

        // skip if we haven't moved far enough
        if let last = lastQueryLocation,
            location.distance(from: last) < Self.minMoveDistance {
            return
        }
        lastQueryLocation = location
        
        let stops = Array(
            DataStore.getNearbyStops(to: location.coordinate,
                                     radius: Self.nearbyRadius,
                                     sortByDistance: true)
                .prefix(Self.maxNearbyResults)
        )

        // only touch state if list actually changed
        if stops.map(\.id) != nearbyStops.map(\.id) {
            nearbyStops = stops
        }
    }
    
    var body: some View {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let isSearching = !query.isEmpty

        // only compute while searching
        let results = isSearching ? filtered(Self.allStops, by: query) : []
          
        List {
            if isSearching {
                ForEach(results, id: \.id) { StopRow(stop: $0, showLineBadges: true) }

            } else {
                let favoriteStops = favorites.getFavoriteStops
                
                if !favoriteStops.isEmpty {
                    CollapsibleSection("Favorites", storageKey: "stops.favorites") {
                        ReorderableForEach(favoriteStops, id: \.id,
                                           onReorder: { favorites.reorderStops($0.map(\.id)) }) {
                            StopRow(stop: $0, showAlias: true)
                        }
                    }
                }
                
                if !nearbyStops.isEmpty || (isNearbyCollapsed && locationProvider.location != nil) {
                    CollapsibleSection("Nearby",
                                       storageKey: "stops.nearby",
                                       onCollapsedChange: { isNearbyCollapsed = $0 }) {
                        ForEach(nearbyStops, id: \.id) { StopRow(stop: $0, showLineBadges: true) }
                    }
                }
                
                // Suggest user to search
                Section {
                    ContentUnavailableView(
                        "Search for a bus stop",
                        systemImage: "magnifyingglass",
                        description: Text("Swipe down to search\n for any STCP bus stop")
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
        }
        .navigationDestination(for: BusStop.self) {
            StopView(stop: $0)
        }
        .overlay {
            if isSearching, results.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
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
        .onChange(of: locationProvider.location, initial: true) { _, _ in
            refreshNearby()
        }
        .onChange(of: isNearbyCollapsed) { _, collapsed in
            // compute when the user expands it
            if !collapsed { refreshNearby() }
        }
        .searchable(text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: "Search stops")
        .autocorrectionDisabled()
        .navigationTitle("Stops")
    }
}

#Preview {
    NavigationStack {
        StopList()
    }
}

