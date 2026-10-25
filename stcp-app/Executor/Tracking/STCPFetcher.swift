//
//  STCPFetcher.swift
//  stcp-app
//
//  Created by Nuno Rios on 07/06/2026.
//

import Foundation

enum STCPFetcher {
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private struct Response: Decodable {
        let arrivals: [Item]

        struct Item: Decodable {
            let tripId: String
            let eta: Date

            enum CodingKeys: String, CodingKey {
                case tripId = "trip_id"
                case eta = "estimated_arrival_time"
            }
        }
    }
    
    nonisolated struct VehiclesSnapshot: Sendable, Decodable {
        let vehicles: [Vehicle]
        let timestamp: Date // when STCP answered
    }

    // A vehicle from STCP's network feed, identified by a tripId.
    nonisolated struct Vehicle: Sendable, Decodable, Equatable {
        let tripId: String
        let lineId: String
        let direction: Bool
        let latitude: Double
        let longitude: Double
        let bearing: Double

        enum CodingKeys: String, CodingKey {
            case tripId = "vehicle_id"
            case lineId = "route_id"
            case direction = "direction_id"
            case latitude, longitude, bearing
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            tripId = try c.decode(String.self, forKey: .tripId)
            lineId = try c.decode(String.self, forKey: .lineId)
            direction = try c.decode(Int.self, forKey: .direction) != 0
            latitude = try c.decode(Double.self, forKey: .latitude)
            longitude = try c.decode(Double.self, forKey: .longitude)
            bearing = try c.decode(Double.self, forKey: .bearing)
        }
    }
    
    //MARK: - API Calls

    /// Gets a snapshot of live buses from STCP.
    /// Gives up after `timeout`.
    static func getLiveVehicles(lineIds: [String]? = nil, // if nil, we fetch all vehicles
                                timeout: TimeInterval = 10) async throws -> VehiclesSnapshot {
        var comps = URLComponents(string: "https://stcp.pt/api/network/vehicles")!
        if let lineIds {
            comps.queryItems = [URLQueryItem(name: "route_ids",
                                             value: Set(lineIds).sorted().joined(separator: ","))]
        }
        
        guard let url = comps.url else {
            throw URLError(.badURL)
        }
        let request = URLRequest(url: url, timeoutInterval: timeout)
        let (data, _) = try await URLSession.shared.data(for: request)
        let snapshot = try decoder.decode(VehiclesSnapshot.self, from: data)

        //a bus is sometimes listed by its ID ("3262") instead of a trip id (bug?)
        //there's no trip to match it to, so drop it
        return VehiclesSnapshot(vehicles: snapshot.vehicles.filter { $0.tripId.contains("|") },
                                timestamp: snapshot.timestamp)
    }

    /// Gets live ETAs for a bus stop from STCP.
    static func getLiveETAs(for stopId: String) async throws -> [String: Date] {
        guard let url = URL(string: "https://stcp.pt/api/stops/\(stopId)/realtime") else {
            throw URLError(.badURL)
        }
        let request = URLRequest(url: url, timeoutInterval: 20)
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try decoder.decode(Response.self, from: data)
        
        //key by the stored trip id, instead of the reported one
        // (in case the store is stale and has a different trip version number)
        return await MainActor.run {
            var result: [String: Date] = [:]
            result.reserveCapacity(response.arrivals.count)

            for item in response.arrivals {
                let key = DataStore.getLiveTrip(id: item.tripId)?.id ?? item.tripId
                result[key] = min(result[key] ?? item.eta, item.eta)
            }
            return result
        }
    }
}
