//
//  TravelView.swift
//  stcp-app
//
//  Created by Nuno Rios on 21/10/2026.
//

import SwiftUI
import CoreLocation

struct JourneyLink: Hashable {
    let id: String
}

struct TravelView: View {
    @State private var model = TravelModel()
    @State private var picking: Field?
    /// The departure being picked; only applied once the picker closes.
    @State private var draftDeparture = Date.now
    /// Fixed when the picker opens: a bound that keeps moving makes the picker snap back.
    @State private var earliestDeparture = Date.now
    @State private var isPickingDeparture = false
    @AppStorage("travel.sort") private var sort: JourneySort = .best
    @AppStorage("travel.liveOnly") private var liveOnly = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    private let iconWidth: CGFloat = 28
    private let locationProvider = LocationProvider.shared

    private let liveInterval: Duration = .seconds(20)

    enum Field: Identifiable {
        case origin, destination
        var id: Self { self }
    }

    private struct TaskKey: Equatable {
        let search: TravelModel.SearchKey
        let isActive: Bool
    }

    var body: some View {
        List {
            Section {
                endpoints
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            .listSectionSpacing(12)
            Section {
                departureRow
                    .padding(.vertical, 6)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            results
        }
        .environment(\.defaultMinListHeaderHeight, 0)
        .navigationTitle("Travel")
        .navigationDestination(for: JourneyLink.self) {
            JourneyView(model: model, journeyId: $0.id)
        }
        .sheet(item: $picking) { field in
            PlacePicker(title: field == .origin ? "From" : "To") { endpoint in
                if field == .origin {
                    model.origin = endpoint
                } else {
                    model.destination = endpoint
                }
            }
        }
        .refreshable {
            await model.search(force: true)
        }
        .onAppear {
            if locationProvider.authorizationStatus == .notDetermined {
                locationProvider.requestPermission()
            }
            locationProvider.startTracking()
        }
        .onDisappear {
            locationProvider.stopTracking()
        }
        .task(id: TaskKey(search: model.searchKey, isActive: scenePhase == .active)) {
            // debounce rapid changes, like location updates while walking
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, scenePhase == .active else { return }
            await model.search()
            while !Task.isCancelled {
                try? await Task.sleep(for: liveInterval)
                await model.refreshLive()
            }
        }
    }

    // MARK: - From / To

    private var endpoints: some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                endpointButton(.origin, icon: "location.circle.fill", tint: .blue,
                               label: "From", value: model.name(of: model.origin))
                Divider()
                    .padding(.leading, iconWidth + 12)
                endpointButton(.destination, icon: "mappin.circle.fill", tint: .red,
                               label: "To", value: model.destination.map { model.name(of: $0) })
            }

            Button {
                withAnimation { model.swap() }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .background(Color(.tertiarySystemFill), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(model.destination == nil)
            .accessibilityLabel("Swap start and destination")
        }
    }

    private func endpointButton(_ field: Field, icon: String, tint: Color,
                                label: String, value: String?) -> some View {
        Button {
            picking = field
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(tint)
                    .frame(width: iconWidth)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(value ?? "Choose destination")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(value == nil ? .secondary : .primary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Depart | Arrive with Now below it; the time with −10 / +10 centered below it.
    private var departureRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "clock")
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: iconWidth, height: 32)
            VStack(alignment: .leading, spacing: 10) {
                modePicker
                if model.departure != nil {
                    Button("Now") {
                        model.arriveBy = false
                        model.departure = nil
                    }
                    .font(.system(.subheadline, design: .rounded))
                    .buttonStyle(.borderless)
                    .padding(.leading, 4)
                    .frame(height: 30)
                }
            }
            Spacer(minLength: 0)
            VStack(spacing: 10) {
                timeButton
                nudgeButtons
            }
        }
    }

    private var timeButton: some View {
        Button {
            let thisMinute = Calendar.current.dateInterval(of: .minute, for: .now)?.start ?? .now
            earliestDeparture = thisMinute
            draftDeparture = max(model.departure ?? thisMinute, thisMinute)
            isPickingDeparture = true
        } label: {
            Text(departureText)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.borderless)
        .onChange(of: isPickingDeparture) { _, isOpen in
            if !isOpen { commitDeparture() }
        }
        .popover(isPresented: $isPickingDeparture) {
            DatePicker("Depart", selection: $draftDeparture, in: earliestDeparture...,
                       displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.graphical)
                .labelsHidden()
                .padding(.horizontal)
                .padding(.top, 8)
                // only as tall as the calendar itself, which always keeps room for 6 weeks
                .frame(width: 340)
                .fixedSize()
                .presentationCompactAdaptation(.popover)
        }
    }

