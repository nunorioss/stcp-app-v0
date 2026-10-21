//
//  GeoPoint.swift
//  stcp-app
//
//  Created by Nuno Rios on 16/09/2026.
//

import CoreLocation

nonisolated public struct GeoPoint: Codable, Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double
    
    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    var clLocation: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
    
    func distance(to other: GeoPoint) -> CLLocationDistance {
        clLocation.distance(from: other.clLocation)
    }
    
    func distance(to coordinate: CLLocationCoordinate2D) -> CLLocationDistance {
        clLocation.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
    }
}
