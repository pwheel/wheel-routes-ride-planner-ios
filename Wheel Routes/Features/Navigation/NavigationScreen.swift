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
