import XCTest
import Darwin
@testable import AmidCore

final class DeclaredServerTests: XCTestCase {
    private func server(pid: Int32 = 303, parent: Int32 = 302, executable: String = "/Users/dev/.nvm/versions/node/v22.0.0/bin/node",
                        address: String = "127.0.0.1", port: UInt16 = 5173) -> ProcessSample {
        ProcessSample(identity: .init(bootID: "boot", pid: pid, uid: getuid(), startSeconds: 4, startMicroseconds: 2),
                      parentPID: parent, executable: executable, name: URL(fileURLWithPath: executable).lastPathComponent,
                      workingDirectory: "/test/project/web", projectPath: "/test/project", applicationID: "executable:" + executable,
                      applicationName: "node", groupingReason: "fixture",
                      endpoints: [.init(address: address, port: port, family: address.contains(":") ? "IPv6" : "IPv4", scope: "fixture")],
                      portAvailability: .available)
    }
    private func snapshot(_ processes: [ProcessSample]) -> Snapshot {
        Snapshot(timestamp: Date(timeIntervalSince1970: 100), processes: processes, availability: .available)
    }
    private func outcome(_ process: ProcessSample, others: [ProcessSample] = []) -> DeclaredServerEligibility.Outcome {
        DeclaredServerEligibility.evaluate(process: process, snapshot: snapshot([process] + others))
    }
    private func assertReadOnly(_ process: ProcessSample, others: [ProcessSample] = [], containing text: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        guard case .readOnly(let reason) = outcome(process, others: others) else {
            return XCTFail("Expected read-only containing \(text)", file: file, line: line)
        }
        XCTAssertTrue(reason.contains(text), reason, file: file, line: line)
    }

    func testEligibilityOffersLoopbackAndWildcardListenersOnly() {
        XCTAssertEqual(outcome(server()), .eligible(exposedToNetwork: false))
        XCTAssertEqual(outcome(server(address: "::1")), .eligible(exposedToNetwork: false))
        XCTAssertEqual(outcome(server(address: "0.0.0.0")), .eligible(exposedToNetwork: true))
        XCTAssertEqual(outcome(server(address: "::")), .eligible(exposedToNetwork: true))
        assertReadOnly(server(address: "192.168.1.5"), containing: "specific network address")
    }

    func testEligibilityReadOnlyReasons() {
        var foreign = server(); foreign.identity.uid = getuid() + 1
        assertReadOnly(foreign, containing: "another user")
        assertReadOnly(server(executable: "/opt/homebrew/bin/postgres"), containing: "runtime")
        assertReadOnly(server(executable: "/Applications/Editor.app/Contents/Resources/node"), containing: "application bundle")
        assertReadOnly(server(executable: "/Applications/Tool.app/Contents/MacOS/Python"), containing: "application bundle")
        assertReadOnly(server(parent: 1), containing: "launchd")
        var noProject = server(); noProject.projectPath = nil
        assertReadOnly(noProject, containing: "project")
        var outside = server(); outside.workingDirectory = "/test/project-other"
        assertReadOnly(outside, containing: "project")
        var silent = server(); silent.endpoints = []
        assertReadOnly(silent, containing: "endpoint ownership")
        var denied = server(); denied.portAvailability = .denied
        assertReadOnly(denied, containing: "endpoint ownership")
        assertReadOnly(server(), others: [server(pid: 404, address: "0.0.0.0")], containing: "also owns this port")
    }

    func testFrameworkPythonInterpreterIsNotTreatedAsAnApplication() {
        for path in ["/Applications/Xcode.app/Contents/Developer/Library/Frameworks/Python3.framework/Versions/3.9/Resources/Python.app/Contents/MacOS/Python",
                     "/opt/homebrew/Cellar/python@3.13/3.13.1/Frameworks/Python.framework/Versions/3.13/Resources/Python.app/Contents/MacOS/Python"] {
            XCTAssertTrue(DeclaredServerEligibility.isFrameworkPythonInterpreter(path), path)
            XCTAssertEqual(outcome(server(executable: path)), .eligible(exposedToNetwork: false), path)
        }
        XCTAssertFalse(DeclaredServerEligibility.isFrameworkPythonInterpreter("/Applications/Tool.app/Contents/Resources/Python.app/Contents/MacOS/Python"))
    }

