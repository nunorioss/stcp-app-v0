//
//  stcp_appTests.swift
//  stcp-appTests
//
//  Created by Nuno Rios on 06/06/2026.
//

import Testing
@testable import stcp_app
import Foundation

struct stcp_appTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
        //let buses = try await PortoDigitalFetcher.getLiveBuses()
        //print(buses)
        
        /*let line = await DataStore.getBusLine(id: "202")!
        let route = line.routes[3]
    
        
        for trip in route.trips {
            print("\(trip.id)   AT   \(trip.tripStops[0].etaNumeric.gtfsTimeString)   AT \(trip.serviceType.serviceId)")
        }
        
        print(route.headsign)
        
        print(route.trips.count)*/
        
        /*let weekday = "DIAS UTEIS"

        let lines = await DataStore.getBusLines()

        let matches = lines
            .flatMap { line in
                line.routes
                    .filter { !$0.isMasterRoute }
                    .map { route in
                        (line: line,
                         route: route,
                         trips: route.trips.filter { $0.serviceType.serviceId == weekday })
                    }
            }
            .filter { $0.trips.count < 10 }
            .sorted { $0.trips.count < $1.trips.count }

        for (line, route, trips) in matches {
            print("Line \(line.shortName) | dir \(route.direction ? 1 : 0) | \(route.headsign) | \(trips.count) trips")

            for trip in trips {
                print("    \(trip.id)   AT   \(trip.tripStops.first?.etaNumeric.gtfsTimeString ?? "n/a")   AT \(trip.serviceType.serviceId)")
            }
        }*/
        
        /*let live603 = try await PortoDigitalFetcher.getLiveBuses(line: "603", direction: false)
        let scheduled603 = await DataStore.getScheduledArrivalsByStop(line: DataStore.getBusLine(id: "603")!, direction: false, within: 60)
        
        print(live603[0].tripId)
        
        print("\n\n")
        print(scheduled603["JFPD2"])*/
       /* let stop = await DataStore.getBusStop(id: "ENX2")!
        let result = try await Estimator.estimate(for: stop)
        await print(DataStore.getServiceType())*/
        let stop = await DataStore.getBusStop(id: "IPO4")!
        await DataStore.benchmarkScheduledTrips(stops: [stop])
    }


    

}

extension Int {
    var gtfsTimeString: String {
        let hours = self / 3_600
        let minutes = (self % 3_600) / 60
        let seconds = self % 60

        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
