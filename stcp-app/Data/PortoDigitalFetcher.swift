//
//  PortoDigitalFetcher.swift
//  stcp-app
//
//  Created by Nuno Rios on 15/09/2026.
//

//
//  PortoDigitalFetcher.swift
//  stcp-app
//
//  Created by Nuno Rios on 15/09/2026.
//
//  Raw access to PortoDigital. Returns `BusReport`s, never touches SwiftData.
//  Use BusTracker to get live buses in the app.
//

import Foundation

enum PortoDigitalFetcher {
    private static let baseURL = "https://broker.fiware.urbanplatform.portodigital.pt/v2/entities"

    private static func fetchBuses(query: String, limit: Int = 700) async throws -> [BusReport] {
        var comps = URLComponents(string: baseURL)!
        comps.queryItems = [
            URLQueryItem(name: "type", value: "Vehicle"),
            URLQueryItem(name: "options", value: "keyValues"),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "q", value: query)
        ]

        guard let url = comps.url else {
            throw URLError(.badURL)
        }

        let (data, _) = try await URLSession.shared.data(from: url)

        // decode off the main thread: the full feed has hundreds of entries
        return try await Task.detached(priority: .userInitiated) {
            try JSONDecoder().decode([Entry].self, from: data).compactMap(\.report)
        }.value
    }

    /// Retrieves all buses currently tracked by Porto Digital.
    static func getLiveBuses() async throws -> [BusReport] {
        try await fetchBuses(query: "vehicleType==bus")
    }

    /// Retrieves buses of a specific bus line tracked by Porto Digital.
    static func getLiveBuses(line: String) async throws -> [BusReport] {
        let q = "vehicleType==bus;annotations==stcp:route:\(line)"
        return try await fetchBuses(query: q, limit: 200)
    }

    /// Retrieves buses of a specific bus line and direction tracked by Porto Digital.
    static func getLiveBuses(line: String, direction: Bool) async throws -> [BusReport] {
        let sentido = direction ? 1 : 0
        let q = "vehicleType==bus;annotations==stcp:route:\(line);annotations==stcp:sentido:\(sentido)"
        return try await fetchBuses(query: q, limit: 100)
    }

    /// Retrives buses serving the given lines and tracked by PortoDigital.
    static func getLiveBuses(forLines lineIds: [String]) async throws -> [BusReport] {
        let ids = Set(lineIds).sorted()
        guard !ids.isEmpty else { return [] }

        // lines are OR-ed together in one clause
        let q = "vehicleType==bus;annotations=="
            + ids.map { "stcp:route:\($0)" }.joined(separator: ",")
        return try await fetchBuses(query: q, limit: 500)
    }
}

// MARK: - PortoDigital's format

private extension PortoDigitalFetcher {
    /// One entry of PortoDigital's response. A malformed entry becomes `nil`
    /// instead of failing the whole feed.
    nonisolated struct Entry: Decodable {
        let report: BusReport?

        init(from decoder: Decoder) throws {
            report = try? Entry.parse(decoder)
        }

        private struct GeoJSONPoint: Decodable {
            let coordinates: [Double]   // GeoJSON order: [longitude, latitude]
        }

        private enum CodingKeys: String, CodingKey {
            case fleetVehicleId, location, annotations, currentTripCount
            case speed, bearing, observationDateTime
        }

        private static func parse(_ decoder: Decoder) throws -> BusReport {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let coordinates = try c.decode(GeoJSONPoint.self, forKey: .location).coordinates
            let tags = parseAnnotations(try c.decode([String].self, forKey: .annotations))
            let rawTimestamp = try c.decode(String.self, forKey: .observationDateTime)

            guard coordinates.count == 2,
                  let lineId = tags["route"],
                  let sentido = tags["sentido"],
                  let tripId = tags["nr_viagem"],
                  let timestamp = parseTimestamp(rawTimestamp) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath, debugDescription: "Malformed bus entry"))
            }

            return try BusReport(
                id: c.decode(String.self, forKey: .fleetVehicleId),
                latitude: coordinates[1],
                longitude: coordinates[0],
                lineId: lineId,
                direction: sentido == "1",
                shift: tags["nr_turno"].flatMap { Int($0) },   // nil for "na" or missing
                reportedTripId: tripId,
                tripCount: c.decode(Int.self, forKey: .currentTripCount),
                speed: c.decode(Float.self, forKey: .speed),
                bearing: c.decode(Double.self, forKey: .bearing),
                timestamp: timestamp
            )
        }

        /// Parses "stcp:key:value" tags from the annotations array into a [key: value] dictionary.
        private static func parseAnnotations(_ annotations: [String]) -> [String: String] {
            var tags: [String: String] = [:]
            for annotation in annotations {
                let parts = annotation.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
                guard parts.count == 3 else { continue }
                tags[String(parts[1])] = String(parts[2])
            }
            return tags
        }

        // ISO8601DateFormatter is thread-safe; it just isn't annotated Sendable.
        private nonisolated(unsafe) static let isoFractional: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f
        }()
        private nonisolated(unsafe) static let iso = ISO8601DateFormatter()

        private static func parseTimestamp(_ raw: String) -> Date? {
            isoFractional.date(from: raw) ?? iso.date(from: raw)
        }
    }
}