    func testBaselinePreviewExplainsReviewButNeverEnablesStop() {
        let process = server()
        let preview = ActionSafety.preview(process: process, snapshot: snapshot([process]))
        XCTAssertFalse(preview.canStop)
        XCTAssertTrue(preview.disabledReason.contains("Review required"), preview.disabledReason)
        XCTAssertEqual(ActionSafety.confirm(preview: preview, current: snapshot([process]), confirmed: true).signalsSent, 0)
    }

    func testDeclaredAdapterEndpointAndDeclarationPolicy() {
        let adapter = TrustedServerAdapter(declaredExecutable: "/usr/local/bin/node", projectRoot: "/test/project")
        for address in ["127.0.0.1", "::1", "0.0.0.0", "::"] {
            XCTAssertTrue(ActionController.endpointsAllowed([.init(address: address, port: 1, family: "IPv4", scope: "")], adapter: adapter), address)
        }
        XCTAssertFalse(ActionController.endpointsAllowed([.init(address: "10.0.0.2", port: 1, family: "IPv4", scope: "")], adapter: adapter))
        XCTAssertFalse(ActionController.endpointsAllowed([], adapter: adapter))
        XCTAssertFalse(ActionController.declarationAllows(adapter: adapter, developmentConfirmed: false))
        XCTAssertTrue(ActionController.declarationAllows(adapter: adapter, developmentConfirmed: true))
    }

    /// Looks up a live incarnation directly: same PID, user and start time means exec, not exit.
    func testVanishedTokenDistinguishesExecFromExitByDirectLookup() throws {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        XCTAssertEqual(proc_pidinfo(getpid(), PROC_PIDTBSDINFO, 0, &info, size), size)
        let own = ProcessIdentity(bootID: "boot", pid: getpid(), uid: info.pbi_uid,
                                  startSeconds: UInt64(info.pbi_start_tvsec), startMicroseconds: UInt64(info.pbi_start_tvusec))
        XCTAssertEqual(ActionController.goneValidation(own), .programChanged)
        var reused = own; reused.startSeconds += 1
        XCTAssertEqual(ActionController.goneValidation(reused), .alreadyExited, "Same PID with a different start is a different process")
        let finished = Process()
        finished.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try finished.run(); finished.waitUntilExit()
        let exited = ProcessIdentity(bootID: "boot", pid: finished.processIdentifier, uid: getuid(), startSeconds: 1, startMicroseconds: 0)
        XCTAssertEqual(ActionController.goneValidation(exited), .alreadyExited)
        let process = server()
        let preview = StopPreview(process: process, descendants: [], createdAt: Date(timeIntervalSince1970: 100),
                                  disabledReason: "", canStop: true, operationID: UUID())
        let refused = ActionController.refusal(preview: preview, current: snapshot([process]), validation: .programChanged)
        XCTAssertEqual(refused.signalsSent, 0)
        XCTAssertTrue(refused.message.contains("switched to another program"), refused.message)
        XCTAssertEqual(refused.remainingIdentities, [process.identity])
    }

    func testForgedDeclaredPreviewCannotSignal() async {
        let process = server()
        var forged = StopPreview(process: process, descendants: [], createdAt: Date(), disabledReason: "", canStop: true, operationID: UUID())
        forged.declaration = "Forged"
        forged.requiresDevelopmentConfirmation = false
        let result = await ActionController().confirm(preview: forged, confirmed: true, developmentConfirmed: true)
        XCTAssertEqual(result.signalsSent, 0)
    }

