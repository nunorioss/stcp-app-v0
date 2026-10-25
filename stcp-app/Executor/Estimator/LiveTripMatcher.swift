//
//  LiveTripMatcher.swift
//  stcp-app
//
//  Created by Nuno Rios on 13/10/2026.
//

enum LiveTripMatcher {
    // how far outside its scheduled window a bus may be
    // and still count as running that trip
    static let maxEarly = 20 * 60 //20min
    static let maxLate = 50 * 60 //50min

    // a stale trip id is at most this many
    // trips behind the real one
    static let maxHops = 2
    
    // just a guard against bad data / cycles
    static let maxSuccessorChainSteps = 10

    static func matchLiveTrip(_ reportedTripId: String,
                              _ nowSeconds: Int = DateUtil.secondsSinceMidnight()) -> Trip? {
        guard let reported = DataStore.getLiveTrip(id: reportedTripId) else {
            return nil
        }
        
        // plausible as reported: no need to rematch
        if isPlausible(reported, nowSeconds: nowSeconds) {
            return reported
        }
        
        var current = reported
        for _ in 0..<maxHops {
            guard let next = successor(of: current) else {
                break
            }
            if isPlausible(next, nowSeconds: nowSeconds) {
                return next
            }
            current = next
        }
        
        // no confidence match:
        // keep what the stale feed gave us
        return reported
    }
    
    private static func isPlausible(_ trip: Trip, nowSeconds: Int) -> Bool {
        let d = deviation(of: trip, nowSeconds: nowSeconds)
        return d >= -maxEarly && d <= maxLate
    }

    private static func deviation(of trip: Trip, nowSeconds: Int) -> Int {
        func offset(_ now: Int) -> Int {
            if now < trip.firstEtaNumeric {
                return now - trip.firstEtaNumeric
            }
            if now > trip.lastEtaNumeric  {
                return now - trip.lastEtaNumeric
            }
            return 0
        }
        
        // etaNumeric can exceed 24h for trips running past midnight,
        // so also try "now" on the previous service day's clock
        let today = offset(nowSeconds)
        let overnight = offset(nowSeconds + DateUtil.secondsPerDay)
        
        return abs(today) <= abs(overnight) ? today : overnight
    }
    
    private static func successor(of trip: Trip) -> Trip? {
        let lineId = trip.route.line.id
        let direction = trip.route.direction

        var current = trip
        for _ in 0..<maxSuccessorChainSteps {
            guard let nextId = current.nextTripId,
                  let next = DataStore.getTrip(id: nextId) else {
                // end of block
                return nil
            }
            if next.route.direction == direction, next.route.line.id == lineId {
                return next
            }
            current = next
        }
        return nil
    }
}
