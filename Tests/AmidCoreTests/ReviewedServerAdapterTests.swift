import XCTest
import Foundation
import Darwin
@testable import AmidCore

final class ReviewedServerAdapterTests: XCTestCase {
    func testIndependentBuildAndDeclarationPolicy() {
        let adapter = SupportedServerBuilds.reviewedDarkHTTPD(executablePath: "/test/darkhttpd", projectRoot: "/test")
        XCTAssertEqual(adapter.sha256, "c7c78d329a49f96044f513ab5a4d4acb08ac5f10eae98e49946370e8db7320e4")
        XCTAssertEqual(adapter.codeDirectoryHash, "465b0edd621f1d6b7f1a7914d51e574088ecbef3")
        XCTAssertFalse(ActionController.declarationAllows(adapter: adapter, developmentConfirmed: false))
        XCTAssertTrue(ActionController.declarationAllows(adapter: adapter, developmentConfirmed: true))
        let fixture = TrustedServerAdapter(ownedFixtureExecutable: "/test/AmidFixture", projectRoot: "/test", expectedSHA256: "caller")
        XCTAssertTrue(ActionController.declarationAllows(adapter: fixture, developmentConfirmed: false))
        XCTAssertTrue(SupportedServerBuilds.canReview(executablePath: "/arbitrary/darkhttpd"))
        XCTAssertFalse(SupportedServerBuilds.canReview(executablePath: "/arbitrary/node"))
        XCTAssertTrue(ActionController.endpointsAllowed([.init(address: "127.0.0.1", port: 1234, family: "IPv4", scope: "Loopback")], adapter: adapter))
        for endpoint in [Endpoint(address: "::1", port: 1234, family: "IPv6", scope: "Loopback"), Endpoint(address: "0.0.0.0", port: 1234, family: "IPv4", scope: "All interfaces"), Endpoint(address: "127.0.0.1", port: 1234, family: "IPv6", scope: "Loopback")] {
            XCTAssertFalse(ActionController.endpointsAllowed([endpoint], adapter: adapter))
        }
    }
    func testOwnedReviewedServerDeclarationsAndActiveStop() async throws {
        guard let binary = ProcessInfo.processInfo.environment["AMID_REVIEWED_DARKHTTPD"] else {
            throw XCTSkip("Set AMID_REVIEWED_DARKHTTPD to the independently pinned optional build for owned integration.")
        }
        let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("amid-reviewed-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("// synthetic project marker\n".utf8).write(to: root.appendingPathComponent("Package.swift"))
        try Data("owned synthetic page".utf8).write(to: root.appendingPathComponent("index.html"))
        let large = root.appendingPathComponent("large.bin")
        FileManager.default.createFile(atPath: large.path, contents: nil)
        let file = try FileHandle(forWritingTo: large); try file.truncate(atOffset: 128 * 1024 * 1024); try file.close()
        let launcherSource = root.appendingPathComponent("bounded.c")
        try Data("#include <unistd.h>\n#include <signal.h>\nint main(int n,char **v){if(n<2)return 2;signal(SIGALRM,SIG_DFL);alarm(8);execv(v[1],v+1);return 3;}\n".utf8).write(to: launcherSource)
        let launcher = root.appendingPathComponent("bounded")
        let compiler = Process(); compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        compiler.arguments = ["clang", launcherSource.path, "-o", launcher.path]
        try compiler.run(); compiler.waitUntilExit(); XCTAssertEqual(compiler.terminationStatus, 0)
        let sampler = Sampler(); let controller = ActionController(sampler: sampler)
        let substitutionDirectory = root.appendingPathComponent("substitution")
        try FileManager.default.createDirectory(at: substitutionDirectory, withIntermediateDirectories: false)
        let substituted = substitutionDirectory.appendingPathComponent("darkhttpd")
        try FileManager.default.copyItem(atPath: binary, toPath: substituted.path)
        let signer = Process(); signer.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        signer.arguments = ["--force", "-s", "-", "--identifier", "amid-owned-distinct-code", substituted.path]
        try signer.run(); signer.waitUntilExit(); XCTAssertEqual(signer.terminationStatus, 0)
        var oldPreview: StopPreview?
        for caseIndex in 0..<3 {
            let active = caseIndex == 1
            let substitution = caseIndex == 2
            let server = Process(); server.executableURL = launcher; server.currentDirectoryURL = root
            server.arguments = [substitution ? substituted.path : binary, root.path, "--addr", "127.0.0.1", "--port", "0"]
            let output = root.appendingPathComponent(active ? "active.log" : "idle.log")
            FileManager.default.createFile(atPath: output.path, contents: nil)
            let log = try FileHandle(forWritingTo: output); server.standardOutput = log; server.standardError = log
            try server.run()
            // All cleanup is a natural eight-second lifetime and waiting for this exact owned child.
            defer { server.waitUntilExit(); try? log.close() }
            var snapshot = await sampler.sample()
            var target: ProcessSample?
            for _ in 0..<20 {
                target = snapshot.processes.first { $0.identity.pid == server.processIdentifier && !$0.endpoints.isEmpty }
                if target != nil { break }
                try await Task.sleep(for: .milliseconds(100)); snapshot = await sampler.sample()
            }
            let process = try XCTUnwrap(target)
            XCTAssertEqual(process.identity.uid, getuid()); XCTAssertEqual(process.parentPID, getpid())
            XCTAssertEqual(process.projectPath, root.resolvingSymlinksInPath().path)
            if let oldPreview {
                let old = await controller.confirm(preview: oldPreview, confirmed: true, developmentConfirmed: true)
                XCTAssertEqual(old.signalsSent, 0)
            }
            print("OWNED_TARGET", process.identity.pid, process.identity.startSeconds, process.identity.startMicroseconds, process.endpoints.map(\.port))
            if substitution {
                // Restore independently trusted bytes while the distinct signed image is still running.
                try FileManager.default.removeItem(at: substituted)
                try FileManager.default.copyItem(atPath: binary, toPath: substituted.path)
                let substitutedPreview = await controller.preview(process: process, snapshot: snapshot)
                XCTAssertFalse(substitutedPreview.canStop)
                XCTAssertTrue(substitutedPreview.disabledReason.contains("Running code signature"), substitutedPreview.disabledReason)
                let refused = await controller.confirm(preview: substitutedPreview, confirmed: true, developmentConfirmed: true)
                XCTAssertEqual(refused.signalsSent, 0)
                server.waitUntilExit(); XCTAssertEqual(server.terminationStatus, SIGALRM)
                continue
            }
            let preview = await controller.preview(process: process, snapshot: snapshot)
            XCTAssertTrue(preview.canStop, preview.disabledReason); XCTAssertTrue(preview.requiresDevelopmentConfirmation)
            var forged = preview; forged.requiresDevelopmentConfirmation = false
            let refused = await controller.confirm(preview: forged, confirmed: true)
            XCTAssertEqual(refused.signalsSent, 0); XCTAssertTrue(server.isRunning)
            let consumed = await controller.confirm(preview: preview, confirmed: true, developmentConfirmed: true)
            XCTAssertEqual(consumed.signalsSent, 0)
            snapshot = await sampler.sample()
            var fresh = await controller.preview(process: try XCTUnwrap(snapshot.processes.first { $0.identity == process.identity }), snapshot: snapshot)
            if !active {
                await controller.resetObservation()
                let invalidated = await controller.confirm(preview: fresh, confirmed: true, developmentConfirmed: true)
                XCTAssertEqual(invalidated.signalsSent, 0)
                snapshot = await sampler.sample()
                fresh = await controller.preview(process: try XCTUnwrap(snapshot.processes.first { $0.identity == process.identity }), snapshot: snapshot)
            }
            var client: Int32 = -1
            if active {
                client = socket(AF_INET, SOCK_STREAM, 0)
                XCTAssertGreaterThanOrEqual(client, 0)
                var address = sockaddr_in()
                address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                address.sin_family = sa_family_t(AF_INET)
                address.sin_port = try XCTUnwrap(process.endpoints.first).port.bigEndian
                address.sin_addr.s_addr = inet_addr("127.0.0.1")
                let connected = withUnsafePointer(to: &address) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        Darwin.connect(client, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
                XCTAssertEqual(connected, 0)
                let request = Array("GET /large.bin HTTP/1.0\r\n\r\n".utf8)
                XCTAssertEqual(request.withUnsafeBytes { Darwin.send(client, $0.baseAddress, $0.count, 0) }, request.count)
                var response = [UInt8](repeating: 0, count: 1024)
                var count = -1
                for _ in 0..<20 {
                    count = response.withUnsafeMutableBytes { Darwin.recv(client, $0.baseAddress, $0.count, MSG_DONTWAIT) }
                    if count > 0 { break }
                    try await Task.sleep(for: .milliseconds(100))
                }
                XCTAssertGreaterThan(count, 0)
                XCTAssertTrue(String(decoding: response.prefix(max(0, count)), as: UTF8.self).contains("200 OK"))
                // Keep this socket open and stop reading the sparse128MiB transfer.
            }
            defer { if client >= 0 { Darwin.close(client) } }
            let stopped = await controller.confirm(preview: fresh, confirmed: true, developmentConfirmed: true)
            XCTAssertEqual(stopped.signalsSent, 1, stopped.message)
            XCTAssertTrue(stopped.remainingObservationAvailable); XCTAssertTrue(stopped.remainingIdentities.isEmpty)
            server.waitUntilExit(); XCTAssertEqual(server.terminationStatus, 0)
            if active {
                try log.synchronize()
                let serverOutput = try String(contentsOf: output, encoding: .utf8)
                XCTAssertTrue(serverOutput.contains("GET /large.bin"), serverOutput)
            }
            let repeatStop = await controller.confirm(preview: fresh, confirmed: true, developmentConfirmed: true)
            XCTAssertEqual(repeatStop.signalsSent, 0)
            oldPreview = fresh
        }
    }

}
