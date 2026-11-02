//
//  Journey.swift
//  Wheel Routes
//

import Foundation
import CoreLocation

enum RoutePlan: String, Codable, CaseIterable {
    case balanced, quietest, fastest

    var displayName: String {
        switch self {
        case .balanced: return "Balanced"
        case .quietest: return "Quietest"
        case .fastest:  return "Fastest"
        }
    }
}

struct Coordinate: Codable, Equatable {
    let longitude: Double
    let latitude: Double

    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct Segment: Codable, Identifiable, Equatable {
    let number: Int
    let name: String
    let distanceMetres: Int
    let timeSeconds: Int
    let turn: String?
    let points: [Coordinate]
    /// Per-point elevation in metres, parallel to `points`. Empty when the API omits it.
    var elevations: [Int] = []
    /// Per-point distance in metres from the previous point, parallel to `points` (first is 0). Empty when omitted.
    var pointDistances: [Int] = []

    var id: Int { number }

    func formattedDistance(metric: Bool) -> String {
        if metric {
            let km = Double(distanceMetres) / 1000.0
            return String(format: "%.1f km", km)
        } else {
            let miles = Double(distanceMetres) / 1609.344
            return String(format: "%.1f mi", miles)
        }
    }
}

struct Journey: Codable, Identifiable, Equatable {
    let number: Int
    let plan: RoutePlan
    let lengthMetres: Int
    let timeSeconds: Int
    let segments: [Segment]

    var id: Int { number }

    func formattedDistance(metric: Bool) -> String {
        if metric {
            let km = Double(lengthMetres) / 1000.0
            return String(format: "%.1f km", km)
        } else {
            let miles = Double(lengthMetres) / 1609.344
            return String(format: "%.1f mi", miles)
        }
    }

    func formattedDuration() -> String {
        let minutes = timeSeconds / 60
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) hr \(minutes % 60) min"
    }

    var allCoordinates: [CLLocationCoordinate2D] {
        segments.flatMap(\.points).map(\.clCoordinate)
    }
}
