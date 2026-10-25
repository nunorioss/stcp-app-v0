//
//  StopView.swift
//  stcp-app
//
//  Created by Nuno Rios on 25/10/2026.
//

import SwiftUI

struct StopView: View {
    let stop: BusStop

    // whether any route boards here / ends here
    private let hasDepartures: Bool
    private let hasArrivals: Bool

    @State private var model: StopArrivals
    @State private var showFarDepartures = false
    @State private var showFarArrivals = false

    @AppStorage("stopview.groupByLine")
    private var groupByLine = false
    
    @AppStorage("stopview.liveOnly")
    private var liveOnly = false
    
    @Environment(\.scenePhase)
    private var scenePhase

    init(stop: BusStop) {
        self.stop = stop
        let routes = stop.routes
        hasDepartures = routes.contains {
            !Self.endsHere($0, at: stop)
        }
        hasArrivals = routes.contains {
            Self.endsHere($0, at: stop)
        }
        _model = State(initialValue: StopArrivals(stop: stop))
    }

    /// True if `route` ends at `stop`: nobody boards there, so it goes under "Arrivals".
    private static func endsHere(_ route: Route, at stop: BusStop) -> Bool {
        let stops = route.stops
        return stops.firstIndex { $0.id == stop.id } == stops.count - 1
    }

    // MARK: Sections

    // StopView's reorderable sections
    private enum StopSection: String, CaseIterable {
        case map,
             departures,
             arrivals
    }

    var body: some View {
        let arrivals = model.arrivals
        let departures = arrivals.filter {
            !Self.endsHere($0.route, at: stop)
        }
        let terminating = arrivals.filter {
            Self.endsHere($0.route, at: stop)
        }

        ReorderableSectionList(StopSection.allCases,
                               hidden: hidden,
                               orderKey: "stopview.sectionOrder") { section in
            switch section {
            case .map:
                CollapsibleSection("Map", storageKey: "stopview.map") {
                    TransitMapRepresentable(shape: .empty, buses: model.buses,
                                            focus: stop.location.coordinate)
                        .frame(height: 240)
                        .listRowInsets(EdgeInsets())
                }
            case .departures:
                TitledSection("Departures") {
                    arrivalList(departures, noun: "departures", showFar: $showFarDepartures)
                } accessory: {
                    HStack(spacing: 12) {
                        LiveToggle(isOn: $liveOnly, accessibilityLabel: "Only departures with live times")
                        groupMenu
                    }
                }
            case .arrivals:
                CollapsibleSection("Arrivals", storageKey: "stopview.arrivals") {
                    arrivalList(terminating, noun: "arrivals", showFar: $showFarArrivals)
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
            //
        }
        // the stored schedule
        .task(id: scenePhase) {
            await repeating(every: .seconds(30)) {
                model.refreshSchedule()
            }
        }
        // failsafe: STCP's own ETAs
        .task(id: scenePhase) {
            await repeating(every: .seconds(15)) {
                await model.refreshStcpETAs()
            }
        }
        // live buses: once on appear, then only when they change
        .task(id: scenePhase) {
            guard scenePhase == .active else {
                return
            }
            await model.refreshLive()
        }
        .onBusUpdate {
            guard scenePhase == .active else {
                return
            }
            await model.refreshLive()
        }
        // subscribes to BusTracker so it keeps tracking
        .tracksLiveBuses()
    }
    
    //Sections the stop has no routes for
    // (hidden, only shown while reordering)
    private var hidden: Set<StopSection> {
        var hidden: Set<StopSection> = []
        if !hasDepartures {
            hidden.insert(.departures)
        }
        if !hasArrivals {
            hidden.insert(.arrivals)
        }
        return hidden
    }
    
    private func message(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .fontWeight(.regular)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
    }
    
    private func farToggle(_ showFar: Binding<Bool>) -> some View {
        Button {
            withAnimation { showFar.wrappedValue.toggle() }
        } label: {
            Image(systemName: "chevron.down")
                .font(.title3)
                .bold()
                .rotationEffect(.degrees(showFar.wrappedValue ? 180 : 0))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func arrivalList(_ all: [Arrival], noun: String, showFar: Binding<Bool>) -> some View {
        let shown = liveOnly ? all.filter(\.isLive) : all
        
        let near = shown.filter {
            !model.farTripIds.contains($0.tripId)
        }
        // if there are no near arrivals, show all faraway ones
        let visible = near.isEmpty || showFar.wrappedValue ? shown : near

        if visible.isEmpty {
            message(liveOnly && !all.isEmpty ?
                    "No live \(noun) right now" : "No \(noun) soon")
        } else if groupByLine {
            LineArrivalList(arrivals: visible)
        } else {
            ArrivalList(arrivals: visible)
        }
        
        if !near.isEmpty && near.count < shown.count {
            farToggle(showFar)
        }
    }

    private var groupMenu: some View {
        MenuPicker(options: [.init(title: "All departures", systemImage: "list.bullet", value: false),
                             .init(title: "Group by line", systemImage: "folder", value: true)],
                   selection: $groupByLine,
                   accessibilityLabel: "Display")
    }


    //TODO: Move to /Util?
    /// Runs `work` now and then every `interval`, while the app is active.
    private func repeating(every interval: Duration, _ work: () async -> Void) async {
        guard scenePhase == .active else {
            return
        }
        while !Task.isCancelled {
            await work()
            try? await Task.sleep(for: interval)
        }
    }
}

#Preview {
    NavigationStack {
        StopView(stop: DataStore.getBusStop(id: "CMP2")!)
    }
}
