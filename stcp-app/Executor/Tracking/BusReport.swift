//
//  BusReport.swift
//  stcp-app
//
//  Created by Nuno Rios on 25/10/2026.
//

import Foundation

nonisolated struct BusReport: Sendable, Identifiable, Equatable {
    let reportedTripId: String
    var id: String {
        reportedTripId
    }
    
    let latitude: Double
    let longitude: Double
    
    let lineId: String
    let direction: Bool
    
    let bearing: Double
    
    // Instant at which data was captured
    let timestamp: Date
}

extension Bus {
    @MainActor
    init(report: BusReport) {
        let location = GeoPoint(latitude: report.latitude,
                                longitude: report.longitude)

        // try to match trip and infer trip progress
        let trip = LiveTripMatcher.matchLiveTrip(report.reportedTripId)
        let tripProgress = trip.flatMap {
            RouteUtil.tripProgress(busLocation: location, along: $0.route.stops)
        }

        self.init(
            reportedTripId: report.reportedTripId,
            location: location,
            lineId: report.lineId,
            direction: report.direction,
            bearing: report.bearing,
            timestamp: report.timestamp,
            trip: trip,
            tripProgress: tripProgress
        )
    }
}
