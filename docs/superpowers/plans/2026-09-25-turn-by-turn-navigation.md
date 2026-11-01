# Turn-by-Turn Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Live turn-by-turn guidance along a planned `Journey`: maneuver banners, progress, spoken cues and automatic rerouting through CycleStreets, built on Ferrostar (GitHub #20).

**Architecture:** A pure `JourneyRouteAdapter` converts the already-fetched `Journey` into Ferrostar's `Route`, so starting navigation needs no extra routing request. `NavigationViewModel` owns a `FerrostarCore` configured with a `WheelRoutesRerouteProvider` (a `CustomRouteProvider` that re-plans through the existing `APIClientProtocol`). `NavigationScreen` hosts Ferrostar's bundled `DynamicallyOrientingNavigationView`, always rendered with MapLibre in an OSM style, and is presented full-screen from `MapView`'s new Start button.

**Tech Stack:** Swift 5 language mode, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, SwiftUI, Swift Testing, Ferrostar 0.57.0 (`FerrostarCore`, `FerrostarCoreFFI`, `FerrostarMapLibreUI`, `FerrostarSwiftUI` modules), `maplibre/swiftui-dsl` 0.25.0 (already present).

**Design spec:** `docs/superpowers/specs/2026-09-25-turn-by-turn-navigation-design.md`. Read it before starting.

## Global Constraints

- Work only in the worktree `.worktrees/turn-by-turn-navigation`, on branch `feat/turn-by-turn-navigation`. Never commit to `main`.
- Ferrostar is pinned with `kind = exactVersion; version = 0.57.0;`. Never use a version range. The existing `swiftui-dsl` exact pin at `0.25.0` stays unchanged.
- Link only the `FerrostarCore` and `FerrostarMapLibreUI` products, and only to the app target, never the test target. The `FerrostarCoreFFI` and `FerrostarSwiftUI` modules can be imported because those products ship them.
- Tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`), not XCTest. Work TDD: write a failing test, watch it fail for the right reason, implement, watch it pass.
- New source files go under the synced folders (`Wheel Routes/…`, `Wheel RoutesTests/…`), where they're picked up automatically. **Never hand-edit `project.pbxproj` to add source files.** The one sanctioned pbxproj edit is Task 1's package reference.
- Every `xcodebuild` call needs `-skipMacroValidation`. Destination: `platform=iOS Simulator,name=iPhone 17`.
- Full test command: `xcodebuild test -project "Wheel Routes.xcodeproj" -scheme "Wheel Routes" -destination "platform=iOS Simulator,name=iPhone 17" -skipMacroValidation`
- Targeted test command: append `-only-testing:"Wheel RoutesTests/<SuiteName>"` to the full command.
- If a newly added test doesn't appear in the output, the build may be stale (see `CLAUDE.md`). `touch` the changed files and rerun. Don't retry resource-related failures in a tight loop.
- Pure navigation types (`TurnManeuver`, `JourneyRouteAdapter`, `WheelRoutesRerouteProvider`) are declared `nonisolated`, because Ferrostar calls into them off the main actor. The project uses Swift 5 language mode, so concurrency diagnostics are warnings. **New warnings are acceptable. New errors are not.** Don't silence errors with `@unchecked Sendable` or `nonisolated(unsafe)`; report them instead.
- Values from the spec:
  - Deviation thresholds: 25 m minimum horizontal accuracy and 25 m maximum acceptable deviation.
  - Spoken cues: advance cue at 200 m; immediate cue at `min(30 m, step distance)`.
  - Visual trigger: the step's full distance.
  - Messages: reroute failure is `"Couldn't recalculate route"`, the recalculating banner is `"Recalculating route…"`, and the arrival card says `"You've arrived"`.
  - `@AppStorage` keys: `"navigationMuted"` (default `false`) and the existing `"useMetric"` (default `true`).
- `docs/SPEC.md` is updated **in the same commit** as each contract it describes (see `docs/REVIEW_CHECKLIST.md`).
- End every commit message with the trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## File Structure

| File | Status | Responsibility |
|---|---|---|
| `Wheel Routes.xcodeproj/project.pbxproj` | Modify (Task 1 only) | Ferrostar package reference and product links |
| `Wheel Routes.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` | Modify | Resolved Ferrostar pin |
| `CLAUDE.md` | Modify | Ferrostar supply-chain note |
| `Wheel Routes/Features/Map/MapStyleOption.swift` | Modify | `navigationStyle` |
| `Wheel Routes/Features/Navigation/TurnManeuver.swift` | Create | CycleStreets turn string → Ferrostar maneuver and instruction text |
| `Wheel Routes/Features/Navigation/JourneyRouteAdapter.swift` | Create | `Journey` → Ferrostar `Route` |
| `Wheel Routes/Features/Navigation/WheelRoutesRerouteProvider.swift` | Create | Ferrostar `CustomRouteProvider` for rerouting via CycleStreets |
| `Wheel Routes/Features/Navigation/NavigationViewModel.swift` | Create | `FerrostarCore` session lifecycle, reroute handling, mute, idle timer |
| `Wheel Routes/Features/Navigation/NavigationScreen.swift` | Create | Full-screen Ferrostar UI, banners, arrival card, permission-lost alert |
| `Wheel Routes/Features/Map/MapViewModel.swift` | Modify | `prepareNavigation()` |
| `Wheel Routes/Features/Map/MapView.swift` | Modify | Start button and `.fullScreenCover` |
| `Wheel RoutesTests/TestSupport/WaitUntil.swift` | Create | Shared `waitUntil` polling helper, moved out of `MapViewModelTests` |
| `Wheel RoutesTests/TestSupport/NavigationFixtures.swift` | Create | Shared 3-segment `Journey` fixture |
| `Wheel RoutesTests/Networking/MockAPIClient.swift` | Modify | Records `planJourney` calls |
| `Wheel RoutesTests/Features/Navigation/*Tests.swift` | Create | Tests for each navigation unit |
| `Wheel RoutesTests/Features/MapStyleOptionTests.swift`, `MapViewModelTests.swift` | Modify | New cases |
| `docs/SPEC.md` | Modify | Architecture, Navigation section, Map screen, tests, limitations |

---

### Task 1: Add the Ferrostar dependency

**Files:**
- Modify: `Wheel Routes.xcodeproj/project.pbxproj`
- Modify: `Wheel Routes.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` (generated)
- Modify: `CLAUDE.md`
- Modify: `docs/SPEC.md` (Architecture)
- Temporary (not committed): `Wheel RoutesTests/FerrostarImportSmokeTests.swift`

**Interfaces:**
- Produces: the app target can `import FerrostarCore`, `FerrostarCoreFFI`, `FerrostarMapLibreUI` and `FerrostarSwiftUI`. The test target can `import FerrostarCore` and `FerrostarCoreFFI`; this is verified in Step 5 and every later task depends on it.

- [ ] **Step 1: Confirm the new object IDs are unused**

```bash
grep -c "5BF0E1A0301700000000A00" "Wheel Routes.xcodeproj/project.pbxproj"
```
Expected: `0`.

- [ ] **Step 2: Add the package reference and product links to `project.pbxproj`**

Make five insertions, each placed next to the existing `swiftui-dsl` entries:

1. In `/* Begin PBXBuildFile section */`, after the `MapLibreSwiftUI in Frameworks` line:
```
		5BF0E1A2301700000000A001 /* FerrostarCore in Frameworks */ = {isa = PBXBuildFile; productRef = 5BF0E1A1301700000000A001 /* FerrostarCore */; };
		5BF0E1A4301700000000A001 /* FerrostarMapLibreUI in Frameworks */ = {isa = PBXBuildFile; productRef = 5BF0E1A3301700000000A001 /* FerrostarMapLibreUI */; };
```
2. In the **app** target's Frameworks build phase (`5BCAB58B2FF461BD0070DF6C /* Frameworks */`), after `5BDC1C97301652C100D06D8C /* MapLibreSwiftMacros in Frameworks */,`:
```
				5BF0E1A2301700000000A001 /* FerrostarCore in Frameworks */,
				5BF0E1A4301700000000A001 /* FerrostarMapLibreUI in Frameworks */,
```
3. In the **app** target's `packageProductDependencies` (the list containing `5BDC1C98301652C100D06D8C /* MapLibreSwiftUI */`), after that line:
```
				5BF0E1A1301700000000A001 /* FerrostarCore */,
				5BF0E1A3301700000000A001 /* FerrostarMapLibreUI */,
```
4. In the project's `packageReferences`, after the `swiftui-dsl` line:
```
				5BF0E1A0301700000000A001 /* XCRemoteSwiftPackageReference "ferrostar" */,
```
5. Before `/* End XCRemoteSwiftPackageReference section */`:
```
		5BF0E1A0301700000000A001 /* XCRemoteSwiftPackageReference "ferrostar" */ = {
			isa = XCRemoteSwiftPackageReference;
			repositoryURL = "https://github.com/stadiamaps/ferrostar";
			requirement = {
				kind = exactVersion;
				version = 0.57.0;
			};
		};
