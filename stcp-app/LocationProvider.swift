//
//  LocationProvider.swift
//  stcp-app
//
//  Created by Nuno Rios on 25/09/2026.
//

import CoreLocation
import Observation

@Observable
@MainActor
final class LocationProvider {
    static let shared = LocationProvider()

    private(set) var location: CLLocation?
    private(set) var authorizationStatus: CLAuthorizationStatus
    private let manager = CLLocationManager()
    private var updateTask: Task<Void, Never>?

    private init() {
        authorizationStatus = manager.authorizationStatus
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func startTracking() {
        updateTask?.cancel()
        updateTask = Task {
            do {
                for try await update in CLLocationUpdate.liveUpdates() {
                    authorizationStatus = manager.authorizationStatus
                    guard let loc = update.location else { continue }
                    location = loc
                }
            } catch {
                //
            }
        }
    }

    func stopTracking() {
        updateTask?.cancel()
        updateTask = nil
    }
}
