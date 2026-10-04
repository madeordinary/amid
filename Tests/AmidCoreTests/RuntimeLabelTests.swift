import XCTest
@testable import AmidCore

/// Display-label facts from synthetic basenames, not running-code or development-intent proof.
final class RuntimeLabelTests: XCTestCase {
    func testDeclaredRuntimeAndToolBasenames() {
        let cases: [(String, String)] = [
            ("node", "Node.js"), ("python", "Python"), ("python3", "Python"),
            ("python3.11", "Python"), ("python3.13.1", "Python"),
            ("swift", "Swift"), ("swift-frontend", "Swift"),
            ("codex", "Codex CLI"), ("claude", "Claude Code CLI"),
            ("gemini", "Gemini CLI"), ("ollama", "Ollama")
        ]
        for (name, expected) in cases {
            XCTAssertEqual(Sampler.runtime("/owned-fixture/bin/\(name)"), expected, name)
            XCTAssertEqual(Sampler.runtime("/owned-fixture/bin/\(name.uppercased())"), expected, name)
        }
    }

    func testGenericRuntimeDoesNotInheritToolLabelFromAncestors() {
        for tool in ["codex", "claude", "gemini", "ollama"] {
            XCTAssertEqual(Sampler.runtime("/owned-fixture/\(tool)/bin/node"), "Node.js")
            XCTAssertEqual(Sampler.runtime("/owned-fixture/\(tool)/bin/python3.12"), "Python")
            XCTAssertNil(Sampler.runtime("/owned-fixture/\(tool)/bin/unknown"))
        }
    }

    func testSimilarBasenamesDoNotBecomeNamedToolsOrRuntimes() {
        for name in ["nodejs", "node-helper", "my-node", "node.exe", "python2", "python-helper",
                     "swiftc", "swift-frontend-helper", "mycodex", "codex-helper", "codex.old",
                     "claude-server", "myclaude", "gemini-helper", "ollama-helper", "ollama.old", "unknown", ""] {
            XCTAssertNil(Sampler.runtime("/owned-fixture/bin/\(name)"), name)
        }
        XCTAssertNil(Sampler.runtime(""))
        XCTAssertNil(Sampler.runtime("/"))
    }

    func testPythonVersionSuffixRequiresNonemptyASCIINumericSegments() {
        for name in ["python3.", "python3.evil", "python3.12evil", "python3.12.egg",
                     "python3..12", "python3.12.", "python3.12..1", "python3.12-1",
                     "python3.１２", "python3.١٢"] {
            XCTAssertNil(Sampler.runtime("/owned-fixture/bin/\(name)"), name)
        }
    }
}
