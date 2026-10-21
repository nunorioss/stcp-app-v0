//
//  Trip.swift
//  stcp-app
//
//  Created by Nuno Rios on 16/09/2026.
//

import SwiftData

@Model
public final class Trip {
    
    @Attribute(.unique)
    public private(set) var id: String
    
    @Relationship(inverse: \Route.trips)
    public internal(set) var route: Route
    
    public private(set) var serviceType: ServiceType
    
    //TODO: Likely unused since we already have next/prevTripId
    // a "shift"/"turno", using the same physical bus
    public internal(set) var blockId: String
    
    // the sequence number within the shift/block
    // N in the tripID (11 for ..|..|..|T2|N11)
    public internal(set) var sequence: Int
    
    //TODO: Consider making it Trip instead of trip id
    public internal(set) var nextTripId: String?
    public internal(set) var previousTripId: String?
    
    // etaNumeric for first and last TripStops
    public internal(set) var firstEtaNumeric: Int = 0
    public internal(set) var lastEtaNumeric: Int = 0
    
    @Relationship(deleteRule: .cascade)
    var storedTripStops: [TripStop] = []
    
    // ordered by TripStop.sequenceNo
    public var tripStops: [TripStop] {
        storedTripStops.sorted { $0.sequenceNo < $1.sequenceNo }
    }
    
    public init(id: String, route: Route, serviceType: ServiceType,
                blockId: String, sequence: Int) {
        self.id = id
        self.route = route
        self.serviceType = serviceType
        self.blockId = blockId
        self.sequence = sequence
    }
    
    // "Now" (seconds since midnight) on this trip's service-day clock.
    func serviceClock(at nowSeconds: Int) -> Int {
        lastEtaNumeric - DateUtil.secondsPerDay >= nowSeconds
        ? nowSeconds + DateUtil.secondsPerDay : nowSeconds
    }
    
    //TODO: Move out of Trip?
    // Clock for a trip a bus is running right now. Picks today or yesterday's
    // service day, whichever makes the bus's position closest to its timetable.
    func liveClock(at nowSeconds: Int, scheduledAt etaLast: Int) -> Int {
        let day = DateUtil.secondsPerDay
        return abs(etaLast - nowSeconds) <= abs(etaLast - (nowSeconds + day))
            ? nowSeconds : nowSeconds + day
    }
    
    // etaNumeric for each one of the given stops
    func etas<S: Sequence>(for stopIds: S) -> [String: Int] where S.Element == String {
        var remaining = Set(stopIds)
        
        var result: [String: Int] = [:]
        result.reserveCapacity(remaining.count)

        for ts in storedTripStops {
            let id = ts.stop.id
            guard remaining.remove(id) != nil else {
                continue
            }
            result[id] = ts.etaNumeric
            
            // found everything, stop early
            if remaining.isEmpty {
                break
            }
        }
        return result
    }
}
