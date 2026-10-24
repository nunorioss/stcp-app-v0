//
//  StopView.swift
//  stcp-app
//
//  Created by Nuno Rios on 09/10/2026.
//

import SwiftUI
import SwiftData

struct StopView: View {
    let stop: BusStop
    
    /// True if `route` terminates at this stop: nobody boards there, so it goes under "Arrivals".
    private func endsHere(_ route: Route) -> Bool {
        route.ends(at: stop)
    }

    @State private var lines: [LineArrivalGroup] = []
    @State private var scheduled: [Arrival] = []
    @State private var reports: [BusReport] = []
    @State private var stcpETAs: [String: Date] = [:]
    @State private var buses: [Bus] = []
    @Environment(\.scenePhase) private var scenePhase
    
    @State private var arrivals: [Arrival] = []        // replaces `lines`
    @State private var farTripIds: Set<String> = []    // trips that came from getNextScheduledArrival
    @State private var showFar = false
    @State private var hasLoaded = false   // scheduled arrivals fetched at least once

    private let refreshInterval: Duration = .seconds(10)
    
    @AppStorage("stop.groupByLine") private var groupByLine = false
    @AppStorage("stop.liveOnly") private var liveOnly = false

    /// What the map needs: the buses referenced by the current arrivals.
    private struct BusQuery: Equatable {
        let ids: Set<String>
        let lineIds: Set<String>
        let isActive: Bool
    }

    private var departures: [Arrival] { arrivals.filter { !endsHere($0.route) } }

    /// Trips whose last stop is this one.
    private var terminating: [Arrival] {
        arrivals.filter { endsHere($0.route) && (!liveOnly || $0.live != nil) }
    }

    private var filteredArrivals: [Arrival] { departures.filter { !liveOnly || $0.live != nil } }

    private var normalArrivals: [Arrival] { filteredArrivals.filter { !farTripIds.contains($0.tripId) } }

    /// Only far-away arrivals exist -> show them all. Otherwise hide them behind the toggle.
    private var visibleArrivals: [Arrival] {
        normalArrivals.isEmpty || showFar ? filteredArrivals : normalArrivals
    }

    private var canToggleFar: Bool {
        !normalArrivals.isEmpty && normalArrivals.count < filteredArrivals.count
    }

    private var busQuery: BusQuery {
        let withBus = arrivals.filter { $0.live?.busId != nil }
        return BusQuery(ids: Set(withBus.compactMap { $0.live?.busId }),
                        lineIds: Set(withBus.map(\.lineId)),
                        isActive: scenePhase == .active)
    }
    
    private var groupMenu: some View {
        Menu {
            Picker("Display", selection: $groupByLine) {
                Label("All departures", systemImage: "list.bullet").tag(false)
                Label("Group by line", systemImage: "folder").tag(true)
            }
        } label: {
            Image(systemName: groupByLine ? "folder" : "list.bullet")
                .font(.title3)
                .fontWeight(.medium )
                .foregroundStyle(.secondary)
        }
        .tint(.secondary)
    }

    private var farToggle: some View {
        Button {
            withAnimation { showFar.toggle() }
        } label: {
            Image(systemName: "chevron.down")
                .font(.title3)
                .bold()
                .rotationEffect(.degrees(showFar ? 180 : 0))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    var body: some View {
            List {
                if hasLoaded {
                    CollapsibleSection("Map", storageKey: "stopview.map") {
                        TransitMapRepresentable(shape: .empty,
                                                buses: buses, focus: stop.location.coordinate)
                            .frame(height: 240)
                            .listRowInsets(EdgeInsets())
                    }
                }
                
                CollapsibleSection("Departures", storageKey: "stopview.departures", forceExpanded: true) {
                    if liveOnly && filteredArrivals.isEmpty && !departures.isEmpty {
                        Text("No departures with live times right now")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    } else if groupByLine {
                        LineArrivalList(arrivals: visibleArrivals)
                    } else {
                        ArrivalList(arrivals: visibleArrivals)
                    }
                    if canToggleFar {
                        farToggle
                    }
                } accessory: {
                    HStack(spacing: 12) {
                        LiveToggle(isOn: $liveOnly, accessibilityLabel: "Only departures with live times")
                        groupMenu
                    }
                }

                if !terminating.isEmpty {
                    CollapsibleSection("Arrivals", storageKey: "stopview.arrivals") {
                        if groupByLine {
                            LineArrivalList(arrivals: terminating)
                        } else {
                            ArrivalList(arrivals: terminating)
                        }
                    }
                }
            }
        .environment(\.defaultMinListHeaderHeight, 0)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                StopBadge(id: stop.id)
            }
        }
        .refreshable {
            await refreshSchedule()
            await refreshLive()
        }
        .task(id: scenePhase) { await poll { await refreshSchedule() } }
        .task(id: scenePhase) {
            await poll { await refreshLive() }
        }
        .task(id: scenePhase) {
            await poll {
                // keep the previous ETAs if the request fails
                stcpETAs = (try? await STCPFetcher.getLiveETAs(for: stop.id)) ?? stcpETAs
                await regroup()
            }
        }
        // restarts only when the set of buses (or scene phase) changes
        .task(id: busQuery) {
            let query = busQuery
            guard !query.ids.isEmpty else {
                buses = []
                return
            }
            guard query.isActive else { return }

            while !Task.isCancelled {
                buses = await BusTracker.shared.getLiveBuses(ids: query.ids,
                                                             lineIds: query.lineIds)
                try? await Task.sleep(for: refreshInterval)
            }
        }
    }

    // MARK: - Data

    /// Runs `work` every `refreshInterval` while the app is active.
    private func poll(_ work: () async -> Void) async {
        guard scenePhase == .active else { return }
        while !Task.isCancelled {
            await work()
            try? await Task.sleep(for: refreshInterval)
        }
    }

    /// Scheduled arrivals only, built off the main thread.
    private func refreshSchedule() async {
        let (arrivals, far) = await StopArrivals.shared.scheduled(stopId: stop.id)
        farTripIds = far
        scheduled = arrivals
        hasLoaded = true
        await regroup()
    }

    private func refreshLive() async {
        reports = await BusTracker.shared.getLiveReports(forLines: Estimator.liveLineIds(for: stop))
        await regroup()
    }
    
    /// Schedule, then Porto Digital (with inference), then STCP, off the main thread.
    private func regroup() async {
        let merged = await StopArrivals.shared.merge(stopId: stop.id,
                                                     scheduled: scheduled,
                                                     reports: reports,
                                                     stcpETAs: stcpETAs)
        lines = merged.groupedByLine()
        arrivals = merged
    }
}

#Preview {
    NavigationStack {
        StopView(stop: DataStore.getBusStop(id: "CMP2")!)
    }
}
