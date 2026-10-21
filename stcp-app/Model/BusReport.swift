//
//  BusReport.swift
//  stcp-app
//
//  Created by Nuno Rios on 15/10/2026.
//


//
//  BusReport.swift
//  stcp-app
//
//  A bus exactly as PortoDigital reports it: plain values, no SwiftData.
//  Sendable, so it can be fetched and decoded off the main thread, and Codable,
//  so BusTracker can keep it on disk. `Bus(report:)` turns it into the `Bus` the app uses.
//

import Foundation

nonisolated struct BusReport: Sendable, Codable, Identifiable {
    let id: String
    let latitude: Double
    let longitude: Double
    let lineId: String
    let direction: Bool
    let shift: Int?
    let reportedTripId: String
    let tripCount: Int
    let speed: Float
    let bearing: Double
    /// Instant at which data was captured
    let timestamp: Date
}
