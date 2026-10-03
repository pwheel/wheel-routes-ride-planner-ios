//
//  JourneyRouteAdapter.swift
//  Wheel Routes
//

import Foundation
import FerrostarCoreFFI

nonisolated enum JourneyRouteAdapterError: Error, Equatable {
    /// No segments, or fewer than 2 distinct coordinates: nothing to navigate along.
    case insufficientGeometry
}

/// Translates an already-fetched CycleStreets `Journey` into Ferrostar's `Route`, so
/// navigation starts without a second routing request.
///
/// CycleStreets' `Segment.turn` is the turn made *to enter* that segment, but Ferrostar
/// shows a step's instructions while the rider is *on* it. So step N's instruction is
/// built from segment N+1's turn and name, the final step's is the arrival, and segment
/// 0's own turn (always empty in live data) is unused.
nonisolated enum JourneyRouteAdapter {
    /// Distance before a maneuver for the "In 200 metres, …" cue. Steps shorter than this
    /// get no advance cue.
    static let advanceCueDistance: Double = 200
    /// Distance before a maneuver for the immediate cue, clamped to the step's own length
    /// so short links (common in CycleStreets data) still announce their turn.
    static let immediateCueDistance: Double = 30

    static func route(from journey: Journey, useMetric: Bool) throws -> Route {
        let segments = journey.segments
        let geometry = joinedGeometry(of: segments)
        guard !segments.isEmpty, Set(geometry).count >= 2,
              let first = geometry.first, let last = geometry.last
        else { throw JourneyRouteAdapterError.insufficientGeometry }

        let steps = segments.indices.map { index in
            let next = index + 1 < segments.count ? segments[index + 1] : nil
            return step(for: segments[index], enteringNext: next, useMetric: useMetric)
        }
        return Route(
            geometry: geometry,
            bbox: boundingBox(of: geometry),
            distance: Double(journey.lengthMetres),
            waypoints: [
                Waypoint(coordinate: first, kind: .break, properties: nil),
                Waypoint(coordinate: last, kind: .break, properties: nil),
            ],
            steps: steps
        )
    }

    static func distancePhrase(metres: Double, useMetric: Bool) -> String {
        if useMetric { return "\(Int(metres.rounded())) metres" }
        let yards = Int((metres / 0.9144 / 10).rounded()) * 10
        return "\(yards) yards"
    }

    /// All segment points in order, collapsing consecutive duplicates (the endpoint one
    /// segment shares with the next).
    private static func joinedGeometry(of segments: [Segment]) -> [GeographicCoordinate] {
        var result: [GeographicCoordinate] = []
        for point in segments.flatMap({ $0.points }).map({ $0.geographicCoordinate }) where result.last != point {
            result.append(point)
        }
        return result
    }

    private static func boundingBox(of geometry: [GeographicCoordinate]) -> BoundingBox {
        let lats = geometry.map { $0.lat }
        let lngs = geometry.map { $0.lng }
        return BoundingBox(
            sw: GeographicCoordinate(lat: lats.min() ?? 0, lng: lngs.min() ?? 0),
            ne: GeographicCoordinate(lat: lats.max() ?? 0, lng: lngs.max() ?? 0)
        )
    }

    /// `next` is the segment entered at the end of `segment`, or nil for the final step.
    private static func step(for segment: Segment, enteringNext next: Segment?, useMetric: Bool) -> RouteStep {
        let distance = Double(segment.distanceMetres)
        let maneuver = next.map { TurnManeuver(cycleStreetsTurn: $0.turn) } ?? .arrival
        let text = maneuver.instructionText(roadName: next?.name)
        // Not `next == nil`: that picks `Segment`'s main-actor `Equatable` conformance, which
        // can't be used from this nonisolated code.
        let isArrival = next.map { _ in false } ?? true
        let banner = VisualInstruction(
            primaryContent: VisualInstructionContent(
                text: text, maneuverType: maneuver.type, maneuverModifier: maneuver.modifier,
                roundaboutExitDegrees: nil, laneInfo: nil, exitNumbers: []
            ),
            secondaryContent: nil,
            subContent: nil,
            // Ferrostar shows no banner until the rider is within this distance of the
            // maneuver, so use the whole step to show it from the moment the step begins.
            triggerDistanceBeforeManeuver: distance
        )
        return RouteStep(
            geometry: segment.points.map { $0.geographicCoordinate },
            distance: distance,
            duration: Double(segment.timeSeconds),
            roadName: TurnManeuver.displayableRoadName(segment.name),
            exits: [],
            instruction: text,
            visualInstructions: [banner],
            spokenInstructions: spokenCues(text: text, isArrival: isArrival, stepDistance: distance, useMetric: useMetric),
            annotations: nil,
            incidents: [],
            // Unknown: CycleStreets responses carry no country or traffic-side data, and the UK
            // (its main market) drives on the left. Ferrostar 0.57.0 only uses this for
            // roundabout rendering (CarPlay/Android Auto), so nil is honest until we derive it.
            drivingSide: nil,
            roundaboutExitNumber: nil
        )
    }

    private static func spokenCues(text: String, isArrival: Bool, stepDistance: Double, useMetric: Bool) -> [SpokenInstruction] {
        var cues: [SpokenInstruction] = []
        if stepDistance >= advanceCueDistance {
            let phrase = distancePhrase(metres: advanceCueDistance, useMetric: useMetric)
            cues.append(SpokenInstruction(
                text: "In \(phrase), \(text.prefix(1).lowercased() + text.dropFirst())",
                ssml: nil, triggerDistanceBeforeManeuver: advanceCueDistance, utteranceId: UUID()
            ))
        }
        cues.append(SpokenInstruction(
            text: isArrival ? "You have arrived" : text,
            ssml: nil, triggerDistanceBeforeManeuver: min(immediateCueDistance, stepDistance), utteranceId: UUID()
        ))
        return cues
    }
}

private extension Coordinate {
    nonisolated var geographicCoordinate: GeographicCoordinate {
        GeographicCoordinate(lat: latitude, lng: longitude)
    }
}
