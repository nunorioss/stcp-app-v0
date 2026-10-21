//
//  RouteGeometry.swift
//  stcp-app
//
//  Created by Nuno Rios on 15/10/2026.
//

import Foundation

public struct TripProgress {
    let lastStopIndex: Int
    // 0..1 from lastStop -> nextStop
    let progress: Double
}

public struct RouteGeometry {
    private static let metersPerLat = 111_320.0

    private let originLat: Double
    private let originLon: Double
    private let metersPerLon: Double

    // Stop i in local meters
    // segment i = stop i -> stop i+1
    private let x: ContiguousArray<Double>
    private let y: ContiguousArray<Double>
    private let dx: ContiguousArray<Double>
    private let dy: ContiguousArray<Double>
    
    // 0 for degenerate segments
    private let invLen2: ContiguousArray<Double>

    var segmentCount: Int {
        dx.count
    }

    init?(coords: [GeoPoint]) {
        guard coords.count > 1 else {
            return nil
        }

        let lat0 = coords[0].latitude, lon0 = coords[0].longitude
        let mLon = Self.metersPerLat * cos(lat0 * .pi / 180)

        let xs = coords.map { ($0.longitude - lon0) * mLon }
        let ys = coords.map { ($0.latitude - lat0) * Self.metersPerLat }

        let n = coords.count - 1
        
        let dxs = (0..<n).map { xs[$0 + 1] - xs[$0] }
        let dys = (0..<n).map { ys[$0 + 1] - ys[$0] }
        
        let inv = (0..<n).map { i -> Double in
            let l2 = dxs[i] * dxs[i] + dys[i] * dys[i]
            return l2 == 0 ? 0 : 1 / l2
        }

        originLat = lat0
        originLon = lon0
        metersPerLon = mLon
        x = ContiguousArray(xs)
        y = ContiguousArray(ys)
        dx = ContiguousArray(dxs)
        dy = ContiguousArray(dys)
        invLen2 = ContiguousArray(inv)
    }

    func progress(of p: GeoPoint, hint: Int? = nil,
                  maxDistance: Double = 250) -> TripProgress? {
        let px = (p.longitude - originLon) * metersPerLon
        let py = (p.latitude - originLat) * Self.metersPerLat

        var bestI = -1, bestT = 0.0, bestD2 = Double.infinity

        @inline(__always) func test(_ i: Int) {
            let apx = px - x[i], apy = py - y[i]
            let t = min(max((apx * dx[i] + apy * dy[i]) * invLen2[i], 0), 1)
            let ex = apx - t * dx[i], ey = apy - t * dy[i]
            let d2 = ex * ex + ey * ey
            
            if d2 < bestD2 {
                bestD2 = d2
                bestI = i
                bestT = t
            }
        }

        // the bus was last seen near segment `hint`,
        //so looks only nearby
        if let hint {
            let lo = max(hint - 1, 0), hi = min(hint + 3, segmentCount - 1)
            if lo <= hi { for i in lo...hi { test(i) } }
            
            // not convincing, rescan
            if bestD2 > 100 * 100 {
                bestI = -1
                bestD2 = .infinity
            }
        }
        if bestI < 0 { for i in 0..<segmentCount { test(i) } }

        guard bestI >= 0, bestD2 <= maxDistance * maxDistance else {
            return nil
        }
        return TripProgress(lastStopIndex: bestI, progress: bestT)
    }
    
    /// Computes the progress of a Bus along a route, returning its last stop
    /// and progress % towards the next one.
    /// Pass previous `lastStopIndex` as a `hint` for a more optimized computation.
    static func progress(busLocation: GeoPoint,
                         along route: Route,
                         hint: Int? = nil) -> TripProgress? {
        route.geometry?.progress(of: busLocation, hint: hint)
    }
}
