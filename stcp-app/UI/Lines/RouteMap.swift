//
//  RouteMap.swift
//  stcp-app
//
//  Created by Nuno Rios on 20/09/2026.
//

import SwiftUI

struct RouteMap: View {
    private let shape: RouteShape
    
    private let lineId: String
    private let direction: Bool

    @State private var buses: [Bus] = []
    @Environment(\.scenePhase) private var scenePhase

    private struct FeedID: Equatable {
        let lineId: String
        let direction: Bool
        let isActive: Bool
    }
    
    init(route: Route) {
        self.shape = RouteShape(route: route)
        self.lineId = route.line.id
        self.direction = route.direction
    }

    // for callers with a cached RouteShape
    init(shape: RouteShape, lineId: String, direction: Bool) {
        self.shape = shape
        self.lineId = lineId
        self.direction = direction
    }

    private func updateLiveBuses(lineId: String, direction: Bool) async {
        buses = await BusTracker.shared.getLiveBuses(line: lineId, direction: direction)
    }

    var body: some View {
        TransitMapRepresentable(shape: shape, buses: buses)
            .task(id: FeedID(lineId: lineId, direction: direction, isActive: scenePhase == .active)) {
                guard scenePhase == .active else {
                    return
                }

                while !Task.isCancelled {
                    await updateLiveBuses(lineId: lineId, direction: direction)
                    try? await Task.sleep(for: .seconds(5))
                }
            }
    }
}

#Preview {
    let line = DataStore.getBusLine(id: "205")!
    RouteMap(route: line.routes[0])
}
