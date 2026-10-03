import XCTest
@testable import AmidApp

final class VerificationPathTests: XCTestCase {
    func testExplicitOwnedServerMatchesBothTemporaryDirectoryAliases() throws {
        let directory = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("amid-path-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("darkhttpd")
        try Data("synthetic path test".utf8).write(to: executable)
        let alias = executable.path.replacingOccurrences(of: "/private/tmp/", with: "/tmp/")
        let parsed = AppModel.verificationOwnedServerPath(arguments: ["Amid", "--verification-owned-server", executable.path])
        print("OWNED_PATH_PARSE", executable.path, parsed ?? "nil")
        for expected in [try XCTUnwrap(parsed), alias, executable.path] {
            XCTAssertTrue(AppModel.matchesVerificationOwnedServer(executable: executable.path, expected: expected))
            XCTAssertTrue(AppModel.matchesVerificationOwnedServer(executable: alias, expected: expected))
            XCTAssertFalse(AppModel.matchesVerificationOwnedServer(executable: executable.path + "-other", expected: expected))
        }
        XCTAssertFalse(AppModel.matchesVerificationOwnedServer(executable: executable.path, expected: nil))
        XCTAssertNil(AppModel.verificationOwnedServerPath(arguments: ["Amid"]))
        XCTAssertNil(AppModel.verificationOwnedServerPath(arguments: ["Amid", "--verification-owned-server"]))
    }
}
