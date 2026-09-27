import Foundation
import MapKit
import SwiftUI

enum MapStyleGroup {
    case apple
    case openStreetMap
}

enum MapStyleOption: String, CaseIterable, Identifiable {
    case appleStandard
    case appleHybrid
    case appleSatellite
    case osmStandard
    case cyclOSM
    case cycleMap

    static let defaultOption: MapStyleOption = .cyclOSM

    var id: String { rawValue }

    var group: MapStyleGroup {
        switch self {
        case .appleStandard, .appleHybrid, .appleSatellite: return .apple
        case .osmStandard, .cyclOSM, .cycleMap: return .openStreetMap
        }
    }

    var isApple: Bool { group == .apple }

    /// The style turn-by-turn navigation renders with. Ferrostar's UI only runs on MapLibre, so
    /// OSM styles navigate as themselves and Apple styles fall back to CyclOSM, which needs no
    /// Thunderforest key. The persisted `mapStyle` choice is never changed.
    var navigationStyle: MapStyleOption { isApple ? .cyclOSM : self }

    /// `true` for the 2 OSM styles whose tiles are served by Thunderforest and therefore need a
    /// real API key to load (`.osmStandard`, `.cycleMap`); `false` for CyclOSM (no key needed)
    /// and all Apple styles.
    var requiresThunderforestKey: Bool {
        switch self {
        case .osmStandard, .cycleMap: return true
        case .appleStandard, .appleHybrid, .appleSatellite, .cyclOSM: return false
        }
    }

    var displayName: String {
        switch self {
        case .appleStandard: return "Apple Standard"
        case .appleHybrid: return "Apple Hybrid"
        case .appleSatellite: return "Apple Satellite"
        case .osmStandard: return "OSM Standard"
        case .cyclOSM: return "CyclOSM"
        case .cycleMap: return "Cycle Map"
        }
    }

    /// Apple's native `MapStyle` for the 3 Apple-provider cases; `nil` for OSM cases.
    var appleMapStyle: MapStyle? {
        switch self {
        case .appleStandard: return .standard
        case .appleHybrid: return .hybrid
        case .appleSatellite: return .imagery
        case .osmStandard, .cyclOSM, .cycleMap: return nil
        }
    }

    /// Tile URL templates in rotation order for the 3 OSM-provider cases; `nil` for Apple cases.
    /// Thunderforest-backed templates contain a `<key>` placeholder substituted in `mapLibreStyleDocument`.
    private var tileURLTemplates: [String]? {
        switch self {
        case .osmStandard:
            return ["https://tile.thunderforest.com/atlas/{z}/{x}/{y}.png?apikey=<key>"]
        case .cycleMap:
            return ["https://tile.thunderforest.com/cycle/{z}/{x}/{y}.png?apikey=<key>"]
        case .cyclOSM:
            return [
                "https://a.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png",
                "https://b.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png",
                "https://c.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png",
            ]
        case .appleStandard, .appleHybrid, .appleSatellite:
            return nil
        }
    }

    private var attribution: String? {
        switch self {
        case .osmStandard, .cycleMap:
            return "© OpenStreetMap contributors, Maps © Thunderforest"
        case .cyclOSM:
            return "© OpenStreetMap contributors, Tiles courtesy of OpenStreetMap France (CyclOSM)"
        case .appleStandard, .appleHybrid, .appleSatellite:
            return nil
        }
    }

    /// A small swatch color for `MapStyleThumbnail`, distinct per style.
    var thumbnailColor: Color {
        switch self {
        case .appleStandard: return .blue
        case .appleHybrid: return .indigo
        case .appleSatellite: return .brown
        case .osmStandard: return .green
        case .cyclOSM: return .orange
        case .cycleMap: return .teal
        }
    }

    /// An SF Symbol name for `MapStyleThumbnail`, distinct per style.
    var thumbnailSymbolName: String {
        switch self {
        case .appleStandard: return "map"
        case .appleHybrid: return "globe.americas.fill"
        case .appleSatellite: return "camera.fill"
        case .osmStandard: return "map.fill"
        case .cyclOSM: return "bicycle"
        case .cycleMap: return "bicycle.circle.fill"
        }
    }

    /// Builds the minimal MapLibre raster-style document for this OSM style, substituting
    /// `<key>` in its tile URL templates with `thunderforestKey` (a no-op for templates without
    /// the placeholder, e.g. CyclOSM). Returns `nil` for Apple cases.
    func mapLibreStyleDocument(thunderforestKey: String) -> MapLibreStyleDocument? {
        guard let templates = tileURLTemplates, let attribution else { return nil }
        let tiles = templates.map { $0.replacingOccurrences(of: "<key>", with: thunderforestKey) }
        let source = MapLibreStyleDocument.Source(tiles: tiles, attribution: attribution)
        let layer = MapLibreStyleDocument.Layer(id: "raster-tiles", source: "raster-tiles")
        return MapLibreStyleDocument(name: displayName, sources: ["raster-tiles": source], layers: [layer])
    }
}

/// A minimal MapLibre style-spec (version 8) document describing a single raster tile layer.
struct MapLibreStyleDocument: Encodable, Equatable {
    struct Source: Encodable, Equatable {
        var type = "raster"
        var tiles: [String]
        var tileSize = 256
        var attribution: String
    }

    struct Layer: Encodable, Equatable {
        var id: String
        var type = "raster"
        var source: String
    }

    var version = 8
    var name: String
    var sources: [String: Source]
    var layers: [Layer]

    /// Writes this document to `<tmp>/<name>.json` (overwriting any existing file with that
    /// name) and returns its file URL, for use as `MapLibreSwiftUI.MapView`'s `styleURL`.
    func writeToTemporaryFile(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).json")
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
        return url
    }
}
