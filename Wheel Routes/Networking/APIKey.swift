import Foundation

enum APIKey {
    enum Error: Swift.Error {
        case fileNotFound, empty
    }

    static func load() throws -> String {
        let name = Bundle.main.object(forInfoDictionaryKey: "APIKeyFileName") as? String
            ?? (ProcessInfo.processInfo.environment["CYCLESTREETS_ENV"] == "live"
                ? "APIKey_live" : "APIKey_dev")
        return try loadKey(named: name, devFallback: "APIKey_dev")
    }

    static func loadThunderforestKey() throws -> String {
        let name = Bundle.main.object(forInfoDictionaryKey: "ThunderforestAPIKeyFileName") as? String
            ?? (ProcessInfo.processInfo.environment["CYCLESTREETS_ENV"] == "live"
                ? "ThunderforestAPIKey_live" : "ThunderforestAPIKey_dev")
        return try loadKey(named: name, devFallback: "ThunderforestAPIKey_dev")
    }

    /// Falls back to the dev key file when the resolved (live) file is missing or blank, since the
    /// live file is gitignored outright and may not exist locally until a distinct production key is set.
    private static func loadKey(named name: String, devFallback: String) throws -> String {
        if let key = try? loadKey(named: name), !key.isEmpty {
            return key
        }
        return try loadKey(named: devFallback)
    }

    private static func loadKey(named name: String) throws -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt") else {
            throw Error.fileNotFound
        }
        let key = (try String(contentsOf: url, encoding: .utf8))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw Error.empty }
        return key
    }
}
