import SwiftUI
import MapKit
import MapLibre
import MapLibreSwiftDSL
import MapLibreSwiftUI

struct MapView: View {
    @State private var vm: MapViewModel
    @Environment(\.apiClient) private var apiClient
    @Binding var pendingJourney: Journey?
    @Binding var pendingPlaceSelection: PendingPlaceSelection?
    @State private var searchText = ""
    @State private var selectingFor: WaypointRole = .from
    @FocusState private var isSearchFieldFocused: Bool
    @State private var savedLocationsVM = SavedLocationsViewModel()
    @State private var isPresentingLocationSavedConfirmation = false
    private static let initialRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 52.2053, longitude: 0.1218),
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )

    @State private var position = MapCameraPosition.region(MapView.initialRegion)
    @State private var mapLibreCamera = MapView.mapViewCamera(for: MapView.initialRegion)
    @State private var isPresentingMapStyleSheet = false
    @State private var hasAutoCenteredOnLaunch = false

    /// Current map bearing in degrees (0 = north), captured from whichever engine is mounted —
    /// `appleMap`'s `.onMapCameraChange` or `osmMap`'s `.onChange(of: mapLibreCamera)`. Reset to 0
    /// on every style switch (see `.task(id: selectedMapStyle)` below) so a stale heading from the
    /// previous engine can't leave `compassButton` incorrectly visible after switching styles.
    @State private var currentHeading: Double = 0
    /// The Apple path's last-seen camera, captured alongside `currentHeading` so `resetToNorth()`
    /// can rebuild it with `heading: 0` while preserving center/distance/pitch — MapKit's
    /// `MapCameraPosition` binding has no in-place "just zero the heading" API.
    @State private var lastAppleCamera: MapCamera?
    @AppStorage("mapStyle") private var mapStyleRawValue = MapStyleOption.defaultOption.rawValue
    @Environment(\.thunderforestAPIKey) private var thunderforestAPIKey

    /// Style-JSON file URLs, written once per style (not on every `body` evaluation) by
    /// `updateOSMStyleCacheIfNeeded()`, keyed by the style they were generated for.
    @State private var osmStyleURLCache: [MapStyleOption: URL] = [:]

    /// Shared base image for the OSM path's start/end waypoint symbols — hoisted to a static
    /// constant so it isn't recreated on every `body` evaluation (only `.iconColor` differs
    /// between the two waypoints).
    private static let waypointSymbolImage = UIImage(systemName: "mappin.circle.fill")!
        .withRenderingMode(.alwaysTemplate)

    init(apiClient: any APIClientProtocol, locationService: any LocationServiceProtocol, locationSearchProvider: any LocationSearchProviding, pendingJourney: Binding<Journey?>, pendingPlaceSelection: Binding<PendingPlaceSelection?>) {
        let storedRawValue = UserDefaults.standard.string(forKey: "defaultRoutePlan") ?? RoutePlan.balanced.rawValue
        let initialPlan = RoutePlan(rawValue: storedRawValue) ?? .balanced
        _vm = State(initialValue: MapViewModel(apiClient: apiClient, locationService: locationService, searchProvider: locationSearchProvider, initialSelectedPlan: initialPlan))
        _pendingJourney = pendingJourney
        _pendingPlaceSelection = pendingPlaceSelection
    }

    private static func mapViewCamera(for region: MKCoordinateRegion) -> MapViewCamera {
        let center = region.center
        let halfLat = region.span.latitudeDelta / 2
        let halfLon = region.span.longitudeDelta / 2
        let sw = CLLocationCoordinate2D(latitude: center.latitude - halfLat, longitude: center.longitude - halfLon)
        let ne = CLLocationCoordinate2D(latitude: center.latitude + halfLat, longitude: center.longitude + halfLon)
        return .boundingBox(MLNCoordinateBounds(sw: sw, ne: ne))
    }

    private func updateCamera(to region: MKCoordinateRegion) {
        position = .region(region)
        mapLibreCamera = MapView.mapViewCamera(for: region)
    }

    /// Switches the camera into each framework's own follow-user-location
    /// tracking mode — draws the live "blue dot" and pans the camera to it,
    /// entirely internally (see the design doc for why this app doesn't
    /// roll its own continuous location tracking). Both triggers (passive
    /// auto-center and the recenter button) call this only once permission
    /// is already known to be granted, so it never itself provokes the
    /// system permission prompt.
    private func startTrackingCurrentLocation() {
        position = .userLocation(fallback: .region(MapView.initialRegion))
        mapLibreCamera = .trackUserLocation(zoom: 15)
    }

    /// Best-effort inverse of `mapViewCamera(for:)`, extracting an `MKCoordinateRegion` from
    /// whatever `CameraState` MapLibre's camera binding currently holds after a user gesture.
    /// Handles the two states this feature realistically produces (`.centered`, from gesture
    /// pans/pinches once the map has moved; `.rect`, our own programmatic bounding-box writes).
    /// Any other state (`.trackingUserLocation`, while the recenter feature has following
    /// active; `showcase`) falls back to `nil`, leaving `position` unchanged. That's fine for
    /// `.trackingUserLocation`: it doesn't carry a coordinate for us to sync anyway — MapLibre
    /// pans its own view internally as GPS fixes arrive without updating this binding's value —
    /// and a real user gesture already exits tracking mode (flipping the binding to `.centered`)
    /// before this is ever called with it.
    private static func region(for camera: MapViewCamera) -> MKCoordinateRegion? {
        switch camera.state {
        case let .centered(onCoordinate: coordinate, zoom: zoom, pitch: _, pitchRange: _, direction: _):
            // MapLibre's centered state only carries a zoom level, not a lat/lon span, so this
            // approximates the visible span from zoom using the standard web-mercator tile size
            // (256px tiles, world width 360°). It won't exactly match the on-screen viewport
            // (that depends on the view's pixel size, which isn't available here), but it's
            // monotonic with zoom and good enough to avoid discarding the user's pan/zoom when
            // switching rendering paths.
            let span = 360.0 / pow(2.0, zoom)
            return MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
            )
        case let .rect(boundingBox: box, edgePadding: _):
            let center = CLLocationCoordinate2D(
                latitude: (box.ne.latitude + box.sw.latitude) / 2,
                longitude: (box.ne.longitude + box.sw.longitude) / 2
            )
            let span = MKCoordinateSpan(
                latitudeDelta: abs(box.ne.latitude - box.sw.latitude),
                longitudeDelta: abs(box.ne.longitude - box.sw.longitude)
            )
            return MKCoordinateRegion(center: center, span: span)
        default:
            return nil
        }
    }

    /// Writes this style's MapLibre style-JSON to disk once per style change (not on every
    /// `body` evaluation) and caches its URL, driven by `.task(id: selectedMapStyle)` in `body`.
    /// A no-op for Apple styles or once the current style is already cached.
    private func updateOSMStyleCacheIfNeeded() {
        guard !selectedMapStyle.isApple, osmStyleURLCache[selectedMapStyle] == nil,
              let document = selectedMapStyle.mapLibreStyleDocument(thunderforestKey: thunderforestAPIKey)
        else { return }
        osmStyleURLCache[selectedMapStyle] = try? document.writeToTemporaryFile(named: selectedMapStyle.rawValue)
    }

    /// True once the map has been rotated away from north by more than a hair — gates
    /// `compassButton`'s visibility. `currentHeading` is degrees clockwise from north in `0..<360`
    /// (both engines report it that way), so distance-from-north is the smaller of the two
    /// directions around the circle.
    private var isRotated: Bool {
        let normalized = currentHeading.truncatingRemainder(dividingBy: 360)
        return min(normalized, 360 - normalized) > 0.5
    }

    /// Resets whichever engine is currently mounted back to north, preserving its center/zoom/
    /// pitch. Only called from `compassButton`, which is only visible while `isRotated`.
    private func resetToNorth() {
        if selectedMapStyle.appleMapStyle != nil {
            guard var camera = lastAppleCamera else { return }
            camera.heading = 0
            withAnimation { position = .camera(camera) }
        } else if case let .centered(onCoordinate: coordinate, zoom: zoom, pitch: pitch, pitchRange: pitchRange, direction: _) = mapLibreCamera.state {
            mapLibreCamera = .center(coordinate, zoom: zoom, pitch: pitch, pitchRange: pitchRange, direction: 0)
        }
        currentHeading = 0
    }

    private var selectedMapStyle: MapStyleOption {
        get { MapStyleOption(rawValue: mapStyleRawValue) ?? .defaultOption }
        nonmutating set { mapStyleRawValue = newValue.rawValue }
    }

    private var mapStyleBinding: Binding<MapStyleOption> {
        Binding(get: { selectedMapStyle }, set: { selectedMapStyle = $0 })
    }

    var body: some View {
        ZStack(alignment: .top) {
            map
                .task(id: selectedMapStyle) {
                    // Also resets `compassButton`'s heading: a style switch remounts the
                    // underlying map view (see the class comment on `MapStyleOption`), so a
                    // heading captured from the previous engine would otherwise linger and
                    // could leave the button incorrectly visible against a freshly north-up map.
                    currentHeading = 0
                    updateOSMStyleCacheIfNeeded()
                }
            VStack(spacing: 0) {
                searchBar
                if isSearchFieldFocused && !resultsListIsEmpty { resultsList }
                if !vm.routeOptions.isEmpty { legendRow.padding(.top, 8) }
            }
            .padding(.top, 8)
        }
        .overlay(alignment: .bottomTrailing) { mapControlButtons }
        .navigationTitle("Plan Route")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let journey = vm.currentJourney {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink("Itinerary") {
                        ItineraryView(journey: journey, apiClient: apiClient)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Clear") {
                        vm.clearRoute()
                        selectingFor = .from
                    }
                }
            }
        }
        .overlay {
            if vm.isLoading { ProgressView().scaleEffect(1.5) }
        }
        .alert("Error", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
        .alert("Location Saved", isPresented: $isPresentingLocationSavedConfirmation) {
            Button("OK", role: .cancel) {}
        }
        .alert("Location Access Needed", isPresented: Binding(
            get: { vm.isPresentingLocationPermissionAlert },
            set: { vm.isPresentingLocationPermissionAlert = $0 }
        )) {
            Button("Cancel", role: .cancel) {}
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text("Location access is off. Enable it in Settings to use Current Location.")
        }
        .onChange(of: pendingJourney) { _, newValue in
            guard let journey = newValue else { return }
            vm.loadJourney(journey)
            if let end = journey.allCoordinates.last {
                withAnimation {
                    updateCamera(to: MKCoordinateRegion(
                        center: end,
                        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                    ))
                }
            }
            pendingJourney = nil
        }
        .onChange(of: pendingPlaceSelection) { _, newValue in
            guard let selection = newValue else { return }
            if selection.role == .from { selectingFor = .to }
            withAnimation {
                updateCamera(to: MKCoordinateRegion(
                    center: selection.place.clCoordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                ))
            }
            Task {
                await vm.selectPlace(selection.place, as: selection.role)
                if vm.fromPlace != nil && vm.toPlace != nil {
                    isSearchFieldFocused = false
                }
                pendingPlaceSelection = nil
            }
        }
        .onAppear {
            // Passive auto-center: only fires once permission was already
            // granted in a previous session, so it never prompts at launch.
            // `hasAutoCenteredOnLaunch` records that the Map screen's first
            // appearance happened — independent of whether authorization was
            // granted at that moment — not that auto-center itself happened.
            // That's what makes switching tabs away and back not re-snap the
            // camera: if we only set the flag inside the authorization guard,
            // a `.notDetermined`-at-first-appearance session where the user
            // later grants access via the recenter button would still have
            // the flag unset, and the next tab-switch-back would incorrectly
            // auto-center over wherever the user had since panned to.
            guard !hasAutoCenteredOnLaunch else { return }
            hasAutoCenteredOnLaunch = true
            guard vm.isLocationAuthorized else { return }
            startTrackingCurrentLocation()
        }
        // One-shot bias-coordinate fetch, tied to this view's real lifetime
        // (not `MapViewModel.init`, which runs on every discarded
        // reconstruction of the `@State` value — e.g. every tab switch).
        // `.task` only runs once per view identity, matching that intent
        // without an extra `@State` guard flag.
        .task {
            vm.loadBiasCoordinateIfAuthorized()
        }
    }

    @ViewBuilder
    private var map: some View {
        if let appleStyle = selectedMapStyle.appleMapStyle {
            appleMap(style: appleStyle)
        } else if let styleURL = osmStyleURLCache[selectedMapStyle] {
            osmMap(styleURL: styleURL)
        } else {
            // The style JSON hasn't been written yet (or failed to write) — degrade to Apple's
            // standard style rather than pointing MapLibre at a guaranteed-nonexistent file.
            // `.task(id: selectedMapStyle)` below populates the cache, which re-evaluates this
            // view and switches to `osmMap` as soon as it lands.
            appleMap(style: .standard)
        }
    }

    private func appleMap(style: MapStyle) -> some View {
        Map(position: $position) {
            UserAnnotation()
            ForEach(nonSelectedRouteOptions) { option in
                if let journey = option.journey {
                    MapPolyline(coordinates: journey.allCoordinates)
                        .stroke(color(for: option.plan), lineWidth: 3)
                }
            }
            if let selectedOption = vm.routeOptions.first(where: { $0.plan == vm.selectedPlan }),
               let journey = selectedOption.journey {
                MapPolyline(coordinates: journey.allCoordinates)
                    .stroke(color(for: selectedOption.plan), lineWidth: 5)
            }
            if let from = vm.fromPlace {
                Marker("Start", coordinate: from.clCoordinate).tint(.green)
            }
            if let to = vm.toPlace {
                Marker("End", coordinate: to.clCoordinate).tint(.red)
            }
        }
        .mapStyle(style)
        .ignoresSafeArea(edges: .bottom)
        .onTapGesture { isSearchFieldFocused = false }
        // Keep the OSM-path camera in sync with user-driven Apple-map gestures (pan/zoom/rotate),
        // not just the 3 programmatic recenters `updateCamera(to:)` already covers — otherwise
        // switching to an OSM style discards whatever the user just panned to. Only mounted while
        // an Apple style is active, so this can't fight with the OSM path's own camera sync below.
        // Also captures the live camera/heading for `compassButton` — MapKit's own `MapCompass`
        // control isn't used here because it's pinned to the map's top-trailing corner, which sits
        // directly under `searchBar`'s opaque background in this screen's layout (GitHub #3
        // follow-up); a custom button stacked above `recenterButton` replaces it for both engines.
        .onMapCameraChange(frequency: .onEnd) { context in
            mapLibreCamera = MapView.mapViewCamera(for: context.region)
            lastAppleCamera = context.camera
            currentHeading = context.camera.heading
        }
    }

    private func osmMap(styleURL: URL) -> some View {
        MapLibreSwiftUI.MapView(styleURL: styleURL, camera: $mapLibreCamera) {
            for option in nonSelectedRouteOptions {
                if let journey = option.journey {
                    let source = ShapeSource(identifier: "route-\(option.plan.rawValue)") {
                        MLNPolylineFeature(coordinates: journey.allCoordinates)
                    }
                    LineStyleLayer(identifier: "route-\(option.plan.rawValue)-line", source: source)
                        .lineCap(.round)
                        .lineJoin(.round)
                        .lineColor(uiColor(for: option.plan))
                        .lineWidth(3)
                }
            }
            if let selectedOption = vm.routeOptions.first(where: { $0.plan == vm.selectedPlan }),
               let journey = selectedOption.journey {
                let source = ShapeSource(identifier: "route-\(selectedOption.plan.rawValue)-selected") {
                    MLNPolylineFeature(coordinates: journey.allCoordinates)
                }
                LineStyleLayer(identifier: "route-\(selectedOption.plan.rawValue)-selected-line", source: source)
                    .lineCap(.round)
                    .lineJoin(.round)
                    .lineColor(uiColor(for: selectedOption.plan))
                    .lineWidth(5)
            }
            if let from = vm.fromPlace {
                let startSource = ShapeSource(identifier: "waypoint-start") {
                    MLNPointFeature(coordinate: from.clCoordinate)
                }
                // No `.text(...)` label here (unlike the Apple path's `Marker("Start", ...)`):
                // MapLibre/Mapbox GL suppresses a symbol's icon entirely if its text can't be
                // rendered (e.g. a glyph-server fetch failure), which is exactly what broke these
                // markers when a `.text("Start")` + external glyphs URL were added in an earlier
                // pass — confirmed by removing them and observing the icons reappear. Not worth
                // re-attempting for a cosmetic label given that fragility.
                SymbolStyleLayer(identifier: "waypoint-start-symbol", source: startSource)
                    .iconImage(MapView.waypointSymbolImage)
                    .iconColor(.systemGreen)
            }
            if let to = vm.toPlace {
                let endSource = ShapeSource(identifier: "waypoint-end") {
                    MLNPointFeature(coordinate: to.clCoordinate)
                }
                SymbolStyleLayer(identifier: "waypoint-end-symbol", source: endSource)
                    .iconImage(MapView.waypointSymbolImage)
                    .iconColor(.systemRed)
            }
        }
        // Move MapLibre's attribution control out from under the new bottom-right layers button
        // (which the ODbL/Thunderforest ToS-required attribution must stay visible/tappable
        // under). Only needed here — Apple's own `Map` has no competing attribution control.
        // No `CompassView()` here (unlike this file's history) — it's pinned to the map's
        // top-trailing corner, which sits directly under `searchBar`'s opaque background in this
        // screen's layout (GitHub #3 follow-up); `compassButton`, stacked above `recenterButton`,
        // replaces it for both engines instead.
        .mapControls {
            LogoView()
            AttributionButton().position(.bottomLeft)
        }
        .ignoresSafeArea(edges: .bottom)
        .onTapGesture { isSearchFieldFocused = false }
        // Propagate user-driven OSM-map gestures back to the Apple-path camera, mirroring
        // `appleMap`'s `.onMapCameraChange` above. Guarded to gesture-originated changes
        // (`lastReasonForChange != .programmatic`) so this doesn't just re-derive `position` from
        // our own `updateCamera(to:)`/cache-driven writes to `mapLibreCamera`. Only mounted while
        // an OSM style is active, so this can't fight with the Apple path's own sync above.
        .onChange(of: mapLibreCamera) { _, newValue in
            // Heading capture for `compassButton`, unguarded by `lastReasonForChange` (unlike the
            // `position` sync below) so it also reflects our own `resetToNorth()` writes. Only
            // the `.centered` case (the one gestures produce) carries a `direction`; tracking
            // states don't, so heading tracking is a no-op while user-location tracking is active.
            if case let .centered(onCoordinate: _, zoom: _, pitch: _, pitchRange: _, direction: direction) = newValue.state {
                currentHeading = direction
            }
            guard let reason = newValue.lastReasonForChange, reason != .programmatic,
                  let region = MapView.region(for: newValue)
            else { return }
            position = .region(region)
        }
    }

    private func uiColor(for plan: RoutePlan) -> UIColor {
        switch plan {
        case .quietest: return .systemGreen
        case .balanced: return .systemYellow
        case .fastest: return .systemRed
        }
    }

    private var nonSelectedRouteOptions: [RouteOption] {
        vm.routeOptions.filter { $0.plan != vm.selectedPlan }
    }

    private func color(for plan: RoutePlan) -> Color {
        switch plan {
        case .quietest: return .green
        case .balanced: return .yellow
        case .fastest: return .red
        }
    }

    private var legendRow: some View {
        HStack(spacing: 12) {
            ForEach(vm.routeOptions) { option in
                Button {
                    vm.selectedPlan = option.plan
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(color(for: option.plan))
                            .frame(width: 10, height: 10)
                        Text(option.plan.displayName)
                        if option.failed {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        option.plan == vm.selectedPlan ? Color.secondary.opacity(0.2) : Color.clear,
                        in: Capsule()
                    )
                }
                .disabled(option.failed)
                .opacity(option.failed ? 0.5 : 1)
            }
        }
        .padding(8)
        .background(.regularMaterial, in: Capsule())
        .padding(.horizontal)
    }

    private var mapControlButtons: some View {
        VStack(spacing: 12) {
            if isRotated { compassButton }
            recenterButton
            layersButton
        }
        .padding()
    }

    /// Reset-to-north control (GitHub #3), stacked above `recenterButton`. Neither engine's own
    /// built-in compass (`MapCompass()`/`CompassView()`) is used — both default to the map's
    /// top-trailing corner, which sits directly under `searchBar`'s opaque background in this
    /// screen's layout, making them invisible in practice.
    private var compassButton: some View {
        Button {
            resetToNorth()
        } label: {
            Image(systemName: "location.north.line.fill")
                .font(.title2)
                .rotationEffect(.degrees(-currentHeading))
                .padding(12)
                .background(.regularMaterial, in: Circle())
        }
        .accessibilityLabel("Reset map to north")
    }

    private var recenterButton: some View {
        Button {
            recenterOnCurrentLocation()
        } label: {
            Image(systemName: "location.fill")
                .font(.title2)
                .padding(12)
                .background(.regularMaterial, in: Circle())
        }
        .accessibilityLabel("Recenter on current location")
    }

    private var layersButton: some View {
        Button {
            isPresentingMapStyleSheet = true
        } label: {
            Image(systemName: "square.3.layers.3d")
                .font(.title2)
                .padding(12)
                .background(.regularMaterial, in: Circle())
        }
        .accessibilityLabel("Map style")
        .sheet(isPresented: $isPresentingMapStyleSheet) {
            MapStyleSheet(selection: mapStyleBinding, thunderforestAPIKey: thunderforestAPIKey)
        }
    }

    /// Fetches the current location via `MapViewModel` first (so a
    /// permission failure surfaces through the existing "Location Access
    /// Needed" / generic error alerts) and only then switches the camera
    /// into tracking mode — never lets the map frameworks request their own
    /// authorization silently with no app-level fallback UI on denial.
    private func recenterOnCurrentLocation() {
        guard !vm.isLoading else { return }
        Task {
            guard await vm.centerOnCurrentLocation() else { return }
            startTrackingCurrentLocation()
        }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(
                selectingFor == .from ? "Search start location" : "Search end location",
                text: $searchText
            )
            .submitLabel(.search)
            .focused($isSearchFieldFocused)
            .onSubmit { Task { await vm.search(query: searchText) } }
            .onChange(of: searchText) { _, newValue in vm.searchTextChanged(newValue) }
            if !searchText.isEmpty {
                Button { searchText = ""; vm.searchResults = [] } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
            Picker("", selection: $selectingFor) {
                Text("From").tag(WaypointRole.from)
                Text("To").tag(WaypointRole.to)
            }
            .pickerStyle(.segmented)
            .frame(width: 100)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    /// True when the *other* waypoint (not the one `selectingFor` is about
    /// to fill) is already the synthesized "Current Location" place —
    /// routing from/to the same point never makes sense, so the row is
    /// hidden rather than left tappable into a no-op-looking result.
    private var otherWaypointIsCurrentLocation: Bool {
        let other = selectingFor == .from ? vm.toPlace : vm.fromPlace
        return other?.isCurrentLocation ?? false
    }

    /// Gates the "Current Location" row: hidden once the user starts
    /// typing (they're searching by name at that point, not picking a
    /// preset — a future "Saved Locations" preset row should follow the
    /// same `searchText.isEmpty` gating) or once the other waypoint is
    /// already Current Location (see `otherWaypointIsCurrentLocation`).
    private var isShowingCurrentLocationRow: Bool {
        searchText.isEmpty && !otherWaypointIsCurrentLocation
    }

    /// True when `resultsList` has nothing to show — e.g. the other
    /// waypoint is already Current Location and the user hasn't typed
    /// anything yet — so the card can be omitted entirely rather than
    /// rendering as an empty floating rounded box.
    private var resultsListIsEmpty: Bool {
        !isShowingCurrentLocationRow && vm.searchResults.isEmpty
    }

    private var resultsList: some View {
        // No `.frame(maxHeight:)` on this VStack itself: inside this view's
        // ZStack (a sibling `.ignoresSafeArea` map offers effectively
        // unbounded height), a plain VStack with an outer maxHeight cap was
        // observed filling that cap even with just the single "Current
        // Location" button and no List at all — confirmed visually via
        // simulator UI automation, not just inferred from code (UAT
        // finding, see docs/superpowers/plans/2026-08-02-uat-findings-current-location.md).
        // The only child that's actually greedy is the List below, so the
        // cap belongs on it alone, matching this view's pre-feature
        // behavior (the List always had its own `.frame(maxHeight:)`).
        VStack(alignment: .leading, spacing: 0) {
            if isShowingCurrentLocationRow {
                Button {
                    useCurrentLocation()
                } label: {
                    // Padding and the minimum height live *inside* the label so the
                    // whole visually-padded row is part of the hit region (and clears
                    // the 44pt HIG minimum) — applied outside the `Button`, only the
                    // bare ~22pt `HStack` would have been tappable.
                    HStack {
                        Image(systemName: "location.fill")
                        Text("Current Location")
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if isShowingCurrentLocationRow && !vm.searchResults.isEmpty {
                Divider()
            }

            if !vm.searchResults.isEmpty {
                List(vm.searchResults) { place in
                    HStack {
                        Button {
                            selectPlace(place)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(place.name).font(.body)
                                if let near = place.near {
                                    Text(near).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        Spacer()
                        Button {
                            savedLocationsVM.save(name: place.name, coordinate: place.coordinate)
                            isPresentingLocationSavedConfirmation = true
                        } label: {
                            Image(systemName: "bookmark")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .listStyle(.plain)
                // `List` is inherently greedy — without its own height, it
                // fills whatever space its container offers regardless of
                // row count. Cap it directly here rather than on an
                // ancestor (UAT finding, see
                // docs/superpowers/plans/2026-08-02-uat-findings-current-location.md).
                .frame(maxHeight: 200)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    private func selectPlace(_ place: Place) {
        searchText = ""
        vm.searchResults = []
        let role = selectingFor
        if role == .from { selectingFor = .to }
        withAnimation {
            updateCamera(to: MKCoordinateRegion(
                center: place.clCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            ))
        }
        Task {
            await vm.selectPlace(place, as: role)
            if vm.fromPlace != nil && vm.toPlace != nil {
                isSearchFieldFocused = false
            }
        }
    }

    private func useCurrentLocation() {
        // The loading overlay is a bare `ProgressView` that doesn't block hit
        // testing, so this row stays tappable during a fetch that can take
        // seconds. A second trigger would strand the first one's continuation,
        // so ignore repeat taps while one is already in flight.
        guard !vm.isLoading else { return }
        searchText = ""
        vm.searchResults = []
        let role = selectingFor
        Task {
            // Unlike `selectPlace`, this can fail (permission denied, no fix).
            // Advance the picker and recenter only once a place actually came
            // back — flipping From→To up front would silently retarget the
            // user's retry after they fix permissions in Settings.
            guard let place = await vm.useCurrentLocation(as: role) else { return }
            if role == .from { selectingFor = .to }
            withAnimation {
                updateCamera(to: MKCoordinateRegion(
                    center: place.clCoordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                ))
            }
            if vm.fromPlace != nil && vm.toPlace != nil {
                isSearchFieldFocused = false
            }
        }
    }
}
