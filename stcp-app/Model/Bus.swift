//
//  Bus.swift
//  stcp-app
//
//  Created by Nuno Rios on 15/09/2026.
//


import Foundation
 
public struct Bus: Identifiable {
 
    public let id: String
 
    public let location: GeoPoint
 
    public let lineId: String
 
    public let direction: Bool
 
    //TODO: mostly nil, should probably remove it
    public let shift: Int?
 
    public let reportedTripId: String
 
    public let tripCount: Int
 
    public let speed: Float
 
    // Direction of travel, where 0/360º is North,
    // 90º is East, 180º is South and 270º is West
    public let bearing: Double
 
    // Instant at which data was captured
    public let timestamp: Date
 
    public let trip: Trip?
 
    public let tripProgress: TripProgress?
 
    public var line: BusLine {
        guard let line = DataStore.getBusLine(id: lineId) else {
            preconditionFailure("Live bus \(id) is on line \(lineId), which is not registered")
        }
        return line
    }
}
 
extension Bus {
    /// Builds a Bus from a raw report: matches its trip and infers its progress along it.
    @MainActor
    init(report: BusReport) {
        let location = GeoPoint(latitude: report.latitude, longitude: report.longitude)
 
        // try to match trip and infer trip progress
        let trip = LiveTripMatcher.matchLiveTrip(report.reportedTripId)
        let tripProgress = trip.flatMap {
            RouteUtil.tripProgress(busLocation: location, along: $0.route.stops)
        }
 
        self.init(
            id: report.id,
            location: location,
            lineId: report.lineId,
            direction: report.direction,
            shift: report.shift,
            reportedTripId: report.reportedTripId,
            tripCount: report.tripCount,
            speed: report.speed,
            bearing: report.bearing,
            timestamp: report.timestamp,
            trip: trip,
            tripProgress: tripProgress
        )
    }
}

