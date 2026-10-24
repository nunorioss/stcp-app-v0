//
//  BusStop.swift
//  stcp-app
//
//  Created by Nuno Rios on 16/09/2026.
//

import Foundation
import SwiftData

@Model
nonisolated public final class BusStop: Identifiable {
    #Index<BusStop>([\.nameKey], [\.geohash5], [\.geohash6], [\.geohash7])
    
    @Attribute(.unique)
    public private(set) var id: String
    
    public private(set) var name: String
    
    // Case- and diacritic-insensitive name
    public private(set) var nameKey: String
    
    public private(set) var zone: String
    
    public private(set) var location: GeoPoint
    
    // Geohash at 3 precisions
    var geohash5: String
    var geohash6: String
    var geohash7: String
    
    @Relationship(deleteRule: .cascade)
    var routeStops: [RouteStop] = []
    
    public var routes: Set<Route> {
        Set(routeStops.map(\.route))
    }
    
    public var lines: Set<BusLine> {
        Set(routeStops.map(\.route.line))
    }
    
    @Relationship(deleteRule: .cascade)
    public internal(set) var tripStops: [TripStop] = []
    
    public init(id: String, name: String, zone: String, location: GeoPoint) {
        self.id = id
        self.name = name
        self.nameKey = BusStop.nameKey(for: name)
        self.zone = zone
        self.location = location
        
        let hash = Geohash.encode(latitude: location.latitude,
                                  longitude: location.longitude,
                                  precision: 7)
        self.geohash7 = hash
        self.geohash6 = String(hash.prefix(6))
        self.geohash5 = String(hash.prefix(5))
    }
    
    public static func nameKey(for name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