    func testFrameworkExemptionIsLimitedToStandardInterpreterInstalls() {
        let suffix = "/Resources/Python.app/Contents/MacOS/Python"
        for allowed in ["/Applications/Xcode-beta.app/Contents/Developer/Library/Frameworks/Python3.framework/Versions/3.9" + suffix,
                        "/Library/Developer/CommandLineTools/Library/Frameworks/Python3.framework/Versions/3.9" + suffix,
                        "/Library/Frameworks/Python.framework/Versions/3.12" + suffix] {
            XCTAssertTrue(DeclaredServerEligibility.isFrameworkPythonInterpreter(allowed), allowed)
        }
        for refused in ["/Applications/Blender.app/Contents/Resources/Python.framework/Versions/3.11" + suffix,
                        "/Applications/Editor.app/Contents/Developer/Library/Frameworks/Python3.framework/Versions/3.9" + suffix,
                        "/Applications/Xcode.app/Contents/Resources/Python3.framework/Versions/3.9" + suffix] {
            XCTAssertFalse(DeclaredServerEligibility.isFrameworkPythonInterpreter(refused), refused)
            assertReadOnly(server(executable: refused), containing: "application bundle")
        }
    }

    func testGrandchildrenAreListedAsDescendants() {
        let target = server(), child = server(pid: 304, parent: 303), grandchild = server(pid: 305, parent: 304)
        var quietChild = child; quietChild.endpoints = []
        var quietGrandchild = grandchild; quietGrandchild.endpoints = []
        let preview = ActionSafety.preview(process: target, snapshot: snapshot([target, quietChild, quietGrandchild]))
        XCTAssertEqual(Set(preview.descendants), [child.identity, grandchild.identity])
    }

    func testRemainingDescendantsAreMatchedByIdentityAfterReparenting() {
        let child = server(pid: 304, parent: 303)
        var reparented = child; reparented.parentPID = 1
        let found = ActionController.remainingDescendants([child.identity], in: snapshot([reparented]))
        XCTAssertEqual(found.observed, [child.identity])
        XCTAssertFalse(found.unknown)
        let gone = ActionController.remainingDescendants([child.identity], in: snapshot([]))
        XCTAssertTrue(gone.observed.isEmpty)
        XCTAssertFalse(gone.unknown)
        var partial = snapshot([]); partial.inaccessibleCount = 1
        XCTAssertTrue(ActionController.remainingDescendants([child.identity], in: partial).unknown)
        var reused = child; reused.identity.startSeconds = 9
        XCTAssertTrue(ActionController.remainingDescendants([child.identity], in: snapshot([reused])).observed.isEmpty)
        let other = server(pid: 306, parent: 303)
        var mixed = snapshot([reparented]); mixed.inaccessibleCount = 1
        let both = ActionController.remainingDescendants([child.identity, other.identity], in: mixed)
        XCTAssertEqual(both.observed, [child.identity])
        XCTAssertTrue(both.unknown, "A known survivor and an unobservable child are both reported")
    }

    func testAncestorsAreOutermostFirstAndBounded() {
        let shell = server(pid: 300, parent: 1, executable: "/bin/zsh")
        let runner = server(pid: 301, parent: 300, executable: "/usr/local/bin/node")
        let wrapper = server(pid: 302, parent: 301, executable: "/bin/sh")
        let target = server(pid: 303, parent: 302)
        XCTAssertEqual(ActionController.ancestors(of: target, in: snapshot([shell, runner, wrapper, target])), ["zsh", "node", "sh"])
        let loop = server(pid: 310, parent: 311), other = server(pid: 311, parent: 310)
        XCTAssertEqual(ActionController.ancestors(of: loop, in: snapshot([loop, other])), ["node"])
    }

    /// Captures a real running-code identity from an owned, naturally exiting platform binary. No signal is sent.
    func testRunningCodeIdentityIsCapturedAndRequired() throws {
        let sleeper = Process()
        sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep")
        sleeper.arguments = ["3"]
        try sleeper.run()
        defer { sleeper.waitUntilExit() }
        let token = try XCTUnwrap(ActionController.auditToken(pid: sleeper.processIdentifier))
        let hash = try XCTUnwrap(ActionController.runningCodeDirectoryHash(token))
        XCTAssertEqual(hash.count, 40)
        XCTAssertTrue(ActionController.matchesRunningCode(token, codeDirectoryHash: hash))
        let other = String(hash.map { $0 == "0" ? "1" : "0" })
        XCTAssertFalse(ActionController.matchesRunningCode(token, codeDirectoryHash: other))
        XCTAssertFalse(ActionController.matchesRunningCode(token, codeDirectoryHash: "not-a-hash"))
    }
}
