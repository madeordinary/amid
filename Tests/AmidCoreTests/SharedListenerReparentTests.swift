import XCTest
import Foundation
import Darwin
@testable import AmidCore

/// Owned fixtures only. No listener connections, payload reads or arbitrary signals.
final class SharedListenerReparentTests: XCTestCase {
    func testOwnedSharedListenerReparentIdentityAndDeclaredCoverage() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("amid-owned-shared-reparent-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("fixture.c"), binary = directory.appendingPathComponent("fixture")
        try Data(Self.fixture.utf8).write(to: source)
        let compiler = Process(); compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        compiler.arguments = ["clang", "-arch", "arm64", "-mmacosx-version-min=15.0", source.path, "-o", binary.path]
        try compiler.run(); compiler.waitUntilExit()
        XCTAssertEqual(compiler.terminationStatus, 0)
        guard compiler.terminationStatus == 0 else { return }
        let parent = Process(), input = Pipe(), output = Pipe()
        parent.executableURL = binary; parent.currentDirectoryURL = directory
        parent.standardInput = input; parent.standardOutput = output
        guard fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) == 0 else { XCTFail("Owned control pipe could not disable SIGPIPE"); return }
        try parent.run()
        // Parent and child have fixed independent deadlines. Cleanup never signals another process.
        defer { try? input.fileHandleForWriting.close(); parent.waitUntilExit(); _ = try? output.fileHandleForReading.readToEnd() }
        let record = String(decoding: output.fileHandleForReading.availableData, as: UTF8.self).split(whereSeparator: { $0.isWhitespace })
        guard record.count == 3, let parentPID = Int32(record[0]), let childPID = Int32(record[1]), let port = UInt16(record[2]) else {
            XCTFail("Owned fixture readiness record unavailable"); return
        }
        XCTAssertEqual(parentPID, parent.processIdentifier)
        let sampler = Sampler()
        let initial = await sampler.sample()
        let expectedPIDs: Set<Int32> = [parentPID, childPID]
        let owned = initial.processes.filter { expectedPIDs.contains($0.identity.pid) }
        let resolved = try XCTUnwrap(realpath(binary.path, nil))
        let expectedExecutable = String(cString: resolved); free(resolved)
        let correctApps = owned.filter { $0.applicationID == "executable:" + expectedExecutable }.count
        let reportedListeners = owned.filter { $0.endpoints.contains { $0.address == "127.0.0.1" && $0.port == port && $0.family == "IPv4" && $0.scope == "Loopback" } }.count
        let precision: Double? = owned.isEmpty ? nil : 100 * Double(correctApps) / Double(owned.count)
        print("OWNED_SHARED_REPARENT_MATRIX expectedProcesses=2 observedProcesses=\(owned.count) unknownProcesses=\(2 - owned.count) correctAppAssignments=\(correctApps) appPrecisionDenominator=\(owned.count) expectedListenerOwners=2 observedListenerOwners=\(reportedListeners) appPrecisionPercent=\(precision.map { String($0) } ?? "unknown") listenerCoveragePercent=\(100 * Double(reportedListeners) / 2)")
        XCTAssertEqual(owned.count, 2, "Declared process denominator=2; missing owners count as unknown, not success.")
        XCTAssertEqual(correctApps, 2, "Both owners must match the declared executable app; a shared wrong assignment fails precision.")
        let a = try XCTUnwrap(owned.first { $0.identity.pid == parentPID })
        let b = try XCTUnwrap(owned.first { $0.identity.pid == childPID })
        XCTAssertEqual(a.identity.uid, getuid()); XCTAssertEqual(b.identity.uid, getuid())
        XCTAssertNotEqual(a.identity, b.identity)
        XCTAssertEqual(b.parentPID, parentPID)
        XCTAssertEqual(a.executable, expectedExecutable); XCTAssertEqual(b.executable, expectedExecutable)
        XCTAssertEqual(a.applicationID, b.applicationID)
        let listeners = owned.filter { $0.endpoints.contains { $0.address == "127.0.0.1" && $0.port == port && $0.family == "IPv4" && $0.scope == "Loopback" } }
        XCTAssertEqual(listeners.count, 2, "Declared owner/endpoint denominator=2, including the inherited child FD.")
        var snapshot = initial; snapshot.processes = owned
        let grouped = ResourceGroup.applications(snapshot)
        XCTAssertEqual(grouped.count, 1); XCTAssertEqual(grouped.first?.processes.count, 2)
        try input.fileHandleForWriting.write(contentsOf: Data("x".utf8))
        parent.waitUntilExit(); XCTAssertEqual(parent.terminationStatus, 0)
        let after = await sampler.sample()
        XCTAssertNil(after.processes.first { $0.identity == a.identity })
        let survivor = try XCTUnwrap(after.processes.first { $0.identity == b.identity })
        XCTAssertNotEqual(survivor.parentPID, parentPID)
        XCTAssertEqual(survivor.applicationID, b.applicationID)
        XCTAssertTrue(survivor.endpoints.contains { $0.address == "127.0.0.1" && $0.port == port })
        // Child reports normal completion on the owned pipe; no waitpid/signal to an unrelated PID.
        let completion = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertTrue(completion.contains("child-exit=0"))
        let final = await sampler.sample()
        XCTAssertNil(final.processes.first { $0.identity == b.identity && !$0.endpoints.isEmpty })
        print("OWNED_SHARED_REPARENT_COMPLETION observedParentWaitStatus=0 childReportedReturn=0 independentChildWaitStatus=unavailable stableSurvivingIdentity=1")
    }
    private static let fixture = """
    #include <arpa/inet.h>
    #include <poll.h>
    #include <stdio.h>
    #include <stdlib.h>
    #include <sys/socket.h>
    #include <unistd.h>
    int main(void) {
      int fd=socket(AF_INET,SOCK_STREAM,0); if(fd<0)return 10;
      struct sockaddr_in address={0}; address.sin_family=AF_INET; address.sin_len=sizeof(address);
      address.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
      if(bind(fd,(struct sockaddr*)&address,sizeof(address))||listen(fd,4))return 11;
      socklen_t length=sizeof(address); if(getsockname(fd,(struct sockaddr*)&address,&length))return 12;
      pid_t parent=getpid(), child=fork(); if(child<0)return 13;
      if(child==0) { close(STDIN_FILENO); sleep(20); close(fd); puts("child-exit=0"); fflush(stdout); return 0; }
      printf("%d %d %u\\n",parent,child,ntohs(address.sin_port)); fflush(stdout);
      struct pollfd control={.fd=STDIN_FILENO,.events=POLLIN}; (void)poll(&control,1,12000);
      close(fd); return 0;
    }
    """
}
