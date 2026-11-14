# Roadmap: Multi-Route Comparison (Quietest / Balanced / Fastest)

> Status: **Not yet planned.** This is a roadmap entry, not an implementation plan — it captures the ask and known constraints so a future session can run `superpowers:brainstorming` → `superpowers:writing-plans` against it. Do not implement directly from this document.

## The ask

From UAT feedback on v1: the Map view currently plans and displays exactly one route at a time, using whichever `RoutePlan` (`balanced`/`quietest`/`fastest`) is selected. Users want to see all three route options plotted simultaneously so they can visually compare them and pick one, rather than re-planning one type at a time.

## Why this is a new phase, not a v1 bug

The v1 plan ([`2026-06-11-cyclestreets-ride-planner-rewrite.md`](./2026-06-11-cyclestreets-ride-planner-rewrite.md)) intentionally scoped `MapViewModel` around a single active journey:

```swift
var currentJourney: Journey?
var routePlan: RoutePlan = .balanced
```

`planRoute(from:to:)` makes one `apiClient.planJourney(...)` call for the current `routePlan` and overwrites `currentJourney`. Showing three routes at once is a different data model and a different map-rendering approach, not a fix to existing code.

## Known constraints / groundwork already in place

- **API supports this cleanly.** The CycleStreets journey-planning endpoint (`www.cyclestreets.net/api/journey.json`) takes a `plan` param per request — there's no bulk "give me all three plans" call, so this requires 3 concurrent requests (one per `RoutePlan` case), not a single API change. (Verified live during the v1 API-endpoint fixes — see the `worktree-implement-plan` commit `ba7652f` for the confirmed real request/response shapes.)
- **Decoding is ready.** `JourneyPlanDecoder.decode(_:requestedPlan:)` already produces a plain `Journey` per response; reusing it 3x (one per plan) requires no changes to the decoder itself.
- **Map rendering needs new work.** `MapView` currently draws a single `MapPolyline` from `vm.currentJourney?.allCoordinates`. Three simultaneous routes need distinct colors/styling per `RoutePlan` and a way to indicate which one is "selected" vs just "shown for comparison."

## Open design questions (resolve during brainstorming, before writing the plan)

1. **Concurrency & partial failure:** if 2 of 3 plan requests succeed and one fails (e.g. "No routes to plan" — observed live for some coordinate pairs), how should the UI degrade? Show 2 routes with a subtle error for the third? Fail all three?
2. **Selection UX:** tap a route on the map to select it? Tap a route in a small legend/chip row (Quietest / Balanced / Fastest) above or below the map? Selecting should presumably set `currentJourney`/feed into `ItineraryView` (once Finding 1 from the UAT findings doc is fixed and `ItineraryView` is reachable).
3. **Visual differentiation:** color-per-plan (e.g. green=quietest, blue=balanced, red=fastest) is the obvious approach, matching common cycle-routing app conventions — needs a legend so it's discoverable.
4. **Cost/perf:** 3x the API calls on every route-plan action. Is that acceptable, or should this be opt-in ("Compare routes" button) rather than the default `MapView` behavior?
5. **Interaction with `Settings.defaultRoutePlan`:** does that setting become "which route is pre-selected when all three are shown" rather than "the only plan requested"?

## Suggested next step

Run `superpowers:brainstorming` on this doc to resolve the open questions above, then `superpowers:writing-plans` to produce a proper dated implementation plan (new `MapViewModel` API for holding 3 journeys, `MapView` multi-polyline rendering + selection UI, tests for concurrent-fetch success/partial-failure behavior).

---

## Also on the roadmap (smaller items, not yet planned)

These don't need their own file — captured here for now, split out if/when one grows into real design work.

### Editable saved location names