    /// −10 / +10 min on the chosen time, for quick tweaks without the picker.
    private var nudgeButtons: some View {
        let base = model.departure ?? .now
        let earlier = base.addingTimeInterval(-10 * 60)
        // departing: going back past now means now; arriving can't be in the past
        let canGoEarlier = model.departure != nil && (!model.arriveBy || earlier > .now)

        return HStack(spacing: 8) {
            nudgeButton("−10 min") {
                model.departure = !model.arriveBy && earlier <= .now ? nil : earlier
            }
            .disabled(!canGoEarlier)
            nudgeButton("+10 min") {
                model.departure = base.addingTimeInterval(10 * 60)
            }
        }
    }

    private func nudgeButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.medium)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color(.tertiarySystemFill), in: Capsule())
        }
        .buttonStyle(.borderless)
    }

    /// Depart (leave at) or Arrive (by): both always visible, so switching is obvious.
    private var modePicker: some View {
        Picker("Time", selection: Binding(get: { model.arriveBy }, set: setArriveBy)) {
            Text("Depart").tag(false)
            Text("Arrive").tag(true)
        }
        .pickerStyle(.segmented)
        .fixedSize()
    }

    /// "Arrive by now" means nothing, so arriving starts half an hour out.
    private func setArriveBy(_ arriveBy: Bool) {
        if arriveBy, model.departure == nil {
            model.departure = Date.now.addingTimeInterval(30 * 60)
        }
        model.arriveBy = arriveBy
    }

    private var departureText: String {
        let date = model.departure ?? .now
        let day = Calendar.current.isDateInToday(date)
            ? "Today"
            : date.formatted(.dateTime.day().month(.abbreviated))
        return "\(day), \(DateUtil.clockText(for: date))"
    }

    /// Searches again only if the picked minute actually differs.
    private func commitDeparture() {
        guard !Calendar.current.isDate(draftDeparture, equalTo: model.departure ?? .now,
                                       toGranularity: .minute) else { return }
        model.departure = draftDeparture
    }

    // MARK: - Results

    @ViewBuilder
    private var results: some View {
        if model.destination == nil {
            message("Where to?", systemImage: "map",
                    description: "Choose a destination to see\nthe best ways to get there")
        } else if model.place(for: model.origin) == nil {
            message("Finding your location", systemImage: "location",
                    description: "Allow location access or\nchoose a starting point")
        } else {
            if model.journeys.isEmpty {
                if model.isSearching {
                    Section {
                        ProgressView("Finding routes…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                            .listRowBackground(Color.clear)
                    }
                } else {
                    message("No routes found", systemImage: "bus",
                            description: "Try another time or destination")
                }
            } else {
                // walk-only routes have no times to be live, so they always show
                let shown = sort.sorted(model.journeys).filter { !liveOnly || $0.isLive || $0.rides.isEmpty }
                CollapsibleSection("Routes", storageKey: "travel.routes", forceExpanded: true) {
                    if shown.isEmpty {
                        Text("No routes with live times right now")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    } else {
                        ForEach(shown) { journey in
                            // hidden link: the whole row opens the journey, without the chevron
                            JourneyRow(journey: journey)
                                .background {
                                    NavigationLink(value: JourneyLink(id: journey.id)) { EmptyView() }
                                        .opacity(0)
                                }
                        }
                    }
                } accessory: {
                    HStack(spacing: 12) {
                        liveToggle
                        sortMenu
                    }
                }
            }
        }
    }

    private var liveToggle: some View {
        LiveToggle(isOn: $liveOnly, accessibilityLabel: "Only routes with live times")
    }

    private func message(_ title: String, systemImage: String, description: String) -> some View {
        Section {
            ContentUnavailableView(title, systemImage: systemImage, description: Text(description))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort by", selection: $sort) {
                ForEach(JourneySort.allCases) { option in
                    Label(option.title, systemImage: option.systemImage).tag(option)
                }
            }
        } label: {
            Image(systemName: sort.systemImage)
                .font(.title3)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
        }
        .tint(.secondary)
        .accessibilityLabel("Sort routes")
    }
}

#Preview {
    NavigationStack {
        TravelView()
    }
}