```
Then before `/* End XCSwiftPackageProductDependency section */`:
```
		5BF0E1A1301700000000A001 /* FerrostarCore */ = {
			isa = XCSwiftPackageProductDependency;
			package = 5BF0E1A0301700000000A001 /* XCRemoteSwiftPackageReference "ferrostar" */;
			productName = FerrostarCore;
		};
		5BF0E1A3301700000000A001 /* FerrostarMapLibreUI */ = {
			isa = XCSwiftPackageProductDependency;
			package = 5BF0E1A0301700000000A001 /* XCRemoteSwiftPackageReference "ferrostar" */;
			productName = FerrostarMapLibreUI;
		};
```

- [ ] **Step 3: Resolve packages and confirm the pins**

```bash
xcodebuild -resolvePackageDependencies -project "Wheel Routes.xcodeproj" -scheme "Wheel Routes" -skipMacroValidation
grep -A6 '"identity" : "ferrostar"' "Wheel Routes.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
grep -A6 '"identity" : "swiftui-dsl"' "Wheel Routes.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
```
Expected: ferrostar resolves to `"version" : "0.57.0"`, and swiftui-dsl is still `"version" : "0.25.0"`, revision `139e83d1487f29b42a4f5db2458594170f0ff7e3`. If resolution fails or swiftui-dsl moves, **stop and report**; don't loosen either pin.

- [ ] **Step 4: Write a temporary smoke test proving the test target can see Ferrostar's modules**

Create `Wheel RoutesTests/FerrostarImportSmokeTests.swift`:
```swift
import Testing
import FerrostarCore
import FerrostarCoreFFI
@testable import Wheel_Routes

struct FerrostarImportSmokeTests {
    @Test func ferrostarTypesAreVisibleToTheTestTarget() {
        let coordinate = GeographicCoordinate(lat: 52.2, lng: 0.1)
        let provider = SimulatedLocationProvider()
        #expect(coordinate.lat == 52.2)
        #expect(provider.lastLocation == nil)
    }
}
```

- [ ] **Step 5: Run it**

Run the targeted test command with `-only-testing:"Wheel RoutesTests/FerrostarImportSmokeTests"`.
Expected: PASS, and the app builds with Ferrostar linked. If it fails with `no such module 'FerrostarCoreFFI'` (or `FerrostarCore`), **stop and report to the user**. Don't link Ferrostar into the test target: linking the static library into both the app and the hosted test bundle risks duplicate Objective-C classes, and needs a decision.

- [ ] **Step 6: Delete the smoke test**

```bash
rm "Wheel RoutesTests/FerrostarImportSmokeTests.swift"
```
Later tasks' tests cover the same imports.

- [ ] **Step 7: Add the supply-chain note to `CLAUDE.md`**

In `## Build & test`, directly after the `**Supply-chain note:**` bullet, add:
```markdown
- **Ferrostar supply-chain note:** `stadiamaps/ferrostar` (turn-by-turn navigation, GitHub #20) is also pinned to an exact version (`0.57.0`), for a different reason. It isn't a macro and needs no extra `xcodebuild` flag, but its core is a **precompiled Rust XCFramework** (a checksum-pinned `binaryTarget` downloaded from GitHub Releases), so the navigation logic can't be reviewed as a source diff at all. The checksum only guarantees the binary matches the tagged release, not that the release is benign. Keep the exact pin, and treat any bump as a deliberate, reviewed change (read the release notes), never a version range. Ferrostar declares `swiftui-dsl` `from: 0.25.0`, so a Ferrostar bump that raises that floor forces a `swiftui-dsl` bump too. Review the two together.
```

- [ ] **Step 8: Add the dependency to `docs/SPEC.md` → Architecture**

After the `- Map rendering supports two providers…` bullet, add:
```markdown
- Turn-by-turn navigation (GitHub #20) is built on [Ferrostar](https://github.com/stadiamaps/ferrostar): an SPM package pinned exactly to `0.57.0`, with the products `FerrostarCore` and `FerrostarMapLibreUI` linked to the app target only. Its core is a precompiled Rust XCFramework (see `CLAUDE.md`'s supply-chain note). Ferrostar's UI is built on the same `swiftui-dsl` package as the OSM map path, so navigation always renders with MapLibre.
```

- [ ] **Step 9: Commit**

```bash
git add "Wheel Routes.xcodeproj/project.pbxproj" "Wheel Routes.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved" CLAUDE.md docs/SPEC.md
git status --short   # must not list APIKey_dev.txt / ThunderforestAPIKey_dev.txt
git commit -m "build: add Ferrostar 0.57.0 (exact pin) for turn-by-turn navigation

Ferrostar ships a precompiled Rust XCFramework, so the exact-version pin
is the only review gate; CLAUDE.md now says so.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: `MapStyleOption.navigationStyle`

**Files:**
- Modify: `Wheel Routes/Features/Map/MapStyleOption.swift`
- Test: `Wheel RoutesTests/Features/MapStyleOptionTests.swift`

**Interfaces:**
- Produces: `var navigationStyle: MapStyleOption { get }`. It returns `self` for OSM cases and `.cyclOSM` for Apple cases.

- [ ] **Step 1: Write the failing tests**

Append inside `struct MapStyleOptionTests`:
```swift
    @Test func osmStylesNavigateInTheirOwnStyle() {
        for option in [MapStyleOption.osmStandard, .cyclOSM, .cycleMap] {
            #expect(option.navigationStyle == option)
        }
    }

    @Test func appleStylesNavigateInCyclOSM() {
        for option in [MapStyleOption.appleStandard, .appleHybrid, .appleSatellite] {
            #expect(option.navigationStyle == .cyclOSM)
        }
    }

    @Test func navigationStyleAlwaysHasAMapLibreStyleDocumentEvenWithoutAThunderforestKey() {
        for option in MapStyleOption.allCases where option.isApple {
            #expect(option.navigationStyle.mapLibreStyleDocument(thunderforestKey: "") != nil)
            #expect(!option.navigationStyle.requiresThunderforestKey)
        }
    }
```
- [ ] **Step 2: Run them and watch them fail**

Targeted run with `-only-testing:"Wheel RoutesTests/MapStyleOptionTests"`.
Expected: build error `value of type 'MapStyleOption' has no member 'navigationStyle'`.

- [ ] **Step 3: Implement**

In `MapStyleOption.swift`, after `var isApple: Bool { group == .apple }`:
```swift

    /// The style turn-by-turn navigation renders with. Ferrostar's UI only runs on MapLibre, so
    /// OSM styles navigate as themselves and Apple styles fall back to CyclOSM, which needs no
    /// Thunderforest key. The persisted `mapStyle` choice is never changed.
    var navigationStyle: MapStyleOption { isApple ? .cyclOSM : self }
```

- [ ] **Step 4: Run them and watch them pass**

Same targeted run. Expected: all `MapStyleOptionTests` pass.

- [ ] **Step 5: Commit**

No SPEC change is needed in this commit; this property is documented in Task 8, alongside the Start button that uses it.
```bash
git add "Wheel Routes/Features/Map/MapStyleOption.swift" "Wheel RoutesTests/Features/MapStyleOptionTests.swift"
git commit -m "feat: add MapStyleOption.navigationStyle (OSM, or CyclOSM for Apple styles)

Ferrostar navigation only renders on MapLibre, so Apple styles need an
OSM fallback that works without a Thunderforest key.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `TurnManeuver`: CycleStreets turn vocabulary

**Files:**
- Create: `Wheel Routes/Features/Navigation/TurnManeuver.swift`
- Test: `Wheel RoutesTests/Features/Navigation/TurnManeuverTests.swift`
- Modify: `docs/SPEC.md` (new Navigation section)

**Interfaces:**
- Consumes: `ManeuverType`, `ManeuverModifier` (from `FerrostarCoreFFI`)
- Produces:
  - `nonisolated struct TurnManeuver: Equatable { let type: ManeuverType; let modifier: ManeuverModifier?; let verb: String; let includesRoadName: Bool }`
  - `init(type:modifier:verb:includesRoadName: Bool = true)`
  - `init(cycleStreetsTurn: String?)`
  - `static let arrival: TurnManeuver`
  - `func instructionText(roadName: String?) -> String`
  - `static func displayableRoadName(_ name: String?) -> String?`

- [ ] **Step 1: Write the failing tests**

Create `Wheel RoutesTests/Features/Navigation/TurnManeuverTests.swift`:
```swift
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
```

- [ ] **Step 2: Run them and watch them fail**

Targeted run with `-only-testing:"Wheel RoutesTests/TurnManeuverTests"`.
Expected: build error `cannot find 'TurnManeuver' in scope`.

- [ ] **Step 3: Implement**