`SavedLocation.name` is set once at save time (`SavedLocationsViewModel.save(name:coordinate:)`, called from `MapView`'s bookmark button using the geocoder result's `place.name` — see [`2026-07-19-uat-findings-v1.md`](./2026-07-19-uat-findings-v1.md) finding 3) and can never be changed afterwards. `SavedLocationsView` only supports delete (`EditButton` + `.onDelete`), no rename/edit affordance. Given the geocoder-supplied name may not be what the user actually wants to call a saved place (e.g. "Downing Street" vs. "Mum's House"), a rename action is worth adding — likely a swipe action or tap-to-edit in `SavedLocationsView`, backed by a new `SavedLocationsViewModel.rename(_:to:)` calling through to `LocationStore` (which already supports arbitrary `save()` upserts by `id`, so no persistence-layer change needed, only a UI affordance + view model method).

### Switchable location-search provider (CycleStreets geocoder vs. MapKit)

> **Resolved (2026-08-12):** implemented as a straight replacement using
> [Photon](https://photon.komoot.io) (OSM-backed), not MapKit — Apple's
> MapKit terms restrict search-result usage to Apple's own map, which
> conflicts with this app's existing OSM-tile rendering (GitHub #9), so
> the MapKit path this section explores was rejected on that basis, not
> pursued as a dual-provider flag. See `docs/superpowers/specs/2026-08-08-improve-typeahead-design.md`
> and `docs/superpowers/plans/2026-08-08-improve-typeahead.md`.

**The complaint:** CycleStreets' own v2 geocoder (`Endpoints.geocode`, used by `MapViewModel.search(query:)` for the "search start/end location" flow) gives disappointing results.

**The observation that opens this up:** CycleStreets' journey-planning endpoint only ever consumes raw `lon,lat` coordinates (`itinerarypoints=lon,lat|lon,lat` — see `Endpoints.journeyPlan`), never place names or IDs. So the geocoder is only used to turn a text search into a coordinate for the "from"/"to" markers — it has no other coupling to CycleStreets' routing itself, and could in principle be swapped for *any* provider that can turn a query into a coordinate.

**Candidate alternative: `MKLocalSearch` (MapKit).** Free, first-party, no API key, no billing — consistent with the v1 plan's "no third-party dependencies" decision. Returns `MKMapItem`s with `.placemark.coordinate`, which map directly onto the existing `Place`/`Coordinate` models. Searches Apple's Maps/POI database rather than the OpenStreetMap data CycleStreets' routing is built on, so an occasional result may snap to a slightly different point than CycleStreets' own geocoder would have — acceptable in practice since only the final coordinate matters to the journey API. `MKLocalSearchCompleter` would also enable real search-as-you-type (current UI only searches on submit), as a nice adjacent upgrade, not a requirement.

**The decision to make:** the user wants to **keep both implementations** (CycleStreets geocoder + MapKit) and pick between them via a configuration flag, rather than replacing one with the other outright — "if that causes too much complexity we can replan," i.e. this preference is not fixed if the complexity turns out not to be worth it.

**Why "just add a flag" isn't free — open design questions for a future brainstorming pass:**
1. **Where does geocoding conceptually live?** Today `geocode(query:)` is a method on `APIClientProtocol` (the CycleStreets network client), which conflates "the CycleStreets API" with "the search provider." Making it swappable likely means extracting a standalone `LocationSearchProviding` (or similar) protocol with two conformances — a `CycleStreetsGeocoderSearch` (wrapping the existing `GeocoderDecoder`) and an `MKLocalSearchProvider` — decoupled from `APIClientProtocol` entirely. That's a real (if mechanical) refactor of `MapViewModel`'s dependency, `AppEnvironment.swift`'s environment key, and `MockAPIClient`/tests.
2. **Where does the flag live?** A user-facing toggle in `SettingsView` (`@AppStorage`, like `useMetric`/`defaultRoutePlan`)? A build-time/compile-time flag (developer-only, no UI)? This changes who can flip it and when.
3. **Test/maintenance burden:** two live search implementations means two things that can regress, and `MapViewModelTests` would need coverage for both providers (or coverage against the abstraction with two provider-specific test suites, mirroring the `GeocoderDecoderTests` pattern).
4. **Is a flag even needed, or is "replace outright" simpler?** If MapKit's results turn out to just be strictly better, a straight swap (no flag, no dual maintenance) may be the pragmatic outcome — worth revisiting once there's a side-by-side comparison of real search results.

**Suggested next step:** do a quick, throwaway side-by-side comparison of CycleStreets-geocoder vs. `MKLocalSearch` results for a handful of real queries (not necessarily shippable code) before deciding whether the dual-implementation-plus-flag approach is worth the complexity in question 1 above, or whether a straight replacement is the better call.

### "Current Location" for journey planning

**The ask:** let the user pick "Current Location" as the from (and/or to) point when planning a route, instead of always having to search by name.

**Why this is greenfield, not a tweak:** confirmed via `grep -rln "CLLocationManager\|NSLocationWhenInUseUsageDescription"` across the whole app target — zero matches. `CoreLocation` is listed in the original plan's tech stack but is only ever actually used today for the `CLLocationCoordinate2D` value type (via `Coordinate.clCoordinate` and MapKit); no permission request, no location manager, no Info.plist usage-description key exists anywhere in the project. This is net-new device-location integration, not an extension of existing code.

**Known groundwork needed:**
- An `NSLocationWhenInUseUsageDescription` entry — since this project uses `GENERATE_INFOPLIST_FILE = YES` with `INFOPLIST_KEY_*` build settings (no checked-in `Info.plist`), this means adding an `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` build setting, not editing a plist file directly.
- A small location-fetching service wrapping `CLLocationManager`'s delegate-based API in something `async/await`-friendly (matching this codebase's style throughout — e.g. `APIClientProtocol`, `GeocoderDecoder`), likely a single one-shot "get current location" call rather than continuous location updates, since route planning only needs a single fix, not live tracking.
- A UI affordance in `MapView`'s search flow (`Features/Map/MapView.swift`) to trigger it — e.g. a location-arrow button next to the search field, or a pinned synthetic row at the top of `resultsList` alongside real geocoder/MapKit results.

