//
//  BusLine.swift
//  stcp-app
//
//  Created by Nuno Rios on 16/09/2026.
//

import SwiftData
import SwiftUI

@Model
nonisolated public final class BusLine: Identifiable {
    
    @Attribute(.unique)
    public private(set) var id: String
    
    // same as ID for most lines
    public private(set) var shortName: String
    
    public private(set) var longName: String
    
    private var backgroundRGB: Int
    private var foregroundRGB: Int
    
    @MainActor public var backgroundColor: Color { Color(backgroundRGB) }
    @MainActor public var foregroundColor: Color { Color(foregroundRGB) }
    
    public internal(set) var isAccessible: Bool?
    
    @Relationship(deleteRule: .cascade)
    var storedRoutes: [Route] = []
    
    public var routes: [Route] {
        storedRoutes.sorted { $0.sortIndex < $1.sortIndex }
    }
    
    // STCP provides 2 shapes per line, 1 per direction
    var shape0: [GeoPoint] = []
    var shape1: [GeoPoint] = []
    
    public func shape(_ direction: Bool) -> [GeoPoint] {
        direction ? shape1 : shape0
    }
    
    // Compass direction from first to last stop of
    // the master route, one per direction
    public internal(set) var heading0: CompassDirection?
    public internal(set) var heading1: CompassDirection?

    public func heading(_ direction: Bool) -> CompassDirection? {
        direction ? heading1 : heading0
    }
    
    // IDs of lines whose buses run into each other, i.e.,
    // the same block (physical bus) alternates between them;
    public internal(set) var sisterLineIds: [String] = []
    
    public init(id: String,
                shortName: String,
                longName: String,
                backgroundRGB: Int,
                foregroundRGB: Int,
                isAccessible: Bool? = nil) {
        self.id = id
        self.shortName = shortName
        self.longName = longName
        self.backgroundRGB = backgroundRGB
        self.foregroundRGB = foregroundRGB
        self.isAccessible = isAccessible
    }
}
