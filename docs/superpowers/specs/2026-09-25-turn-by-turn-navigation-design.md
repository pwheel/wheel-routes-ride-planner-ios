# Turn-by-turn navigation via Ferrostar — Design

**Issue:** GitHub #20
**Date:** 2026-09-25
**Status:** Approved design, pending implementation plan

## Goal

Live guidance along a planned `Journey` (maneuver banners, progress, spoken cues, automatic rerouting) using [Ferrostar](https://github.com/stadiamaps/ferrostar), instead of only the static route/marker view that exists today.

## Decisions

| Question | Decision |
|---|---|
| Apple map styles | Navigation is its own full-screen view that **always renders with MapLibre**. It uses the current map style if that style is an OSM one, and falls back to CyclOSM otherwise. The Start button is available whichever style is active, and the planning map's persisted `mapStyle` is never changed. |
| Off-route | **Automatic reroute** through CycleStreets, from the current location to the destination, using the same `RoutePlan`. |
| Voice / background | **Voice guidance in the foreground only**, with a mute toggle and the screen kept awake. No `UIBackgroundModes`. Background navigation is a follow-up issue. |
| UI approach | **Ferrostar's bundled UI** (`DynamicallyOrientingNavigationView`), not custom overlays. |
| Route source | Ferrostar is given a `Route` translated from the already-fetched `Journey` (`startNavigation(route:)`). There's no HTTP `RouteAdapter`. Rerouting uses a `CustomRouteProvider`. |
| Location updates | Ferrostar's own `CoreLocationProvider`. The app's `LocationService` is **not changed**; it's only used as the permission gate before navigation starts. |

## Dependency

- Add `https://github.com/stadiamaps/ferrostar`, **pinned to exactly `0.57.0`**, with the products `FerrostarCore` and `FerrostarMapLibreUI`. `FerrostarMapLibreUI` already includes the `FerrostarSwiftUI` target, so `import FerrostarSwiftUI` works without linking it separately. `SpokenInstructionObserver` lives in `FerrostarCore`, and the route model types (`Route`, `RouteStep` and so on) live in the `FerrostarCoreFFI` module, which the `FerrostarCore` product also ships. Commit the updated `Package.resolved`.
- Ferrostar 0.57.0 requires `maplibre/swiftui-dsl` `from: 0.25.0`, which is compatible with the existing exact pin at `0.25.0`. Leave that pin as it is.
- Ferrostar ships a **precompiled Rust XCFramework** (a checksum-pinned `binaryTarget`) plus generated Swift bindings. Because the binary can't be reviewed as a diff, add a supply-chain note to `CLAUDE.md` next to the `swiftui-dsl` one: keep the exact-version pin, and review every version bump deliberately. It isn't a macro, so no `-skipMacroValidation` changes are needed.

## Components

New group: `Wheel Routes/Features/Navigation/`.

| Unit | Responsibility | Depends on |
|---|---|---|
| `JourneyRouteAdapter` | A pure, throwing function that converts a `Journey` and `useMetric: Bool` into a Ferrostar `Route`. No I/O. | Ferrostar model types |
| `WheelRoutesRerouteProvider` | Ferrostar `CustomRouteProvider`. `getRoutes(userLocation:waypoints:)` calls `apiClient.planJourney(from: userLocation, to: lastWaypoint, plan:)` and converts the result with `JourneyRouteAdapter`. Before rethrowing an error, it calls its `onFailure` callback, because `FerrostarCore` silently swallows reroute errors (`catch {}` in 0.57.0). | `APIClientProtocol`, `JourneyRouteAdapter` |
| `NavigationViewModel` | `@Observable @MainActor final class` that owns `FerrostarCore`. It exposes `navigationState`, `isMuted`, `hasArrived`, `rerouteErrorMessage`, `start()` and `stop()`, and owns `isIdleTimerDisabled`. | `FerrostarCore`, `LocationProviding`, `WheelRoutesRerouteProvider` |
| `NavigationScreen` | Full-screen view hosting `DynamicallyOrientingNavigationView`. Its `styleURL` comes from `MapStyleOption.navigationStyle.mapLibreStyleDocument(...).writeToTemporaryFile(...)`. It also shows the arrival card, the reroute-error banner and the permission-lost alert. | `NavigationViewModel`, `MapStyleOption` |

Changes to existing code:

- `MapStyleOption.navigationStyle` returns `self` for OSM cases and `.cyclOSM` for Apple cases. CyclOSM needs no Thunderforest key.
- `MapViewModel.prepareNavigation() async -> Bool` reuses the existing `currentLocation()` permission and error path. `.permissionDenied`/`.restricted` set `isPresentingLocationPermissionAlert`, `.alreadyInProgress` is swallowed silently, and other errors set `errorMessage`. It returns `true` only on success.
- `MapView` shows a **Start** button when `currentJourney != nil`. On a successful `prepareNavigation()` it presents `NavigationScreen` via `.fullScreenCover` for the selected journey and plan.

**Location in development.** In DEBUG builds, the launch argument `-simulateNavigation` makes `NavigationViewModel` use Ferrostar's `SimulatedLocationProvider`, which replays the route geometry, instead of `CoreLocationProvider`.

## `Journey` → `Route` mapping

### Geometry and metadata
- `Route.geometry` is every segment's `points` joined in order. Where segment *N*'s last point equals segment *N+1*'s first point, it appears only once.
- `bbox` is computed from `Route.geometry`.
- `distance` is `Journey.lengthMetres`.
- `waypoints` holds the first and last coordinates, both with kind `.break`, and `properties` = `nil`.
- Each segment becomes one `RouteStep`:
  - `geometry` = `segment.points`, `distance` = `distanceMetres`, `duration` = `timeSeconds`, `roadName` = `name`
  - `exits` = `[]`, `annotations` = `nil`, `incidents` = `[]`, `drivingSide` = `.right`, `roundaboutExitNumber` = `nil`

### Off-by-one: turns attach to the preceding step
CycleStreets' `segment.turn` is the turn made *to enter* that segment. Ferrostar shows a step's instructions *while the rider is on that step*, so they must describe the maneuver at the step's *end*.

- The instruction for step *N* comes from segment *N+1*'s `turn` and `name`.
- The last step's instruction is **"Arrive at destination"**, with `ManeuverType.arrive` and no modifier.
- Segment 0's own `turn` (the departure) is not used.

### Turn vocabulary
Matching is case-insensitive after trimming whitespace.

| CycleStreets `turn` | `ManeuverType` | `ManeuverModifier` | Verb |
|---|---|---|---|
| straight on | `.continue` | `.straight` | "Continue straight" |
| bear left / bear right | `.turn` | `.slightLeft` / `.slightRight` | "Bear left/right" |
| turn left / turn right | `.turn` | `.left` / `.right` | "Turn left/right" |
| sharp left / sharp right | `.turn` | `.sharpLeft` / `.sharpRight` | "Turn sharp left/right" |
| join roundabout | `.roundabout` | `nil` | "Enter the roundabout" |
| first exit … fifth exit | `.roundabout` | `nil` | "Take the first … fifth exit" |
| nil, empty, or unrecognised | `.continue` | `nil` | "Continue" |

This vocabulary was checked on 2026-09-25 against 18 live journeys (6 cities × 3 plans). Observed values: `straight on`, `turn left/right`, `bear left/right`, `sharp left/right`, `join roundabout`, `second exit`, `third exit`, and `''`. The first segment's turn was always `''`. `first`, `fourth` and `fifth exit` are included by pattern. Anything else falls through to the "Continue" row.

### Instruction text
- **Unnamed segments.** Omit the "onto {name}" clause when the next segment's `name` is blank, or when its lowercased form contains `un-named`. The placeholders observed live were "Short un-named link" and "Un-named alley". For example, "Turn left onto Mill Road" becomes just "Turn left".
- **Visual.** One `VisualInstruction` per step. `primaryContent` has the text, maneuver type and modifier. There's no secondary or sub content. `triggerDistanceBeforeManeuver` is `step.distance`, so the banner shows from the moment the step begins. Ferrostar shows no banner until the distance to the maneuver falls within the trigger distance.
- **Spoken.** Up to two `SpokenInstruction`s per step, each with `ssml` = `nil` and a fresh `UUID`:
  - an advance cue, "In {distance}, {instruction}", triggered at 200 m
  - an immediate cue, "{instruction}", triggered at `min(30 m, step distance)`

  The advance cue is dropped when the step is shorter than 200 m. The immediate cue is always present, with its trigger clamped to the step's length, so short links (common in live data) still announce their turn. The distance phrase follows `useMetric`. Metric is "200 metres". Imperial converts the trigger distance to yards and rounds to the nearest 10, so 200 m becomes "220 yards". The last step's immediate cue is "You have arrived".
- **`RouteStep.instruction`** is the same text as the visual primary content.

### Errors
The adapter throws `JourneyRouteAdapterError.insufficientGeometry` if the journey has fewer than 2 distinct coordinates in total, or no segments.

## Runtime flow

1. **Start.** The Start button calls `MapViewModel.prepareNavigation()`. On success, `NavigationScreen` is presented, and `NavigationViewModel.start()` converts the journey and calls `core.startNavigation(route:)`. It also sets `isIdleTimerDisabled = true`. If the adapter throws, the screen shows an error message and an exit button.
2. **Starting away from the route.** No special handling. The first fixes trigger a deviation, and the rider is rerouted from where they are.
3. **Deviation.** Ferrostar's `.staticThreshold(minimumHorizontalAccuracy:maxAcceptableDeviation:)` deviation detection is used, with named constants starting at a **25 m** minimum horizontal accuracy and a **25 m** maximum acceptable deviation, to be tuned during on-device testing. Ferrostar has no time-window setting here, so poor GPS fixes are filtered by the accuracy gate instead.
4. **Reroute.** Ferrostar calls `WheelRoutesRerouteProvider`, and the delegate's `core(_:loadedAlternateRoutes:)` accepts the first route and clears `rerouteErrorMessage`. That delegate method can be called from a non-main `Task`, so it hops to the main actor before touching the core or view model state. Ferrostar's own in-flight guard prevents overlapping requests. While `navigationState.isCalculatingNewRoute` is true, a "Recalculating route…" loading banner shows.
5. **Reroute failure.** Navigation continues on the old route. `FerrostarCore` swallows the error, so the provider's `onFailure` callback sets `rerouteErrorMessage`, which shows a non-blocking "Couldn't recalculate route" banner, and Ferrostar retries at the next deviation check. A reroute failure never ends the session.
6. **Arrival.** When the trip state is `.complete`, `hasArrived` becomes true and a "You've arrived" card with a **Done** button appears.
7. **Exit.** Both `onTapExit` and Done call `stop()`, which runs `core.stopNavigation()` and sets `isIdleTimerDisabled = false`, then dismiss the screen. `stop()` also runs from `.onDisappear` and is safe to call twice.
8. **Voice.** `FerrostarCore` is built with `SpokenInstructionObserver.initAVSpeechSynthesizer(isMuted: <persisted value>)`, and the mute button calls `toggleMute()`. `isMuted` is persisted with `@AppStorage("navigationMuted")` and defaults to `false`.
9. **Permission lost mid-ride.** `FerrostarCore`'s `didFailWithError` does nothing in 0.57.0, so it can't be relied on. The only way to revoke permission is to leave the app for Settings, so when `scenePhase` becomes `.active`, `NavigationScreen` checks `LocationServiceProtocol.isAuthorized`. If access is no longer authorized, it shows an alert with **Open Settings** and **End Navigation**.
10. **Backgrounding.** Guidance pauses, since v1 is foreground only. When the app returns to the foreground, Ferrostar continues from fresh fixes.

## Testing

TDD with Swift Testing:

- `JourneyRouteAdapterTests`:
  - geometry joining and de-duplication; bbox; distance and duration
  - the turn off-by-one and the arrival step
  - every row of the vocabulary table, plus the unknown and empty cases
  - unnamed-segment wording
  - visual and spoken trigger distances, including dropping cues on short steps
  - metric and imperial phrasing
  - the `insufficientGeometry` error
- `WheelRoutesRerouteProviderTests`: using `MockAPIClient`, checks the from, to and plan passed through, that a successful plan is converted to a route, and that errors propagate.
- `MapStyleOptionTests`: `navigationStyle` for every case.
- `MapViewModelTests`: `prepareNavigation` success, denied, restricted, `.alreadyInProgress` and unavailable.
- `NavigationViewModel`: logic that can be separated from `FerrostarCore` (arrival detection from a `NavigationState` fixture, reroute-error banner state, whether `stop()` is safe to call twice) is tested with state fixtures or a thin protocol seam.

**Build-verify only** (added to SPEC's known gaps): `NavigationScreen` and the Start-button / `.fullScreenCover` wiring. Manual checks are a simulator run with `-simulateNavigation`, and one real ride on a device before merge.

## Docs to update in the same change

- `docs/SPEC.md`:
  - a new "Navigation" screen section
  - Map screen: the Start button and the `navigationStyle` fallback
  - Architecture: the Ferrostar dependency
  - Test coverage: the new tests and gaps
  - Known limitations: no background navigation, and no voice while backgrounded
- `CLAUDE.md`: the Ferrostar supply-chain note.
- A new GitHub issue for background navigation (`UIBackgroundModes` location+audio).

## Out of scope

Background navigation, CarPlay, lane guidance, roundabout exit numbers, navigation on the Apple `Map` engine, and offline routing.
