import Testing
@testable import Wheel_Routes

struct RouteSummaryViewTests {

    private func samples(_ elevations: [Int]) -> [ElevationSample] {
        elevations.enumerated().map { ElevationSample(distanceMetres: Double($0.offset * 100), elevationMetres: $0.element) }
    }

    @Test func domainSpansLowestToHighest() {
        #expect(RouteSummaryView.elevationDomain(for: samples([20, 175, 60])) == 20...175)
    }

    @Test func flatRouteDomainIsNotDegenerate() {
        #expect(RouteSummaryView.elevationDomain(for: samples([50, 50])) == 50...60)
    }

    @Test func emptySamplesGiveDefaultDomain() {
        #expect(RouteSummaryView.elevationDomain(for: []) == 0...10)
    }

    @Test func distanceDomainSpansZeroToLastSample() {
        let s = [0.0, 5, 12].map { ElevationSample(distanceMetres: $0, elevationMetres: 0) }
        #expect(RouteSummaryView.distanceDomain(for: s) == 0...12)
    }

    @Test func zeroLengthRouteDistanceDomainIsNotDegenerate() {
        let s = [0.0, 0].map { ElevationSample(distanceMetres: $0, elevationMetres: 0) }
        #expect(RouteSummaryView.distanceDomain(for: s) == 0...1)
    }

    @Test func emptySamplesGiveDefaultDistanceDomain() {
        #expect(RouteSummaryView.distanceDomain(for: []) == 0...1)
    }
}