Create `Wheel Routes/Features/Navigation/TurnManeuver.swift`:
```swift
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
```

- [ ] **Step 4: Run them and watch them pass**

Same targeted run. Expected: all 8 tests pass.

- [ ] **Step 5: Start the Navigation section in `docs/SPEC.md`**

Insert a new section between `### Map (\`Features/Map/\`)` (after its last bullet) and `### Itinerary (\`Features/Itinerary/\`)`:
```markdown
### Navigation (`Features/Navigation/`)
Turn-by-turn guidance along a planned `Journey` (GitHub #20), built on Ferrostar (see Architecture). Design record: `docs/superpowers/specs/2026-09-25-turn-by-turn-navigation-design.md`.

- `TurnManeuver`: maps a CycleStreets `Segment.turn` string (case- and whitespace-insensitive) to a Ferrostar `ManeuverType`/`ManeuverModifier` plus an imperative verb. The known vocabulary was verified live: straight on, bear/turn/sharp left/right, join roundabout, first–fifth exit. Anything else falls back to "Continue". `instructionText(roadName:)` appends "onto <road>" unless the road is blank or a CycleStreets placeholder containing "un-named", or the maneuver is joining a roundabout or arriving.
```

- [ ] **Step 6: Commit**

```bash
git add "Wheel Routes/Features/Navigation/TurnManeuver.swift" "Wheel RoutesTests/Features/Navigation/TurnManeuverTests.swift" docs/SPEC.md
git commit -m "feat: map CycleStreets turn strings to Ferrostar maneuvers

Vocabulary checked against live API responses rather than guessed;
unknown values degrade to a neutral 'Continue'.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: `JourneyRouteAdapter`: `Journey` → Ferrostar `Route`

**Files:**
- Create: `Wheel Routes/Features/Navigation/JourneyRouteAdapter.swift`
- Create: `Wheel RoutesTests/TestSupport/NavigationFixtures.swift`
- Test: `Wheel RoutesTests/Features/Navigation/JourneyRouteAdapterTests.swift`
- Modify: `docs/SPEC.md` (Navigation section)

**Interfaces:**
- Consumes: `TurnManeuver` (Task 3); `Journey`, `Segment`, `Coordinate` (existing models)
- Produces:
  - `enum JourneyRouteAdapterError: Error, Equatable { case insufficientGeometry }`
  - `nonisolated enum JourneyRouteAdapter`, with `static func route(from journey: Journey, useMetric: Bool) throws -> Route`, `static let advanceCueDistance: Double = 200`, `static let immediateCueDistance: Double = 30` and `static func distancePhrase(metres: Double, useMetric: Bool) -> String`
  - Test support: `enum NavigationFixtures { static func threeSegmentJourney() -> Journey }`

- [ ] **Step 1: Create the shared fixture**

Create `Wheel RoutesTests/TestSupport/NavigationFixtures.swift`:
```swift
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
```

- [ ] **Step 2: Write the failing tests**

Create `Wheel RoutesTests/Features/Navigation/JourneyRouteAdapterTests.swift`:
```swift
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
```

- [ ] **Step 3: Run them and watch them fail**

Targeted run with `-only-testing:"Wheel RoutesTests/JourneyRouteAdapterTests"`.
Expected: build error `cannot find 'JourneyRouteAdapter' in scope`.

- [ ] **Step 4: Implement**

Create `Wheel Routes/Features/Navigation/JourneyRouteAdapter.swift`:
```swift
//
//  JourneyRouteAdapter.swift
//  Wheel Routes
//

import Foundation
import FerrostarCoreFFI

