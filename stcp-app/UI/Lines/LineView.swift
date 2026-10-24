//
// LineView.swift
// stcp-app
//
// Shows a bus line: a map with the shape of the selected route, a route
// picker, and every stop of that route from start to finish.
//

import SwiftUI

/// If the newest bus fix in the whole feed is older than this, real-time
/// tracking is considered down.
let feedStaleAfter: TimeInterval = 5 * 60

func isFeedStale(latestFix: Date?, now: Date = Date()) -> Bool {
    guard let latestFix else { return false } // nothing seen yet, nothing to judge
    return now.timeIntervalSince(latestFix) > feedStaleAfter
}

struct LineView: View {

    let line: BusLine

    @State private var selection = 0
    @State private var isMapExpanded = false

    // Cheap to create; all the real work happens lazily, the first time a
    // route is shown (see LineContent).
    @State private var content: LineContent

    init(line: BusLine) {
        self.line = line
        _content = State(initialValue: LineContent(line: line))
    }

    var body: some View {
        let stops = content.stops(at: selection)

        VStack(spacing: 0) {
            // Own view with its own camera state, so panning the map
            // never re-evaluates the stop list below. It also owns the live
            // bus polling, which restarts by itself when `selection` changes.
            liveMap
                .frame(height: 260)
                .overlay(alignment: .bottomTrailing) {
                    MapButton(systemName: "arrow.up.left.and.arrow.down.right",
                              label: "Expand map") {
                        isMapExpanded = true
                    }
                    .padding(10)
                }

            RouteSelector(routes: content.routes, selection: $selection)

            // No `List` wrapper: StopTimeline has its own ScrollView + LazyVStack.
            // Inside a List row it got unbounded height and built every row at once.
            // `.id` gives each route a fresh timeline (and fresh arrival state).
            StopTimeline(stops: stops,
                         color: line.backgroundColor,
                         line: line,
                         direction: content.direction(at: selection) ?? false)
                .id("\(line.id)-\(selection)")
        }
        .fullScreenCover(isPresented: $isMapExpanded) {
            fullScreenMap
        }
        .navigationTitle(line.shortName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                LineBadge(busLine: line)
            }
        }
    }

    /// Small rounded-square button that floats over a map.
    private struct MapButton: View {
        let systemName: String
        let label: String
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Image(systemName: systemName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 34, height: 34)
                    .background(.regularMaterial,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
        }
    }

    // Built once here so the inline and full-screen maps always match.
    private var liveMap: some View {
        RouteMap(shape: content.shape(at: selection),
                 lineId: line.id,
                 direction: content.direction(at: selection) ?? false)
    }

    private var fullScreenMap: some View {
        liveMap
            .ignoresSafeArea()
            .overlay(alignment: .bottomTrailing) {
                MapButton(systemName: "arrow.down.right.and.arrow.up.left",
                          label: "Close map") {
                    isMapExpanded = false
                }
                .padding(10)
            }
    }

    // MARK: - Data

    /// Everything derived from the line's routes, computed on demand and remembered.
    ///
    /// - `BusLine.routes` and `Route.routeStops` sort on every access, so each is
    ///   read once per line / route.
    /// - A route's shape is only built when the route is first selected.
    /// - `init` does no work, because SwiftUI may create a view's `@State`
    ///   initial value more than once.
    private final class LineContent {
        private let line: BusLine

        lazy var routes: [Route] = {
            let all = line.routes
            // Ignore routes with very few weekday trips
            let main = all.filter { route in
                route.trips.filter { $0.serviceType == .weekday }.count >= 3
            }
            // never leave a line with nothing to show
            return main.isEmpty ? all : main
        }()
        
        private var stopsCache: [Int: [RouteStop]] = [:]
        private var shapeCache: [Int: RouteShape] = [:]

        init(line: BusLine) {
            self.line = line
        }

        func stops(at index: Int) -> [RouteStop] {
            guard routes.indices.contains(index) else { return [] }

            if let cached = stopsCache[index] {
                return cached
            }

            let stops = routes[index].routeStops
            stopsCache[index] = stops
            return stops
        }

        /// Which way the route goes, `nil` if there is no such route.
        func direction(at index: Int) -> Bool? {
            routes.indices.contains(index) ? routes[index].direction : nil
        }

        func shape(at index: Int) -> RouteShape {
            guard routes.indices.contains(index) else { return .empty }

            if let cached = shapeCache[index] {
                return cached
            }

            let shape = RouteShape(route: routes[index])
            shapeCache[index] = shape
            return shape
        }
    }
}

