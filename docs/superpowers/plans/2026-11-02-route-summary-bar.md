# Route Summary Bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show distance, duration, elevation gain/loss and an elevation profile in a card at the bottom of the Map screen once a route is planned (GitHub #7).

**Architecture:** The decoder reads two more per-point attributes onto `Segment`. `Journey` derives gain/loss and the profile from them as pure computed members. A new `RouteSummaryView` renders `vm.currentJourney`, so plan switching needs no extra wiring.

**Tech Stack:** SwiftUI, Swift Charts (system framework, no package), Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-02-route-summary-bar-design.md`

## Live verification results (2026-11-02)

The design's "Open verification" was run before this plan: `journey.json`, Bath city centre to Claverton Down (`-2.3597,51.3811` to `-2.3300,51.3700`), all three plans, 22–26 segments each.

| Question | Result |
|---|---|
| `elevations` name and format | Confirmed: comma-separated integer metres in a string, e.g. `"25,24,24,24"` |
| Count matches `points` | Yes, on every segment of all three plans |
| On the route marker too | Yes, with the shared endpoints already collapsed (191 values for 214 segment points). Not used; per-segment data lets us validate each segment |
| `distances` present | Yes, per point, the first value is always `0`, e.g. `"0,29,4,9"`. Each segment's values sum exactly to its `distance`, and all segments sum exactly to the route's `length` |
| Shared endpoints | Elevation and coordinates are identical at every segment boundary |
| Gain vs cyclestreets.net | The site shows **no total climb figure**. Summing its coarser profile table gives about 162 m up / 12 m down. For balanced, raw sum gives 178 / 29 and a 2 m hysteresis gives 166 / 16. Net climb is 149 m on all of them |

## Departures from the design

1. **Point distances come from the API, with no `CLLocation` fallback.** The design says to prefer a usable `distances` attribute, and it is usable. The profile's x-axis then ends exactly on the distance shown in the stats row. If `distances` is missing, only the profile is hidden.
2. **`var`, not `let`, for the new `Segment` fields.** A `let` with a default value is excluded from the memberwise initialiser, so the decoder couldn't set it.
3. **The design's stored-`Journey`-JSON concern doesn't apply.** Only `SavedRoute` and `SavedLocation` are persisted; `Journey` is only ever built by `JourneyPlanDecoder`.
4. **Non-string attributes must not throw.** A plain `String?` would throw on a non-string value and lose the whole journey, which breaks the design's "never throws" rule. See Task 1.
5. **Hidden while searching.** The card is hidden while the search field is focused, because the bottom overlay rises with the keyboard and would collide with the results list. The chart is also dropped in landscape.

## Global Constraints

- Gain/loss is the **raw sum** to start with. Hysteresis stays a follow-up (design: "Raw sum to start with").
- Never show a misleading "↑ 0 m": missing or mismatched data hides the figure and the profile.
- Units follow `@AppStorage("useMetric")`: km and m, or mi and ft. Round feet to the nearest integer (145 m → 476 ft, 120 m → 394 ft).
- Elevation text format: `"↑ 145 m ↓ 120 m"`, `"↑ 476 ft ↓ 394 ft"`.
- No new endpoint, request parameter or package.
- `MemberImportVisibility` is on: `RouteSummaryView.swift` must `import Charts` and `import SwiftUI` explicitly.
- Work only in this worktree. Serena is activated on the main checkout, so don't use its editing tools here.
- Test command base: `xcodebuild test -project "Wheel Routes.xcodeproj" -scheme "Wheel Routes" -destination "platform=iOS Simulator,name=iPhone 17" -skipMacroValidation`.

## Review Focus

1. **An attribute arrives as a non-string (`{}`, `[]`, a number):** the journey still decodes, with empty arrays. Test in Task 1.
2. **One malformed value in a list (`"25,x,24"`):** it's dropped, the count no longer matches, and the elevation UI is hidden rather than wrong. Tests in Tasks 1 and 2.
3. **Below-sea-level routes (`"-2,1"`):** negatives parse, and gain/loss is correct. Tests in Tasks 1 and 2.
4. **A completely flat route:** the chart gets a non-degenerate y-range, and the text reads "↑ 0 m ↓ 0 m", which is true here. Tests in Tasks 2 and 3.
5. **Search focus, landscape, and long imperial text:** the card doesn't collide with the results list, cover the map in landscape, or truncate the stats row. Manual check in Task 3.

---

### Task 1: Decode per-point elevations and distances

**Files:**
- Modify: `Wheel Routes/Models/Journey.swift` (`Segment`)
- Modify: `Wheel Routes/Networking/JourneyPlanDecoder.swift`
- Modify: `docs/SPEC.md` (API contract, Models)
- Test: `Wheel RoutesTests/Networking/JourneyPlanDecoderTests.swift`

**Interfaces:**
- Produces: `Segment.elevations: [Int]` and `Segment.pointDistances: [Int]`, both `var` defaulting to `[]`, declared after `points` so existing `Segment(...)` call sites still compile.

- [ ] **Step 1: Write the failing tests.** Add a `liveElevationJSON` fixture: the route marker (`itinerary` 124337882, `plan` balanced, `length` 3240, `time` 1880) plus these live segments, each with `type: "segment"`:

| name | distance | time | turn | points | elevations | distances |
|---|---|---|---|---|---|---|
| Abbey Churchyard | 42 | 41 | (empty) | `-2.35975,51.38126 -2.36015,51.38118 -2.36021,51.38118 -2.36024,51.38126` | `25,24,24,24` | `0,29,4,9` |
| Pedestrian area | 8 | 11 | turn left | `-2.36024,51.38126 -2.36035,51.38124` | `24,24` | `0,8` |
| Stall Street | 32 | 40 | turn right | `-2.36035,51.38124 -2.36041,51.38141 -2.36044,51.3815 -2.36045,51.38153` | `24,25,25,25` | `0,19,10,3` |

Tests:

```swift
@Test func parsesPerPointElevationsAndDistances() throws {
    let segments = try JourneyPlanDecoder.decode(liveElevationJSON, requestedPlan: .balanced).segments
    #expect(segments[0].elevations == [25, 24, 24, 24])
    #expect(segments[0].pointDistances == [0, 29, 4, 9])
    #expect(segments[1].elevations == [24, 24])
}
@Test func missingElevationAttributesDecodeAsEmpty() throws {
    let segments = try JourneyPlanDecoder.decode(sampleJSON, requestedPlan: .balanced).segments
    #expect(segments[0].elevations == [])
    #expect(segments[0].pointDistances == [])
}
```

Add `skipsMalformedElevationValues` (`"25,x,24"` → `[25, 24]`), `parsesNegativeElevations` (`"-2,1"` → `[-2, 1]`), and `nonStringElevationAttributesDoNotThrow`, parameterised over `elevations` values `{}`, `[]` and `25`, expecting `[]` and no throw.

- [ ] **Step 2: Run to verify they fail.** Run the base command with `-only-testing:"Wheel RoutesTests/JourneyPlanDecoderTests"`. Expected: compile failure, `Segment` has no member `elevations`.

- [ ] **Step 3: Implement.** Add the two `Segment` fields. In `RawAttributes`, add `elevations` and `distances` as `LossyString?`, where `LossyString` is a private `Decodable` struct whose `init(from:)` sets `value: String?` using `try? decoder.singleValueContainer().decode(String.self)`. Add `private static func parseIntegers(_ raw: String?) -> [Int]`, which splits on `,` and `compactMap`s `Int.init`, in the style of `parsePoints`. Update the type's doc comment.

- [ ] **Step 4: Run to verify they pass.** Same command. Expected: all `JourneyPlanDecoderTests` pass.

- [ ] **Step 5: Update `docs/SPEC.md`.** In the API contract, say that segment `elevations` and `distances` are parsed, and that non-string or malformed values never fail a decode. Add both fields to the `Segment` entry under Models.

- [ ] **Step 6: Commit** with the message `feat: decode per-point elevations and distances (#7)`.

### Task 2: Derive gain/loss, profile and formatted text

**Files:**
- Modify: `Wheel Routes/Models/Journey.swift`
- Modify: `docs/SPEC.md` (Models)
- Test: `Wheel RoutesTests/Models/JourneyTests.swift`

**Interfaces:**
- Consumes: `Segment.elevations`, `Segment.pointDistances`.
- Produces:
  - `struct ElevationSample: Equatable { let distanceMetres: Double; let elevationMetres: Int }`
  - `Journey.elevationGainLoss: (gain: Int, loss: Int)?`
  - `Journey.elevationProfile: [ElevationSample]?`
  - `Journey.formattedElevation(metric: Bool) -> String?`
  - `static Journey.formattedHeight(metres: Int, metric: Bool) -> String`, e.g. `"145 m"` or `"476 ft"`

- [ ] **Step 1: Write the failing tests.** Add a private helper `segment(_ number: Int, elevations: [Int], distances: [Int]) -> Segment` that generates one `Coordinate` per elevation, and a `journey(_ segments: [Segment]) -> Journey`.

```swift
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
@Test func formattedElevationMetricAndImperial() {
    let route = journey([segment(1, elevations: [0, 145, 25], distances: [0, 5, 5])])
    #expect(route.formattedElevation(metric: true) == "↑ 145 m ↓ 120 m")
    #expect(route.formattedElevation(metric: false) == "↑ 476 ft ↓ 394 ft")
}
```

Add these too:
- `gainLossHandlesNegativeElevations`: `[-2, 1, -1]` gives gain 3, loss 2.
- `gainLossNilWhenAnySegmentHasNoElevations`: one good segment and one empty.
- `gainLossNilWhenCountDoesNotMatchPoints`: build a `Segment` directly with 3 points and 2 elevations. Also assert `formattedElevation(metric: true) == nil`.
- `gainLossNilForJourneyWithNoSegments`.
- `profileNilWhenDistancesMissingButGainLossStillAvailable`.
- `profileNilWhenFewerThanTwoSamples`: one point.

- [ ] **Step 2: Run to verify they fail.** Run the base command with `-only-testing:"Wheel RoutesTests/JourneyTests"`. Expected: compile failure, no member `elevationGainLoss`.

- [ ] **Step 3: Implement** in `Journey.swift`. Rules the tests don't fully fix:
  - Gain/loss sums within each segment only. It's `nil` if `segments` is empty, or if any segment has empty `elevations` or `elevations.count != points.count`.
  - The profile has the same `nil` conditions, and also requires `pointDistances.count == points.count` and at least 2 samples. Skip index 0 of every segment after the first, and always add that point's distance to the running total.
  - Imperial heights use `Int((Double(metres) * 3.28084).rounded())`. Convert gain and loss separately from the metre totals.

- [ ] **Step 4: Run to verify they pass.** Same command. Expected: all `JourneyTests` pass.

- [ ] **Step 5: Update `docs/SPEC.md`** Models with `ElevationSample` and the new `Journey` members, including their `nil` conditions.

- [ ] **Step 6: Commit** with the message `feat: derive elevation gain, loss and profile from a journey (#7)`.

### Task 3: Summary card on the Map screen

**Files:**
- Create: `Wheel Routes/Features/Map/RouteSummaryView.swift`
- Modify: `Wheel Routes/Features/Map/MapView.swift:206-208`
- Modify: `docs/SPEC.md` (Map screen, Test coverage, Known limitations, "Last verified")
- Modify: `docs/superpowers/specs/2026-11-02-route-summary-bar-design.md` (Status, and Open verification results)
- Test: `Wheel RoutesTests/Features/RouteSummaryViewTests.swift`

**Interfaces:**
- Consumes: everything Task 2 produces, `Journey.formattedDistance(metric:)`, `Journey.formattedDuration()`, and `MapView.color(for:)`.
- Produces: `RouteSummaryView(journey: Journey, tint: Color)`, and `static RouteSummaryView.elevationDomain(for samples: [ElevationSample]) -> ClosedRange<Int>`, which returns `lowest...max(highest, lowest + 10)`.

- [ ] **Step 1: Write the failing test** for the domain, the only logic in this task:

```swift
@Test func domainSpansLowestToHighest() {
    #expect(RouteSummaryView.elevationDomain(for: samples([20, 175, 60])) == 20...175)
}
@Test func flatRouteDomainIsNotDegenerate() {
    #expect(RouteSummaryView.elevationDomain(for: samples([50, 50])) == 50...60)
}
```

- [ ] **Step 2: Run to verify it fails.** Run the base command with `-only-testing:"Wheel RoutesTests/RouteSummaryViewTests"`. Expected: compile failure, `RouteSummaryView` not found.

- [ ] **Step 3: Implement `RouteSummaryView`.**
  - Read `@AppStorage("useMetric")` and `@Environment(\.verticalSizeClass)`.
  - **Stats row:** a single-line `.subheadline` row of distance · duration · elevation, omitting the elevation when `nil`. Use `.lineLimit(1)` and `.minimumScaleFactor(0.8)`.
  - **Chart:** only when `elevationProfile` is non-`nil` and the vertical size class isn't `.compact`. It's 60 pt tall, with `AreaMark(x:, yStart: domain.lowerBound, yEnd:)` at low opacity plus `LineMark`, both in `tint`. Use `.chartYScale(domain:)`, a hidden x axis, and y-axis marks at the domain's two ends only, labelled with `formattedHeight`. Key points by array offset, since distances can repeat.
  - **Background:** `.padding(12)` with `.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))`.

- [ ] **Step 4: Wire `MapView`.** Replace the bottom overlay's content with a `VStack(spacing: 8)`, shown when `vm.currentJourney` is non-`nil`:
  - `RouteSummaryView(journey:, tint: color(for: journey.plan))`, only when `!isSearchFieldFocused`, with `.padding(.leading)` and `.padding(.trailing, 78)`. The 78 pt clears the control column: 16 outer padding + about 50 button + 12 gap.
  - `startNavigationButton`, unchanged and still screen-centred.

- [ ] **Step 5: Run the full suite.** Run the base command. Expected: all tests pass, including `RouteSummaryViewTests`. Check the output rather than inferring from a build success, and apply the stale-bundle check in `CLAUDE.md` if a new test is missing.

- [ ] **Step 6: Manual check in the simulator.** First set `git update-index --skip-worktree` on `APIKey_dev.txt` and `ThunderforestAPIKey_dev.txt` in this worktree, then copy the real keys in from the main checkout (they're currently not flagged here, so this order matters). Plan a route and confirm:
  - the stats and chart show, and switching plans updates them and the tint;
  - the imperial setting changes the units, and a long imperial row isn't truncated;
  - focusing search hides the card and the results list stays clear;
  - landscape shows stats only;
  - the card doesn't overlap the map controls, including with the compass showing;
  - Clear removes the card.

- [ ] **Step 7: Update the docs.**
  - `docs/SPEC.md`: add `RouteSummaryView` to the Map screen section, add `RouteSummaryViewTests` to Test coverage, list its layout as build-and-manual-check only, and refresh "Last verified".
  - Known limitations: gain/loss is a raw sum (178/29 m against about 162/12 m from the site's coarser table on the test route), with hysteresis as the follow-up.
  - Design doc: set the status to implemented and record the results table above.

- [ ] **Step 8: Work through `docs/REVIEW_CHECKLIST.md`**, confirming `git status` shows neither key file and no signing changes in `project.pbxproj`.

- [ ] **Step 9: Commit** with the message `feat: show route summary card with elevation profile on the map (#7)`.
