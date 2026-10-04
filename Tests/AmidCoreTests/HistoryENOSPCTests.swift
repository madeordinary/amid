import XCTest
import Foundation
import Darwin
import CryptoKit
@testable import AmidCore

/// Explicitly opt-in: the enabled test fails on denied create/attach, never skips it.
final class HistoryENOSPCTests: XCTestCase, @unchecked Sendable {
    func testOwnedDiskImageExhaustionPreservesCommittedHistory() async throws {
        guard ProcessInfo.processInfo.environment["AMID_ENOSPC_TEST"] == "1" else {
            throw XCTSkip("Opt-in owned 64 MiB HFS+ disk-image ENOSPC integration.")
        }
        let volume = try OwnedENOSPCVolume()
        do {
            try volume.attach()
            let directory = volume.mount.appendingPathComponent("history", isDirectory: true)
            let provider = EphemeralHistoryKeyProvider()
            let store = HistoryStore(directory: directory, keyProvider: provider)
            let base = Date()
            await store.updateSettings(.init(retention: .week), now: base)
            var initial = Snapshot(timestamp: base, availability: .available)
            initial.system.cpuPercent = 12
            await store.ingest(initial)
            await store.flush()
            let prior = await store.history(entityID: "system", since: base.addingTimeInterval(-3600), until: base.addingTimeInterval(180))
            let priorMetadata = await store.metadata()
            XCTAssertNil(prior.error)
            XCTAssertFalse(prior.points.isEmpty)
            XCTAssertNil(priorMetadata.error)
            let committed = try volume.committedHashes(in: directory)
            XCTAssertNotNil(committed["history.aesgcm"])
            XCTAssertGreaterThan(committed.count, 1)

            let filledBytes = try volume.fillUntilENOSPC()
            XCTAssertGreaterThan(filledBytes, 0)
            XCTAssertLessThanOrEqual(filledBytes, 128 * 1024 * 1024)
            try volume.validateMount()
            var attempted = Snapshot(timestamp: base.addingTimeInterval(65), availability: .available)
            attempted.system.cpuPercent = 88
            await store.ingest(attempted)
            await store.flush()
            let failedMetadata = await store.metadata()
            let failedQuery = await store.history(entityID: "system", since: prior.since, until: prior.until)
            XCTAssertNotNil(failedMetadata.error)
            XCTAssertNotNil(failedQuery.error)
            XCTAssertTrue(failedQuery.points.isEmpty)
            // Existing committed generations are checked individually; failed staging leftovers are not confused with committed rows.
            try volume.validateMount()
            for (name, hash) in committed {
                XCTAssertEqual(try volume.hash(directory.appendingPathComponent(name)), hash)
            }

            try volume.releaseFiller()
            try volume.validateMount()
            let restored = HistoryStore(directory: directory, keyProvider: provider)
            await restored.load()
            let recovered = await restored.history(entityID: "system", since: prior.since, until: prior.until)
            let recoveredMetadata = await restored.metadata()
            XCTAssertNil(recoveredMetadata.error)
            XCTAssertNil(recovered.error)
            XCTAssertEqual(recoveredMetadata.aggregateCount, priorMetadata.aggregateCount)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            XCTAssertEqual(try encoder.encode(recovered.points), try encoder.encode(prior.points))
            XCTAssertFalse(recovered.points.contains { $0.cpu.maximum == 88 })
            print("OWNED_ENOSPC fillerErrno=\(ENOSPC) fillerBytes=\(filledBytes) committedFiles=\(committed.count) recoveredRecords=\(recovered.points.count)")
            try volume.cleanup()
        } catch {
            do { try volume.cleanup() }
            catch { XCTFail("Owned ENOSPC cleanup incomplete; exact private temporary artifacts are retained. No force detach was attempted.") }
            throw error
        }
    }
}

private final class OwnedENOSPCVolume: @unchecked Sendable {
    enum Failure: Error { case backingSpace, unsafePath, utilityFailed, utilityTimedOut, unexpectedAttachment, unsafeMount, fillerFailed(Int32), capReached, cleanupIncomplete }
    let root: URL
    let mount: URL
    private let image: URL
    private var mountFD: Int32 = -1
    private var device: String?
    private var mountedDevice: String?
    private var mountFSID: [UInt8]?
    private var parentFSID: [UInt8]
    private var attachAttempted = false
    private var detached = false
    private var cleaned = false
    private var fillerPresent = false
    private var utilityUnsettled = false

