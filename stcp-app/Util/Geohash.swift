//
//  Geohash.swift
//  stcp-app
//
//  Created by Nuno Rios on 07/06/2026.
//

import CoreLocation

enum Geohash {
    private static let base32 = Array("0123456789bcdefghjkmnpqrstuvwxyz")
    private static let base32Map: [Character: Int] = {
        Dictionary(uniqueKeysWithValues: base32.enumerated().map { ($1, $0) })
    }()

    static func encode(latitude: Double, longitude: Double, precision: Int) -> String {
        var minLat = -90.0,  maxLat = 90.0
        var minLon = -180.0, maxLon = 180.0
        var isLon = true
        var bits = 0, bitCount = 0
        var hash = ""

        while hash.count < precision {
            if isLon {
                let mid = (minLon + maxLon) / 2
                
                if longitude >= mid {
                    bits = (bits << 1) | 1
                    minLon = mid
                }
                else {
                    bits = bits << 1
                    maxLon = mid
                }
            } else {
                let mid = (minLat + maxLat) / 2
                
                if latitude >= mid {
                    bits = (bits << 1) | 1
                    minLat = mid
                }
                else {
                    bits = bits << 1
                    maxLat = mid
                }
            }
            
            isLon.toggle()
            bitCount += 1
            
            if bitCount == 5 {
                hash.append(base32[bits])
                bits = 0; bitCount = 0
            }
        }
        return hash
    }

    private static func bounds(of hash: String) -> (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) {
        var minLat = -90.0,  maxLat = 90.0
        var minLon = -180.0, maxLon = 180.0
        var isLon = true

        for char in hash {
            guard let val = base32Map[char] else {
                continue
            }
            
            for i in stride(from: 4, through: 0, by: -1) {
                let bit = (val >> i) & 1
                
                if isLon {
                    let mid = (minLon + maxLon) / 2
                    
                    if bit == 1 {
                        minLon = mid
                    } else {
                        maxLon = mid
                    }
                } else {
                    let mid = (minLat + maxLat) / 2
                    
                    if bit == 1 {
                        minLat = mid
                    } else {
                        maxLat = mid
                    }
                }
                isLon.toggle()
            }
        }
        return (minLat, maxLat, minLon, maxLon)
    }

    static func neighbors(of hash: String) -> [String] {
        let b = bounds(of: hash)
        let centerLat = (b.minLat + b.maxLat) / 2
        let centerLon = (b.minLon + b.maxLon) / 2
        
        let precision = hash.count
        let latStep = b.maxLat - b.minLat
        let lonStep = b.maxLon - b.minLon
        
        let epsilon = 0.1
        
        let n = encode(latitude: b.maxLat + latStep * epsilon, longitude: centerLon, precision: precision)
        let s = encode(latitude: b.minLat - latStep * epsilon, longitude: centerLon, precision: precision)
        
        let e = encode(latitude: centerLat, longitude: b.maxLon + lonStep * epsilon, precision: precision)
        let w = encode(latitude: centerLat, longitude: b.minLon - lonStep * epsilon, precision: precision)
        
        let ne = encode(latitude: b.maxLat + latStep * epsilon, longitude: b.maxLon + lonStep * epsilon, precision: precision)
        let nw = encode(latitude: b.maxLat + latStep * epsilon, longitude: b.minLon - lonStep * epsilon, precision: precision)
        
        let se = encode(latitude: b.minLat - latStep * epsilon, longitude: b.maxLon + lonStep * epsilon, precision: precision)
        let sw = encode(latitude: b.minLat - latStep * epsilon, longitude: b.minLon - lonStep * epsilon, precision: precision)

        return [nw, n, ne, w, e, sw, s, se]
    }

    /// Returns center + 8 neighbor hashes for a coordinate at a given precision.
    static func searchHashes(for coordinate: CLLocationCoordinate2D, precision: Int) -> [String] {
        let center = encode(latitude: coordinate.latitude, longitude: coordinate.longitude, precision: precision)
        return [center] + neighbors(of: center)
    }

    /// Picks the best precision for a given radius.
    static func precision(for radius: CLLocationDistance) -> Int {
        switch radius {
        case ..<400:    return 7  // ~153m × 76m cells
        case ..<2500:   return 6  // ~1.2km × 0.6km cells
        default:        return 5  // ~4.9km × 4.9km cells
        }
    }
}
