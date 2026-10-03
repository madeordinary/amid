import XCTest
import CryptoKit
import Security
@testable import AmidCore

final class ActionTests: XCTestCase {
    private func process(pid: Int32 = 101, parent: Int32 = 1, start: UInt64 = 4) -> ProcessSample {
        ProcessSample(identity: .init(bootID: "boot", pid: pid, uid: 501, startSeconds: start, startMicroseconds: 2),
                      parentPID: parent, executable: "/bin/node", name: "node", runtime: "node", workingDirectory: "/test/project",
                      projectPath: "/test/project", applicationID: "fixture", applicationName: "fixture", groupingReason: "fixture",
                      endpoints: [.init(address: "127.0.0.1", port: 43210, family: "IPv4", scope: "Loopback")], portAvailability: .available)
    }
    private func snapshot(_ processes: [ProcessSample], age: Double = 0) -> Snapshot {
        Snapshot(timestamp: Date(timeIntervalSince1970: 100 + age), processes: processes, availability: .available)
    }
    func testPreviewExactTargetsAndFailClosedConfirmation() {
        let p = process(); let child = process(pid: 102, parent: 101)
        let state = snapshot([p, child]); let preview = ActionSafety.preview(process: p, snapshot: state)
        XCTAssertEqual(Set(preview.identities), Set([p.identity, child.identity]))
        XCTAssertEqual(preview.endpoints, p.endpoints)
        XCTAssertFalse(preview.canStop)
        XCTAssertTrue(preview.disabledReason.contains("PID"))
        XCTAssertEqual(ActionSafety.confirm(preview: preview, current: state, confirmed: true).signalsSent, 0)
        XCTAssertEqual(ActionSafety.confirm(preview: preview, current: state, confirmed: false).signalsSent, 0)
    }
    func testPIDReuseAndExitNeverTargetReplacement() {
        let p = process(); let preview = ActionSafety.preview(process: p, snapshot: snapshot([p]))
        XCTAssertEqual(ActionSafety.validate(preview: preview, current: snapshot([])), .alreadyExited)
        XCTAssertEqual(ActionSafety.validate(preview: preview, current: snapshot([process(start: 5)])), .identityChanged)
        var changed = p; changed.identity.bootID = "reboot"
        XCTAssertEqual(ActionSafety.validate(preview: preview, current: snapshot([changed])), .identityChanged)
        changed = p; changed.identity.uid = 502
        XCTAssertEqual(ActionSafety.validate(preview: preview, current: snapshot([changed])), .identityChanged)
    }
    func testReparentExecProjectEndpointAndCoverageInvalidation() {
        let p = process(); let preview = ActionSafety.preview(process: p, snapshot: snapshot([p]))
        for field in 0..<6 {
            var changed = p
            switch field {
            case 0: changed.parentPID = 9
            case 1: changed.executable = "/bin/database"
            case 2: changed.projectPath = "/test/other"
            case 3: changed.endpoints = []
            case 4: changed.portAvailability = .denied
            default: changed.workingDirectory = "/test/other"
            }
            XCTAssertEqual(ActionSafety.validate(preview: preview, current: snapshot([changed])), .metadataChanged)
        }
        XCTAssertEqual(ActionSafety.validate(preview: preview, current: snapshot([p], age: 120)), .unchanged)
        XCTAssertEqual(ActionSafety.validate(preview: preview, current: snapshot([p], age: 121)), .stale)
        XCTAssertEqual(ActionSafety.validate(preview: preview, current: snapshot([p], age: -1)), .stale)
    }
    func testSharedEndpointAndDescendantChange() {
        let p = process(); let preview = ActionSafety.preview(process: p, snapshot: snapshot([p]))
        XCTAssertEqual(ActionSafety.validate(preview: preview, current: snapshot([p, process(pid: 103)])), .sharedEndpoint)
        var wildcard = process(pid: 103)
        wildcard.endpoints[0].address = "0.0.0.0"
        wildcard.endpoints[0].scope = "All interfaces"
        XCTAssertEqual(ActionSafety.validate(preview: preview, current: snapshot([p, wildcard])), .sharedEndpoint)
        var child = process(pid: 102, parent: 101); child.endpoints = []
        XCTAssertEqual(ActionSafety.validate(preview: preview, current: snapshot([p, child])), .descendantsChanged)
        let initial = snapshot([p, child]); let withChild = ActionSafety.preview(process: p, snapshot: initial)
        child.parentPID = 1
        XCTAssertEqual(ActionSafety.validate(preview: withChild, current: snapshot([p, child])), .descendantsChanged)
    }
    func testObservationResetInvalidatesCapturedAuthorizationGeneration() async {
        let controller = ActionController()
        let captured = await controller.observationGeneration
        let initiallyCurrent = await controller.isCurrentObservation(captured)
        XCTAssertTrue(initiallyCurrent)
        await controller.resetObservation()
        let invalidated = await controller.isCurrentObservation(captured)
        XCTAssertFalse(invalidated)
        let fresh = await controller.observationGeneration
        let current = await controller.isCurrentObservation(fresh)
        XCTAssertTrue(current)
        await controller.resetObservation()
        let invalidatedAgain = await controller.isCurrentObservation(fresh)
        XCTAssertFalse(invalidatedAgain)
        let original = process()
        let disabled = ActionSafety.preview(process: original, snapshot: snapshot([original]))
        let refused = await controller.confirm(preview: disabled, confirmed: true)
        XCTAssertEqual(refused.signalsSent, 0)
        XCTAssertFalse(refused.remainingObservationAvailable)
        XCTAssertTrue(refused.remainingIdentities.isEmpty)
        XCTAssertTrue(refused.remainingEndpoints.isEmpty)
    }
    func testExpiredRefusalReportsObservedOriginalWithoutAction() {
        let original = process()
        let preview = ActionSafety.preview(process: original, snapshot: snapshot([original]))
        let current = snapshot([original], age: 121)
        let validation = ActionSafety.validate(preview: preview, current: current)
        let result = ActionController.refusal(preview: preview, current: current, validation: validation)
        XCTAssertEqual(result.validation, .stale)
        XCTAssertTrue(result.remainingObservationAvailable)
        XCTAssertEqual(result.signalsSent, 0)
        XCTAssertTrue(result.message.contains("Preview expired"))
        XCTAssertEqual(result.remainingIdentities, [original.identity])
        XCTAssertEqual(result.remainingEndpoints, original.endpoints)
        let replacement = ActionController.refusal(preview: preview, current: snapshot([process(start: 5)], age: 121), validation: .stale)
        XCTAssertTrue(replacement.remainingObservationAvailable)
        XCTAssertTrue(replacement.remainingIdentities.isEmpty)
        XCTAssertTrue(replacement.remainingEndpoints.isEmpty)
        let signature = ActionController.refusal(preview: preview, current: current, validation: .metadataChanged,
                                                reason: "Running code signature does not match the trusted fixture build; no signal sent.")
        XCTAssertEqual(signature.signalsSent, 0)
        XCTAssertTrue(signature.message.contains("signature"))
        XCTAssertEqual(signature.remainingIdentities, [original.identity])
    }
    func testUnobservedExpiredAndCancelledResultsDoNotClaimZeroRemaining() async {
        let original = process()
        let preview = StopPreview(process: original, descendants: [], createdAt: Date(timeIntervalSince1970: 100),
                                  disabledReason: "", canStop: true, operationID: UUID())
        let controller = ActionController()
        await controller.expirePreviews(now: Date(timeIntervalSince1970: 221))
        let expired = await controller.confirm(preview: preview, confirmed: true)
        XCTAssertEqual(expired.signalsSent, 0)
        XCTAssertFalse(expired.remainingObservationAvailable)
        let cancelled = await controller.confirm(preview: preview, confirmed: false)
        XCTAssertEqual(cancelled.signalsSent, 0)
        XCTAssertFalse(cancelled.remainingObservationAvailable)
        let unavailable = ActionController.refusal(preview: preview, current: .empty, validation: .stale)
        XCTAssertFalse(unavailable.remainingObservationAvailable)
        XCTAssertFalse(ActionController.remainingObservationAvailable(in: .empty, target: original.identity))
        let observedEmpty = snapshot([], age: 121)
        XCTAssertTrue(ActionController.remainingObservationAvailable(in: observedEmpty, target: original.identity))
        let exited = ActionController.refusal(preview: preview, current: observedEmpty, validation: .alreadyExited)
        XCTAssertTrue(exited.remainingObservationAvailable)
        XCTAssertTrue(exited.remainingIdentities.isEmpty)
        XCTAssertTrue(exited.remainingEndpoints.isEmpty)
        let suspended = ActionSafety.confirm(preview: preview, current: .empty, confirmed: true)
        XCTAssertFalse(suspended.remainingObservationAvailable)
        XCTAssertEqual(suspended.signalsSent, 0)
    }
    func testRemainingStateRequiresTargetPortCoverageAndKnownAbsence() {
        let original = process()
        let preview = ActionSafety.preview(process: original, snapshot: snapshot([original]))
        for availability in [Availability.denied, .unavailable, .unsupported, .stale] {
            var unknown = original
            unknown.portAvailability = availability; unknown.endpoints = []
            let result = ActionController.refusal(preview: preview, current: snapshot([unknown]), validation: .metadataChanged)
            XCTAssertFalse(result.remainingObservationAvailable)
            XCTAssertTrue(result.remainingEndpoints.isEmpty)
            XCTAssertEqual(result.signalsSent, 0)
        }
        var inaccessible = snapshot([])
        inaccessible.inaccessibleCount = 1
        XCTAssertFalse(ActionController.remainingObservationAvailable(in: inaccessible, target: original.identity))
        XCTAssertTrue(ActionController.remainingObservationAvailable(in: inaccessible, target: original.identity, originalKnownGone: true))
        var replacement = snapshot([process(start: 5)])
        replacement.inaccessibleCount = 1
        XCTAssertTrue(ActionController.remainingObservationAvailable(in: replacement, target: original.identity))
        XCTAssertTrue(ActionController.remainingObservationAvailable(in: snapshot([original]), target: original.identity))
    }
    func testProtectedAndUnknownRuntimesRemainReadOnly() {
        for runtime in ["Ollama", "Postgres", "Terminal", "container", "unknown"] {
            var p = process(); p.runtime = runtime
            let preview = ActionSafety.preview(process: p, snapshot: snapshot([p]))
            XCTAssertFalse(preview.canStop)
            XCTAssertEqual(ActionSafety.confirm(preview: preview, current: snapshot([p]), confirmed: true).signalsSent, 0)
        }
    }
}

