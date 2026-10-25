//
//  FavoritesStore.swift
//  stcp-app
//
//  Created by Nuno Rios on 21/08/2026.
//

import Foundation
import Combine

// persisted in UserDefaults
final class FavoritesStore: ObservableObject {

    static let shared = FavoritesStore()
    
    private let defaults: UserDefaults
    
    static let maxAliasLength = 30
    
    private static let stopsKey = "favoriteStopIds"
    private static let linesKey = "favoriteLineIds"
    private static let aliasesKey = "stopAliases"
    
    // IDs in the order of "shown"
    //any not shown (gone from the data) stay at the end
    private static func reordered(_ ids: [String], as shown: [String]) -> [String] {
        let shownSet = Set(shown)
        return shown.filter(ids.contains) + ids.filter { !shownSet.contains($0) }
    }

    @Published private(set) var stopIds: [String] {
        didSet { defaults.set(stopIds, forKey: Self.stopsKey) }
    }

    @Published private(set) var lineIds: [String] {
        didSet { defaults.set(lineIds, forKey: Self.linesKey) }
    }

    // stop id -> stop alias
    @Published private(set) var aliases: [String: String] {
        didSet { defaults.set(aliases, forKey: Self.aliasesKey) }
    }

    private convenience init() {
        self.init(defaults: .standard)
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults

        stopIds = defaults.stringArray(forKey: Self.stopsKey) ?? []
        lineIds = defaults.stringArray(forKey: Self.linesKey) ?? []
        aliases = defaults.dictionary(forKey: Self.aliasesKey) as? [String: String] ?? [:]
    }
    
    var getFavoriteStops: [BusStop] {
        stopIds.compactMap { DataStore.getBusStop(id: $0) }
    }

    func isFavorite(stop stopId: String) -> Bool {
        stopIds.contains(stopId)
    }
    
    func toggleFavorite(stop stopId: String) {
        if let index = stopIds.firstIndex(of: stopId) {
            stopIds.remove(at: index)
            aliases[stopId] = nil
        } else {
            stopIds.append(stopId)
        }
    }

    func reorderStops(_ ids: [String]) {
        stopIds = Self.reordered(stopIds, as: ids)
    }

    var getFavoriteLines: [BusLine] {
        lineIds.compactMap { DataStore.getBusLine(id: $0) }
    }

    func isFavorite(line lineId: String) -> Bool {
        lineIds.contains(lineId)
    }

    func toggleFavorite(line lineId: String) {
        if let index = lineIds.firstIndex(of: lineId) {
            lineIds.remove(at: index)
        } else {
            lineIds.append(lineId)
        }
    }

    func reorderLines(_ ids: [String]) {
        lineIds = Self.reordered(lineIds, as: ids)
    }

    /// Gets the user's set alias for a bus stop.
    func getStopAlias(for stopId: String) -> String? {
        aliases[stopId]
    }

    /// Sets the alias for a bus stop; an empty or nil alias removes it.
    func setAlias(_ alias: String?, for stopId: String) {
        // aliases are only for favorited stops
        guard isFavorite(stop: stopId) else {
            return
        }
        
        guard let trimmed = alias?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            aliases[stopId] = nil
            return
        }

        aliases[stopId] = String(trimmed.prefix(Self.maxAliasLength))
    }
}
