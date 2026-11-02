import Charts
import SwiftUI

/// Floating card over the map: distance · duration · elevation gain/loss, plus an elevation
/// profile when the journey has complete elevation data. Layout is build-and-manual-check only;
/// `elevationDomain(for:)` and `distanceDomain(for:)` are the tested logic.
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

    /// X-axis range for the profile: 0 to the last sample's distance, so the line fills the chart
    /// width instead of Swift Charts rounding the domain up. At least 1 so a zero-length route
    /// isn't degenerate. Empty input gives `0...1`.
    static func distanceDomain(for samples: [ElevationSample]) -> ClosedRange<Double> {
        guard let last = samples.last?.distanceMetres else { return 0...1 }
        return 0...max(last, 1)
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

    /// One line when it fits; otherwise distance · duration above the elevation figures, so a
    /// narrow phone or large Dynamic Type never truncates the descent.
    private var statsRow: some View {
        let basics = [journey.formattedDistance(metric: useMetric), journey.formattedDuration()]
            .joined(separator: " · ")
        let elevation = journey.formattedElevation(metric: useMetric)
        return ViewThatFits(in: .horizontal) {
            statsText([basics, elevation].compactMap { $0 }.joined(separator: " · "))
            VStack(alignment: .leading, spacing: 2) {
                statsText(basics)
                if let elevation { statsText(elevation) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(statsAccessibilityLabel(basics: basics))
    }

    private func statsText(_ string: String) -> some View {
        Text(string)
            .font(.subheadline)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private func statsAccessibilityLabel(basics: String) -> String {
        var parts = [journey.formattedDistance(metric: useMetric), journey.formattedDuration()]
        if let (gain, loss) = journey.elevationGainLoss {
            parts.append("climb \(Journey.formattedHeight(metres: gain, metric: useMetric))")
            parts.append("descent \(Journey.formattedHeight(metres: loss, metric: useMetric))")
        }
        return parts.joined(separator: ", ")
    }

    /// `AreaPlot` has no constant-baseline form, so each sample carries the y-domain floor.
    private struct AreaSample {
        let distanceMetres: Double
        let base: Int
        let elevationMetres: Int
    }

    private func profileChart(_ profile: [ElevationSample]) -> some View {
        let domain = Self.elevationDomain(for: profile)
        let area = profile.map {
            AreaSample(distanceMetres: $0.distanceMetres, base: domain.lowerBound, elevationMetres: $0.elevationMetres)
        }
        return Chart {
            AreaPlot(
                area,
                x: .value("Distance", \.distanceMetres),
                yStart: .value("Base", \.base),
                yEnd: .value("Elevation", \.elevationMetres)
            )
            .foregroundStyle(tint.opacity(0.25))
            LinePlot(
                profile,
                x: .value("Distance", \.distanceMetres),
                y: .value("Elevation", \.elevationMetres)
            )
            .foregroundStyle(tint)
        }
        .chartXScale(domain: Self.distanceDomain(for: profile))
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