enum JourneyRouteAdapterError: Error, Equatable {
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
        for point in segments.flatMap(\.points).map(\.geographicCoordinate) where result.last != point {
            result.append(point)
        }
        return result
    }

    private static func boundingBox(of geometry: [GeographicCoordinate]) -> BoundingBox {
        let lats = geometry.map(\.lat)
        let lngs = geometry.map(\.lng)
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
            geometry: segment.points.map(\.geographicCoordinate),
            distance: distance,
            duration: Double(segment.timeSeconds),
            roadName: TurnManeuver.displayableRoadName(segment.name),
            exits: [],
            instruction: text,
            visualInstructions: [banner],
            spokenInstructions: spokenCues(text: text, isArrival: next == nil, stepDistance: distance, useMetric: useMetric),
            annotations: nil,
            incidents: [],
            drivingSide: .right,
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
```
If the compiler rejects an argument label on a Ferrostar initializer, check the generated signature. It's in the resolved package checkout: `find ~/Library/Developer/Xcode/DerivedData -path "*SourcePackages/checkouts/ferrostar/apple/Sources/UniFFI/ferrostar.swift" | head -1`. Grep there for `public struct <TypeName>`, then match its `public init(`.

- [ ] **Step 5: Run them and watch them pass**

Same targeted run. Expected: all 10 tests pass. Then run `TurnManeuverTests` again to confirm nothing regressed.

- [ ] **Step 6: Add the adapter to `docs/SPEC.md` → Navigation**

Append to the Navigation section's bullet list:
```markdown
- `JourneyRouteAdapter.route(from:useMetric:) throws -> Route`: a pure translation of the already-fetched `Journey` into Ferrostar's model, with no extra routing request.
  - **Geometry and metadata:** one `RouteStep` per `Segment`. Route geometry is all points with shared segment endpoints collapsed. Waypoints are the first and last coordinates (`.break`).
  - **Off-by-one:** CycleStreets' `turn` is the turn *into* a segment, so step N's instruction is built from segment N+1's turn and name, and the final step is "Arrive at destination".
  - **Instructions:** each step has one banner, shown for the whole step. Spoken cues are "In 200 metres, …" (only for steps ≥ 200 m, or "220 yards" when imperial) plus an immediate cue at `min(30 m, step length)`.
  - **Errors:** throws `JourneyRouteAdapterError.insufficientGeometry` when there are no segments or fewer than 2 distinct points.
```

- [ ] **Step 7: Commit**

```bash
git add "Wheel Routes/Features/Navigation/JourneyRouteAdapter.swift" "Wheel RoutesTests/TestSupport/NavigationFixtures.swift" "Wheel RoutesTests/Features/Navigation/JourneyRouteAdapterTests.swift" docs/SPEC.md
git commit -m "feat: translate CycleStreets journeys into Ferrostar routes

Turns are shifted onto the preceding step because CycleStreets attaches
a turn to the segment it enters, while Ferrostar announces the maneuver
at the end of the current step.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: `WheelRoutesRerouteProvider`

**Files:**
- Create: `Wheel Routes/Features/Navigation/WheelRoutesRerouteProvider.swift`
- Modify: `Wheel RoutesTests/Networking/MockAPIClient.swift`
- Test: `Wheel RoutesTests/Features/Navigation/WheelRoutesRerouteProviderTests.swift`
- Modify: `docs/SPEC.md` (Navigation section)

**Interfaces:**
- Consumes: `APIClientProtocol.planJourney(from:to:plan:)`, `JourneyRouteAdapter.route(from:useMetric:)`, Ferrostar's `CustomRouteProvider`, `UserLocation` and `Waypoint`
- Produces:
  - `enum WheelRoutesRerouteError: Error, Equatable { case noDestination }`
  - `nonisolated final class WheelRoutesRerouteProvider: CustomRouteProvider`, with `init(apiClient: any APIClientProtocol, plan: RoutePlan, useMetric: Bool)`, `var onFailure: ((Error) -> Void)?` and `func getRoutes(userLocation: UserLocation, waypoints: [Waypoint]) async throws -> [Route]`
  - `MockAPIClient.planJourneyCalls: [(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, plan: RoutePlan)]`

- [ ] **Step 1: Make `MockAPIClient` record `planJourney` calls**

In `MockAPIClient`, add a property after `var errorsByPlan…`:
```swift
    /// Every `planJourney` request, in order, recorded before any configured error is thrown,
    /// matching the real client, which has already sent the request by the time it fails.
    private(set) var planJourneyCalls: [(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, plan: RoutePlan)] = []
```
Then make this the first line of `planJourney(from:to:plan:)`'s body:
```swift
        planJourneyCalls.append((from: from, to: to, plan: plan))
```

- [ ] **Step 2: Write the failing tests**

Create `Wheel RoutesTests/Features/Navigation/WheelRoutesRerouteProviderTests.swift`:
```swift
//
//  WheelRoutesRerouteProviderTests.swift
//  Wheel RoutesTests
//

import Foundation
import Testing
import FerrostarCore
import FerrostarCoreFFI
@testable import Wheel_Routes

@MainActor
struct WheelRoutesRerouteProviderTests {
    private let client = MockAPIClient()
    private let rider = UserLocation(
        coordinates: GeographicCoordinate(lat: 52.2100, lng: 0.1300),
        horizontalAccuracy: 5, courseOverGround: nil, timestamp: Date(), speed: nil
    )
    private let waypoints = [
        Waypoint(coordinate: GeographicCoordinate(lat: 52.20, lng: 0.10), kind: .break, properties: nil),
        Waypoint(coordinate: GeographicCoordinate(lat: 52.30, lng: 0.20), kind: .break, properties: nil),
    ]

    /// Collects errors passed to `onFailure`.
    private final class FailureLog { var errors: [Error] = [] }

    @Test func replansFromTheRiderToTheFinalWaypointWithTheSamePlan() async throws {
        let provider = WheelRoutesRerouteProvider(apiClient: client, plan: .quietest, useMetric: true)
        _ = try await provider.getRoutes(userLocation: rider, waypoints: waypoints)
        let call = try #require(client.planJourneyCalls.only)
        #expect(call.from.latitude == 52.2100 && call.from.longitude == 0.1300)
        #expect(call.to.latitude == 52.30 && call.to.longitude == 0.20)
        #expect(call.plan == .quietest)
    }

    @Test func returnsTheReplannedJourneyAsASingleRoute() async throws {
        client.journeyToReturn = NavigationFixtures.threeSegmentJourney()
        let provider = WheelRoutesRerouteProvider(apiClient: client, plan: .quietest, useMetric: true)
        let routes = try await provider.getRoutes(userLocation: rider, waypoints: waypoints)
        #expect(routes.count == 1)
        #expect(routes.first?.distance == 820)
    }

    @Test func reportsAndRethrowsPlanningFailures() async {
        client.shouldThrow = URLError(.notConnectedToInternet)
        let provider = WheelRoutesRerouteProvider(apiClient: client, plan: .quietest, useMetric: true)
        let log = FailureLog()
        provider.onFailure = { log.errors.append($0) }
        await #expect(throws: URLError.self) {
            try await provider.getRoutes(userLocation: rider, waypoints: waypoints)
        }
        #expect((log.errors.only as? URLError)?.code == .notConnectedToInternet)
    }

    @Test func reportsAndThrowsWhenThereIsNoDestination() async {
        let provider = WheelRoutesRerouteProvider(apiClient: client, plan: .quietest, useMetric: true)
        let log = FailureLog()
        provider.onFailure = { log.errors.append($0) }
        await #expect(throws: WheelRoutesRerouteError.noDestination) {
            try await provider.getRoutes(userLocation: rider, waypoints: [])
        }
        #expect(log.errors.count == 1)
        #expect(client.planJourneyCalls.isEmpty)
    }
}

private extension Array {
    /// The sole element, or nil if the array doesn't have exactly one.
    var only: Element? { count == 1 ? first : nil }
}
```

- [ ] **Step 3: Run them and watch them fail**

Targeted run with `-only-testing:"Wheel RoutesTests/WheelRoutesRerouteProviderTests"`.
Expected: build error `cannot find 'WheelRoutesRerouteProvider' in scope`.

- [ ] **Step 4: Implement**

Create `Wheel Routes/Features/Navigation/WheelRoutesRerouteProvider.swift`:
```swift
//
//  WheelRoutesRerouteProvider.swift
//  Wheel Routes
//

import CoreLocation
import FerrostarCore
import FerrostarCoreFFI

enum WheelRoutesRerouteError: Error, Equatable {
    /// Ferrostar asked for a route with no remaining waypoints to head for.
    case noDestination
}

/// Ferrostar `CustomRouteProvider` used when the rider leaves the route: re-plans from
/// their current position to the final remaining waypoint with the same `RoutePlan`,
/// through the app's existing CycleStreets client.
///
/// `nonisolated` because `FerrostarCore` calls `getRoutes` from an unstructured `Task`,
/// off the main actor.
nonisolated final class WheelRoutesRerouteProvider: CustomRouteProvider {
    private let apiClient: any APIClientProtocol
    private let plan: RoutePlan
    private let useMetric: Bool

    /// Called with the error before it's rethrown. Ferrostar 0.57.0 swallows reroute errors
    /// (`catch {}` in `FerrostarCore`), so this is the only way the UI learns a reroute failed.
    /// May be called off the main actor.
    var onFailure: ((Error) -> Void)?

    init(apiClient: any APIClientProtocol, plan: RoutePlan, useMetric: Bool) {
        self.apiClient = apiClient
        self.plan = plan
        self.useMetric = useMetric
    }

    func getRoutes(userLocation: UserLocation, waypoints: [Waypoint]) async throws -> [Route] {
        do {
            guard let destination = waypoints.last else { throw WheelRoutesRerouteError.noDestination }
            let journey = try await apiClient.planJourney(
                from: CLLocationCoordinate2D(latitude: userLocation.coordinates.lat, longitude: userLocation.coordinates.lng),
                to: CLLocationCoordinate2D(latitude: destination.coordinate.lat, longitude: destination.coordinate.lng),
                plan: plan
            )
            return [try JourneyRouteAdapter.route(from: journey, useMetric: useMetric)]
        } catch {
            onFailure?(error)
            throw error
        }
    }
}
```

- [ ] **Step 5: Run them and watch them pass**

Same targeted run. Expected: all 4 tests pass. Then run `MapViewModelTests` and `SavedRoutesViewModelTests` to confirm the `MockAPIClient` change broke nothing.

- [ ] **Step 6: Add the provider to `docs/SPEC.md` → Navigation**

Append:
```markdown
- `WheelRoutesRerouteProvider`: a Ferrostar `CustomRouteProvider`. When the rider deviates, it re-plans from the rider's position to the last remaining waypoint with the journey's own `RoutePlan`, via `APIClientProtocol.planJourney`, then passes the result through `JourneyRouteAdapter`. It's `nonisolated` because Ferrostar calls it off the main actor. `FerrostarCore` 0.57.0 silently swallows reroute errors, so the provider reports every failure through `onFailure` before rethrowing (with `WheelRoutesRerouteError.noDestination` if there are no waypoints).
```

- [ ] **Step 7: Commit**

```bash
git add "Wheel Routes/Features/Navigation/WheelRoutesRerouteProvider.swift" "Wheel RoutesTests/Networking/MockAPIClient.swift" "Wheel RoutesTests/Features/Navigation/WheelRoutesRerouteProviderTests.swift" docs/SPEC.md
git commit -m "feat: reroute off-route riders through CycleStreets

FerrostarCore swallows route-provider errors, so the provider surfaces
failures via onFailure for the UI to report.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: `MapViewModel.prepareNavigation()`

**Files:**
- Modify: `Wheel Routes/Features/Map/MapViewModel.swift`
- Create: `Wheel RoutesTests/TestSupport/WaitUntil.swift` (moved helper)
- Modify: `Wheel RoutesTests/Features/MapViewModelTests.swift`
- Modify: `docs/SPEC.md` (Map screen → `MapViewModel`)

**Interfaces:**
- Consumes: `LocationServiceProtocol.currentLocation()`
- Produces:
  - `func prepareNavigation() async -> Bool`
  - `@MainActor func waitUntil(timeout: Duration = .seconds(5), pollInterval: Duration = .milliseconds(10), _ condition: () -> Bool) async throws` (test support, internal)

- [ ] **Step 1: Move `waitUntil` into shared test support**

Create `Wheel RoutesTests/TestSupport/WaitUntil.swift` with the helper cut from the top of `MapViewModelTests.swift`, unchanged apart from dropping `private`:
```swift
//
//  WaitUntil.swift
//  Wheel RoutesTests
//

import Testing

/// Polls `condition` until it becomes true or `timeout` elapses, instead of
/// sleeping a fixed duration and hoping the async work under test finished in
/// time. Suites run with default (non-serialized) Swift Testing parallelism,
/// so a fixed sleep margin is unreliable under CI's variable CPU contention.
/// Condition-based waiting is deterministic regardless of scheduling delay.
@MainActor
func waitUntil(
    timeout: Duration = .seconds(5),
    pollInterval: Duration = .milliseconds(10),
    _ condition: () -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        if ContinuousClock.now >= deadline {
            Issue.record("Timed out after \(timeout) waiting for condition")
            return
        }
        try await Task.sleep(for: pollInterval)
    }
}
```
Delete the `private func waitUntil…` block and its doc comment from `MapViewModelTests.swift`.

- [ ] **Step 2: Write the failing tests**

Append inside `final class MapViewModelTests`:
```swift
    // MARK: - prepareNavigation

    @Test func prepareNavigationSucceedsWhenALocationFixIsAvailable() async {
        let ready = await vm.prepareNavigation()
        #expect(ready)
        #expect(!vm.isLoading)
        #expect(vm.errorMessage == nil)
        #expect(!vm.isPresentingLocationPermissionAlert)
    }

    @Test func prepareNavigationOffersSettingsWhenPermissionIsDeniedOrRestricted() async {
        for error in [LocationServiceError.permissionDenied, .restricted] {
            vm.isPresentingLocationPermissionAlert = false
            locationService.errorToThrow = error
            let ready = await vm.prepareNavigation()
            #expect(!ready)
            #expect(vm.isPresentingLocationPermissionAlert)
            #expect(!vm.isLoading)
        }
    }

    @Test func prepareNavigationShowsAGenericErrorWhenLocationIsUnavailable() async {
        locationService.errorToThrow = LocationServiceError.unavailable
        let ready = await vm.prepareNavigation()
        #expect(!ready)
        #expect(vm.errorMessage == "Couldn't get your current location. Please try again.")
        #expect(!vm.isPresentingLocationPermissionAlert)
    }

    @Test func prepareNavigationStaysSilentForADuplicateInFlightFetch() async {
        locationService.errorToThrow = LocationServiceError.alreadyInProgress
        let ready = await vm.prepareNavigation()
        #expect(!ready)
        #expect(vm.errorMessage == nil)
        #expect(!vm.isPresentingLocationPermissionAlert)
    }

    @Test func prepareNavigationNeverTouchesWaypointsOrRoutes() async {
        _ = await vm.prepareNavigation()
        #expect(vm.fromPlace == nil)
        #expect(vm.toPlace == nil)
        #expect(vm.routeOptions.isEmpty)
    }
```

- [ ] **Step 3: Run them and watch them fail**

Targeted run with `-only-testing:"Wheel RoutesTests/MapViewModelTests"`.
Expected: build error `value of type 'MapViewModel' has no member 'prepareNavigation'`.

- [ ] **Step 4: Implement by extracting the shared body**

In `MapViewModel.swift`, replace the whole `centerOnCurrentLocation()` method (doc comment included) with:
```swift
    /// Fetches the device's current location purely to recenter the map
    /// camera. Unlike `useCurrentLocation(as:)`, this never touches
    /// `fromPlace`/`toPlace` or triggers route planning. The caller doesn't
    /// need the coordinate itself: on success it switches the map camera
    /// into the frameworks' own follow-user-location tracking mode rather
    /// than centering on a point held here. Error handling is
    /// `confirmCurrentLocationAvailable()`'s.
    @discardableResult
    func centerOnCurrentLocation() async -> Bool {
        await confirmCurrentLocationAvailable()
    }

    /// Gate before presenting turn-by-turn navigation. Ferrostar's own location
    /// provider assumes permission is already granted, so this confirms a real fix
    /// through the app's service first. That way a denial surfaces through the same
    /// "Location Access Needed" alert as everywhere else, instead of navigation
    /// silently showing no position. Error handling is
    /// `confirmCurrentLocationAvailable()`'s.
    func prepareNavigation() async -> Bool {
        await confirmCurrentLocationAvailable()
    }

    /// One-shot location fetch used only to confirm access, with the Map screen's
    /// shared error handling: `.permissionDenied`/`.restricted` set
    /// `isPresentingLocationPermissionAlert`, other failures set `errorMessage`,
    /// and `.alreadyInProgress` is swallowed silently, leaving `isLoading` owned
    /// by the first call.
    private func confirmCurrentLocationAvailable() async -> Bool {
        isLoading = true
        do {
            _ = try await locationService.currentLocation()
            isLoading = false
            return true
        } catch LocationServiceError.alreadyInProgress {
            return false
        } catch LocationServiceError.permissionDenied, LocationServiceError.restricted {
            isLoading = false
            isPresentingLocationPermissionAlert = true
            return false
        } catch {
            isLoading = false
            errorMessage = "Couldn't get your current location. Please try again."
            return false
        }
    }
```

- [ ] **Step 5: Run them and watch them pass**

Same targeted run. Expected: every `MapViewModelTests` test passes, including the existing `centerOnCurrentLocation` ones, which confirms the refactor preserved their behaviour.

- [ ] **Step 6: Document it in `docs/SPEC.md`**

In the Map section's `MapViewModel` bullet list, directly after the `centerOnCurrentLocation() -> Bool` bullet, add:
```markdown
  - `prepareNavigation() -> Bool`: the gate before presenting turn-by-turn navigation. It shares `centerOnCurrentLocation()`'s one-shot fetch and error handling (both call a private `confirmCurrentLocationAvailable()`), and returns `true` only once a real fix confirms location access. Ferrostar's own location provider assumes permission is already granted, so this routes a denial through the existing "Location Access Needed" alert instead of navigation silently showing no position.
```

- [ ] **Step 7: Commit**

```bash
git add "Wheel Routes/Features/Map/MapViewModel.swift" "Wheel RoutesTests/TestSupport/WaitUntil.swift" "Wheel RoutesTests/Features/MapViewModelTests.swift" docs/SPEC.md
git commit -m "feat: add MapViewModel.prepareNavigation location gate

Ferrostar assumes location permission is already granted, so check it
through the app's own service and existing alerts before navigating.
waitUntil moves to shared test support for the navigation suites.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: `NavigationViewModel`

**Files:**
- Create: `Wheel Routes/Features/Navigation/NavigationViewModel.swift`
- Test: `Wheel RoutesTests/Features/Navigation/NavigationViewModelTests.swift`
- Modify: `docs/SPEC.md` (Navigation section)

**Interfaces:**
- Consumes: `JourneyRouteAdapter`, `WheelRoutesRerouteProvider`, `APIClientProtocol`, and Ferrostar's `FerrostarCore`, `FerrostarCoreDelegate`, `LocationProviding`, `SimulatedLocationProvider`, `CoreLocationProvider`, `NavigationState` and `TripState`
- Produces the `@Observable @MainActor final class NavigationViewModel`:
  - `init(journey: Journey, apiClient: any APIClientProtocol, useMetric: Bool, isInitiallyMuted: Bool, locationProvider: LocationProviding, setIdleTimerDisabled: @escaping (Bool) -> Void = { UIApplication.shared.isIdleTimerDisabled = $0 })`
  - read-only properties `navigationState: NavigationState?`, `isMuted: Bool`, `rerouteErrorMessage: String?`, `startErrorMessage: String?`, `hasArrived: Bool`
  - methods `start()`, `stop()`, `toggleMute()`, `dismissRerouteError()`
  - `nonisolated static func isComplete(_ tripState: TripState?) -> Bool`
  - `static func makeLocationProvider() -> LocationProviding`
  - message constants `rerouteFailedMessage = "Couldn't recalculate route"` and `unnavigableRouteMessage = "This route can't be navigated."`
  - thresholds `deviationMinimumHorizontalAccuracy: UInt16 = 25` and `maxAcceptableDeviationMetres: Double = 25`

These tests drive a **real** `FerrostarCore` with Ferrostar's `SimulatedLocationProvider`. The core is deterministic Rust with no network, so this exercises the actual session, deviation and reroute behaviour instead of a hand-written fake.

- [ ] **Step 1: Write the failing tests**

Create `Wheel RoutesTests/Features/Navigation/NavigationViewModelTests.swift`:
```swift
//
//  NavigationViewModelTests.swift
//  Wheel RoutesTests
//

import Foundation
import Testing
import FerrostarCore
import FerrostarCoreFFI
@testable import Wheel_Routes

@MainActor
final class NavigationViewModelTests {
    let client = MockAPIClient()
    let locationProvider = SimulatedLocationProvider()
    var idleTimerCalls: [Bool] = []

    /// Muted by default so test runs don't speak cues aloud in the simulator.
    private func makeViewModel(journey: Journey = NavigationFixtures.threeSegmentJourney(), muted: Bool = true) -> NavigationViewModel {
        NavigationViewModel(
            journey: journey, apiClient: client, useMetric: true, isInitiallyMuted: muted,
            locationProvider: locationProvider,
            setIdleTimerDisabled: { [weak self] in self?.idleTimerCalls.append($0) }
        )
    }

    /// A fix ~100 km from the fixture route with good accuracy, so Ferrostar flags a deviation.
    private let farOffRoute = UserLocation(
        coordinates: GeographicCoordinate(lat: 51.5, lng: -0.9),
        horizontalAccuracy: 5, courseOverGround: nil, timestamp: Date(), speed: nil
    )

    @Test func startBeginsNavigationAndKeepsTheScreenAwake() async throws {
        let vm = makeViewModel()
        vm.start()
        try await waitUntil { vm.navigationState != nil }
        #expect(idleTimerCalls == [true])
        #expect(vm.startErrorMessage == nil)
        vm.stop()
    }

    @Test func startIsIdempotent() async throws {
        let vm = makeViewModel()
        vm.start()
        vm.start()
        try await waitUntil { vm.navigationState != nil }
        #expect(idleTimerCalls == [true])
        vm.stop()
    }

    @Test func stopEndsNavigationRestoresTheIdleTimerAndIsSafeToRepeat() async throws {
        let vm = makeViewModel()
        vm.start()
        try await waitUntil { vm.navigationState != nil }
        vm.stop()
        vm.stop()
        try await waitUntil { vm.navigationState == nil }
        #expect(idleTimerCalls == [true, false])
    }

    @Test func unnavigableJourneyReportsAnErrorWithoutStarting() {
        let vm = makeViewModel(journey: Journey(number: 1, plan: .balanced, lengthMetres: 0, timeSeconds: 0, segments: []))
        vm.start()
        #expect(vm.startErrorMessage == NavigationViewModel.unnavigableRouteMessage)
        #expect(vm.navigationState == nil)
        #expect(idleTimerCalls.isEmpty)
    }

    @Test func failedRerouteShowsABannerAndKeepsNavigating() async throws {
        client.shouldThrow = URLError(.notConnectedToInternet)
        let vm = makeViewModel()
        vm.start()
        try await waitUntil { vm.navigationState != nil }
        locationProvider.lastLocation = farOffRoute
        try await waitUntil { vm.rerouteErrorMessage != nil }
        #expect(vm.rerouteErrorMessage == NavigationViewModel.rerouteFailedMessage)
        #expect(vm.navigationState != nil)
        vm.dismissRerouteError()
        #expect(vm.rerouteErrorMessage == nil)
        vm.stop()
    }

    @Test func successfulRerouteSwitchesToTheReplannedRoute() async throws {
        let replanned = client.makeJourney()   // single segment starting at (52.2054, 0.1132)
        client.journeyToReturn = replanned
        let vm = makeViewModel()
        vm.start()
        try await waitUntil { vm.navigationState != nil }
        locationProvider.lastLocation = farOffRoute
        try await waitUntil { vm.navigationState?.routeGeometry.first == GeographicCoordinate(lat: 52.2054, lng: 0.1132) }
        #expect(client.planJourneyCalls.first?.plan == .quietest)
        #expect(vm.rerouteErrorMessage == nil)
        vm.stop()
    }

    @Test func muteStateStartsFromThePersistedValueAndFollowsToggles() async throws {
        let vm = makeViewModel(muted: false)
        #expect(!vm.isMuted)
        vm.toggleMute()
        try await waitUntil { vm.isMuted }
        #expect(makeViewModel(muted: true).isMuted)
    }

    @Test func onlyACompleteTripCountsAsArrived() {
        let summary = TripSummary(distanceTraveled: 820, snappedDistanceTraveled: 820, startedAt: Date(), endedAt: Date())
        #expect(!NavigationViewModel.isComplete(nil))
        #expect(!NavigationViewModel.isComplete(.idle(userLocation: nil)))
        #expect(NavigationViewModel.isComplete(.complete(userLocation: farOffRoute, summary: summary)))
    }
}
```

- [ ] **Step 2: Run them and watch them fail**

Targeted run with `-only-testing:"Wheel RoutesTests/NavigationViewModelTests"`.
Expected: build error `cannot find 'NavigationViewModel' in scope`.

- [ ] **Step 3: Implement**

Create `Wheel Routes/Features/Navigation/NavigationViewModel.swift`:
```swift
//
//  NavigationViewModel.swift
//  Wheel Routes
//

import Combine
import FerrostarCore
import FerrostarCoreFFI
import Foundation
import Observation
import UIKit

/// Drives one turn-by-turn session over a `FerrostarCore`: starts it from an
/// already-planned `Journey`, accepts automatic reroutes, surfaces reroute failures
/// (which Ferrostar itself swallows), mirrors the mute state, and keeps the screen
/// awake while active. One instance per session. `MapView` creates it when the
/// rider taps Start.
@Observable
@MainActor
final class NavigationViewModel {
    static let rerouteFailedMessage = "Couldn't recalculate route"
    static let unnavigableRouteMessage = "This route can't be navigated."

    /// Starting values from the design spec, to be tuned during on-device testing.
    /// Fixes less accurate than this are ignored for deviation checks.
    static let deviationMinimumHorizontalAccuracy: UInt16 = 25
    /// How far (in metres) from the route line counts as off-route.
    static let maxAcceptableDeviationMetres: Double = 25

    private(set) var navigationState: NavigationState?
    private(set) var isMuted: Bool
    private(set) var rerouteErrorMessage: String?
    private(set) var startErrorMessage: String?
    var hasArrived: Bool { Self.isComplete(navigationState?.tripState) }

    @ObservationIgnored private let core: FerrostarCore
    @ObservationIgnored private let journey: Journey
    @ObservationIgnored private let useMetric: Bool
    @ObservationIgnored private let locationProvider: LocationProviding
    @ObservationIgnored private let setIdleTimerDisabled: (Bool) -> Void
    /// Held strongly here because `FerrostarCore.delegate` is weak.
    @ObservationIgnored private let coreDelegate = CoreDelegateProxy()
    @ObservationIgnored private var cancellables: Set<AnyCancellable> = []
    @ObservationIgnored private var isActive = false

    init(
        journey: Journey,
        apiClient: any APIClientProtocol,
        useMetric: Bool,
        isInitiallyMuted: Bool,
        locationProvider: LocationProviding,
        setIdleTimerDisabled: @escaping (Bool) -> Void = { UIApplication.shared.isIdleTimerDisabled = $0 }
    ) {
        let rerouteProvider = WheelRoutesRerouteProvider(apiClient: apiClient, plan: journey.plan, useMetric: useMetric)
        self.journey = journey
        self.useMetric = useMetric
        self.locationProvider = locationProvider
        self.setIdleTimerDisabled = setIdleTimerDisabled
        self.isMuted = isInitiallyMuted
        self.core = FerrostarCore(
            customRouteProvider: rerouteProvider,
            locationProvider: locationProvider,
            navigationControllerConfig: Self.navigationControllerConfig,
            spokenInstructionObserver: .initAVSpeechSynthesizer(isMuted: isInitiallyMuted)
        )

        core.delegate = coreDelegate
        coreDelegate.onRoutesLoaded = { [weak self] routes in self?.acceptReroute(routes) }
        rerouteProvider.onFailure = { [weak self] _ in
            Task { @MainActor in self?.rerouteErrorMessage = Self.rerouteFailedMessage }
        }
        core.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.navigationState = state }
            .store(in: &cancellables)
        core.spokenInstructionObserver.$isMuted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] muted in self?.isMuted = muted }
            .store(in: &cancellables)
    }

    /// Converts the journey and starts the Ferrostar session. Safe to call more than once;
    /// only the first call of an active session does anything.
    func start() {
        guard !isActive else { return }
        do {
            let route = try JourneyRouteAdapter.route(from: journey, useMetric: useMetric)
            if let simulated = locationProvider as? SimulatedLocationProvider {
                try simulated.setSimulatedRoute(route)
            }
            try core.startNavigation(route: route)
            isActive = true
            setIdleTimerDisabled(true)
        } catch {
            startErrorMessage = Self.unnavigableRouteMessage
        }
    }

    /// Ends the session and lets the screen sleep again. Safe to call more than once.
    func stop() {
        guard isActive else { return }
        isActive = false
        core.stopNavigation()
        setIdleTimerDisabled(false)
    }

    func toggleMute() {
        core.spokenInstructionObserver.toggleMute()
    }

    func dismissRerouteError() {
        rerouteErrorMessage = nil
    }

    nonisolated static func isComplete(_ tripState: TripState?) -> Bool {
        guard let tripState, case .complete = tripState else { return false }
        return true
    }

    /// Real GPS for rides. In DEBUG builds, the launch argument `-simulateNavigation` replays
    /// the route instead (`start()` loads it into the simulator), for checking navigation in
    /// the iOS Simulator without a GPX file.
    static func makeLocationProvider() -> LocationProviding {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-simulateNavigation") {
            return SimulatedLocationProvider()
        }
        #endif
        return CoreLocationProvider(activityType: .fitness, allowBackgroundLocationUpdates: false)
    }

    private func acceptReroute(_ routes: [Route]) {
        guard isActive, let route = routes.first else { return }
        do {
            try core.startNavigation(route: route)
            rerouteErrorMessage = nil
        } catch {
            rerouteErrorMessage = Self.rerouteFailedMessage
        }
    }

    private static var navigationControllerConfig: SwiftNavigationControllerConfig {
        SwiftNavigationControllerConfig(
            waypointAdvance: .waypointWithinRange(50),
            stepAdvanceCondition: stepAdvanceDistanceEntryAndExit(
                distanceToEndOfStep: 20, distanceAfterEndOfStep: 5, minimumHorizontalAccuracy: 25
            ),
            arrivalStepAdvanceCondition: stepAdvanceDistanceToEndOfStep(distance: 15, minimumHorizontalAccuracy: 25),
            routeDeviationTracking: .staticThreshold(
                minimumHorizontalAccuracy: deviationMinimumHorizontalAccuracy,
                maxAcceptableDeviation: maxAcceptableDeviationMetres
            ),
            snappedLocationCourseFiltering: .snapToRoute
        )
    }
}

/// Ferrostar 0.57.0 calls `core(_:loadedAlternateRoutes:)` from an unstructured `Task`,
/// possibly off the main actor, so this nonisolated shim hops to the main actor before
/// forwarding. It always requests a reroute on deviation.
private nonisolated final class CoreDelegateProxy: FerrostarCoreDelegate {
    var onRoutesLoaded: (@MainActor ([Route]) -> Void)?

    func core(_: FerrostarCore, didStartWith _: Route) {}

    func core(
        _: FerrostarCore,
        correctiveActionForDeviation _: DeviationKind,
        remainingWaypoints waypoints: [Waypoint]
    ) -> CorrectiveAction {
        .getNewRoutes(waypoints: waypoints)
    }

    func core(_: FerrostarCore, loadedAlternateRoutes routes: [Route]) {
        let handler = onRoutesLoaded
        Task { @MainActor in handler?(routes) }
    }
}
```

- [ ] **Step 4: Run them and watch them pass**

Same targeted run. Expected: all 8 tests pass. If either reroute test times out, don't add sleeps. First check that `farOffRoute`'s `horizontalAccuracy` (5) is under `deviationMinimumHorizontalAccuracy` (25), and that `SimulatedLocationProvider.lastLocation`'s `didSet` reaches the core while updating (it only notifies when `isUpdating`, and `startNavigation` sets that). Then report what you found.

- [ ] **Step 5: Run the whole suite**

Full test command. Expected: every suite passes.

- [ ] **Step 6: Add the view model to `docs/SPEC.md` → Navigation**

Append:
```markdown
- `NavigationViewModel` (`@Observable @MainActor`, one instance per session): owns a `FerrostarCore` built with `WheelRoutesRerouteProvider`, and mirrors `core.$state` into `navigationState` and the speech observer's mute state into `isMuted`.
  - **Lifecycle:** `start()` adapts the journey and calls `startNavigation(route:)`; an adapter failure sets `startErrorMessage`. `stop()` stops the core. Both are idempotent, and they toggle `isIdleTimerDisabled` through an injectable closure.
  - **Deviation and rerouting:** deviation uses `.staticThreshold` with a 25 m accuracy gate and a 25 m maximum deviation. A private nonisolated `CoreDelegateProxy` always requests a reroute and hops `loadedAlternateRoutes` to the main actor (Ferrostar calls it from an unstructured `Task`); the first route is accepted while the session is active. Reroute failures set `rerouteErrorMessage` ("Couldn't recalculate route") without ending the session.
  - **Arrival:** `hasArrived` is true when the trip state is `.complete`.
  - **Location source:** `makeLocationProvider()` returns `CoreLocationProvider(activityType: .fitness)`, or, in DEBUG builds with the launch argument `-simulateNavigation`, a `SimulatedLocationProvider` that replays the route.
```

- [ ] **Step 7: Commit**

```bash
git add "Wheel Routes/Features/Navigation/NavigationViewModel.swift" "Wheel RoutesTests/Features/Navigation/NavigationViewModelTests.swift" docs/SPEC.md
git commit -m "feat: add NavigationViewModel driving a Ferrostar session

Tested against a real FerrostarCore with the simulated location
provider, so deviation and reroute behaviour is exercised for real.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: `NavigationScreen` and the Start button

**Files:**
- Create: `Wheel Routes/Features/Navigation/NavigationScreen.swift`
- Modify: `Wheel Routes/Features/Map/MapView.swift`
- Modify: `docs/SPEC.md` (Navigation section, Map screen, Test coverage gaps)

**Interfaces:**
- Consumes: `NavigationViewModel` (Task 7), `MapViewModel.prepareNavigation()` (Task 6), `MapStyleOption.navigationStyle` (Task 2), and Ferrostar's `DynamicallyOrientingNavigationView`, `navigationViewInnerGrid` and `NavigationUIBanner`
- Produces:
  - `struct ActiveNavigation: Identifiable { let id: UUID; let viewModel: NavigationViewModel; let styleURL: URL }`
  - `struct NavigationScreen: View { init(navigation: ActiveNavigation, locationService: any LocationServiceProtocol) }`

This is SwiftUI wiring with no new testable logic, so it's **build-verified plus a manual simulator check**, per the project convention (`docs/SPEC.md` → Test coverage).

- [ ] **Step 1: Create `NavigationScreen`**

Create `Wheel Routes/Features/Navigation/NavigationScreen.swift`:
```swift
//
//  NavigationScreen.swift
//  Wheel Routes
//

import SwiftUI
import FerrostarCore
import FerrostarCoreFFI
import FerrostarMapLibreUI
import FerrostarSwiftUI
import MapLibreSwiftUI

/// One navigation session as presented by `MapView`: the view model, created once when the
/// rider taps Start (not on every `MapView` re-render), and the MapLibre style it renders with.
struct ActiveNavigation: Identifiable {
    let id = UUID()
    let viewModel: NavigationViewModel
    let styleURL: URL
}

/// Full-screen turn-by-turn guidance using Ferrostar's bundled UI. It always renders with
/// MapLibre, since Ferrostar doesn't support Apple's `Map`. See `MapStyleOption.navigationStyle`.
struct NavigationScreen: View {
    let navigation: ActiveNavigation
    let locationService: any LocationServiceProtocol

    @State private var camera: MapViewCamera = .automotiveNavigation()
    @State private var isPresentingPermissionLostAlert = false
    @AppStorage("navigationMuted") private var navigationMuted = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    private var vm: NavigationViewModel { navigation.viewModel }

    var body: some View {
        DynamicallyOrientingNavigationView(
            styleURL: navigation.styleURL,
            camera: $camera,
            navigationState: vm.navigationState,
            isMuted: vm.isMuted,
            onTapMute: { vm.toggleMute() },
            onTapExit: { endNavigation() }
        )
        .navigationViewInnerGrid(topCenter: { statusBanner })
        .overlay {
            if vm.hasArrived {
                messageCard(systemImage: "flag.checkered", title: "You've arrived", buttonTitle: "Done")
            } else if let message = vm.startErrorMessage {
                messageCard(systemImage: "exclamationmark.triangle", title: message, buttonTitle: "Close")
            }
        }
        .task { vm.start() }
        .onDisappear { vm.stop() }
        .onChange(of: vm.isMuted) { _, muted in navigationMuted = muted }
        // Ferrostar 0.57.0 ignores location-provider errors, so it can't report a revoked
        // permission. Revoking needs a trip to Settings, so check on every return to the app.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, !locationService.isAuthorized {
                isPresentingPermissionLostAlert = true
            }
        }
        .alert("Location Access Needed", isPresented: $isPresentingPermissionLostAlert) {
            Button("End Navigation", role: .cancel) { endNavigation() }
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text("Navigation needs location access. Enable it in Settings to keep going.")
        }
    }

    @ViewBuilder private var statusBanner: some View {
        if let message = vm.rerouteErrorMessage {
            NavigationUIBanner(severity: .error) { Text(message) }
                .onTapGesture { vm.dismissRerouteError() }
        } else if vm.navigationState?.isCalculatingNewRoute == true {
            NavigationUIBanner(severity: .loading) { Text("Recalculating route…") }
        }
    }

    private func messageCard(systemImage: String, title: String, buttonTitle: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage).font(.largeTitle)
            Text(title).font(.title2.bold()).multilineTextAlignment(.center)
            Button(buttonTitle) { endNavigation() }
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding()
    }

    private func endNavigation() {
        vm.stop()
        dismiss()
    }
}
```

- [ ] **Step 2: Wire the Start button and cover into `MapView`**

In `Wheel Routes/Features/Map/MapView.swift`:

1. Add `import FerrostarCore` after `import MapLibreSwiftUI`.
2. After `@Environment(\.apiClient) private var apiClient`, add:
```swift
    @Environment(\.locationService) private var locationService
    @AppStorage("useMetric") private var useMetric = true
    @AppStorage("navigationMuted") private var navigationMuted = false
    /// The running turn-by-turn session, if any. Holding the view model here means it's
    /// created exactly once per session, when Start is tapped.
    @State private var activeNavigation: ActiveNavigation?
