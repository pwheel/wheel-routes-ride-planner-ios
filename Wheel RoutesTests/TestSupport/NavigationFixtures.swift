//
//  NavigationFixtures.swift
//  Wheel RoutesTests
//

@testable import Wheel_Routes

enum NavigationFixtures {
    /// High Street (500 m) → turn left onto Mill Road (300 m) → bear right onto a 20 m
    /// "Short un-named link". Segment 0's turn is nil, as in live data (the decoder maps
    /// CycleStreets' empty string to nil). Consecutive segments share their joining point.
    static func threeSegmentJourney() -> Journey {
        Journey(number: 42, plan: .quietest, lengthMetres: 820, timeSeconds: 105, segments: [
            Segment(number: 1, name: "High Street", distanceMetres: 500, timeSeconds: 60, turn: nil,
                    points: [Coordinate(longitude: 0.10, latitude: 52.20), Coordinate(longitude: 0.11, latitude: 52.21)]),
            Segment(number: 2, name: "Mill Road", distanceMetres: 300, timeSeconds: 40, turn: "turn left",
                    points: [Coordinate(longitude: 0.11, latitude: 52.21), Coordinate(longitude: 0.12, latitude: 52.20)]),
            Segment(number: 3, name: "Short un-named link", distanceMetres: 20, timeSeconds: 5, turn: "bear right",
                    points: [Coordinate(longitude: 0.12, latitude: 52.20), Coordinate(longitude: 0.121, latitude: 52.201)]),
        ])
    }
}
