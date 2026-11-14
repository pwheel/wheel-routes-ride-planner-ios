import CoreLocation
import MapKit
import Testing
import UIKit
@testable import Wheel_Routes

struct RouteFramingTests {

    private let mapSize = CGSize(width: 402, height: 780)
    private let obstructions = UIEdgeInsets(top: 120, left: 0, bottom: 280, right: 0)

    private let northSouthRoute = [
        CLLocationCoordinate2D(latitude: 51.40, longitude: -2.36),
        CLLocationCoordinate2D(latitude: 52.20, longitude: -2.30),
    ]
    private let eastWestRoute = [
        CLLocationCoordinate2D(latitude: 52.20, longitude: -0.50),
        CLLocationCoordinate2D(latitude: 52.25, longitude: 1.20),
    ]

    /// Where `coordinate` lands on screen when `framing.region` fills a view of `mapSize`.
    private func screenPoint(of coordinate: CLLocationCoordinate2D, in framing: RouteFraming) -> CGPoint {
        let region = framing.region
        let topLeft = MKMapPoint(CLLocationCoordinate2D(
            latitude: region.center.latitude + region.span.latitudeDelta / 2,
            longitude: region.center.longitude - region.span.longitudeDelta / 2
        ))
        let bottomRight = MKMapPoint(CLLocationCoordinate2D(
            latitude: region.center.latitude - region.span.latitudeDelta / 2,
            longitude: region.center.longitude + region.span.longitudeDelta / 2
        ))
        let point = MKMapPoint(coordinate)
        return CGPoint(
            x: (point.x - topLeft.x) / (bottomRight.x - topLeft.x) * mapSize.width,
            y: (point.y - topLeft.y) / (bottomRight.y - topLeft.y) * mapSize.height
        )
    }

    // MARK: - Fitting

    @Test func noCoordinatesGiveNoFraming() {
        #expect(RouteFraming(coordinates: [], mapSize: mapSize, obstructions: obstructions) == nil)
    }

    @Test func unmeasuredMapGivesNoFraming() {
        #expect(RouteFraming(coordinates: northSouthRoute, mapSize: .zero, obstructions: obstructions) == nil)
    }

    @Test func boundsEncloseEveryCoordinate() throws {
        let route = northSouthRoute + eastWestRoute
        let framing = try #require(RouteFraming(coordinates: route, mapSize: mapSize, obstructions: obstructions))
        #expect(framing.southWest.latitude == 51.40)
        #expect(framing.southWest.longitude == -2.36)
        #expect(framing.northEast.latitude == 52.25)
        #expect(framing.northEast.longitude == 1.20)
    }

    @Test(arguments: [0, 1])
    func wholeRouteLandsClearOfOverlays(routeIndex: Int) throws {
        let route = [northSouthRoute, eastWestRoute][routeIndex]
        let framing = try #require(RouteFraming(coordinates: route, mapSize: mapSize, obstructions: obstructions))
        for coordinate in route {
            let point = screenPoint(of: coordinate, in: framing)
            #expect(point.y >= obstructions.top - 0.5)
            #expect(point.y <= mapSize.height - obstructions.bottom + 0.5)
            #expect(point.x >= -0.5)
            #expect(point.x <= mapSize.width + 0.5)
        }
    }

    @Test func routeIsCentredInTheClearAreaNotTheView() throws {
        let framing = try #require(RouteFraming(coordinates: northSouthRoute, mapSize: mapSize, obstructions: obstructions))
        let north = screenPoint(of: northSouthRoute[1], in: framing)
        let south = screenPoint(of: northSouthRoute[0], in: framing)
        let clearAreaMidY = obstructions.top + (mapSize.height - obstructions.top - obstructions.bottom) / 2
        #expect(abs((north.y + south.y) / 2 - clearAreaMidY) < 1)
    }

