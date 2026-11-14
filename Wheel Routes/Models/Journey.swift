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

    /// True when there is at least one segment and every segment has exactly one elevation per point.
    private var hasCompleteElevations: Bool {
        !segments.isEmpty && segments.allSatisfy { !$0.elevations.isEmpty && $0.elevations.count == $0.points.count }
    }

    /// Raw sum of rises and falls (no smoothing), summed within each segment so a shared
    /// segment endpoint is not double counted. `nil` when elevation data is missing or mismatched.
    var elevationGainLoss: (gain: Int, loss: Int)? {
        guard hasCompleteElevations else { return nil }
        var gain = 0, loss = 0
        for segment in segments {
            for (previous, next) in zip(segment.elevations, segment.elevations.dropFirst()) {
                let delta = next - previous
                if delta > 0 { gain += delta } else { loss -= delta }
            }
        }
        return (gain, loss)
    }

    /// Elevation against cumulative distance along the route. `nil` under the same conditions as
    /// `elevationGainLoss`, or when per-point distances are missing/mismatched or there are fewer than 2 samples.
    var elevationProfile: [ElevationSample]? {
        guard hasCompleteElevations,
              segments.allSatisfy({ $0.pointDistances.count == $0.points.count }) else { return nil }
        var samples: [ElevationSample] = []
        var runningDistance = 0.0
        for (segmentIndex, segment) in segments.enumerated() {
            for index in segment.elevations.indices {
                runningDistance += Double(segment.pointDistances[index])
                // The first point of each later segment repeats the previous segment's last point.
                if segmentIndex > 0 && index == 0 { continue }
                samples.append(ElevationSample(distanceMetres: runningDistance, elevationMetres: segment.elevations[index]))
            }
        }
        return samples.count >= 2 ? samples : nil
    }

    func formattedElevation(metric: Bool) -> String? {
        guard let (gain, loss) = elevationGainLoss else { return nil }
        return "↑ \(Self.formattedHeight(metres: gain, metric: metric)) ↓ \(Self.formattedHeight(metres: loss, metric: metric))"
    }

    static func formattedHeight(metres: Int, metric: Bool) -> String {
        if metric { return "\(metres) m" }
        return "\(Int((Double(metres) * 3.28084).rounded())) ft"
    }
}

struct ElevationSample: Equatable {
    let distanceMetres: Double
    let elevationMetres: Int
}
