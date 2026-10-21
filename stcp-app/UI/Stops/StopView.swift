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
    
    /// True if `route` terminates at this stop: nobody boards there, so there's nothing to show.
    /// Uses the first occurrence of the stop, the same one `Estimator.estimate` uses, so the
    /// start of a circular line (first and last stop are the same) still shows its departures.
    private func endsHere(_ route: Route) -> Bool {
        let stops = route.stops
        return stops.firstIndex(where: { $0.id == stop.id }) == stops.count - 1
    }

    @State private var lines: [LineArrivalGroup] = []
    @State private var scheduled: [Arrival] = []
    @State private var live = Estimator.LiveData()
    @State private var stcpETAs: [String: Date] = [:]
    @State private var buses: [Bus] = []
    @Environment(\.scenePhase) private var scenePhase
    
    @State private var arrivals: [Arrival] = []        // replaces `lines`
    @State private var farTripIds: Set<String> = []    // trips that came from getNextScheduledArrival
    @State private var showFar = false

    private let refreshInterval: Duration = .seconds(10)
    
    @AppStorage("stop.groupByLine") private var groupByLine = false

    /// What the map needs: the buses referenced by the current arrivals.
    private struct BusQuery: Equatable {
        let ids: Set<String>
        let lineIds: Set<String>
        let isActive: Bool
    }

    private var normalArrivals: [Arrival] { arrivals.filter { !farTripIds.contains($0.tripId) } }

    /// Only far-away arrivals exist -> show them all. Otherwise hide them behind the toggle.
    private var visibleArrivals: [Arrival] {
        normalArrivals.isEmpty || showFar ? arrivals : normalArrivals
    }

    private var canToggleFar: Bool {
        !normalArrivals.isEmpty && normalArrivals.count < arrivals.count
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
                CollapsibleSection("Map", storageKey: "stopview.map") {
                    TransitMapRepresentable(shape: .empty,
                                            buses: buses, focus: stop.location.coordinate)
                        .frame(height: 240)
                        .listRowInsets(EdgeInsets())
                }
                
                CollapsibleSection("Departures", storageKey: "stopview.departures", forceExpanded: true) {
                    if groupByLine {
                        LineArrivalList(arrivals: visibleArrivals)
                    } else {
                        ArrivalList(arrivals: visibleArrivals)
                    }
                    if canToggleFar {
                        farToggle
                    }
                } accessory: {
                    groupMenu
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
            live = await Estimator.fetchLiveDataFromPortoDigital(for: stop)
            regroup()
        }
        .task(id: scenePhase) { await poll { await refreshSchedule() } }
        .task(id: scenePhase) {
            await poll {
                live = await Estimator.fetchLiveDataFromPortoDigital(for: stop)
                regroup()
            }
        }
        .task(id: scenePhase) {
            await poll {
                // keep the previous ETAs if the request fails
                stcpETAs = (try? await STCPFetcher.getLiveETAs(for: stop.id)) ?? stcpETAs
                regroup()
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

    /// Scheduled arrivals only. No network, so it's instant.
    /// On top of what the estimator returns, adds the next scheduled arrival of every
    /// master route serving this stop (possibly hours or days away), so lines with
    /// nothing due soon still show up.
    /// 
    private func refreshSchedule() async {
        var arrivals = Estimator.estimate(for: stop, within: 75).filter { !endsHere($0.route) }
        var tripIds = Set(arrivals.map(\.tripId))
        var far: Set<String> = []

        for route in stop.routes where route.isMasterRoute && !endsHere(route) {
            guard let (tripId, eta) = DataStore.getNextScheduledArrival(at: stop,
                                                                        line: route.line,
                                                                        direction: route.direction),
                  tripIds.insert(tripId).inserted,   // skip if the estimator already has it
                  let trip = DataStore.getTrip(id: tripId),
                  !endsHere(trip.route)
            else { continue }
            
            far.insert(tripId)

            
            arrivals.append(Arrival(
                tripId: tripId,
                lineId: route.line.id,
                routeId: route.persistentModelID,
                routeSortIndex: route.sortIndex,
                scheduledEta: eta,
                live: nil)
            )
        }
        farTripIds = far
        scheduled = arrivals

        regroup()
    }
    
    /// Schedule, then Porto Digital (with inference), then STCP.
    private func regroup() {
        let withLive = Estimator.applyLiveDataFromPortoDigital(live, to: scheduled, for: stop)
        let merged = Estimator.applyETAsFromSTCP(stcpETAs, to: withLive)
            .filter { !endsHere($0.route) }

        let pd = withLive.filter { $0.live?.inferred == false }.count
        let inferred = withLive.filter { $0.live?.inferred == true }.count
        let stcp = merged.filter { $0.live?.source == .stcp }.count
        print("[\(stop.id)] \(scheduled.count) scheduled | porto digital: \(pd) live, \(inferred) inferred "
              + "| stcp: \(stcpETAs.count) received, \(stcp) applied")
        
        let stcpApplied = merged.filter { $0.live?.source == .stcp }

        for a in stcpApplied {
            print("[\(stop.id)]   stcp → \(a.line.shortName) \(a.route.headsign) | \(a.tripId) "
                  + "| eta \(a.eta.formatted(date: .omitted, time: .standard)) "
                  + "(scheduled \(a.scheduledEta.formatted(date: .omitted, time: .standard)))")
        }

        lines = merged.groupedByLine()
        arrivals = merged
    }
}

#Preview {
    NavigationStack {
        StopView(stop: DataStore.getBusStop(id: "CMP2")!)
    }
}
