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
    
    @State private var searchText = ""      // current search field
    @State private var results: [BusStop] = []
    @State private var resultsQuery = ""    // the query "results" was computed for
    @State private var matchCount = 0       // total matches, excluding cap

    // Max. results for a single letter query
    private static let oneLetterCap = 100

    //Stops sorted by ID
    private static let allStops: [BusStop] = DataStore.getBusStops().sorted { a, b in
        return a.id.localizedStandardCompare(b.id) == .orderedAscending
    }

    private static let warmUp: Void = {
        _ = DataStore.getLines(servingStop: "")
        _ = allStops
    }()
    
    private static func search(_ query: String) -> [BusStop] {
        guard !query.isEmpty else {
            return []
        }
        
        let key = BusStop.nameKey(for: query)
        let id = query.uppercased()
        
        let matches = allStops.filter {
            $0.id.contains(id) || $0.nameKey.contains(key)
        }
        
        let startsWith: (BusStop) -> Bool = {
            $0.id.hasPrefix(id) || $0.nameKey.hasPrefix(key) || $0.nameKey.contains(" " + key)
        }
        return matches.filter(startsWith) + matches.filter { !startsWith($0) }
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
          
        List {
            Section {
                SearchField(text: $searchText, prompt: "Search stops")
            }

            if isSearching {
                if resultsQuery == query, results.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .listRowBackground(Color.clear)
                }

                ForEach(results, id: \.id) { StopRow(stop: $0, showLineBadges: true) }

                if matchCount > results.count {
                    Text("Only the first \(results.count) results are shown.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

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
                
                if favoriteStops.isEmpty && nearbyStops.isEmpty {
                    // Suggest user to search
                    Section {
                        ContentUnavailableView(
                            "Search for a bus stop",
                            systemImage: "magnifyingglass",
                            description: Text("Find any STCP bus stop\nby its name or code.")
                        )
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }
            }
        }
        .navigationDestination(for: BusStop.self) {
            StopView(stop: $0)
        }
        // once the screen is up
        .task {
            try? await Task.sleep(for: .milliseconds(100))
            Self.warmUp
        }
        .onChange(of: query) { _, query in
            let matches = Self.search(query)
            
            // cap 1 letter query results
            results = query.count == 1 ? Array(matches.prefix(Self.oneLetterCap)) : matches
            
            matchCount = matches.count
            resultsQuery = query
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
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle("Stops")
    }
}

#Preview {
    NavigationStack {
        StopList()
    }
}