    init() throws {
        root = URL(fileURLWithPath: "/private/tmp/amid-owned-enospc-\(UUID().uuidString)", isDirectory: true)
        mount = root.appendingPathComponent("mount", isDirectory: true)
        image = root.appendingPathComponent("owned.dmg")
        var parent = statfs()
        guard statfs("/private/tmp", &parent) == 0 else { throw Failure.backingSpace }
        let free = UInt64(parent.f_bavail).multipliedReportingOverflow(by: UInt64(parent.f_bsize))
        guard !free.overflow, free.partialValue > 512 * 1024 * 1024 else { throw Failure.backingSpace }
        parentFSID = Self.bytes(parent.f_fsid)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        print("OWNED_ENOSPC_RESOURCE root=\(root.path)")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        try verifyOwnedDirectory(root)
        try verifyOwnedDirectory(mount)
    }
    private func verifyOwnedDirectory(_ url: URL) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_uid == getuid(),
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              info.st_mode & mode_t(0o777) == mode_t(0o700) else { throw Failure.unsafePath }
    }
    private func utility(_ arguments: [String]) throws -> Data {
        let outputURL = root.appendingPathComponent("utility-\(UUID().uuidString).out")
        let errorURL = root.appendingPathComponent("utility-\(UUID().uuidString).err")
        let outputFD = open(outputURL.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard outputFD >= 0 else { throw Failure.utilityFailed }
        let output = FileHandle(fileDescriptor: outputFD, closeOnDealloc: true)
        defer { try? output.close() }
        let errorFD = open(errorURL.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard errorFD >= 0 else { throw Failure.utilityFailed }
        let errors = FileHandle(fileDescriptor: errorFD, closeOnDealloc: true)
        defer { try? errors.close() }
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output; process.standardError = errors
        try process.run()
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        while process.isRunning && ContinuousClock.now < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning {
            print("OWNED_ENOSPC_UTILITY_TIMEOUT pid=\(process.processIdentifier) root=\(root.path)")
            process.terminate() // One normal SIGTERM, only to the Process instance launched above.
            let grace = ContinuousClock.now.advanced(by: .seconds(5))
            while process.isRunning && ContinuousClock.now < grace { Thread.sleep(forTimeInterval: 0.05) }
            if !process.isRunning { process.waitUntilExit() }
            else { utilityUnsettled = true }
            throw Failure.utilityTimedOut // No SIGKILL or force detach, even if the helper remains alive.
        }
        process.waitUntilExit()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else { throw Failure.utilityFailed }
        let outputSize = try FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? NSNumber
        let errorSize = try FileManager.default.attributesOfItem(atPath: errorURL.path)[.size] as? NSNumber
        guard let outputSize, let errorSize, outputSize.intValue <= 128 * 1024, errorSize.intValue <= 128 * 1024 else { throw Failure.utilityFailed }
        return try Data(contentsOf: outputURL)
    }
    func attach() throws {
        // Every argument is a fixed operation or an exact newly owned path. No existing device is formatted.
        _ = try utility(["create", "-size", "64m", "-type", "UDIF", "-fs", "HFS+", "-volname", "AmidOwnedENOSPC", image.path])
        attachAttempted = true
        let data = try utility(["attach", "-plist", "-nobrowse", "-mountpoint", mount.path, image.path])
        guard let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]] else { throw Failure.unexpectedAttachment }
        let volumes = entities.filter { ($0["mount-point"] as? String).map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path == mount.resolvingSymlinksInPath().path } ?? false }
        guard volumes.count == 1, let slice = volumes[0]["dev-entry"] as? String,
              slice.range(of: #"^/dev/disk[0-9]+s[0-9]+$"#, options: .regularExpression) != nil,
              let disk = entities.compactMap({ $0["dev-entry"] as? String }).first(where: { $0.range(of: #"^/dev/disk[0-9]+$"#, options: .regularExpression) != nil && slice.hasPrefix($0 + "s") }) else { throw Failure.unexpectedAttachment }
        device = disk; mountedDevice = slice
        mountFD = open(mount.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard mountFD >= 0 else { throw Failure.unsafeMount }
        try validateMount()
    }
    func validateMount() throws {
        var fs = statfs(), info = stat()
        guard mountFD >= 0, fstatfs(mountFD, &fs) == 0, fstat(mountFD, &info) == 0,
              info.st_uid == getuid(), info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              Self.string(fs.f_fstypename) == "hfs", Self.string(fs.f_mntfromname) == mountedDevice,
              URL(fileURLWithPath: Self.string(fs.f_mntonname)).resolvingSymlinksInPath().path == mount.resolvingSymlinksInPath().path,
              Self.bytes(fs.f_fsid) != parentFSID else { throw Failure.unsafeMount }
        let capacity = UInt64(fs.f_blocks).multipliedReportingOverflow(by: UInt64(fs.f_bsize))
        guard !capacity.overflow, capacity.partialValue >= UInt64(32 * 1024 * 1024),
              capacity.partialValue <= UInt64(80 * 1024 * 1024) else { throw Failure.unsafeMount }
        if let mountFSID { guard mountFSID == Self.bytes(fs.f_fsid) else { throw Failure.unsafeMount } }
        else { mountFSID = Self.bytes(fs.f_fsid) }
        // Verify the path used by HistoryStore still resolves to the held mounted filesystem.
        var pathInfo = stat()
        guard lstat(mount.path, &pathInfo) == 0, pathInfo.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              pathInfo.st_dev == info.st_dev, pathInfo.st_ino == info.st_ino else { throw Failure.unsafeMount }
    }
    func fillUntilENOSPC() throws -> Int {
        try validateMount()
        let fd = openat(mountFD, "owned-filler", O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard fd >= 0 else { throw Failure.fillerFailed(errno) }
        fillerPresent = true
        defer { close(fd) }
        let chunk = [UInt8](repeating: 0x5A, count: 1024 * 1024)
        let cap = 128 * 1024 * 1024
        var total = 0
        var requestSize = chunk.count
        var attemptedBytes = 0
        while total < cap && attemptedBytes < cap {
            let size = min(requestSize, cap - attemptedBytes)
            attemptedBytes += size
            let count = chunk.withUnsafeBytes { Darwin.write(fd, $0.baseAddress!, size) }
            if count > 0 { total += count; continue }
            let failure = errno
            if count < 0 && failure == EINTR { continue }
            guard count < 0, failure == ENOSPC else { throw Failure.fillerFailed(failure) }
            // A large failing allocation may leave smaller allocatable space: exhaust down to one byte.
            if requestSize > 4096 { requestSize = 4096; continue }
            if requestSize > 512 { requestSize = 512; continue }
            if requestSize > 1 { requestSize = 1; continue }
            // Only the filler errno is asserted; HistoryStore deliberately exposes generic commit failure.
            return total
        }
        throw Failure.capReached
    }
    func releaseFiller() throws {
        try validateMount()
        if fillerPresent {
            guard unlinkat(mountFD, "owned-filler", 0) == 0 else { throw Failure.cleanupIncomplete }
            fillerPresent = false
        }
    }
    func hash(_ url: URL) throws -> String { SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined() }
    func committedHashes(in directory: URL) throws -> [String: String] {
        try validateMount()
        return try Dictionary(uniqueKeysWithValues: FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent == "history.aesgcm" || $0.lastPathComponent.hasPrefix("bucket-") }
            .map { ($0.lastPathComponent, try hash($0)) })
    }
    func cleanup() throws {
        if cleaned { return }
        guard !utilityUnsettled else { throw Failure.cleanupIncomplete }
        if fillerPresent { try releaseFiller() }
        if mountFD >= 0 { close(mountFD); mountFD = -1 }
        if let device, !detached {
            _ = try utility(["detach", device]) // Never -force, never an enumerated or inferred user device.
            detached = true
        } else if attachAttempted && !detached { throw Failure.cleanupIncomplete }
        var fs = statfs()
        guard statfs(mount.path, &fs) == 0, Self.bytes(fs.f_fsid) == parentFSID else { throw Failure.cleanupIncomplete }
        try verifyOwnedDirectory(root)
        try FileManager.default.removeItem(at: root)
        cleaned = true
    }
    deinit { if mountFD >= 0 { close(mountFD) } }
    private static func bytes<T>(_ value: T) -> [UInt8] { withUnsafeBytes(of: value) { Array($0) } }
    private static func string<T>(_ value: T) -> String { withUnsafeBytes(of: value) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) } }
}
