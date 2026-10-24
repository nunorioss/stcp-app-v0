//
//  TripStop.swift
//  stcp-app
//
//  Created by Nuno Rios on 16/09/2026.
//

import Foundation
import SwiftData

@Model
nonisolated public final class TripStop {
    #Index<TripStop>([\.serviceTypeRaw, \.etaNumeric])

    @Relationship(inverse: \Trip.storedTripStops)
    public private(set) var trip: Trip
    
    @Relationship(inverse: \BusStop.tripStops)
    public private(set) var stop: BusStop
    
    public private(set) var sequenceNo: Int
    
    public private(set) var etaNumeric: Int
    
    // Denormalized from Trip for efficient indexed querying
    // when retrieving next scheduled arrivals
    var serviceTypeRaw: Int
    
    public init(trip: Trip,
                stop: BusStop,
                sequenceNo: Int,
                etaNumeric: Int) {
        self.trip = trip
        self.stop = stop
        self.sequenceNo = sequenceNo
        self.etaNumeric = etaNumeric
        self.serviceTypeRaw = trip.serviceType.rawValue
    }
    
    public convenience init(trip: Trip,
                            stop: BusStop,
                            sequenceNo: Int,
                            etaString: String) {
        // GTFS "HH:MM:SS" (hours may exceed 23 for post-midnight trips)
        let parts = etaString.split(separator: ":").compactMap { Int($0) }
        let seconds = parts.count == 3 ? parts[0] * 3600 + parts[1] * 60 + parts[2] : 0
        
        self.init(trip: trip,
                  stop: stop,
                  sequenceNo: sequenceNo,
                  etaNumeric: seconds)
    }
}
