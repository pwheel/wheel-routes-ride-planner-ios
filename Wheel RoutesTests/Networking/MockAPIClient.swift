//
//  MockAPIClient.swift
//  Wheel RoutesTests
//

import Foundation
import CoreLocation
@testable import Wheel_Routes

final class MockAPIClient: APIClientProtocol {
    var journeyToReturn: Journey?
    var gpxDataToReturn = Data("gpx content".utf8)
    var shouldThrow: Error?
    var journeysByPlan: [RoutePlan: Journey] = [:]
    var errorsByPlan: [RoutePlan: Error] = [:]
    /// Every `planJourney` request, in order, recorded before any configured error is thrown,
    /// matching the real client, which has already sent the request by the time it fails.
    private(set) var planJourneyCalls: [(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, plan: RoutePlan)] = []

    private func checkThrow() throws {
        if let e = shouldThrow { throw e }
    }

    func planJourney(from: CLLocationCoordinate2D,
                     to: CLLocationCoordinate2D,
                     plan: RoutePlan) async throws -> Journey {
        planJourneyCalls.append((from: from, to: to, plan: plan))
        if let error = errorsByPlan[plan] { throw error }
        try checkThrow()
        return journeysByPlan[plan] ?? journeyToReturn ?? makeJourney(plan: plan)
    }

    func downloadGPX(journeyID: Int, plan: RoutePlan) async throws -> Data {
        try checkThrow()
        return gpxDataToReturn
    }

    func reloadJourney(itineraryID: Int, plan: RoutePlan) async throws -> Journey {
        try checkThrow()
        return journeyToReturn ?? makeJourney(id: itineraryID, plan: plan)
    }

    // MARK: - Helpers

    func makeJourney(id: Int = 1, plan: RoutePlan = .balanced) -> Journey {
        Journey(
            number: id, plan: plan, lengthMetres: 4200, timeSeconds: 1080,
            segments: [
                Segment(number: 1, name: "High Street", distanceMetres: 450,
                        timeSeconds: 120, turn: "Straight on",
                        points: [
                            Coordinate(longitude: 0.1132, latitude: 52.2054),
                            Coordinate(longitude: 0.1140, latitude: 52.2060),
                        ])
            ]
        )
    }
}
