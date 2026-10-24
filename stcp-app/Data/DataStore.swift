//
//  DataStore.swift
//  stcp-app
//
//  Created by Nuno Rios on 16/09/2026.
//

import SwiftData
import CoreLocation

nonisolated enum DataStore {
    /// A context that is only used by the task that set it, so it never actually crosses threads.
    struct TaskContext: @unchecked Sendable {
        let context: ModelContext
    }

    /// Queries run on the main context, unless a task sets its own context here
    /// (`$taskContext.withValue`), as `StopArrivals` does to run off the main thread.
    @TaskLocal static var taskContext: TaskContext?

    private static var context: ModelContext {
        if let taskContext {
            return taskContext.context
        }
        return MainActor.assumeIsolated { TaskContext(context: SwiftDataManager.context) }.context
    }
    
    private static func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> [T] {
        (try? context.fetch(descriptor)) ?? []
    }
    
    nonisolated(unsafe) private static var cachedGlobalTripNo: String?

    /// Retrieves the global, magic trip number for the dataset.
    static var globalTripNo: String {
        if cachedGlobalTripNo == nil {
            do {
                print("TripConfig rows:", try context.fetch(FetchDescriptor<TripConfig>()).count)
            } catch {
                print("TripConfig fetch failed:", error)
            }
            var descriptor = FetchDescriptor<TripConfig>()
            descriptor.fetchLimit = 1
            cachedGlobalTripNo = fetch(descriptor).first?.globalTripNo
        }
        return cachedGlobalTripNo!
    }
    
    /// Retrieves the service type applicable on a `date`.
    static func getServiceType(on date: Date = Date()) -> ServiceType {
        let c = DateUtil.portoCalendar.dateComponents([.year, .month, .day], from: date)
        let yyyymmdd = c.year! * 10000 + c.month! * 100 + c.day!

        var descriptor = FetchDescriptor<ServiceDate>(
            predicate: #Predicate { $0.date == yyyymmdd }
        )
        descriptor.fetchLimit = 1

        return fetch(descriptor).first?.serviceType ?? ServiceType.defaultServiceType(for: date)
    }
    
    /// Yesterday's trips can only still be running shortly after midnight,
    /// so nothing is expected to go past ~2am.
    private static func isYesterdayRelevant(at date: Date = Date()) -> Bool {
        DateUtil.secondsSinceMidnight(at: date) < 2 * 3600
    }

    /// Retrieves service types of `date` and `date -1d`, if relevant. GTFS times can
    /// go past 24h, so yesterday's late trips may still be running after midnight.
    private static func getActiveServiceTypes(on date: Date = Date())
    -> (today: Int, yesterday: Int?) {
        let today = getServiceType(on: date).rawValue
        guard isYesterdayRelevant(at: date) else {
            return (today, nil)
        }
        let yesterday = DateUtil.portoCalendar.date(byAdding: .day, value: -1, to: date) ?? date
        return (today, getServiceType(on: yesterday).rawValue)
    }

    /// Retrieves all bus lines.
    static func getBusLines() -> [BusLine] {
        fetch(FetchDescriptor<BusLine>())
    }

    /// Retrieves all bus stops.
    static func getBusStops() -> [BusStop] {
        fetch(FetchDescriptor<BusStop>())
    }

    /// Retrieves a bus line by its unique id.
    static func getBusLine(id: String) -> BusLine? {
        var descriptor = FetchDescriptor<BusLine>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return fetch(descriptor).first
    }

    /// Retrieves a bus stop by its unique id.
    static func getBusStop(id: String) -> BusStop? {
        var descriptor = FetchDescriptor<BusStop>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return fetch(descriptor).first
    }

    /// Retrieves all bus stops with a given name.
    static func getBusStops(named name: String, ignoreCase: Bool = false) -> [BusStop] {
        if ignoreCase { // ignore case and accents!
            let key = BusStop.nameKey(for: name)
            return fetch(FetchDescriptor<BusStop>(
                predicate: #Predicate { $0.nameKey == key }
            ))
        } else {
            return fetch(FetchDescriptor<BusStop>(
                predicate: #Predicate { $0.name == name }
            ))
        }
    }
    
    /// Retrieves a trip by its unique id.
    static func getTrip(id: String) -> Trip? {
        var descriptor = FetchDescriptor<Trip>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return fetch(descriptor).first
    }
    
    /// Retrieves all bus stops within a given radius of a coordinate.
    static func getNearbyStops(to coordinate: CLLocationCoordinate2D,
                               radius: CLLocationDistance,
                               sortByDistance: Bool = false) -> [BusStop] {
        let precision = Geohash.precision(for: radius)
        let hashes = Geohash.searchHashes(for: coordinate, precision: precision)
        
        let predicate: Predicate<BusStop>
        switch precision {
        case 5:
            predicate = #Predicate { hashes.contains($0.geohash5) }
        case 6:
            predicate = #Predicate { hashes.contains($0.geohash6) }
        default:
            predicate = #Predicate { hashes.contains($0.geohash7) }
        }
        
        // index lookup first
        let candidates = fetch(FetchDescriptor<BusStop>(predicate: predicate))
        
        // distance filter (prune quad corners, keep it within radius)
        let results = candidates.compactMap { stop -> (BusStop, CLLocationDistance)? in
            let distance = stop.location.distance(to: coordinate)
            return distance <= radius ? (stop, distance) : nil
        }

        guard sortByDistance else {
            return results.map { $0.0 }
        }

        // sort by ascending distance to target
        return results
            .sorted { $0.1 < $1.1 }
            .map { $0.0 }
    }
    
    static func getScheduledTrips(for stop: BusStop, within: Int = 60) -> Set<Trip> {
        let types = getActiveServiceTypes()
        let daySeconds = DateUtil.secondsPerDay
        let now = DateUtil.secondsSinceMidnight()
        let end = now + within * 60
        
        var result = Set<Trip>()
        
        for ts in stop.tripStops {
            let eta = ts.etaNumeric
            let today = ts.serviceTypeRaw == types.today
                && (now...end).contains(eta)
            let yesterday = ts.serviceTypeRaw == types.yesterday
                && (now+daySeconds...end+daySeconds).contains(eta)
            
            if today || yesterday {
                result.insert(ts.trip)
            }
        }
        return result
    }
    
    static func getScheduledTrips(line: BusLine,
                                  direction: Bool,
                                  within: Int = 60) -> Set<Trip> {
        let types = getActiveServiceTypes()
        let daySeconds = DateUtil.secondsPerDay
        let now = DateUtil.secondsSinceMidnight()
        let end = now + within * 60

        var result = Set<Trip>()

        for route in line.storedRoutes where route.direction == direction {
            for trip in route.trips {
                let type = trip.serviceType.rawValue
                let today = type == types.today
                    && trip.firstEtaNumeric <= end
                    && trip.lastEtaNumeric >= now
                let yesterday = type == types.yesterday
                    && trip.firstEtaNumeric <= end + daySeconds
                    && trip.lastEtaNumeric >= now + daySeconds
                
                if today || yesterday {
                    result.insert(trip)
                }
            }
        }
        return result
    }
    
    /// Retrieves the next scheduled arrival of a line+direction combo at a bus stop,
    /// looking into following days if none remain today. Returns trip id and date of arrival.
    /// Search starts at `nonBefore` (seconds since midnight) if it is later than now.
    static func getNextScheduledArrival(at stop: BusStop,
                                        line: BusLine,
                                        direction: Bool,
                                        searchDays: Int = 8,
                                        notBefore: Int? = nil) -> (String, Date)? {
        let cal = DateUtil.portoCalendar
        let startOfToday = cal.startOfDay(for: Date())
        
        let stopModelId = stop.persistentModelID

        // all trips serving the line in the target direction
        let allTrips = line.storedRoutes
            .filter { $0.direction == direction }
            .flatMap { $0.trips }

        // service types known to be empty
        var searchedWithoutResult = Set<Int>()

        for offset in -1..<searchDays {
            guard let dayStart = cal.date(byAdding: .day, value: offset, to: startOfToday)
            else { continue }

            let serviceType = getServiceType(on: dayStart).rawValue
            
            if offset > 0 && searchedWithoutResult.contains(serviceType) {
                continue
            }

            // "yesterday": trips going past 24h
            // "today": only ongoing or upcoming trips (after `nonBefore`)
            // days after: any trip
            
            let now = DateUtil.secondsSinceMidnight()
            let base = Swift.max(now, notBefore ?? 0)
            let minEta = offset < 0 ? base + DateUtil.secondsPerDay
                : offset == 0 ? base
                : 0
            
            let candidates = allTrips.filter {
                $0.serviceType.rawValue == serviceType
                && $0.lastEtaNumeric >= minEta
            }
            .sorted {
                $0.firstEtaNumeric < $1.firstEtaNumeric
            }

            var best: (tripId: String, eta: Int)?

            for trip in candidates {
                // a stop's ETA is never earlier than its trip's first ETA, so once a
                // trip starts after the best result found, no later trip can beat it.
                if let best, trip.firstEtaNumeric >= best.eta {
                    break
                }

                for ts in trip.storedTripStops where
                ts.etaNumeric >= minEta && ts.stop.persistentModelID == stopModelId {
                    if best == nil || ts.etaNumeric < best!.eta {
                        best = (trip.id, ts.etaNumeric)
                    }
                    break   // a trip visits a given stop once
                }
            }

            if let best {
                return (best.tripId, dayStart.addingTimeInterval(TimeInterval(best.eta)))
            }
            if offset > 0 {
                searchedWithoutResult.insert(serviceType)
            }
        }
        
        return nil
    }
}
