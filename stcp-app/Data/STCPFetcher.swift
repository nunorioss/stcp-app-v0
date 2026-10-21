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

    /// Gets live ETAs for a bus stop from the STCP API.
    static func getLiveETAs(for stopId: String) async throws -> [String: Date] {
        guard let url = URL(string: "https://stcp.pt/api/stops/\(stopId)/realtime") else {
            throw URLError(.badURL)
        }
        let request = URLRequest(url: url, timeoutInterval: 20)
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try decoder.decode(Response.self, from: data)
        
        // Replace every tripId's magic tripNo with the stored one
        let magic = DataStore.globalTripNo

        var result: [String: Date] = [:]
        result.reserveCapacity(response.arrivals.count)

        for item in response.arrivals {
            var parts = item.tripId.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard parts.count > 1 else { continue }
            parts[1] = magic

            let key = parts.joined(separator: "|")
            result[key] = min(result[key] ?? item.eta, item.eta)
        }
        return result
    }
}
