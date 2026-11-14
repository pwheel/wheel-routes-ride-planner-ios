//
//  JourneyPlanDecoderTests.swift
//  Wheel RoutesTests
//

import Testing
import Foundation
@testable import Wheel_Routes

struct JourneyPlanDecoderTests {

    @Test func decodesRouteMarkerIntoJourney() throws {
        let journey = try JourneyPlanDecoder.decode(sampleJSON, requestedPlan: .balanced)
        #expect(journey.number == 123700734)
        #expect(journey.plan == .quietest)
        #expect(journey.lengthMetres == 6372)
        #expect(journey.timeSeconds == 1914)
        #expect(journey.segments.count == 2)
    }

    @Test func decodesSegmentFields() throws {
        let journey = try JourneyPlanDecoder.decode(sampleJSON, requestedPlan: .balanced)
        let first = journey.segments[0]
        #expect(first.name == "Senate House Hill")
        #expect(first.distanceMetres == 25)
        #expect(first.timeSeconds == 15)
        #expect(first.number == 1)
    }

    @Test func mapsEmptyTurnStringToNil() throws {
        let journey = try JourneyPlanDecoder.decode(sampleJSON, requestedPlan: .balanced)
        #expect(journey.segments[0].turn == nil)
    }

    @Test func preservesNonEmptyTurnInstruction() throws {
        let journey = try JourneyPlanDecoder.decode(sampleJSON, requestedPlan: .balanced)
        #expect(journey.segments[1].turn == "turn right")
    }

    @Test func parsesSpaceSeparatedPoints() throws {
        let journey = try JourneyPlanDecoder.decode(sampleJSON, requestedPlan: .balanced)
        let points = journey.segments[0].points
        #expect(points.count == 3)
        #expect(points[0].longitude == 0.11783)
        #expect(points[0].latitude == 52.20530)
        #expect(points[2].longitude == 0.11786)
        #expect(points[2].latitude == 52.20553)
    }

    @Test func fallsBackToRequestedPlanWhenPlanFieldUnrecognized() throws {
        let journey = try JourneyPlanDecoder.decode(sampleJSONWithMissingPlan, requestedPlan: .fastest)
        #expect(journey.plan == .fastest)
    }

    @Test func throwsWhenNoRouteMarkerPresent() {
        #expect(throws: (any Error).self) {
            try JourneyPlanDecoder.decode(sampleJSONWithNoRouteMarker, requestedPlan: .balanced)
        }
    }

    @Test func parsesPerPointElevationsAndDistances() throws {
        let segments = try JourneyPlanDecoder.decode(liveElevationJSON, requestedPlan: .balanced).segments
        #expect(segments[0].elevations == [25, 24, 24, 24])
        #expect(segments[0].pointDistances == [0, 29, 4, 9])
        #expect(segments[1].elevations == [24, 24])
    }

    @Test func missingElevationAttributesDecodeAsEmpty() throws {
        let segments = try JourneyPlanDecoder.decode(sampleJSON, requestedPlan: .balanced).segments
        #expect(segments[0].elevations == [])
        #expect(segments[0].pointDistances == [])
    }

    @Test func skipsMalformedElevationValues() throws {
        let segments = try JourneyPlanDecoder.decode(elevationJSON(#""25,x,24""#), requestedPlan: .balanced).segments
        #expect(segments[0].elevations == [25, 24])
    }

    @Test func parsesNegativeElevations() throws {
        let segments = try JourneyPlanDecoder.decode(elevationJSON(#""-2,1""#), requestedPlan: .balanced).segments
        #expect(segments[0].elevations == [-2, 1])
    }

    @Test(arguments: ["{}", "[]", "25"])
    func nonStringElevationAttributesDoNotThrow(rawValue: String) throws {
        let segments = try JourneyPlanDecoder.decode(elevationJSON(rawValue), requestedPlan: .balanced).segments
        #expect(segments[0].elevations == [])
    }
}

/// A one-segment response whose `elevations` attribute is the given raw JSON value.
private func elevationJSON(_ elevations: String) -> Data {
    Data("""
    {"marker": [
        {"@attributes": {"itinerary": "1", "plan": "balanced", "length": "10", "time": "5", "type": "route"}},
        {"@attributes": {"type": "segment", "name": "A", "distance": "10", "time": "5", "turn": "",
                         "points": "0.1,52.2 0.2,52.3", "elevations": \(elevations)}}
    ]}
    """.utf8)
}

private let liveElevationJSON = Data("""
{"marker": [
    {"@attributes": {"itinerary": "124337882", "plan": "balanced", "length": "3240", "time": "1880", "type": "route"}},
    {"@attributes": {"type": "segment", "name": "Abbey Churchyard", "distance": "42", "time": "41", "turn": "",
        "points": "-2.35975,51.38126 -2.36015,51.38118 -2.36021,51.38118 -2.36024,51.38126",
        "elevations": "25,24,24,24", "distances": "0,29,4,9"}},
    {"@attributes": {"type": "segment", "name": "Pedestrian area", "distance": "8", "time": "11", "turn": "turn left",
        "points": "-2.36024,51.38126 -2.36035,51.38124", "elevations": "24,24", "distances": "0,8"}},
    {"@attributes": {"type": "segment", "name": "Stall Street", "distance": "32", "time": "40", "turn": "turn right",
        "points": "-2.36035,51.38124 -2.36041,51.38141 -2.36044,51.3815 -2.36045,51.38153",
        "elevations": "24,25,25,25", "distances": "0,19,10,3"}}
]}
""".utf8)

/// Trimmed from a real captured `journey.json` response — field names,
/// string-typing, and the "@attributes" wrapper match the live API exactly.
private let sampleJSON = """
{
    "marker": [
        {
            "@attributes": {
                "itinerary": "123700734",
                "plan": "quietest",
                "length": "6372",
                "time": "1914",
                "type": "route"
            }
        },
        {
            "@attributes": {
                "name": "Senate House Hill",
                "distance": "25",
                "time": "15",
                "turn": "",
                "points": "0.11783,52.20530 0.11783,52.20541 0.11786,52.20553",
                "type": "segment"
            }
        },
        {
            "@attributes": {
                "name": "St Mary's Street",
                "distance": "60",
                "time": "16",
                "turn": "turn right",
                "points": "0.11786,52.20553 0.118,52.2055",
                "type": "segment"
            }
        }
    ],
    "waypoint": []
}
""".data(using: .utf8)!

private let sampleJSONWithMissingPlan = """
{
    "marker": [
        {
            "@attributes": {
                "itinerary": "1",
                "length": "100",
                "time": "60",
                "type": "route"
            }
        }
    ]
}
""".data(using: .utf8)!

private let sampleJSONWithNoRouteMarker = """
{
    "marker": [
        {
            "@attributes": {
                "name": "Orphan Segment",
                "distance": "10",
                "time": "5",
                "type": "segment"
            }
        }
    ]
}
""".data(using: .utf8)!
