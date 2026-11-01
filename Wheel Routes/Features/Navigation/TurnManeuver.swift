//
//  TurnManeuver.swift
//  Wheel Routes
//

import Foundation
import FerrostarCoreFFI

/// A CycleStreets `Segment.turn` string normalised into Ferrostar's maneuver vocabulary,
/// plus the imperative verb phrase used to build banner and spoken instruction text.
///
/// Vocabulary verified against live CycleStreets responses on 2026-09-25 (see
/// `docs/superpowers/specs/2026-09-25-turn-by-turn-navigation-design.md`). Anything
/// unrecognised falls back to a plain "Continue" rather than guessing a direction.
nonisolated struct TurnManeuver: Equatable {
    let type: ManeuverType
    let modifier: ManeuverModifier?
    /// Capitalised, no trailing punctuation, e.g. "Turn left".
    let verb: String
    /// False where "onto <road>" would read wrongly (joining a roundabout, arriving).
    let includesRoadName: Bool

    static let arrival = TurnManeuver(type: .arrive, modifier: nil, verb: "Arrive at destination", includesRoadName: false)

    init(type: ManeuverType, modifier: ManeuverModifier?, verb: String, includesRoadName: Bool = true) {
        self.type = type
        self.modifier = modifier
        self.verb = verb
        self.includesRoadName = includesRoadName
    }

    init(cycleStreetsTurn turn: String?) {
        let key = (turn ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch key {
        case "straight on": self.init(type: .continue, modifier: .straight, verb: "Continue straight")
        case "bear left": self.init(type: .turn, modifier: .slightLeft, verb: "Bear left")
        case "bear right": self.init(type: .turn, modifier: .slightRight, verb: "Bear right")
        case "turn left": self.init(type: .turn, modifier: .left, verb: "Turn left")
        case "turn right": self.init(type: .turn, modifier: .right, verb: "Turn right")
        case "sharp left": self.init(type: .turn, modifier: .sharpLeft, verb: "Turn sharp left")
        case "sharp right": self.init(type: .turn, modifier: .sharpRight, verb: "Turn sharp right")
        case "join roundabout":
            self.init(type: .roundabout, modifier: nil, verb: "Enter the roundabout", includesRoadName: false)
        case "first exit", "second exit", "third exit", "fourth exit", "fifth exit":
            self.init(type: .roundabout, modifier: nil, verb: "Take the \(key)")
        default: self.init(type: .continue, modifier: nil, verb: "Continue")
        }
    }

    /// "Turn left onto Mill Road", or just the verb when the road is unnamed or the
    /// maneuver doesn't take a road name.
    func instructionText(roadName: String?) -> String {
        guard includesRoadName, let name = Self.displayableRoadName(roadName) else { return verb }
        return "\(verb) onto \(name)"
    }

    /// The segment name, trimmed, or nil when it's blank or a CycleStreets placeholder
    /// ("Short un-named link", "Un-named alley", …) that shouldn't be read out or displayed.
    static func displayableRoadName(_ name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty, !trimmed.lowercased().contains("un-named")
        else { return nil }
        return trimmed
    }
}
