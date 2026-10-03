import Foundation
import CryptoKit
import Darwin

/// Explicit disposable synthetic-fixture import, never a normal-store or Keychain path.
public enum VerificationHistorySeed {
    public enum Failure: Error { case invalidMode, invalidPath, invalidFixture, invalidHash, io }
    public struct Summary: Codable, Sendable {
        public var days: Int
        public var entities: Int
        public var declaredRecords: Int
        public var ciphertextBytes: Int
        public var anchor: Date
        public var manifestSHA256: String
        public var ciphertextSHA256: String
        public var note: String
    }
    public struct Imported: Sendable { public var store: HistoryStore; public var summary: Summary }
    private struct Descriptor: Decodable {
        var days: Int; var entities: Int; var minuteBuckets: Int; var hourlyBuckets: Int
        var records: Int; var ciphertextBytes: Int; var anchor: Date
    }
    private struct Manifest: Decodable {
        var version: Int; var settings: HistorySettings; var aggregates: [HistoryAggregate]
        var alerts: [AlertEvent]; var actions: [ActionRecord]; var shortenedByCap: Bool; var segmentFiles: [String]
    }
    private static let maximumBytes = 128 * 1024 * 1024
    private static var fixtureKey: SymmetricKey { SymmetricKey(data: Data(repeating: 0x5a, count: 32)) }
    private static func child(_ url: URL, prefix: String) throws -> String {
        let name = url.lastPathComponent
        guard url.path == "/private/tmp/" + name, url.deletingLastPathComponent().path == "/private/tmp",
              name.hasPrefix(prefix), name.count > prefix.count, name.count <= 160,
              !name.contains(".."), name.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 }) else { throw Failure.invalidPath }
        return name
    }
    private static func ownedDirectory(_ parent: Int32, _ name: String) throws -> Int32 {
        let fd = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        var info = stat()
        guard fd >= 0 else { throw Failure.invalidPath }
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFDIR, info.st_uid == getuid() else { close(fd); throw Failure.invalidPath }
        return fd
    }
    private static func read(_ directory: Int32, _ name: String, limit: Int) throws -> Data {
        let fd = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw Failure.invalidPath }; defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(), info.st_nlink == 1,
              info.st_size >= 0, info.st_size <= limit else { throw Failure.invalidFixture }
        var data = Data(count: Int(info.st_size))
        try data.withUnsafeMutableBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.read(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw Failure.io }; offset += count
            }
        }
        var extra: UInt8 = 0
        guard Darwin.read(fd, &extra, 1) == 0 else { throw Failure.invalidFixture }
        return data
    }
    private static func write(_ directory: Int32, _ name: String, data: Data) throws {
        let fd = openat(directory, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw Failure.io }; defer { close(fd) }
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw Failure.io }; offset += count
            }
        }
        guard fsync(fd) == 0 else { throw Failure.io }
    }
    private static func reseal(_ encrypted: Data, using destinationKey: SymmetricKey) throws -> Data {
        guard encrypted.prefix(4) == Data("AMID".utf8) else { throw Failure.invalidFixture }
        let clear = try AES.GCM.open(AES.GCM.SealedBox(combined: encrypted.dropFirst(4)), using: fixtureKey, authenticating: Data("AMID".utf8))
        return Data("AMID".utf8) + (try AES.GCM.seal(clear, using: destinationKey, authenticating: Data("AMID".utf8)).combined!)
    }
    private static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    public static func importStore(from source: URL, to destination: URL, expectedManifestSHA256: String, verificationMode: Bool, now: Date = Date()) throws -> Imported {
        guard verificationMode else { throw Failure.invalidMode }
        let sourceName = try child(source, prefix: "amid-owned-retained-profile-")
        let targetName = try child(destination, prefix: "amid-ui-verification-seeded-")
        guard sourceName != targetName, expectedManifestSHA256.count == 64,
              expectedManifestSHA256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw Failure.invalidHash }
        let parent = open("/private/tmp", O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard parent >= 0 else { throw Failure.invalidPath }; defer { close(parent) }
        let input = try ownedDirectory(parent, sourceName); defer { close(input) }
        let descriptor = try JSONDecoder().decode(Descriptor.self, from: read(input, "profile-fixture.json", limit: 16 * 1024))
        guard [7, 30].contains(descriptor.days), [21, 76].contains(descriptor.entities), descriptor.minuteBuckets == 1440,
              descriptor.hourlyBuckets == (descriptor.days - 1) * 24,
              descriptor.records == (descriptor.minuteBuckets + descriptor.hourlyBuckets) * descriptor.entities,
              descriptor.records <= 165_000, descriptor.ciphertextBytes > 0, descriptor.ciphertextBytes <= maximumBytes,
              descriptor.anchor.timeIntervalSince1970.isFinite, now.timeIntervalSince1970.isFinite,
              abs(now.timeIntervalSince(descriptor.anchor)) <= 3600 else { throw Failure.invalidFixture }
        let encrypted = try read(input, "history.aesgcm", limit: 1024 * 1024)
        guard hash(encrypted) == expectedManifestSHA256 else { throw Failure.invalidHash }
        guard encrypted.prefix(4) == Data("AMID".utf8) else { throw Failure.invalidFixture }
        let clear = try AES.GCM.open(AES.GCM.SealedBox(combined: encrypted.dropFirst(4)), using: fixtureKey, authenticating: Data("AMID".utf8))
        let manifest = try JSONDecoder().decode(Manifest.self, from: clear)
        guard manifest.version == 3, manifest.aggregates.isEmpty, manifest.alerts.isEmpty, manifest.actions.isEmpty,
              !manifest.shortenedByCap, manifest.settings.retention == (descriptor.days == 7 ? .week : .month),
              !manifest.settings.paused, manifest.settings.aliases.isEmpty, manifest.settings.excludedApplications.isEmpty,
              manifest.settings.excludedProjects.isEmpty, !manifest.settings.notificationsEnabled, !manifest.settings.launchAtLogin,
              !manifest.settings.updateChecks, manifest.settings.projectBoundaries.isEmpty,
              manifest.segmentFiles.count == descriptor.minuteBuckets + descriptor.hourlyBuckets,
              Set(manifest.segmentFiles).count == manifest.segmentFiles.count else { throw Failure.invalidFixture }
        for name in manifest.segmentFiles {
            guard name.count <= 160, name.hasPrefix("bucket-"), name.hasSuffix(".aesgcm"), !name.contains(".."),
                  name.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 46 }) else { throw Failure.invalidFixture }
        }
        // Exclusive creation prevents replacing any existing disposable or normal store.
        guard mkdirat(parent, targetName, 0o700) == 0 else { throw Failure.invalidPath }
        let output: Int32
        do { output = try ownedDirectory(parent, targetName) } catch { unlinkat(parent, targetName, AT_REMOVEDIR); throw error }
        var created: [String] = []; var complete = false
        defer {
            if !complete { for name in created { unlinkat(output, name, 0) } }
            close(output)
            if !complete { unlinkat(parent, targetName, AT_REMOVEDIR) }
        }
        let destinationKey = SymmetricKey(size: .bits256)
        var total = encrypted.count; var digest = SHA256(); digest.update(data: encrypted)
        for name in manifest.segmentFiles.sorted() {
            let data = try read(input, name, limit: 2 * 1024 * 1024)
            guard data.prefix(4) == Data("AMID".utf8), data.count <= maximumBytes - total else { throw Failure.invalidFixture }
            total += data.count; digest.update(data: data)
            let rekeyed = try autoreleasepool { try reseal(data, using: destinationKey) }
            created.append(name); try write(output, name, data: rekeyed)
        }
        guard total == descriptor.ciphertextBytes else { throw Failure.invalidFixture }
        created.append("history.aesgcm"); try write(output, "history.aesgcm", data: reseal(encrypted, using: destinationKey))
        guard fsync(output) == 0, fsync(parent) == 0 else { throw Failure.io }
        complete = true
        let summary = Summary(days: descriptor.days, entities: descriptor.entities, declaredRecords: descriptor.records,
            ciphertextBytes: total, anchor: descriptor.anchor, manifestSHA256: expectedManifestSHA256,
            ciphertextSHA256: digest.finalize().map { String(format: "%02x", $0) }.joined(),
            note: "Disposable synthetic fixture re-encrypted with a fresh ephemeral destination key. Import hashes source ciphertext and authenticates/reseals every blob; production load validates aggregate payloads and performs normal maintenance. Declared counts are provenance, not postload counts. Import overhead is not normal-store load overhead.")
        return Imported(store: HistoryStore(directory: destination, keyProvider: EphemeralHistoryKeyProvider(key: destinationKey)), summary: summary)
    }
}