final class FixtureIntegrationTests: XCTestCase {
    func testOwnedNativeListenersAttributionAndRestart() async throws {
        guard ProcessInfo.processInfo.environment["AMID_RUN_FIXTURES"] == "1" else {
            throw XCTSkip("Opt-in owned native fixtures: scripts/test-fixtures.sh")
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let environment = ProcessInfo.processInfo.environment
        let node = try XCTUnwrap(environment["AMID_FIXTURE_NODE"])
        let swift = try XCTUnwrap(environment["AMID_FIXTURE_SWIFT"])
        let specs = [("node", node, ["server.js"]), ("python", "/usr/bin/python3", ["server.py"]), ("swift", swift, [])]
        let sampler = Sampler()
        var records: [[String: Any]] = []
        var children: [Process] = []
        for (name, executable, arguments) in specs {
            let process = Process(); let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.currentDirectoryURL = root.appendingPathComponent("fixtures/\(name)")
            process.standardOutput = pipe
            try process.run(); children.append(process)
            let record = try XCTUnwrap(try JSONSerialization.jsonObject(with: pipe.fileHandleForReading.availableData) as? [String: Any])
            XCTAssertEqual(record["pid"] as? Int32, process.processIdentifier)
            records.append(record)
        }
        // Cleanup never uses kill/terminate: each owned fixture has a hard finite lifetime.
        defer { for process in children { process.waitUntilExit() } }
        _ = await sampler.sample()
        try await Task.sleep(for: .seconds(2))
        let sampled = await sampler.sample()
        var matches = 0
        var identities: [ProcessIdentity] = []
        for (index, record) in records.enumerated() {
            let pid = children[index].processIdentifier
            let observed = try XCTUnwrap(sampled.processes.first { $0.identity.pid == pid })
            identities.append(observed.identity)
            let expected = root.appendingPathComponent("fixtures/\(specs[index].0)").resolvingSymlinksInPath().path
            let port = try XCTUnwrap(record["port"] as? UInt16)
            if observed.projectPath == expected && observed.endpoints.contains(where: { $0.port == port }) { matches += 1 }
            XCTAssertNotNil(observed.memoryBytes)
            XCTAssertNotNil(observed.cpuPercent)
            let preview = ActionSafety.preview(process: observed, snapshot: sampled)
            XCTAssertFalse(preview.canStop)
            XCTAssertEqual(ActionSafety.confirm(preview: preview, current: sampled, confirmed: true).signalsSent, 0)
        }
        let coverage = Double(matches) / Double(records.count)
        print("FIXTURE_EVIDENCE native project/port coverage=\(coverage) identities=\(identities.map(\.id))")
        XCTAssertGreaterThanOrEqual(coverage, 0.95)
        let fixtureBytes = try Data(contentsOf: URL(fileURLWithPath: swift))
        let hash = SHA256.hash(data: fixtureBytes).map { String(format: "%02x", $0) }.joined()
        var trustedStaticCode: SecStaticCode?
        XCTAssertEqual(SecStaticCodeCreateWithPath(URL(fileURLWithPath: swift) as CFURL, [], &trustedStaticCode), errSecSuccess)
        var signingInfo: CFDictionary?
        XCTAssertEqual(SecCodeCopySigningInformation(try XCTUnwrap(trustedStaticCode), SecCSFlags(rawValue: kSecCSSigningInformation), &signingInfo), errSecSuccess)
        let signing = try XCTUnwrap(signingInfo as? [String: Any])
        let codeDirectory = try XCTUnwrap(signing[kSecCodeInfoUnique as String] as? Data)
        let cdhash = codeDirectory.map { String(format: "%02x", $0) }.joined()
        let trusted = TrustedServerAdapter(ownedFixtureExecutable: swift,
            projectRoot: root.appendingPathComponent("fixtures/swift").resolvingSymlinksInPath().path, expectedSHA256: hash, expectedCodeDirectoryHash: cdhash)
        let wrong = TrustedServerAdapter(ownedFixtureExecutable: swift, projectRoot: trusted.projectRoot, expectedSHA256: String(repeating: "0", count: 64))
        let wrongController = ActionController(adapters: [wrong], sampler: sampler)
        let controller = ActionController(adapters: [trusted], sampler: sampler)
        let swiftProcess = try XCTUnwrap(sampled.processes.first { $0.identity.pid == children[2].processIdentifier })
        let rejected = await wrongController.preview(process: swiftProcess, snapshot: sampled)
        XCTAssertFalse(rejected.canStop)
        let rejectedResult = await wrongController.confirm(preview: rejected, confirmed: true)
        XCTAssertEqual(rejectedResult.signalsSent, 0)
        let expiring = await controller.preview(process: swiftProcess, snapshot: sampled)
        XCTAssertTrue(expiring.canStop)
        await controller.expirePreviews(now: expiring.createdAt.addingTimeInterval(121))
        let expired = await controller.confirm(preview: expiring, confirmed: true)
        XCTAssertEqual(expired.signalsSent, 0)
        let supported = await controller.preview(process: swiftProcess, snapshot: sampled)
        XCTAssertTrue(supported.canStop, supported.disabledReason + " executable=\(swiftProcess.executable) cwd=\(swiftProcess.workingDirectory ?? "nil") project=\(swiftProcess.projectPath ?? "nil") endpoints=\(swiftProcess.endpoints)")
        let stopped = await controller.confirm(preview: supported, confirmed: true)
        XCTAssertEqual(stopped.signalsSent, 1)
        XCTAssertTrue(stopped.remainingIdentities.isEmpty)
        XCTAssertTrue(stopped.remainingEndpoints.isEmpty)
        let repeated = await controller.confirm(preview: supported, confirmed: true)
        XCTAssertEqual(repeated.signalsSent, 0)
        let short = Process(); let shortReady = Pipe()
        short.executableURL = URL(fileURLWithPath: swift)
        short.arguments = ["1"]
        short.currentDirectoryURL = root.appendingPathComponent("fixtures/swift")
        short.standardOutput = shortReady
        try short.run()
        defer { short.waitUntilExit() }
        _ = shortReady.fileHandleForReading.availableData
        let shortState = await sampler.sample()
        let shortObserved = try XCTUnwrap(shortState.processes.first { $0.identity.pid == short.processIdentifier })
        let shortPreview = await controller.preview(process: shortObserved, snapshot: shortState)
        XCTAssertTrue(shortPreview.canStop, shortPreview.disabledReason)
        short.waitUntilExit()
        let alreadyGone = await controller.confirm(preview: shortPreview, confirmed: true)
        XCTAssertEqual(alreadyGone.validation, .alreadyExited)
        XCTAssertEqual(alreadyGone.signalsSent, 0)
        for (index, process) in children.enumerated() {
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, index == 2 ? 15 : 0)
        }
        let exited = await sampler.sample()
        for identity in identities { XCTAssertFalse(exited.processes.contains { $0.identity == identity }) }
        let restarted = Process(); let output = Pipe()
        restarted.executableURL = URL(fileURLWithPath: node)
        restarted.arguments = ["server.js"]
        restarted.currentDirectoryURL = root.appendingPathComponent("fixtures/node")
        restarted.standardOutput = output
        try restarted.run()
        _ = output.fileHandleForReading.availableData
        let fresh = await sampler.sample()
        let replacement = try XCTUnwrap(fresh.processes.first { $0.identity.pid == restarted.processIdentifier })
        XCTAssertFalse(identities.contains(replacement.identity))
        restarted.waitUntilExit()
        XCTAssertEqual(restarted.terminationStatus, 0)
        if let untrusted = environment["AMID_FIXTURE_UNTRUSTED"] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("amid-running-image-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let replacedPath = directory.appendingPathComponent("AmidFixture")
            try FileManager.default.copyItem(at: URL(fileURLWithPath: untrusted), to: replacedPath)
            let impostor = Process(); let ready = Pipe()
            impostor.executableURL = replacedPath
            impostor.currentDirectoryURL = root.appendingPathComponent("fixtures/swift")
            impostor.standardOutput = ready
            try impostor.run()
            defer { impostor.waitUntilExit() }
            _ = ready.fileHandleForReading.availableData
            // Preserve the loaded untrusted inode; replace only its pathname with trusted bytes.
            try FileManager.default.removeItem(at: replacedPath)
            try FileManager.default.copyItem(at: URL(fileURLWithPath: swift), to: replacedPath)
            let state = await sampler.sample()
            let target = try XCTUnwrap(state.processes.first { $0.identity.pid == impostor.processIdentifier })
            let replacementTrust = TrustedServerAdapter(ownedFixtureExecutable: replacedPath.path,
                projectRoot: trusted.projectRoot, expectedSHA256: hash, expectedCodeDirectoryHash: cdhash)
            let replacementController = ActionController(adapters: [replacementTrust], sampler: sampler)
            let refused = await replacementController.preview(process: target, snapshot: state)
            XCTAssertFalse(refused.canStop, "Disk bytes must not authorize a different running image")
            let refusedResult = await replacementController.confirm(preview: refused, confirmed: true)
            XCTAssertEqual(refusedResult.signalsSent, 0)
            print("FIXTURE_EVIDENCE running-image substitution refused: \(refused.disabledReason)")
            impostor.waitUntilExit()
            XCTAssertEqual(impostor.terminationStatus, 0)
        }
    }
}
