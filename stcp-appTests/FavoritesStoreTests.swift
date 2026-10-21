//
//  FavoritesStoreTests.swift
//  stcp-appTests
//
//  Created by Nuno Rios on 21/08/2026.
//

import Testing
import Foundation
@testable import stcp_app

struct FavoritesStoreTests {

    private func makeStore() -> FavoritesStore {
        let defaults = UserDefaults(suiteName: "FavoritesStoreTests_\(UUID().uuidString)")!
        return FavoritesStore(defaults: defaults)
    }

    @Test func testStopFavorite_toggleOn() {
        let store = makeStore()
        #expect(store.isFavorite(stop: "stop1") == false)
        store.toggleFavorite(stop: "stop1")
        #expect(store.isFavorite(stop: "stop1") == true)
        #expect(store.stopIds == ["stop1"])
    }

    @Test func testStopFavorite_toggleOff() {
        let store = makeStore()
        store.toggleFavorite(stop: "stop1")
        store.toggleFavorite(stop: "stop1")
        #expect(store.isFavorite(stop: "stop1") == false)
        #expect(store.stopIds.isEmpty)
    }

    @Test func testStopFavorite_multiple() {
        let store = makeStore()
        store.toggleFavorite(stop: "A")
        store.toggleFavorite(stop: "B")
        store.toggleFavorite(stop: "C")
        #expect(store.stopIds == ["A", "B", "C"])
        store.toggleFavorite(stop: "B")
        #expect(store.stopIds == ["A", "C"])
    }

    @Test func testLineFavorite_toggleOn() {
        let store = makeStore()
        #expect(store.isFavorite(line: "line1") == false)
        store.toggleFavorite(line: "line1")
        #expect(store.isFavorite(line: "line1") == true)
        #expect(store.lineIds == ["line1"])
    }

    @Test func testLineFavorite_toggleOff() {
        let store = makeStore()
        store.toggleFavorite(line: "line1")
        store.toggleFavorite(line: "line1")
        #expect(store.isFavorite(line: "line1") == false)
        #expect(store.lineIds.isEmpty)
    }

    @Test func testSetAlias() {
        let store = makeStore()
        store.setAlias("Home", for: "stop1")
        #expect(store.getStopAlias(for: "stop1") == "Home")
    }

    @Test func testSetAlias_replaces() {
        let store = makeStore()
        store.setAlias("Home", for: "stop1")
        store.setAlias("Gym", for: "stop1")
        #expect(store.getStopAlias(for: "stop1") == "Gym")
    }

    @Test func testSetAlias_emptyString_removes() {
        let store = makeStore()
        store.setAlias("Home", for: "stop1")
        store.setAlias("", for: "stop1")
        #expect(store.getStopAlias(for: "stop1") == nil)
    }

    @Test func testSetAlias_whitespace_removes() {
        let store = makeStore()
        store.setAlias("Home", for: "stop1")
        store.setAlias("   ", for: "stop1")
        #expect(store.getStopAlias(for: "stop1") == nil)
    }

    @Test func testSetAlias_nil_removes() {
        let store = makeStore()
        store.setAlias("Home", for: "stop1")
        store.setAlias(nil, for: "stop1")
        #expect(store.getStopAlias(for: "stop1") == nil)
    }

    @Test func testSetAlias_trimsWhitespace() {
        let store = makeStore()
        store.setAlias("  Home  ", for: "stop1")
        #expect(store.getStopAlias(for: "stop1") == "Home")
    }

    @Test func testGetAlias_unknownStop_returnsNil() {
        let store = makeStore()
        #expect(store.getStopAlias(for: "nonexistent") == nil)
    }

    @Test func testPersistence() {
        let suiteName = "FavoritesStoreTests_Persistence_\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        let store1 = FavoritesStore(defaults: defaults)
        store1.toggleFavorite(stop: "stop1")
        store1.toggleFavorite(line: "line1")
        store1.setAlias("Home", for: "stop1")

        // A new instance with same suite should load persisted data
        let store2 = FavoritesStore(defaults: defaults)
        #expect(store2.isFavorite(stop: "stop1") == true)
        #expect(store2.isFavorite(line: "line1") == true)
        #expect(store2.getStopAlias(for: "stop1") == "Home")
    }
}
