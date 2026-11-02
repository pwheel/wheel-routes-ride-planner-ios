import CoreLocation
import MapKit
import UIKit

/// Camera framing that fits a whole route into the part of the map not covered by the Map screen's
/// overlays. Holds one form per engine: MapLibre takes `southWest`/`northEast` plus `edgePadding`
/// directly, while SwiftUI's `Map` has no edge-padding API, so `region` is the equivalent visible
/// area, widened so the route lands in the same clear area when the region fills the map.
struct RouteFraming {
    /// Gap between the route and the overlays or map edge, leaving room for marker pins.
    static let margin: CGFloat = 32
    /// Smallest route box, in degrees, so a very short route doesn't zoom in to street-sign level.
    static let minimumSpanDegrees = 0.002
    /// Share of the map kept for the route on each axis when overlays would otherwise fill it, as
    /// they nearly do in landscape. The route then sits partly under the centered Start button and
    /// legend, but stays large enough to read, with its ends clear on the wider screen.
    static let minimumClearFraction: CGFloat = 0.4

    let southWest: CLLocationCoordinate2D
    let northEast: CLLocationCoordinate2D
    let edgePadding: UIEdgeInsets
    let region: MKCoordinateRegion

    /// `nil` when there's nothing to frame, or the map hasn't been measured yet.
    init?(coordinates: [CLLocationCoordinate2D], mapSize: CGSize, obstructions: UIEdgeInsets) {
        guard mapSize.width > 0, mapSize.height > 0,
              let minLatitude = coordinates.map(\.latitude).min(),
              let maxLatitude = coordinates.map(\.latitude).max(),
              let minLongitude = coordinates.map(\.longitude).min(),
              let maxLongitude = coordinates.map(\.longitude).max()
        else { return nil }

        let latitudes = Self.widened(minLatitude...maxLatitude)
        let longitudes = Self.widened(minLongitude...maxLongitude)
        southWest = CLLocationCoordinate2D(latitude: latitudes.lowerBound, longitude: longitudes.lowerBound)
        northEast = CLLocationCoordinate2D(latitude: latitudes.upperBound, longitude: longitudes.upperBound)

        let vertical = Self.padding(obstructions.top, obstructions.bottom, within: mapSize.height)
        let horizontal = Self.padding(obstructions.left, obstructions.right, within: mapSize.width)
        edgePadding = UIEdgeInsets(top: vertical.leading, left: horizontal.leading, bottom: vertical.trailing, right: horizontal.trailing)

        // Web-mercator map points run east and south, so the route's north-west corner is its origin.
        let routeOrigin = MKMapPoint(CLLocationCoordinate2D(latitude: northEast.latitude, longitude: southWest.longitude))
        let routeEnd = MKMapPoint(CLLocationCoordinate2D(latitude: southWest.latitude, longitude: northEast.longitude))
        let clearWidth = Double(mapSize.width - edgePadding.left - edgePadding.right)
        let clearHeight = Double(mapSize.height - edgePadding.top - edgePadding.bottom)
        let mapPointsPerScreenPoint = max((routeEnd.x - routeOrigin.x) / clearWidth, (routeEnd.y - routeOrigin.y) / clearHeight)

        let visibleOrigin = MKMapPoint(
            x: (routeOrigin.x + routeEnd.x) / 2 - (Double(edgePadding.left) + clearWidth / 2) * mapPointsPerScreenPoint,
            y: (routeOrigin.y + routeEnd.y) / 2 - (Double(edgePadding.top) + clearHeight / 2) * mapPointsPerScreenPoint
        )
        let visibleEnd = MKMapPoint(
            x: visibleOrigin.x + Double(mapSize.width) * mapPointsPerScreenPoint,
            y: visibleOrigin.y + Double(mapSize.height) * mapPointsPerScreenPoint
        )
        // Built from the corners rather than `MKCoordinateRegion(MKMapRect)`, whose center is the
        // mercator midpoint: a region's edges are its center ± half the span in plain degrees.
        let topLeft = visibleOrigin.coordinate
        let bottomRight = visibleEnd.coordinate
        region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (topLeft.latitude + bottomRight.latitude) / 2,
                longitude: (topLeft.longitude + bottomRight.longitude) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: topLeft.latitude - bottomRight.latitude,
                longitudeDelta: bottomRight.longitude - topLeft.longitude
            )
        )
    }

    /// `edgePadding` less an inset the map already applies itself. MapLibre adds its automatic
    /// content inset (the tab bar, in portrait) to any padding it's given, which would otherwise
    /// count that space twice.
    func edgePadding(discounting contentInset: UIEdgeInsets) -> UIEdgeInsets {
        UIEdgeInsets(
            top: max(0, edgePadding.top - contentInset.top),
            left: max(0, edgePadding.left - contentInset.left),
            bottom: max(0, edgePadding.bottom - contentInset.bottom),
            right: max(0, edgePadding.right - contentInset.right)
        )
    }

    /// How far the Map screen's overlays reach into the map from its top and bottom edges. Frames
    /// must share a coordinate space. The map runs under the tab bar, so the bottom figure includes
    /// the tab bar as well as the overlay itself.
    static func obstructions(mapFrame: CGRect, topOverlayFrame: CGRect, bottomOverlayFrame: CGRect) -> UIEdgeInsets {
        UIEdgeInsets(
            top: max(0, topOverlayFrame.maxY - mapFrame.minY),
            left: 0,
            bottom: max(0, mapFrame.maxY - bottomOverlayFrame.minY),
            right: 0
        )
    }

    private static func widened(_ range: ClosedRange<Double>) -> ClosedRange<Double> {
        let shortfall = minimumSpanDegrees - (range.upperBound - range.lowerBound)
        guard shortfall > 0 else { return range }
        return (range.lowerBound - shortfall / 2)...(range.upperBound + shortfall / 2)
    }

    /// Adds `margin` to both sides of an axis, scaling them down together if they would leave less
    /// than `minimumClearFraction` of `length` clear.
    private static func padding(_ leading: CGFloat, _ trailing: CGFloat, within length: CGFloat) -> (leading: CGFloat, trailing: CGFloat) {
        let paddedLeading = leading + margin
        let paddedTrailing = trailing + margin
        let total = paddedLeading + paddedTrailing
        let limit = length * (1 - minimumClearFraction)
        guard total > limit else { return (paddedLeading, paddedTrailing) }
        return (paddedLeading * limit / total, paddedTrailing * limit / total)
    }
}
