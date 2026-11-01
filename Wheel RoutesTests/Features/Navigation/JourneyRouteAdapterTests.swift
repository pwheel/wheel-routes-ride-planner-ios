//
//  JourneyRouteAdapterTests.swift
//  Wheel RoutesTests
//

import Foundation
import Testing
import FerrostarCoreFFI
@testable import Wheel_Routes

struct JourneyRouteAdapterTests {
    private func route(useMetric: Bool = true) throws -> Route {
        try JourneyRouteAdapter.route(from: NavigationFixtures.threeSegmentJourney(), useMetric: useMetric)
    }

    @Test func geometryJoinsSegmentsWithoutDuplicatingSharedEndpoints() throws {
        #expect(try route().geometry == [
            GeographicCoordinate(lat: 52.20, lng: 0.10),
            GeographicCoordinate(lat: 52.21, lng: 0.11),
            GeographicCoordinate(lat: 52.20, lng: 0.12),
            GeographicCoordinate(lat: 52.201, lng: 0.121),
        ])
    }

    @Test func boundingBoxDistanceAndWaypointsDescribeTheWholeJourney() throws {
        let route = try route()
        #expect(route.bbox.sw == GeographicCoordinate(lat: 52.20, lng: 0.10))
        #expect(route.bbox.ne == GeographicCoordinate(lat: 52.21, lng: 0.121))
        #expect(route.distance == 820)
        #expect(route.waypoints.map(\.coordinate) == [route.geometry.first, route.geometry.last])
        #expect(route.waypoints.allSatisfy { $0.kind == .break })
    }

    @Test func eachSegmentBecomesAStepWithItsOwnMetadata() throws {
        let steps = try route().steps
        #expect(steps.map(\.distance) == [500, 300, 20])
        #expect(steps.map(\.duration) == [60, 40, 5])
        #expect(steps.map(\.roadName) == ["High Street", "Mill Road", nil])
        #expect(steps[0].geometry == [GeographicCoordinate(lat: 52.20, lng: 0.10), GeographicCoordinate(lat: 52.21, lng: 0.11)])
    }

    /// CycleStreets attaches a turn to the segment it *enters*; Ferrostar shows a step's
    /// instruction while riding it, so step N must announce segment N+1's turn.
    @Test func eachStepAnnouncesTheTurnIntoTheNextSegment() throws {
        let steps = try route().steps
        #expect(steps.map(\.instruction) == ["Turn left onto Mill Road", "Bear right", "Arrive at destination"])
        let banners = steps.map { $0.visualInstructions.first?.primaryContent }
        #expect(banners.map { $0?.maneuverType } == [.turn, .turn, .arrive])
        #expect(banners.map { $0?.maneuverModifier } == [.left, .slightRight, nil])
        #expect(banners.map { $0?.text } == steps.map(\.instruction))
    }

    @Test func bannerIsShownForTheWholeStep() throws {
        for step in try route().steps {
            #expect(step.visualInstructions.count == 1)
            #expect(step.visualInstructions.first?.triggerDistanceBeforeManeuver == step.distance)
        }
    }

    @Test func longStepsGetAnAdvanceCueAndAnImmediateCue() throws {
        let cues = try route().steps[0].spokenInstructions
        #expect(cues.map(\.text) == ["In 200 metres, turn left onto Mill Road", "Turn left onto Mill Road"])
        #expect(cues.map(\.triggerDistanceBeforeManeuver) == [200, 30])
    }

    @Test func shortStepsSkipTheAdvanceCueButKeepAClampedImmediateCue() throws {
        let cues = try route().steps[2].spokenInstructions
        #expect(cues.map(\.text) == ["You have arrived"])
        #expect(cues.map(\.triggerDistanceBeforeManeuver) == [20])
    }

    @Test func imperialAdvanceCueUsesYardsRoundedToTen() throws {
        #expect(try route(useMetric: false).steps[0].spokenInstructions.first?.text == "In 220 yards, turn left onto Mill Road")
        #expect(JourneyRouteAdapter.distancePhrase(metres: 200, useMetric: true) == "200 metres")
    }

    @Test func everySpokenCueHasAUniqueUtteranceID() throws {
        let ids = try route().steps.flatMap(\.spokenInstructions).map(\.utteranceId)
        #expect(Set(ids).count == ids.count)
    }

    @Test func rejectsJourneysWithNothingToNavigate() {
        let point = Coordinate(longitude: 0.1, latitude: 52.2)
        let journeys = [
            Journey(number: 1, plan: .balanced, lengthMetres: 0, timeSeconds: 0, segments: []),
            Journey(number: 2, plan: .balanced, lengthMetres: 0, timeSeconds: 0, segments: [
                Segment(number: 1, name: "A", distanceMetres: 0, timeSeconds: 0, turn: nil, points: [point]),
            ]),
            Journey(number: 3, plan: .balanced, lengthMetres: 0, timeSeconds: 0, segments: [
                Segment(number: 1, name: "A", distanceMetres: 0, timeSeconds: 0, turn: nil, points: [point, point]),
            ]),
        ]
        for journey in journeys {
            #expect(throws: JourneyRouteAdapterError.insufficientGeometry) {
                try JourneyRouteAdapter.route(from: journey, useMetric: true)
            }
        }
    }
}
