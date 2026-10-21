//
//  CompassDirection.swift
//  stcp-app
//
//  Created by Nuno Rios on 02/10/2026.
//

public enum CompassDirection: Int, Codable, CaseIterable, Sendable {
    case north,
         northEast,
         east,
         southEast,
         south,
         southWest,
         west,
         northWest

    public var arrow: String {
        switch self {
        case .north:        "↑"
        case .northEast:    "↗"
        case .east:         "→"
        case .southEast:    "↘"
        case .south:        "↓"
        case .southWest:    "↙"
        case .west:         "←"
        case .northWest:    "↖"
        }
    }

    public var degrees: Double { Double(rawValue) * 45 }

    /// `bearing` in degrees, 0 = north, clockwise.
    public init(bearing: Double) {
        let normalized = bearing.truncatingRemainder(dividingBy: 360)
        let positive = normalized < 0 ? normalized + 360 : normalized
        
        // each direction owns a 45° sector centered on its heading
        let sector = Int(((positive + 22.5) / 45).rounded(.down)) % 8
        
        self = CompassDirection(rawValue: sector)!
    }
}