// MARK: - Stop timeline

/// The stops as a timeline, with a bus badge wherever a live bus is, and the
/// next arrivals for this line/direction shown as a caption under each stop's
/// name.
///
/// All estimation lives in `Estimator`; this view only polls and draws.
/// Each live bus gets its own line: a green dot + live ETA, plus how early or
/// late it is against its own timetable (nothing when on time). Scheduled runs
/// that have no live bus are listed in the caption below. When nothing is due
/// within the hour, the caption shows the next scheduled arrival, however far out.
private struct StopTimeline: View {
    let stops: [RouteStop]
    let color: Color
    let line: BusLine
    let direction: Bool

    @State private var snapshot = Snapshot()
    @State private var scheduled: [String: [Arrival]] = [:]
    @State private var live = Estimator.LiveData()
    @State private var nextByStop: [String: NextArrival] = [:]
    @State private var hasLoaded = false
    @State private var latestFix: Date?
    @State private var isStale = false
    @Environment(\.scenePhase) private var scenePhase

    /// Only arrivals due within this many minutes are listed under a stop.
    private let horizonMinutes = 60
    private let refreshInterval: Duration = .seconds(5)
    private let feedCheckInterval: Duration = .seconds(30)

    init(stops: [RouteStop], color: Color, line: BusLine, direction: Bool) {
        self.stops = stops
        self.color = color
        self.line = line
        self.direction = direction
    }

    private struct FeedID: Equatable {
        let lineId: String
        let direction: Bool
        let isActive: Bool
    }