    @Test func tallerCardZoomsOutFurther() throws {
        let oneLine = try #require(RouteFraming(
            coordinates: northSouthRoute, mapSize: mapSize,
            obstructions: UIEdgeInsets(top: 120, left: 0, bottom: 240, right: 0)
        ))
        let twoLine = try #require(RouteFraming(
            coordinates: northSouthRoute, mapSize: mapSize,
            obstructions: UIEdgeInsets(top: 120, left: 0, bottom: 280, right: 0)
        ))
        #expect(twoLine.region.span.latitudeDelta > oneLine.region.span.latitudeDelta)
    }

    @Test func singlePointRouteIsNotDegenerate() throws {
        let point = CLLocationCoordinate2D(latitude: 52.2, longitude: 0.12)
        let framing = try #require(RouteFraming(coordinates: [point], mapSize: mapSize, obstructions: obstructions))
        #expect(framing.northEast.latitude - framing.southWest.latitude >= RouteFraming.minimumSpanDegrees - 1e-9)
        #expect(framing.northEast.longitude - framing.southWest.longitude >= RouteFraming.minimumSpanDegrees - 1e-9)
        #expect(framing.region.span.latitudeDelta > 0)
        #expect(framing.region.span.longitudeDelta > 0)
    }

    @Test func shortRouteStaysCentredWhenWidenedToMinimumSpan() throws {
        let route = [
            CLLocationCoordinate2D(latitude: 52.2000, longitude: 0.1200),
            CLLocationCoordinate2D(latitude: 52.2002, longitude: 0.1202),
        ]
        let framing = try #require(RouteFraming(coordinates: route, mapSize: mapSize, obstructions: obstructions))
        #expect(abs((framing.southWest.latitude + framing.northEast.latitude) / 2 - 52.2001) < 1e-9)
        #expect(abs((framing.southWest.longitude + framing.northEast.longitude) / 2 - 0.1201) < 1e-9)
    }

    // MARK: - Edge padding

    @Test func edgePaddingAddsMarginToEachObstruction() throws {
        let framing = try #require(RouteFraming(coordinates: northSouthRoute, mapSize: mapSize, obstructions: obstructions))
        #expect(framing.edgePadding.top == 120 + RouteFraming.margin)
        #expect(framing.edgePadding.bottom == 280 + RouteFraming.margin)
        #expect(framing.edgePadding.left == RouteFraming.margin)
        #expect(framing.edgePadding.right == RouteFraming.margin)
    }

    @Test func oversizedObstructionsStillLeaveRoomForTheRoute() throws {
        // Landscape: the overlays nearly fill a short map.
        let landscape = CGSize(width: 874, height: 340)
        let framing = try #require(RouteFraming(
            coordinates: northSouthRoute, mapSize: landscape,
            obstructions: UIEdgeInsets(top: 150, left: 0, bottom: 180, right: 0)
        ))
        let clearHeight = landscape.height - framing.edgePadding.top - framing.edgePadding.bottom
        #expect(clearHeight >= landscape.height * RouteFraming.minimumClearFraction - 0.5)
        #expect(framing.edgePadding.top > 0)
        #expect(framing.edgePadding.bottom > framing.edgePadding.top)
    }

    @Test func mapLibrePaddingDiscountsItsOwnContentInset() throws {
        let framing = try #require(RouteFraming(coordinates: northSouthRoute, mapSize: mapSize, obstructions: obstructions))
        let padding = framing.edgePadding(discounting: UIEdgeInsets(top: 0, left: 10, bottom: 83, right: 0))
        #expect(padding.top == framing.edgePadding.top)
        #expect(padding.left == framing.edgePadding.left - 10)
        #expect(padding.bottom == framing.edgePadding.bottom - 83)
        #expect(padding.right == framing.edgePadding.right)
    }

    @Test func discountedPaddingIsNeverNegative() throws {
        let framing = try #require(RouteFraming(coordinates: northSouthRoute, mapSize: mapSize, obstructions: .zero))
        let padding = framing.edgePadding(discounting: UIEdgeInsets(top: 500, left: 500, bottom: 500, right: 500))
        #expect(padding == .zero)
    }

    // MARK: - Obstruction measuring

    @Test func obstructionsMeasureFromTheMapEdges() {
        // The map runs under the tab bar, so the bottom overlay ends above the map's bottom edge.
        let insets = RouteFraming.obstructions(
            mapFrame: CGRect(x: 0, y: 100, width: 402, height: 774),
            topOverlayFrame: CGRect(x: 0, y: 100, width: 402, height: 110),
            bottomOverlayFrame: CGRect(x: 0, y: 600, width: 402, height: 190)
        )
        #expect(insets.top == 110)
        #expect(insets.bottom == 274)
        #expect(insets.left == 0)
        #expect(insets.right == 0)
    }

    @Test func overlaysOutsideTheMapGiveNoObstruction() {
        let insets = RouteFraming.obstructions(
            mapFrame: CGRect(x: 0, y: 100, width: 402, height: 500),
            topOverlayFrame: CGRect(x: 0, y: 0, width: 402, height: 50),
            bottomOverlayFrame: CGRect(x: 0, y: 700, width: 402, height: 50)
        )
        #expect(insets.top == 0)
        #expect(insets.bottom == 0)
    }
}