```
3. Directly after the `.toolbar { … }` modifier's closing brace, add:
```swift
        .overlay(alignment: .bottom) {
            if vm.currentJourney != nil { startNavigationButton }
        }
        .fullScreenCover(item: $activeNavigation) { navigation in
            NavigationScreen(navigation: navigation, locationService: locationService)
        }
```
4. In the existing "Location Access Needed" alert, change the message text from `"Location access is off. Enable it in Settings to use Current Location."` to `"Location access is off. Enable it in Settings to use your current location."`, since the alert now also covers navigation.
5. After the `layersButton` property, add:
```swift
    private var startNavigationButton: some View {
        Button {
            startNavigation()
        } label: {
            Label("Start", systemImage: "figure.outdoor.cycle")
                .font(.headline)
                .padding(.horizontal, 8)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(.bottom)
        .accessibilityLabel("Start turn-by-turn navigation")
    }

    /// Confirms location access first via `MapViewModel.prepareNavigation()`, so a denial
    /// surfaces through the existing "Location Access Needed" alert, then presents
    /// `NavigationScreen` for the selected plan's journey.
    private func startNavigation() {
        guard !vm.isLoading, let journey = vm.currentJourney else { return }
        Task {
            guard await vm.prepareNavigation() else { return }
            guard let styleURL = navigationStyleURL() else {
                vm.errorMessage = "Couldn't load the navigation map. Please try again."
                return
            }
            activeNavigation = ActiveNavigation(
                viewModel: NavigationViewModel(
                    journey: journey, apiClient: apiClient, useMetric: useMetric,
                    isInitiallyMuted: navigationMuted,
                    locationProvider: NavigationViewModel.makeLocationProvider()
                ),
                styleURL: styleURL
            )
        }
    }

    /// Navigation always renders with MapLibre, so Apple styles fall back to
    /// `MapStyleOption.navigationStyle`. The file is written under its own name so it never
    /// clobbers `osmStyleURLCache`'s files.
    private func navigationStyleURL() -> URL? {
        let style = selectedMapStyle.navigationStyle
        return try? style.mapLibreStyleDocument(thunderforestKey: thunderforestAPIKey)?
            .writeToTemporaryFile(named: "navigation-\(style.rawValue)")
    }
```

- [ ] **Step 3: Build**

```bash
xcodebuild build -project "Wheel Routes.xcodeproj" -scheme "Wheel Routes" -destination "platform=iOS Simulator,name=iPhone 17" -skipMacroValidation 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
```
Expected: `** BUILD SUCCEEDED **` with no `error:` lines. If `.automotiveNavigation()` or `NavigationUIBanner(severity:)` won't resolve, confirm the imports match Step 1 exactly (`FerrostarMapLibreUI` and `FerrostarSwiftUI` respectively) before changing anything else.

- [ ] **Step 4: Check it manually in the simulator with a simulated ride**

```bash
xcrun simctl boot "iPhone 17" 2>/dev/null; open -a Simulator
xcrun simctl privacy "iPhone 17" grant location uk.slartibartfast.Wheel-Routes
xcrun simctl location "iPhone 17" set 52.2054,0.1132
APP=$(find ~/Library/Developer/Xcode/DerivedData -path "*Build/Products/Debug-iphonesimulator/Wheel Routes.app" -maxdepth 6 | head -1)
xcrun simctl install "iPhone 17" "$APP"
xcrun simctl launch "iPhone 17" uk.slartibartfast.Wheel-Routes -simulateNavigation
```
Then, in the app:
1. Plan a short Cambridge route using Current Location → a searched place.
2. Tap **Start**, and check that the full-screen navigation appears with a maneuver banner and moves along the route. Check that tapping mute toggles it, and that the exit button returns to the Map screen.
3. Switch the map style to **Apple Standard** and tap Start again. Navigation should still show OSM (CyclOSM) tiles, and the Map screen should still be on Apple Standard afterwards.
4. Let a short simulated route finish, and check that "You've arrived" with **Done** appears.

Record which checks passed in the task report. If any fail, stop and report with screenshots. Don't tune thresholds blind.

- [ ] **Step 5: Update `docs/SPEC.md`**

1. Append to the Navigation section:
```markdown
- `NavigationScreen`: a full-screen `DynamicallyOrientingNavigationView` (Ferrostar's bundled UI: maneuver banner, trip progress, mute and exit, automotive follow camera, portrait/landscape) for one `ActiveNavigation` (the view model plus a MapLibre style URL).
  - **Banners and cards:** the top-center banner shows the reroute failure (tap to dismiss) or "Recalculating route…". An overlay card shows "You've arrived" / Done, or `startErrorMessage` / Close.
  - **Settings:** mute is persisted to `@AppStorage("navigationMuted")`.
  - **Lifecycle:** it's foreground-only. `.task` starts the session, and `.onDisappear` stops it.
  - **Lost permission:** Ferrostar 0.57.0 ignores location-provider errors, so on each `scenePhase == .active` it checks `LocationServiceProtocol.isAuthorized` and offers Open Settings / End Navigation.
```
2. In the Map section's `MapView` bullet, before its final sentence about `compassButton`, add:
```markdown
Once a route exists, a bottom-center **Start** button (`figure.outdoor.cycle`) gates on `MapViewModel.prepareNavigation()`, then presents `NavigationScreen` via `.fullScreenCover(item:)`. It creates one `NavigationViewModel` per session, for the selected plan's journey, using `MapStyleOption.navigationStyle`: the current style if it's OSM, otherwise CyclOSM, since Ferrostar only renders on MapLibre. The persisted `mapStyle` is left unchanged. The "Location Access Needed" alert's copy is generic ("…to use your current location") because it also covers navigation.
```
3. In `## Test coverage` → **Known gaps**, add `NavigationScreen` and `MapView`'s Start-button / `.fullScreenCover` wiring to the build-verify-only list, with the note "(manual check: simulator launch with `-simulateNavigation`)".

- [ ] **Step 6: Commit**

```bash
git add "Wheel Routes/Features/Navigation/NavigationScreen.swift" "Wheel Routes/Features/Map/MapView.swift" docs/SPEC.md
git commit -m "feat: add turn-by-turn navigation screen and Start button

Navigation always renders with MapLibre (Ferrostar can't drive Apple's
Map), falling back to CyclOSM when an Apple style is selected, so the
feature works regardless of the planning map's style.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Final verification, remaining docs, follow-up issue

**Files:**
- Modify: `docs/SPEC.md` (Test coverage list, Known limitations, "Last verified")

- [ ] **Step 1: Run the full suite**

Full test command. Expected: `** TEST SUCCEEDED **`, with every suite passing, including `TurnManeuverTests`, `JourneyRouteAdapterTests`, `WheelRoutesRerouteProviderTests` and `NavigationViewModelTests`. Paste the summary lines into the task report.

- [ ] **Step 2: Finish `docs/SPEC.md`**

1. In `## Test coverage`, add to the list of test files: `Features/Navigation/{TurnManeuverTests, JourneyRouteAdapterTests, WheelRoutesRerouteProviderTests, NavigationViewModelTests}`, and `TestSupport/{WaitUntil, NavigationFixtures}`.
2. In `## Known limitations / roadmap`, add:
```markdown
Turn-by-turn navigation (GitHub #20) is implemented, but only in the foreground. Guidance and voice pause when the app is backgrounded or the screen locks; the screen is kept awake during navigation instead. Background navigation (`UIBackgroundModes` location+audio) is tracked separately (see the follow-up issue linked from #20). Navigation always renders with MapLibre/OSM tiles, never Apple's `Map`, which is Ferrostar's constraint. Deviation thresholds (25 m / 25 m) are starting values pending real rides. Design record: `docs/superpowers/specs/2026-09-25-turn-by-turn-navigation-design.md`; implementation plan: `docs/superpowers/plans/2026-09-25-turn-by-turn-navigation.md`.
```
3. Update the `Last verified against:` line to `feat/turn-by-turn-navigation @ <current short SHA>`.

- [ ] **Step 3: Work through `docs/REVIEW_CHECKLIST.md`**

Check every box explicitly. In particular:
- `MockAPIClient` still behaves like the real client: it records before throwing, and the real client has sent the request by then.
- `git status` shows no API key files.
- `project.pbxproj` contains only the Ferrostar package entries: `git diff origin/main -- "Wheel Routes.xcodeproj/project.pbxproj"` shows no signing or team changes.

- [ ] **Step 4: Commit**

```bash
git add docs/SPEC.md
git commit -m "docs: record navigation test coverage and foreground-only limitation

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 5: Ask the user before filing the follow-up issue**

Filing an issue is outward-facing, so confirm first. Then:
```bash
gh issue create --repo pwheel/wheel-routes-ride-planner-ios --label enhancement \
  --title "Background turn-by-turn navigation (screen locked / app backgrounded)" \
  --body "Follow-up to #20. v1 navigation is foreground-only: guidance and voice pause when the app is backgrounded or the screen locks (the screen is kept awake while navigating instead).

Scope:
- \`UIBackgroundModes\`: \`location\` and \`audio\`
- \`CoreLocationProvider(activityType: .fitness, allowBackgroundLocationUpdates: true)\` while a session is active
- Location-permission wording and App Store review notes for background location
- Consider Ferrostar's Live Activity / Dynamic Island widget provider

See docs/superpowers/specs/2026-09-25-turn-by-turn-navigation-design.md (Out of scope)."
```

- [ ] **Step 6: Hand back for the on-device ride**

Before merging, report to the user that a real ride on a device is still needed (per the spec), and list what it should confirm:
- The rider's position tracks the route.
- Banners change at the right time.
- Voice cues are timely at cycling speed.
- A deliberate wrong turn triggers "Recalculating route…" and a sensible new route.
- The arrival card appears.

Don't claim the feature is ride-tested until that has happened.