    private struct LiveDataWarning: View {
        var body: some View {
            Label("Real-time location services appear to be down. Arrival times may be less accurate.",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.12))
        }
    }

    // MARK: - State

    /// What is due at one stop, soonest first.
    private struct StopArrivals {
        var live: [Arrival] = []
        var scheduled: [Arrival] = []

        var isEmpty: Bool { live.isEmpty && scheduled.isEmpty }
    }

    /// One estimate, regrouped for drawing: arrivals per stop, and the live
    /// buses (used for the badges). The buses come straight from `LiveData`,
    /// which only holds this line and direction, since `Arrival.Live` carries
    /// just a bus id.
    private struct Snapshot {
        var stops: [String: StopArrivals] = [:]
        var buses: [Bus] = []

        init() {}

        init(_ arrivalsByStop: [String: [Arrival]], buses: [Bus], within minutes: Int) {
            let horizon = Date().addingTimeInterval(Double(minutes) * 60)

            for (stopId, arrivals) in arrivalsByStop {
                var grouped = StopArrivals()

                for arrival in arrivals.sorted(by: { $0.eta < $1.eta }) {
                    guard arrival.eta <= horizon else {
                        continue
                    }
                    if arrival.isLive {
                        grouped.live.append(arrival)
                    } else {
                        grouped.scheduled.append(arrival)
                    }
                }

                if !grouped.isEmpty {
                    stops[stopId] = grouped
                }
            }
            self.buses = buses
        }
    }

    /// Next scheduled arrival at a stop with nothing due within the horizon.
    private enum NextArrival {
        case upcoming(Date)
        case unavailable

        var isExpired: Bool {
            if case .upcoming(let date) = self {
                return date < Date()
            }
            return false
        }
    }

    // MARK: - Body

    var body: some View {

        let offsets = isStale ? [:] : busOffsets() // badges hidden when stale
        let feedID = FeedID(lineId: line.id, direction: direction, isActive: scenePhase == .active)

        VStack(spacing: 0) {
            if isStale {
                LiveDataWarning()
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(stops.enumerated()), id: \.element.sequenceNo) { index, routeStop in
                        let stopId = routeStop.stop.id
                        let arrivals = snapshot.stops[stopId] ?? StopArrivals()
                        let next = nextByStop[stopId]
                        let needsNext = hasLoaded && arrivals.isEmpty && next == nil

                        VStack(alignment: .leading, spacing: 2) {
                            StopRow(stop: routeStop.stop)

                            ForEach(arrivals.live, id: \.tripId) { arrival in
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 6, height: 6)
                                    Text(formattedMinutes(arrival.minutesTilArrival))
                                        .foregroundStyle(.green)

                                    if let label = delayLabel(delaySeconds(of: arrival)) {
                                        Text(label.text)
                                            .foregroundStyle(label.color)
                                    }
                                }
                                .font(.caption)
                            }

                            if let text = caption(for: arrivals, next: next) {
                                Text(text)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.leading, TimelineMarker.width)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(alignment: .leading) {
                            TimelineMarker(color: color,
                                           isFirst: index == 0,
                                           isLast: index == stops.count - 1,
                                           busOffsets: offsets[index] ?? [])
                                .padding(.leading, 16)
                        }
                        // lets a badge overflow onto the next row instead of hiding under it
                        .zIndex(offsets[index] == nil ? 0 : 1)
                        // Only does work for stops with nothing due within the hour, and
                        // only while the row is on screen. Runs again once a cached
                        // "next arrival" has gone by.
                        .task(id: needsNext) {
                            if needsNext {
                                await loadNext(for: routeStop.stop)
                            }
                        }
                    }
                }
            }
        }
        // scheduled arrivals: no network, so it's instant
        .task(id: feedID) {
            guard feedID.isActive else { return }

            while !Task.isCancelled {
                refreshSchedule()
                try? await Task.sleep(for: refreshInterval)
            }
        }
        // live buses: slow or offline fetches never block the scheduled ones
        .task(id: feedID) {
            guard feedID.isActive else { return }

            while !Task.isCancelled {
                live = await Estimator.fetchLiveDataFromPortoDigital(for: line, direction: direction)
                regroup()
                try? await Task.sleep(for: refreshInterval)
            }
        }
    }

    // MARK: - Loading

    /// Scheduled arrivals only. No network, so it's instant.
    private func refreshSchedule() {
        scheduled = Estimator.estimate(line: line, direction: direction, within: horizonMinutes)
        regroup()

        // drop "next arrivals" that already happened so they get looked up again
        nextByStop = nextByStop.filter { !$0.value.isExpired }
        hasLoaded = true
    }

    /// Schedule, then Porto Digital (with inference).
    private func regroup() {
        let merged = Estimator.applyPortoDigitalLiveData(live, to: scheduled,
                                                         line: line, direction: direction)
        snapshot = Snapshot(merged, buses: live.buses, within: horizonMinutes)
    }

    /// Looks up the next scheduled arrival at a stop, however far out.
    private func loadNext(for stop: BusStop) async {

        await Task.yield() // let the screen draw before the query
        guard !Task.isCancelled else { return }

        if let next = DataStore.getNextScheduledArrival(at: stop, line: line, direction: direction) {
            nextByStop[stop.id] = .upcoming(next.1)
        } else {
            nextByStop[stop.id] = .unavailable
        }
    }

    // MARK: - Text

    /// Caption under a stop: scheduled-only runs, else the next arrival, else nothing.
    private func caption(for arrivals: StopArrivals, next: NextArrival?) -> String? {
        if !arrivals.scheduled.isEmpty {
            return arrivals.scheduled.prefix(2)
                .map { formattedMinutes($0.minutesTilArrival) }
                .joined(separator: ", ")
        }

        // live buses are already listed above
        guard arrivals.live.isEmpty else { return nil }

        switch next {
        case .upcoming(let date)?:
            return "Next arrival " + formattedNextArrival(date)
        case .unavailable?:
            return "No arrivals found"
        case nil:
            return " " // blank placeholder keeps the row height stable
        }
    }

    private func formattedMinutes(_ minutes: Int) -> String {
        minutes < 1 ? "now" : "in \(minutes)min"
    }

    private func formattedClockTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// Text for a next arrival that may be on a later day, e.g. "at 6:55",
    /// "tomorrow at 6:55" or "Sat at 6:55".
    private func formattedNextArrival(_ date: Date) -> String {
        let cal = DateUtil.portoCalendar
        let time = formattedClockTime(date)

        if cal.isDateInToday(date) {
            return "at \(time)"
        } else if cal.isDateInTomorrow(date) {
            return "tomorrow at \(time)"
        } else {
            let day = date.formatted(.dateTime.weekday(.abbreviated))
            return "\(day) at \(time)"
        }
    }

    /// Seconds a live bus is ahead of (negative) or behind (positive) its timetable.
    private func delaySeconds(of arrival: Arrival) -> Int {
        Int(arrival.eta.timeIntervalSince(arrival.scheduledEta).rounded())
    }

    /// Label for how far a live bus is from its schedule, or nil when it is on
    /// time (rounds to 0min). Late is orange up to 5min and red beyond that.
    private func delayLabel(_ seconds: Int) -> (text: String, color: Color)? {
        let minutes = Int((Double(abs(seconds)) / 60).rounded())
        guard minutes > 0 else { return nil }

        if seconds < 0 {
            return ("\(minutes)min early", .blue)
        }
        return ("\(minutes)min late", minutes > 5 ? .red : .orange)
    }

    // MARK: - Badges

    /// For each row, where its bus badges are centered: 0 = top of the row, 1 = bottom.
    /// Between two stops the offset goes past 1, which draws the badge over the next row.
    /// Buses whose segment isn't part of this route (another variant) get no badge.
    private func busOffsets() -> [Int: [Double]] {
        let indexById = Dictionary(stops.enumerated().map { ($1.stop.id, $0) },
                                   uniquingKeysWith: { first, _ in first })
        var result: [Int: [Double]] = [:]

        for bus in snapshot.buses {
            // the bus' own trip may be another variant, so match segments by stop id
            guard let progress = bus.tripProgress,
                  let tripStops = bus.trip?.route.stops,
                  tripStops.indices.contains(progress.lastStopIndex + 1),
                  let index = indexById[tripStops[progress.lastStopIndex].id],
                  stops.indices.contains(index + 1),
                  stops[index + 1].stop.id == tripStops[progress.lastStopIndex + 1].id else {
                continue
            }

            result[index, default: []].append(0.5 + progress.progress)
        }

        return result
    }
}

