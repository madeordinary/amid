import XCTest
import Foundation
import Darwin
@testable import AmidCore

final class AttributionMatrixTests: XCTestCase {
    private func directory() throws -> URL {
        let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("amid-owned-attribution-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.resolvingSymlinksInPath()
    }
    private func physicalPath(_ path: URL) throws -> String {
        let resolved = try XCTUnwrap(realpath(path.path, nil))
        defer { free(resolved) }
        return String(cString: resolved)
    }
    private func make(_ path: URL) throws {
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
    }
    private func marker(_ path: URL) throws {
        try Data("synthetic marker: existence only\n".utf8).write(to: path)
    }
    func testNestedRootsWorktreeMarkersAndFreshLookup() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let outer = root.appendingPathComponent("monorepo")
        let nested = outer.appendingPathComponent("packages/native")
        let cwd = nested.appendingPathComponent("src")
        try make(cwd); try marker(outer.appendingPathComponent("package.json"))
        XCTAssertEqual(ProjectAttribution.root(for: cwd.path), outer.path)
        try marker(nested.appendingPathComponent("Package.swift"))
        XCTAssertEqual(ProjectAttribution.root(for: cwd.path), nested.path)
        XCTAssertEqual(ProjectAttribution.root(for: cwd.path, boundaries: [outer.path, nested.path]), nested.path)
        XCTAssertEqual(ProjectAttribution.root(for: cwd.path, boundaries: [outer.path]), outer.path)
        try FileManager.default.removeItem(at: nested.appendingPathComponent("Package.swift"))
        XCTAssertEqual(ProjectAttribution.root(for: cwd.path), outer.path, "Marker removal must be visible on the next lookup.")
        let sibling = root.appendingPathComponent("monorepo-other")
        try make(sibling); try marker(sibling.appendingPathComponent("go.mod"))
        XCTAssertEqual(ProjectAttribution.root(for: sibling.path, boundaries: [outer.path]), sibling.path, "Containing boundaries must respect a path separator.")
        var worktrees: [String] = []
        for name in ["worktree-a", "worktree-b"] {
            let tree = root.appendingPathComponent(name); let source = tree.appendingPathComponent("src")
            try make(source); try marker(tree.appendingPathComponent(".git"))
            worktrees.append(try XCTUnwrap(ProjectAttribution.root(for: source.path)))
        }
        XCTAssertNotEqual(worktrees[0], worktrees[1], "A .git file is marker evidence, not permission to combine worktrees.")
        XCTAssertEqual(ProjectAttribution.root(for: cwd.appendingPathComponent("../src").path), outer.path)
    }
    func testOwnedBundleHelpersDistinctExecutablesAndCanonicalWorkingDirectories() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("bounded.c")
        try Data("#include <stdio.h>\n#include <unistd.h>\nint main(void){printf(\"%d\\n\",getpid());if(fflush(stdout))return 1;sleep(12);return 0;}\n".utf8).write(to: source)
        let original = root.appendingPathComponent("bounded")
        let compiler = Process(); compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        compiler.arguments = ["clang", "-arch", "arm64", "-mmacosx-version-min=15.0", source.path, "-o", original.path]
        try compiler.run(); compiler.waitUntilExit()
        XCTAssertEqual(compiler.terminationStatus, 0)
        guard compiler.terminationStatus == 0 else { return }
        let projectA = root.appendingPathComponent("worktree-a"), projectB = root.appendingPathComponent("worktree-b")
        for project in [projectA, projectB] { try make(project.appendingPathComponent("src")); try marker(project.appendingPathComponent(".git")) }
        let alias = root.appendingPathComponent("alias-a")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: projectA)
        let names = ["A.app/Contents/MacOS/Worker", "A.app/Contents/Frameworks/Helper.app/Contents/MacOS/Worker", "B.app/Contents/Frameworks/Helper.app/Contents/MacOS/Worker", "plain-a/Worker", "plain-b/Worker"]
        var children: [Process] = []
        defer { for child in children { child.waitUntilExit() } }
        var executablePaths: [String] = []
        for (index, name) in names.enumerated() {
            let executable = root.appendingPathComponent(name)
            try make(executable.deletingLastPathComponent()); try FileManager.default.copyItem(at: original, to: executable)
            let child = Process(); let pipe = Pipe(); child.executableURL = executable
            child.currentDirectoryURL = (index == 0 ? alias : index == 1 ? projectA : projectB).appendingPathComponent("src")
            child.standardOutput = pipe
            try child.run(); children.append(child)
            let ready = String(decoding: pipe.fileHandleForReading.availableData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertEqual(Int32(ready), child.processIdentifier)
            executablePaths.append(try physicalPath(executable))
        }
        let snapshot = await Sampler().sample()
        let ownIDs = Set(children.map(\.processIdentifier))
        let owned = snapshot.processes.filter { ownIDs.contains($0.identity.pid) }
        XCTAssertEqual(owned.count, 5, "Only this run's recorded child identities are assessed.")
        for (index, child) in children.enumerated() {
            let observed = try XCTUnwrap(owned.first { $0.identity.pid == child.processIdentifier })
            XCTAssertEqual(observed.identity.uid, getuid())
            XCTAssertEqual(observed.executable, executablePaths[index])
            XCTAssertEqual(observed.projectPath, (index < 2 ? projectA : projectB).path)
            XCTAssertEqual(observed.workingDirectory, try physicalPath((index < 2 ? projectA : projectB).appendingPathComponent("src")))
            XCTAssertTrue(observed.endpoints.isEmpty)
        }
        let a = try XCTUnwrap(owned.first { $0.identity.pid == children[0].processIdentifier })
        let helper = try XCTUnwrap(owned.first { $0.identity.pid == children[1].processIdentifier })
        let b = try XCTUnwrap(owned.first { $0.identity.pid == children[2].processIdentifier })
        XCTAssertEqual(a.applicationID, helper.applicationID)
        XCTAssertEqual(a.applicationName, "A"); XCTAssertEqual(b.applicationName, "B")
        XCTAssertNotEqual(a.applicationID, b.applicationID)
        var filtered = snapshot; filtered.processes = owned
        let groups = ResourceGroup.applications(filtered)
        XCTAssertEqual(groups.count, 4)
        XCTAssertEqual(groups.first { $0.id == a.applicationID }?.processes.count, 2)
        let plainA = try XCTUnwrap(owned.first { $0.identity.pid == children[3].processIdentifier })
        let plainB = try XCTUnwrap(owned.first { $0.identity.pid == children[4].processIdentifier })
        XCTAssertNotEqual(plainA.applicationID, plainB.applicationID)
        for child in children { child.waitUntilExit(); XCTAssertEqual(child.terminationStatus, 0) }
        print("OWNED_ATTRIBUTION_MATRIX processes=5 applicationGroups=4 projectRoots=2 naturalExits=5")
    }
}
