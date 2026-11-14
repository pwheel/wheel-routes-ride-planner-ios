//
//  JourneyPlanDecoder.swift
//  Wheel Routes
//

import Foundation

/// Decodes the CycleStreets v1 `journey.json` response into a `Journey`.
///
/// The real API returns a flat `marker` array where every field is
/// string-typed and nested under `"@attributes"`: the first marker with
/// `type == "route"` carries the journey summary, and markers with
/// `type == "segment"` carry turn-by-turn steps. Coordinates arrive as a
/// single space-separated `"lon,lat lon,lat ..."` string per segment.
/// Segments also carry comma-separated per-point `elevations` and `distances`
/// strings; these are decoded leniently (a non-string or malformed value yields
/// an empty/shorter array rather than failing the whole decode).
enum JourneyPlanDecoder {

    enum DecodingFailure: Error {
        case missingRouteMarker
        case malformedRouteFields
        case malformedSegmentFields
    }

    private struct RawResponse: Decodable {
        let marker: [RawMarker]
    }

    private struct RawMarker: Decodable {
        let attributes: RawAttributes
        enum CodingKeys: String, CodingKey { case attributes = "@attributes" }
    }

    private struct RawAttributes: Decodable {
        let type: String
        let itinerary: String?
        let plan: String?
        let length: String?
        let time: String?
        let name: String?
        let distance: String?
        let turn: String?
        let points: String?
        let elevations: LossyString?
        let distances: LossyString?
    }

    /// Decodes to `nil` instead of throwing when the JSON value isn't a string.
    private struct LossyString: Decodable {
        let value: String?
        init(from decoder: Decoder) throws {
            value = try? decoder.singleValueContainer().decode(String.self)
        }
    }

    static func decode(_ data: Data, requestedPlan: RoutePlan) throws -> Journey {
        let raw = try JSONDecoder().decode(RawResponse.self, from: data)

        guard let route = raw.marker.first(where: { $0.attributes.type == "route" })?.attributes
        else { throw DecodingFailure.missingRouteMarker }

        guard let itineraryString = route.itinerary, let number = Int(itineraryString),
              let lengthString = route.length, let lengthMetres = Int(lengthString),
              let timeString = route.time, let timeSeconds = Int(timeString)
        else { throw DecodingFailure.malformedRouteFields }

        let plan = route.plan.flatMap(RoutePlan.init(rawValue:)) ?? requestedPlan

        let segments = try raw.marker
            .filter { $0.attributes.type == "segment" }
            .enumerated()
            .map { index, marker -> Segment in
                let attributes = marker.attributes
                guard let distanceString = attributes.distance, let distanceMetres = Int(distanceString),
                      let segmentTimeString = attributes.time, let segmentTimeSeconds = Int(segmentTimeString)
                else { throw DecodingFailure.malformedSegmentFields }

                let turn = (attributes.turn?.isEmpty ?? true) ? nil : attributes.turn
                return Segment(
                    number: index + 1,
                    name: attributes.name ?? "",
                    distanceMetres: distanceMetres,
                    timeSeconds: segmentTimeSeconds,
                    turn: turn,
                    points: parsePoints(attributes.points ?? ""),
                    elevations: parseIntegers(attributes.elevations?.value),
                    pointDistances: parseIntegers(attributes.distances?.value)
                )
            }

        return Journey(
            number: number,
            plan: plan,
            lengthMetres: lengthMetres,
            timeSeconds: timeSeconds,
            segments: segments
        )
    }

    /// Parses a `"25,24,x"` string into integers, skipping malformed entries.
    private static func parseIntegers(_ raw: String?) -> [Int] {
        (raw ?? "").split(separator: ",").compactMap { Int($0) }
    }

    /// Parses a `"lon,lat lon,lat ..."` string into coordinates.
    private static func parsePoints(_ raw: String) -> [Coordinate] {
        raw.split(separator: " ").compactMap { pair in
            let parts = pair.split(separator: ",")
            guard parts.count == 2, let lon = Double(parts[0]), let lat = Double(parts[1])
            else { return nil }
            return Coordinate(longitude: lon, latitude: lat)
        }
    }
}
