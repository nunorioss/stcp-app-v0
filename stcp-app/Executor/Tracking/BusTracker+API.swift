//
//  BusTracker+API.swift
//  stcp-app
//
//  Created by Nuno Rios on 25/10/2026.
//

import Foundation

extension BusTracker {
    func track() async {
        subscribers += 1
        startTracking()
        
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3600))
        }
        subscribers -= 1
    }
    
    /// Get live buses of one line, in one direction.
    func getLiveBuses(line: String, direction: Bool) async -> [Bus] {
        await getLiveBuses(lineIds: [line])
            .filter { $0.direction == direction }
    }

    /// Get live buses serving a group of lines.
    func getLiveBuses(lineIds: [String]) async -> [Bus] {
        lastRequest = .now
        startTracking()
        
        // tracking just started: get STCP's feed now,
        // so that answer isn't empty
        if Date().timeIntervalSince(lastFetch) > maxCacheAge {
            _ = await pollSTCP()
        }
        
        let lines = Set(lineIds)
        let now = Date()
        
        return reports.values
            .filter {
                lines.contains($0.lineId)
                && now.timeIntervalSince($0.timestamp) <= maxStaleness
            }
            .map(Bus.init(report:))
    }
}
