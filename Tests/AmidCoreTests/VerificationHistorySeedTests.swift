import XCTest
import CryptoKit
import Darwin
@testable import AmidCore

final class VerificationHistorySeedTests: XCTestCase, @unchecked Sendable {
    private struct Descriptor: Encodable { var days = 7; var entities = 21; var minuteBuckets = 1440; var hourlyBuckets = 144; var records = 33_264; var ciphertextBytes: Int; var anchor: Date }
    private struct Manifest: Encodable { var version = 3; var settings = HistorySettings(retention: .week); var aggregates: [HistoryAggregate] = []; var alerts: [AlertEvent] = []; var actions: [ActionRecord] = []; var shortenedByCap = false; var segmentFiles: [String] }
    private let key = SymmetricKey(data: Data(repeating: 0x5a, count: 32))
    private func source() -> URL { URL(fileURLWithPath: "/private/tmp/amid-owned-retained-profile-" + UUID().uuidString) }
    private func target() -> URL { URL(fileURLWithPath: "/private/tmp/amid-ui-verification-seeded-" + UUID().uuidString) }
    private func encrypted<T: Encodable>(_ value: T) throws -> Data {
        Data("AMID".utf8) + (try AES.GCM.seal(JSONEncoder().encode(value), using: key, authenticating: Data("AMID".utf8)).combined!)
    }
    private func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private func fixture(_ source: URL, populated: Bool = false) throws -> String {
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970 / 60) * 60)
        var files: [String] = []; var bytes = 0
        for index in 0..<1584 {
            let resolution: Double = index < 144 ? 3600 : 60
            let time = index < 144 ? floor(now.timeIntervalSince1970 / 3600) * 3600 - Double(168-index) * 3600 : now.timeIntervalSince1970 - Double(1584-index) * 60
            let name = "bucket-\(Int64(time))-\(Int(resolution)).aesgcm"; files.append(name)
            if populated {
                let rows = (0..<21).map { HistoryAggregate(entityID: $0 == 0 ? "system" : "app:owned.synthetic.application.\($0)", name: "Synthetic \($0)", start: Date(timeIntervalSince1970: time), resolution: resolution) }
                let data = try encrypted(rows); try data.write(to: source.appendingPathComponent(name)); bytes += data.count
            }
        }
        let manifest = try encrypted(Manifest(segmentFiles: files))
        try manifest.write(to: source.appendingPathComponent("history.aesgcm"))
        try JSONEncoder().encode(Descriptor(ciphertextBytes: bytes + manifest.count, anchor: now)).write(to: source.appendingPathComponent("profile-fixture.json"))
        return hash(manifest)
    }
    func testModeHashExistingTargetAndSymlinkAreRejectedWithoutReplacingAnything() throws {
        let input = source(); let output = target()
        defer { try? FileManager.default.removeItem(at: input); try? FileManager.default.removeItem(at: output) }
        let digest = try fixture(input)
        XCTAssertThrowsError(try VerificationHistorySeed.importStore(from: input, to: output, expectedManifestSHA256: digest, verificationMode: false))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertThrowsError(try VerificationHistorySeed.importStore(from: input, to: output, expectedManifestSHA256: String(repeating: "0", count: 64), verificationMode: true))
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        let sentinel = output.appendingPathComponent("owned-sentinel"); try Data([42]).write(to: sentinel)
        XCTAssertThrowsError(try VerificationHistorySeed.importStore(from: input, to: output, expectedManifestSHA256: digest, verificationMode: true))
        XCTAssertEqual(try Data(contentsOf: sentinel), Data([42]))
        let alias = source(); defer { try? FileManager.default.removeItem(at: alias) }
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: input)
        XCTAssertThrowsError(try VerificationHistorySeed.importStore(from: alias, to: target(), expectedManifestSHA256: digest, verificationMode: true))
        XCTAssertThrowsError(try VerificationHistorySeed.importStore(from: input, to: URL(fileURLWithPath: "/private/tmp/Amid"), expectedManifestSHA256: digest, verificationMode: true))
    }
    func testMissingOrSymlinkSegmentAndStaleDescriptorFailAndRemovePartialOwnedTarget() throws {
        let input = source(); let output = target()
        defer { try? FileManager.default.removeItem(at: input); try? FileManager.default.removeItem(at: output) }
        let digest = try fixture(input)
        XCTAssertThrowsError(try VerificationHistorySeed.importStore(from: input, to: output, expectedManifestSHA256: digest, verificationMode: true))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertThrowsError(try VerificationHistorySeed.importStore(from: input, to: output, expectedManifestSHA256: digest, verificationMode: true, now: Date().addingTimeInterval(7200)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        let manifestData = try Data(contentsOf: input.appendingPathComponent("history.aesgcm"))
        let clear = try AES.GCM.open(AES.GCM.SealedBox(combined: manifestData.dropFirst(4)), using: key, authenticating: Data("AMID".utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: clear) as? [String: Any])
        let first = try XCTUnwrap((object["segmentFiles"] as? [String])?.sorted().first)
        try FileManager.default.createSymbolicLink(at: input.appendingPathComponent(first), withDestinationURL: input.appendingPathComponent("history.aesgcm"))
        XCTAssertThrowsError(try VerificationHistorySeed.importStore(from: input, to: output, expectedManifestSHA256: digest, verificationMode: true))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }
    func testDescriptorCountAndCiphertextBoundsRejectBeforeTargetCreation() throws {
        let input = source(); let output = target()
        defer { try? FileManager.default.removeItem(at: input); try? FileManager.default.removeItem(at: output) }
        let digest = try fixture(input)
        let descriptor = input.appendingPathComponent("profile-fixture.json")
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: descriptor)) as? [String: Any])
        for (field, invalid) in [("entities", 999), ("records", 165001), ("ciphertextBytes", 128 * 1024 * 1024 + 1), ("minuteBuckets", 1)] {
            var value = original; value[field] = invalid
            try JSONSerialization.data(withJSONObject: value).write(to: descriptor)
            XCTAssertThrowsError(try VerificationHistorySeed.importStore(from: input, to: output, expectedManifestSHA256: digest, verificationMode: true))
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        }
    }
    func testImportedAndSubsequentSyntheticActivityRejectPublicFixtureKey() async throws {
        let input = source(); let output = target()
        defer { try? FileManager.default.removeItem(at: input); try? FileManager.default.removeItem(at: output) }
        let digest = try fixture(input, populated: true)
        let sourceFiles = try FileManager.default.contentsOfDirectory(at: input, includingPropertiesForKeys: nil).filter { $0.pathExtension == "aesgcm" }
        let originals = try Dictionary(uniqueKeysWithValues: sourceFiles.map { ($0.lastPathComponent, try Data(contentsOf: $0)) })
        let imported = try VerificationHistorySeed.importStore(from: input, to: output, expectedManifestSHA256: digest, verificationMode: true)
        let segment = try XCTUnwrap(sourceFiles.first { $0.lastPathComponent.hasPrefix("bucket-") })
        for name in ["history.aesgcm", segment.lastPathComponent] {
            let data = try Data(contentsOf: output.appendingPathComponent(name))
            XCTAssertThrowsError(try AES.GCM.open(AES.GCM.SealedBox(combined: data.dropFirst(4)), using: key, authenticating: Data("AMID".utf8)))
        }
        await imported.store.load()
        let initialMetadata = await imported.store.metadata(); XCTAssertNil(initialMetadata.error)
        await imported.store.ingest(Snapshot(timestamp: Date(), availability: .available))
        await imported.store.flush()
        let finalMetadata = await imported.store.metadata(); XCTAssertNil(finalMetadata.error)
        let written = try FileManager.default.contentsOfDirectory(at: output, includingPropertiesForKeys: nil).filter { $0.pathExtension == "aesgcm" }
        for file in written {
            let data = try Data(contentsOf: file)
            XCTAssertThrowsError(try AES.GCM.open(AES.GCM.SealedBox(combined: data.dropFirst(4)), using: key, authenticating: Data("AMID".utf8)))
        }
        for (name, bytes) in originals { XCTAssertEqual(try Data(contentsOf: input.appendingPathComponent(name)), bytes) }
    }
    func testValidCiphertextImportLoadsOnceAndTamperedSegmentFailsClosed() async throws {
        let input = source(); let output = target(); let tamperedOutput = target()
        defer { for url in [input, output, tamperedOutput] where FileManager.default.fileExists(atPath: url.path) { try? FileManager.default.removeItem(at: url) } }
        let digest = try fixture(input, populated: true)
        let imported = try VerificationHistorySeed.importStore(from: input, to: output, expectedManifestSHA256: digest, verificationMode: true)
        XCTAssertEqual(imported.summary.entities, 21); XCTAssertEqual(imported.summary.declaredRecords, 33_264)
        XCTAssertEqual(imported.summary.manifestSHA256, digest)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathComponent("profile-fixture.json").path))
        await imported.store.load(); let state = await imported.store.state()
        XCTAssertNil(state.error); XCTAssertFalse(state.aggregates.isEmpty)
        let permissions = try FileManager.default.attributesOfItem(atPath: output.appendingPathComponent("history.aesgcm").path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
        let files = try FileManager.default.contentsOfDirectory(at: input, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("bucket-") }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        let last = try XCTUnwrap(files.last); var data = try Data(contentsOf: last); data[data.count-1] ^= 1; try data.write(to: last)
        XCTAssertThrowsError(try VerificationHistorySeed.importStore(from: input, to: tamperedOutput, expectedManifestSHA256: digest, verificationMode: true))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tamperedOutput.path))
        XCTAssertEqual(hash(try Data(contentsOf: input.appendingPathComponent("history.aesgcm"))), digest)
    }
}
