import Foundation
import Testing
@testable import Wheel_Routes

struct MapStyleOptionTests {

    @Test func appleStylesHaveNoTileTemplatesOrAttributionOrStyleDocument() {
        for option in [MapStyleOption.appleStandard, .appleHybrid, .appleSatellite] {
            #expect(option.group == .apple)
            #expect(option.isApple)
            #expect(option.appleMapStyle != nil)
            #expect(option.mapLibreStyleDocument(thunderforestKey: "fake-key") == nil)
        }
    }

    @Test func osmStylesAreNotApple() {
        for option in [MapStyleOption.osmStandard, .cyclOSM, .cycleMap] {
            #expect(option.group == .openStreetMap)
            #expect(!option.isApple)
            #expect(option.appleMapStyle == nil)
        }
    }

    @Test func osmStandardUsesThunderforestAtlasWithInterpolatedKey() throws {
        let document = try #require(MapStyleOption.osmStandard.mapLibreStyleDocument(thunderforestKey: "fake-key"))
        let source = try #require(document.sources["raster-tiles"])
        #expect(source.tiles == ["https://tile.thunderforest.com/atlas/{z}/{x}/{y}.png?apikey=fake-key"])
        #expect(source.attribution.contains("Thunderforest"))
    }

    @Test func cycleMapUsesThunderforestCycleWithInterpolatedKey() throws {
        let document = try #require(MapStyleOption.cycleMap.mapLibreStyleDocument(thunderforestKey: "fake-key"))
        let source = try #require(document.sources["raster-tiles"])
        #expect(source.tiles == ["https://tile.thunderforest.com/cycle/{z}/{x}/{y}.png?apikey=fake-key"])
        #expect(source.attribution.contains("Thunderforest"))
    }

    @Test func cyclOSMUsesThreeRotatingSubdomainsAndNoKey() throws {
        let document = try #require(MapStyleOption.cyclOSM.mapLibreStyleDocument(thunderforestKey: "unused"))
        let source = try #require(document.sources["raster-tiles"])
        #expect(source.tiles == [
            "https://a.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png",
            "https://b.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png",
            "https://c.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png",
        ])
        #expect(!source.tiles.contains { $0.contains("unused") })
        #expect(source.attribution.contains("OpenStreetMap"))
    }

    @Test func allCasesHaveDisplayNameAndDistinctThumbnailSymbol() {
        var seenSymbols = Set<String>()
        for option in MapStyleOption.allCases {
            #expect(!option.displayName.isEmpty)
            #expect(!option.thumbnailSymbolName.isEmpty)
            seenSymbols.insert(option.thumbnailSymbolName)
        }
        #expect(seenSymbols.count == MapStyleOption.allCases.count)
    }

    @Test func styleDocumentWritesValidJSONToDisk() throws {
        let document = try #require(MapStyleOption.cyclOSM.mapLibreStyleDocument(thunderforestKey: "unused"))
        let url = try document.writeToTemporaryFile(named: "test-cyclosm-style")
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try Data(contentsOf: url)
        let roundTripped = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(roundTripped?["version"] as? Int == 8)
        #expect((roundTripped?["sources"] as? [String: Any])?["raster-tiles"] != nil)
    }

    @Test func onlyThunderforestBackedStylesRequireAKey() {
        #expect(MapStyleOption.osmStandard.requiresThunderforestKey)
        #expect(MapStyleOption.cycleMap.requiresThunderforestKey)
        #expect(!MapStyleOption.cyclOSM.requiresThunderforestKey)
        #expect(!MapStyleOption.appleStandard.requiresThunderforestKey)
        #expect(!MapStyleOption.appleHybrid.requiresThunderforestKey)
        #expect(!MapStyleOption.appleSatellite.requiresThunderforestKey)
    }

    @Test func osmStylesNavigateInTheirOwnStyle() {
        for option in [MapStyleOption.osmStandard, .cyclOSM, .cycleMap] {
            #expect(option.navigationStyle == option)
        }
    }

    @Test func appleStylesNavigateInCyclOSM() {
        for option in [MapStyleOption.appleStandard, .appleHybrid, .appleSatellite] {
            #expect(option.navigationStyle == .cyclOSM)
        }
    }

    @Test func navigationStyleAlwaysHasAMapLibreStyleDocumentEvenWithoutAThunderforestKey() {
        for option in MapStyleOption.allCases where option.isApple {
            #expect(option.navigationStyle.mapLibreStyleDocument(thunderforestKey: "") != nil)
            #expect(!option.navigationStyle.requiresThunderforestKey)
        }
    }
}