**Open design questions:**
1. **Permission UX:** what happens on denied/restricted access — hide the affordance entirely, or show an alert pointing the user at Settings? First-time "when in use" prompt timing (on app launch vs. only when the user actually taps "Current Location")?
2. **From-only or from-and-to?** "Route from where I am" is the obvious common case; is "route to where I am" worth supporting too?
3. **Does it need a display name?** Tapping "Current Location" gets a raw coordinate immediately; showing a human-readable address would mean reverse-geocoding, which pulls in the same provider question as the [switchable location-search provider item above](#switchable-location-search-provider-cyclestreets-geocoder-vs-mapkit) — or the UI could just label it literally "Current Location" and skip reverse geocoding entirely, avoiding that dependency.
4. **Testability:** can't be exercised via `xcodebuild test` on a simulator without either mocking the location service (straightforward, matches this codebase's protocol-based DI pattern) or using a simulated GPX location — worth deciding the test approach up front, not after the fact.

**Suggested next step:** run `superpowers:brainstorming` on the open questions above (especially permission UX and from/to scope) before writing an implementation plan.

### Route summary card follow-ups (GitHub #7)

Two refinements deferred from the route summary card, not yet planned:

1. **Elevation gain/loss hysteresis.** `Journey.elevationGainLoss` sums every raw up/down step between consecutive points, which overstates climbing on noisy data: on a Bath test route the raw sum gave 178 m up / 29 m down against about 162 m / 12 m from cyclestreets.net's coarser elevation table, whereas ignoring changes smaller than about 2 m (hysteresis) gives 166 m / 16 m. A ~2 m threshold in the gain/loss derivation (with tests) would bring the figures in line without changing the profile.
2. **Fit-to-route camera framing with bottom insets.** The summary card sits over the bottom of the map and can cover the route. Framing the camera to fit the whole route with a bottom inset equal to the card/Start-button overlay height, on both map engines (Apple `MapCameraPosition` and MapLibre `MapViewCamera`), would keep the route visible above the card.
