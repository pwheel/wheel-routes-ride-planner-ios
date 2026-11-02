//
//  JourneyTests.swift
//  Wheel RoutesTests
//

import Foundation
import Testing
@testable import Wheel_Routes

struct JourneyTests {

    // Journey/segment decoding from the real CycleStreets wire format is
    // covered by JourneyPlanDecoderTests — Journey/Segment here are plain
    // Codable value types with no bespoke decoding of their own.

    @Test func testSegmentFormattedDistance() {
        let segment = Segment(
            number: 1, name: "Mill Road",
            distanceMetres: 1500, timeSeconds: 360,
            turn: "Turn left",
            points: []
        )
        #expect(segment.formattedDistance(metric: true) == "1.5 km")
        #expect(segment.formattedDistance(metric: false) == "0.9 mi")
    }

    // MARK: - Elevation

    private func segment(_ number: Int, elevations: [Int], distances: [Int]) -> Segment {
        Segment(
            number: number, name: "Seg \(number)",
            distanceMetres: 0, timeSeconds: 0, turn: nil,
            points: elevations.indices.map { Coordinate(longitude: Double($0), latitude: 0) },
            elevations: elevations, pointDistances: distances
        )
    }

    private func journey(_ segments: [Segment]) -> Journey {
        Journey(number: 1, plan: .balanced, lengthMetres: 0, timeSeconds: 0, segments: segments)
    }

    @Test func gainLossFlatRoute() {
        let result = journey([segment(1, elevations: [10, 10, 10], distances: [0, 5, 5])]).elevationGainLoss
        #expect(result?.gain == 0); #expect(result?.loss == 0)
    }

    @Test func gainLossDoesNotDoubleCountSharedEndpoint() {
        let result = journey([
            segment(1, elevations: [10, 20], distances: [0, 5]),
            segment(2, elevations: [20, 15], distances: [0, 5]),
        ]).elevationGainLoss
        #expect(result?.gain == 10); #expect(result?.loss == 5)
    }

    @Test func gainLossHandlesNegativeElevations() {
        let result = journey([segment(1, elevations: [-2, 1, -1], distances: [0, 5, 5])]).elevationGainLoss
        #expect(result?.gain == 3); #expect(result?.loss == 2)
    }

    @Test func gainLossNilWhenAnySegmentHasNoElevations() {
        let route = journey([
            segment(1, elevations: [10, 20], distances: [0, 5]),
            segment(2, elevations: [], distances: []),
        ])
        #expect(route.elevationGainLoss == nil)
        #expect(route.elevationProfile == nil)
    }

    @Test func gainLossNilWhenCountDoesNotMatchPoints() {
        let bad = Segment(
            number: 1, name: "Bad", distanceMetres: 0, timeSeconds: 0, turn: nil,
            points: (0..<3).map { Coordinate(longitude: Double($0), latitude: 0) },
            elevations: [1, 2], pointDistances: [0, 1, 1]
        )
        let route = journey([bad])
        #expect(route.elevationGainLoss == nil)
        #expect(route.formattedElevation(metric: true) == nil)
        #expect(route.elevationProfile == nil)
    }

    @Test func gainLossNilForJourneyWithNoSegments() {
        #expect(journey([]).elevationGainLoss == nil)
    }

    @Test func profileCollapsesSharedEndpointAndAccumulatesDistance() {
        let profile = journey([
            segment(1, elevations: [10, 20], distances: [0, 5]),
            segment(2, elevations: [20, 15], distances: [0, 7]),
        ]).elevationProfile
        #expect(profile == [
            ElevationSample(distanceMetres: 0, elevationMetres: 10),
            ElevationSample(distanceMetres: 5, elevationMetres: 20),
            ElevationSample(distanceMetres: 12, elevationMetres: 15),
        ])
    }

    @Test func profileNilWhenDistancesMissingButGainLossStillAvailable() {
        let route = journey([segment(1, elevations: [10, 20], distances: [])])
        #expect(route.elevationProfile == nil)
        #expect(route.elevationGainLoss?.gain == 10)
    }

    @Test func profileNilWhenDistancesWrongLength() {
        let route = journey([segment(1, elevations: [10, 20, 30], distances: [0, 5])])
        #expect(route.elevationProfile == nil)
    }

    @Test func profileNilWhenFewerThanTwoSamples() {
        #expect(journey([segment(1, elevations: [10], distances: [0])]).elevationProfile == nil)
    }

    @Test func formattedElevationMetricAndImperial() {
        let route = journey([segment(1, elevations: [0, 145, 25], distances: [0, 5, 5])])
        #expect(route.formattedElevation(metric: true) == "↑ 145 m ↓ 120 m")
        #expect(route.formattedElevation(metric: false) == "↑ 476 ft ↓ 394 ft")
    }

}
