# Design: Heading ("gaze") indicator on the Map screen's location dot

> Addresses GitHub issue #28: "'Gaze' icon on map to show which way you're
> facing." The issue has no further detail; the intent taken here is the
> heading beam/cone familiar from Apple Maps and Google Maps.

## Summary

When the blue user-location dot is visible on the Map screen, it also shows
a beam pointing in the direction the **device is facing** (compass heading).
This is distinct from direction of *travel* (course), and is what helps when
standing still at a junction working out which way to go.

Implemented purely with each map engine's **native** heading indicator. There
is no new location/heading code of our own, and no change to
`LocationService`.

## Where the dot comes from today

- **Apple styles:** `UserAnnotation()` inside `appleMap`'s `Map` content.
- **OSM styles (MapLibre):** we never enable the dot directly. It appears
  because `MapViewCamera.trackUserLocation(zoom:)` puts `MLNMapView` into
  `userTrackingMode = .follow`, which implicitly sets `showsUserLocation =
  true`. Leaving tracking (`.centered`) sets `userTrackingMode = .none` but
  doesn't hide the dot. Confirmed against `swiftui-dsl` v0.25.0
  `MapViewCoordinator.swift`.

## Design

### OSM path (MapLibre)

Set `MLNMapView.showsUserHeadingIndicator` via swiftui-dsl's
`.unsafeMapViewControllerModifier` escape hatch (the DSL has no first-class
modifier for it). This property makes the default user-location annotation
permanently draw its heading indicator, independent of `userTrackingMode`
(without it, MapLibre only draws heading in `.followWithHeading`).

**Permission gate.** Setting `showsUserHeadingIndicator = true` also sets
`showsUserLocation = true`, which starts the map's own location manager and,
for a user who hasn't been asked yet, fires the system permission prompt.
That would break the existing "never prompt at launch" principle (see
SPEC.md → `MapViewModel.isLocationAuthorized`). So the value assigned is
`vm.isLocationAuthorized`, sampled in `body` and captured into the closure:

- Not yet authorized → `false` → no dot, no prompt (unchanged behaviour).
- Authorized (previous session, or just granted via the recenter button /
  "Current Location" row) → `true` → dot + beam, even after the user pans
  away from tracking.

**Update timing caveat.** swiftui-dsl v0.25.0 runs the unsafe closure only
from `updateUIViewController`, never on initial `makeUIViewController`. In
practice the map re-renders almost immediately (camera/state changes after
mount, e.g. launch auto-centering), and the in-context permission grant is
always followed by a camera change (recenter), so the beam picks up on the
next re-render. `isLocationAuthorized` is a non-observable read of
`CLLocationManager.authorizationStatus`, which is why it relies on such
re-renders rather than observation.

The setter is guarded on inequality since the closure runs on every
`updateUIViewController`.

**It can also run too early.** The first update can arrive while the view is
still 0x0, with the camera not yet positioned. Setting the flag then starts
location updates before layout, so launch auto-centering flies in from about
zoom 0.57. At that zoom the whole world fits on screen, MapLibre clamps
latitude to 0, and the follow animation's completion zooms to 15 on the equator.
The result is a flat blue map with the dot pinned to the centre, for an
already-authorized user launching on an OSM style. Found in simulator testing
(the tests can't see it), so the setter also waits for a non-zero frame.

**Side effect, accepted:** an already-authorized user switching to an OSM
style now sees the dot even without having tapped recenter (previously it
appeared only via tracking). This matches the Apple path, where
`UserAnnotation()` always shows the dot when authorized.

### Apple path

No code change expected: MapKit's `UserAnnotation()` draws its native
heading beam on-device when heading data is available. **This needs
on-device confirmation** (the simulator has no compass). If it turns out not
to, the fallback is a custom `UserAnnotation { … }` view, rotated by
`heading − camera.heading` and fed by a new heading stream on
`LocationService` (`startUpdatingHeading`). That would be a new
continuous-updates contract, which contradicts the current "one-shot, no
continuous tracking" `LocationService` invariant, so it needs a SPEC update
and its own tests. It is deliberately not built speculatively.

### Out of scope

- **`NavigationScreen`** (Ferrostar). It has its own course-up puck showing
  direction of travel, which is the right behaviour while riding. Navigation
  passes its own map view, not `osmMap`, so this change doesn't reach it.
- **"Follow with heading" camera mode** (map rotates with the phone), e.g. a
  second tap on recenter. Possible later via `.trackUserLocationWithHeading`
  / `.userLocation(followsHeading: true)`, but not what the issue asks.

## Alternatives considered

- **Own heading stream + custom annotation for both engines:** consistent
  visuals across engines, but needs continuous heading updates in
  `LocationService` (breaking a documented invariant), custom MapLibre
  annotation views, and manual compensation for map rotation. Far more code
  for the same user-visible result. Rejected unless the Apple native check
  fails (see above).

## Testing

View wiring only, with no ViewModel logic, so it's **build-verify-only**
per project convention (added to SPEC.md → Test coverage → Known gaps).
Manual on-device checks:

1. Apple style: rotate the phone → beam on the dot follows.
2. OSM style (e.g. CyclOSM): same; also after panning away from tracking.
3. Fresh install (permission not yet asked): launch → no permission prompt,
   on both an Apple and an OSM persisted style.
4. Grant via the recenter button on an OSM style → beam appears.
5. Full `xcodebuild test` suite still green.
