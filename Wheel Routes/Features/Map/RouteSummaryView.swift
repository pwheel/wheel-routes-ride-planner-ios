import Charts
import SwiftUI

/// Floating card over the map: distance · duration · elevation gain/loss, plus an elevation
/// profile when the journey has complete elevation data. Layout is build-and-manual-check only;
/// `elevationDomain(for:)` is the tested logic.
struct RouteSummaryView: View {
    let journey: Journey
    let tint: Color

    @AppStorage("useMetric") private var useMetric = true
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// Y-axis range for the profile: lowest to highest sample, at least 10 m tall so a flat
    /// route doesn't collapse to a zero-height domain. Empty input gives `0...10`.
    static func elevationDomain(for samples: [ElevationSample]) -> ClosedRange<Int> {
        let heights = samples.map(\.elevationMetres)
        guard let lowest = heights.min(), let highest = heights.max() else { return 0...10 }
        return lowest...max(highest, lowest + 10)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            statsRow
            if verticalSizeClass != .compact, let profile = journey.elevationProfile {
                profileChart(profile)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var statsRow: some View {
        let parts = [
            journey.formattedDistance(metric: useMetric),
            journey.formattedDuration(),
            journey.formattedElevation(metric: useMetric)
        ].compactMap { $0 }
        return Text(parts.joined(separator: " · "))
            .font(.subheadline)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private func profileChart(_ profile: [ElevationSample]) -> some View {
        let domain = Self.elevationDomain(for: profile)
        return Chart(Array(profile.enumerated()), id: \.offset) { _, sample in
            AreaMark(
                x: .value("Distance", sample.distanceMetres),
                yStart: .value("Base", domain.lowerBound),
                yEnd: .value("Elevation", sample.elevationMetres)
            )
            .foregroundStyle(tint.opacity(0.25))
            LineMark(
                x: .value("Distance", sample.distanceMetres),
                y: .value("Elevation", sample.elevationMetres)
            )
            .foregroundStyle(tint)
        }
        .chartYScale(domain: domain)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(values: [domain.lowerBound, domain.upperBound]) { value in
                AxisValueLabel {
                    if let metres = value.as(Int.self) {
                        Text(Journey.formattedHeight(metres: metres, metric: useMetric))
                            .font(.caption2)
                    }
                }
            }
        }
        .frame(height: 60)
        .accessibilityHidden(true)
    }
}
