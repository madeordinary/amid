import Foundation

/// Parsing never opens a store. Explicit malformed seed flags stop startup.
enum VerificationHistorySeedRequest: Equatable, Sendable {
    case disabled
    case invalid
    case configured(source: URL, manifestSHA256: String)

    static func parse(arguments: [String]) -> Self {
        let pathFlag = "--verification-history-seed"
        let hashFlag = "--verification-history-sha256"
        let paths = arguments.indices.filter { arguments[$0] == pathFlag }
        let hashes = arguments.indices.filter { arguments[$0] == hashFlag }
        guard !paths.isEmpty || !hashes.isEmpty else { return .disabled }
        guard arguments.contains("--verification") || arguments.contains("--performance-verification"),
              paths.count == 1, hashes.count == 1,
              arguments.indices.contains(paths[0] + 1), arguments.indices.contains(hashes[0] + 1) else { return .invalid }
        let path = arguments[paths[0] + 1], hash = arguments[hashes[0] + 1]
        guard path.hasPrefix("/private/tmp/amid-owned-retained-profile-"),
              URL(fileURLWithPath: path).deletingLastPathComponent().path == "/private/tmp",
              path == "/private/tmp/" + URL(fileURLWithPath: path).lastPathComponent,
              hash.utf8.count == 64, hash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { return .invalid }
        return .configured(source: URL(fileURLWithPath: path), manifestSHA256: hash)
    }
}