/// Wraps a row with a vertical track and a dot, so consecutive rows join up
/// into one continuous line from the first stop to the last.
/// The vertical track and dot for one row. It's used as the row's background,
/// so it fills the whole cell and consecutive rows join with no gaps.
private struct TimelineMarker: View {
    static let width: CGFloat = 28

    let color: Color
    let isFirst: Bool
    let isLast: Bool
    let busOffsets: [Double]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                TimelineTrack(isFirst: isFirst, isLast: isLast)
                    .stroke(color, lineWidth: 4)

                Circle()
                    .fill(color)
                    .frame(width: isFirst || isLast ? 14 : 10,
                           height: isFirst || isLast ? 14 : 10)

                ForEach(Array(busOffsets.enumerated()), id: \.offset) { _, offset in
                    BusBadge(color: color, bearing: 180)
                        .position(x: Self.width / 2, y: offset * proxy.size.height)
                }
            }
            .frame(width: Self.width, height: proxy.size.height)
        }
        .frame(width: Self.width)
        .accessibilityHidden(true)
    }
}

/// A vertical line through the middle of its frame. It starts at the center
/// for the first stop and ends at the center for the last one.
private struct TimelineTrack: Shape {
    let isFirst: Bool
    let isLast: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: isFirst ? rect.midY : rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: isLast ? rect.midY : rect.maxY))
        return path
    }
}

#Preview {
    NavigationStack {
        LineView(line: DataStore.getBusLine(id: "205")!)
    }
}
