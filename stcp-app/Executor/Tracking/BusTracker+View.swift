//
//  BusTracker+View.swift
//  stcp-app
//
//  Created by Nuno Rios on 25/10/2026.
//

import SwiftUI

private struct TracksLiveBuses: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content.task(id: scenePhase) {
            guard scenePhase == .active else {
                return
            }
            await BusTracker.shared.track()
        }
    }
}

extension View {
    // Keeps BusTracker polling while this view is on screen and the app is active
    func tracksLiveBuses() -> some View {
        modifier(TracksLiveBuses())
    }

    // Runs "action" whenever BusTracker's live buses change
    func onBusUpdate(perform action: @escaping () async -> Void) -> some View {
        onChange(of: BusTracker.shared.revision) {
            Task { await action() }
        }
    }
}
