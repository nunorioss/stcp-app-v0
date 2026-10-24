//
//  FavoritePlacesStore.swift
//  stcp-app
//
//  Created by Nuno Rios on 22/10/2026.
//

import Foundation
import Combine

/// A saved spot to travel from or to: a coordinate, its name, and an optional alias.
nonisolated struct FavoritePlace: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    let name: String
    var alias: String?
    let location: GeoPoint

    var displayName: String { alias ?? name }
}

// persisted in UserDefaults, as JSON; kept apart from favorite stops and lines
final class FavoritePlacesStore: ObservableObject {

    static let shared = FavoritePlacesStore()

    private let defaults: UserDefaults
    private static let placesKey = "favoritePlaces"

    /// Places closer than this count as the same one.
    private static let sameSpot = 15.0

    @Published private(set) var places: [FavoritePlace] {
        didSet { defaults.set(try? JSONEncoder().encode(places), forKey: Self.placesKey) }
    }

    private convenience init() {
        self.init(defaults: .standard)
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        places = defaults.data(forKey: Self.placesKey)
            .flatMap { try? JSONDecoder().decode([FavoritePlace].self, from: $0) } ?? []
    }

    private func index(at location: GeoPoint) -> Int? {
        places.firstIndex { Timetable.meters($0.location, location) < Self.sameSpot }
    }

    func isFavorite(at location: GeoPoint) -> Bool {
        index(at: location) != nil
    }

    /// Adds the place, or removes it if one is already saved at that spot.
    func toggleFavorite(name: String, location: GeoPoint) {
        if let i = index(at: location) {
            places.remove(at: i)
        } else {
            places.append(FavoritePlace(name: name, location: location))
        }
    }

    func remove(_ id: FavoritePlace.ID) {
        places.removeAll { $0.id == id }
    }

    /// Sets the alias for a place; an empty or nil alias removes it.
    func setAlias(_ alias: String?, for id: FavoritePlace.ID) {
        guard let i = places.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = alias?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        places[i].alias = trimmed.isEmpty ? nil : String(trimmed.prefix(FavoritesStore.maxAliasLength))
    }
}
