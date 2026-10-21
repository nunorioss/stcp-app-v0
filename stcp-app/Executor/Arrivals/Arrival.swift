//
//  Arrival.swift
//  stcp-app
//
//  Created by Nuno Rios on 09/10/2026.
//

import Foundation
import SwiftData

public nonisolated enum LiveSource: Sendable {
    case portoDigital, stcp
}

public nonisolated struct Arrival: Sendable, Identifiable {
    public var id: String {
        tripId
    }
    
    public let tripId: String
    public let lineId: String
    
    // For grouping/sorting
    public let routeId: PersistentIdentifier
    public let routeSortIndex: Int
    
    public let scheduledEta: Date
    
    public nonisolated struct Live: Sendable {
        let eta: Date
        let busId: String?
        let source: LiveSource
        let inferred: Bool
        
        init(eta: Date, busId: String?,
             source: LiveSource = .portoDigital,
             inferred: Bool = false) {
            self.busId = busId
            self.eta = eta
            self.source = source
            self.inferred = inferred
        }
    }
    
    public let live: Live?
    
    public var isLive: Bool {
        live != nil
    }
    
    // Live ETA is prioritized
    public var eta: Date {
        live?.eta ?? scheduledEta
    }
    
    public var minutesTilArrival: Int {
        max(Int((eta.timeIntervalSinceNow / 60).rounded(.down)), 0)
    }
    
    // 0 if not live
    public var delay: TimeInterval {
        eta.timeIntervalSince(scheduledEta)
    }
    
    //MARK: utilities
    
    /// Same arrival with different live data.
    func with(live: Live?) -> Arrival {
        Arrival(tripId: tripId,
                lineId: lineId,
                routeId: routeId,
                routeSortIndex: routeSortIndex,
                scheduledEta: scheduledEta,
                live: live)
    }
    
    // far if it doesn't arrive within 2h
    public var isFar: Bool {
        minutesTilArrival > 2 * 60
    }
    
    public var isToday: Bool {
        DateUtil.portoCalendar.isDateInToday(eta)
    }
}
