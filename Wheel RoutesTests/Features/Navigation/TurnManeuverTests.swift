//
//  TurnManeuverTests.swift
//  Wheel RoutesTests
//

import Testing
import FerrostarCoreFFI
@testable import Wheel_Routes

struct TurnManeuverTests {

    /// Every value observed across 18 live CycleStreets journeys on 2026-09-25, plus the
    /// first/fourth/fifth exit values implied by the "second exit"/"third exit" pattern.
    @Test func mapsEveryKnownCycleStreetsTurn() {
        let cases: [(turn: String, type: ManeuverType, modifier: ManeuverModifier?, verb: String)] = [
            ("straight on", .continue, .straight, "Continue straight"),
            ("bear left", .turn, .slightLeft, "Bear left"),
            ("bear right", .turn, .slightRight, "Bear right"),
            ("turn left", .turn, .left, "Turn left"),
            ("turn right", .turn, .right, "Turn right"),
            ("sharp left", .turn, .sharpLeft, "Turn sharp left"),
            ("sharp right", .turn, .sharpRight, "Turn sharp right"),
            ("join roundabout", .roundabout, nil, "Enter the roundabout"),
            ("first exit", .roundabout, nil, "Take the first exit"),
            ("second exit", .roundabout, nil, "Take the second exit"),
            ("third exit", .roundabout, nil, "Take the third exit"),
            ("fourth exit", .roundabout, nil, "Take the fourth exit"),
            ("fifth exit", .roundabout, nil, "Take the fifth exit"),
        ]
        for c in cases {
            let maneuver = TurnManeuver(cycleStreetsTurn: c.turn)
            #expect(maneuver.type == c.type, "turn: \(c.turn)")
            #expect(maneuver.modifier == c.modifier, "turn: \(c.turn)")
            #expect(maneuver.verb == c.verb, "turn: \(c.turn)")
        }
    }

    @Test func matchingIgnoresCaseAndSurroundingWhitespace() {
        #expect(TurnManeuver(cycleStreetsTurn: "  Turn Left \n") == TurnManeuver(cycleStreetsTurn: "turn left"))
    }

    @Test func nilEmptyAndUnrecognisedTurnsFallBackToContinue() {
        for turn in [nil, "", "   ", "double-back", "something new"] as [String?] {
            let maneuver = TurnManeuver(cycleStreetsTurn: turn)
            #expect(maneuver.type == .continue)
            #expect(maneuver.modifier == nil)
            #expect(maneuver.verb == "Continue")
        }
    }

    @Test func instructionTextNamesTheRoadBeingEntered() {
        #expect(TurnManeuver(cycleStreetsTurn: "turn left").instructionText(roadName: "Mill Road") == "Turn left onto Mill Road")
        #expect(TurnManeuver(cycleStreetsTurn: "second exit").instructionText(roadName: "Hills Road") == "Take the second exit onto Hills Road")
        #expect(TurnManeuver(cycleStreetsTurn: nil).instructionText(roadName: "Hills Road") == "Continue onto Hills Road")
    }

    @Test func instructionTextOmitsBlankAndUnnamedRoads() {
        let maneuver = TurnManeuver(cycleStreetsTurn: "turn left")
        for name in [nil, "", "   ", "Short un-named link", "Un-named alley"] as [String?] {
            #expect(maneuver.instructionText(roadName: name) == "Turn left", "name: \(name ?? "nil")")
        }
    }

    @Test func joiningARoundaboutNeverNamesTheRoad() {
        #expect(TurnManeuver(cycleStreetsTurn: "join roundabout").instructionText(roadName: "Station Road") == "Enter the roundabout")
    }

    @Test func arrivalIsAnArriveManeuverThatIgnoresRoadName() {
        #expect(TurnManeuver.arrival.type == .arrive)
        #expect(TurnManeuver.arrival.modifier == nil)
        #expect(TurnManeuver.arrival.instructionText(roadName: "Mill Road") == "Arrive at destination")
    }

    @Test func displayableRoadNameFiltersPlaceholders() {
        #expect(TurnManeuver.displayableRoadName("Mill Road") == "Mill Road")
        #expect(TurnManeuver.displayableRoadName("  Mill Road ") == "Mill Road")
        #expect(TurnManeuver.displayableRoadName("Short un-named link") == nil)
        #expect(TurnManeuver.displayableRoadName("") == nil)
        #expect(TurnManeuver.displayableRoadName(nil) == nil)
    }
}
