//
//  PollCalibrator.swift
//  stcp-app
//
//  Created by Nuno Rios on 25/10/2026.
//

import Foundation

nonisolated struct PollCalibrator {
    let name: String
    
    // How often the feed refreshes
    let period: Duration
    
    // Poll interval while calibrating
    let step: Duration
    
    // How long after the predicted refresh to poll
    let margin: Duration
    
    // How much earlier to aim, every locked cycle
    let lean: Duration
    
    // Feed considered quiet if it hasn't changed for "quietAfter"
    //(no buses at night, for example); we then poll every "quietStep"
    let quietAfter: Duration
    let quietStep: Duration

    static let stcp = PollCalibrator(name: "STCP", period: .seconds(10), step: .seconds(1),
                                     margin: .milliseconds(300), lean: .milliseconds(150),
                                     quietAfter: .seconds(30), quietStep: .seconds(3))

    typealias Instant = ContinuousClock.Instant

    // the predicted time of the last refresh; nil while calibrating
    private var lastRefresh: Instant?
    
    // the last poll without new data, and when calibration began
    private var lastUnchanged: Instant?
    
    private var calibratingSince: Instant?

    /// Takes a poll's outcome (`changed`: whether it brought new data, nil if it failed)
    /// and the middle of its request, and returns how long to wait before the next one.
    mutating func next(after changed: Bool?, at time: Instant) -> Duration {
        let now = ContinuousClock.now

        switch changed {
        case nil: // request failed, calibrate..
            return step

        case true?:
            if let lastRefresh {
                self.lastRefresh = lastRefresh + period - lean
            } else {
                // between the last poll without new data and this one
                self.lastRefresh = lastUnchanged.map { $0 + (time - $0) / 2 } ?? time
                
                print("[\(name) poll] locked" + (lastUnchanged.map { ", refresh found within \(time - $0)" } ?? ""))
            }
            lastUnchanged = nil
            calibratingSince = nil
            return max(.zero, self.lastRefresh! + period + margin - now)

        case false?:
            if lastRefresh != nil {
                // aimed right after a refresh and got none
                //it drifted, so recalibrate
                lastRefresh = nil
                
                print("[\(name) poll] no new data at the predicted refresh: recalibrating")
            }
            lastUnchanged = time
            let since = calibratingSince ?? now
            
            if calibratingSince == nil {
                print("[\(name) poll] calibrating")
            }
            calibratingSince = since
            return now - since > quietAfter ? quietStep : step
        }
    }
}
