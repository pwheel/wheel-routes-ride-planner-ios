# Route summary bar (distance, duration, elevation, profile) — Design

**Issue:** GitHub #7
**Date:** 2026-11-02
**Status:** Approved design, pending implementation. The live API response shape hasn't been verified yet (see "Open verification").

## Goal

Once a route is planned, show a summary at the bottom of the Map screen. It gives total distance, duration, elevation gain and loss, and an elevation profile chart, so you no longer have to open the Itinerary to see them.

## Decisions

| Question | Decision |
|---|---|
| Data source | The existing CycleStreets v1 `journey.json` response. No new endpoint or request parameter. Segment markers are believed to carry an `elevations` attribute: a comma-separated list of metres, one per point in `points`. The only evidence so far is third-party: the `cyclestreets` R package reads `elevations` and `distances` from `marker` → `@attributes`. **This must be confirmed against a live response before the decoder fixture is written.** |
| Gain/loss algorithm | **Raw sum to start with**: add up the rises and drops between consecutive points within each segment. Compare the result with the climb figure cyclestreets.net shows for the same route. If it's clearly inflated by terrain-model noise, add a hysteresis threshold of about 2 m as a follow-up. |
| Missing data | If any segment has no elevations, the elevation figure and the profile are hidden, and the bar shows distance and duration only. It never shows a misleading "↑ 0 m". The decoder never throws on missing or malformed elevations. |
| Contents | Distance · duration · ↑gain ↓loss, then the elevation profile chart. |
| Layout | The existing `.overlay(alignment: .bottom)` becomes a `VStack`: the summary card (stats row plus profile) above the Start button. It uses the `.regularMaterial` rounded background, matching the legend capsule. The bottom-trailing map control buttons stay where they are, and the card is inset so it doesn't overlap them. |
| Units | Follows `@AppStorage("useMetric")`: km and m, or mi and ft. |
| Plan switching | The bar reads `vm.currentJourney`, so switching between quietest, balanced and fastest updates it automatically. |

## Components

### Model (`Models/Journey.swift`)
- `Segment.elevations: [Int] = []`, in metres, one per point. The default value keeps existing call sites and stored `Journey` JSON compiling and decoding.
- `Journey.elevationGainLoss: (gain: Int, loss: Int)?`: the raw sum of rises and drops between consecutive points within each segment. Adjacent segments share their endpoint, so the step between segments contributes 0. It's `nil` if any segment has no elevations, or a count that doesn't match its `points`.
- `Journey.elevationProfile: [ElevationSample]?`: one `(distanceMetres: Double, elevationMetres: Int)` per point, where distance is the cumulative great-circle distance along `points`, computed with `CLLocation.distance(from:)`. The duplicate point shared by adjacent segments is collapsed. It's `nil` under the same conditions as above. If the live response turns out to include a usable per-point `distances` attribute, prefer it over computing distances.
- `Journey.formattedElevation(metric:) -> String?`, for example "↑ 145 m ↓ 120 m" or "↑ 476 ft ↓ 394 ft".

### Decoder (`Networking/JourneyPlanDecoder.swift`)
- `RawAttributes.elevations: String?`. Parse it by splitting on `,` and keeping only values that convert to an integer, the same way `parsePoints` handles bad pairs. A missing attribute becomes `[]`.

### UI (`Features/Map/MapView.swift`, or a small `RouteSummaryView.swift` in `Features/Map/`)
- Stats row: `formattedDistance(metric:)` · `formattedDuration()` · `formattedElevation(metric:)`.
- Profile: a Swift Charts `AreaMark` + `LineMark` over `elevationProfile`, roughly 60 pt tall, with minimal axes (a min/max elevation label at most), tinted with the selected plan's color. Hidden when the profile is `nil`.

## Testing (Swift Testing, TDD)
- Decoder: elevations are parsed per segment; a missing attribute gives `[]`; malformed values are skipped.
- `elevationGainLoss`: a flat route; a climb then a descent; several segments (no double counting at the shared endpoint); `nil` when data is missing or doesn't match the points.
- `elevationProfile`: distances add up and increase along the route; the shared endpoint isn't duplicated; `nil` cases.
- `formattedElevation`: metric and imperial.
- The `MapView`/chart wiring is build-check only, per the convention in `docs/SPEC.md` → Test coverage.

## Open verification
1. Capture one live `journey.json` response, with the API key removed, and confirm the following:
   - the `elevations` attribute name and format;
   - whether it's present on the route marker as well as on segments;
   - that its count matches `points` for each segment;
   - whether `distances` is present.

   Use the trimmed response as the decoder test fixture.
2. Compare the raw-sum gain against cyclestreets.net's figure for the same route.

## Docs
Update `docs/SPEC.md` in the implementing commit: the Map screen section, Models (`Segment.elevations` and the new `Journey` members), the API contract (the `elevations` attribute is now parsed), and Test coverage.
