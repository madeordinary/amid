import Foundation

/// Decides only when Stop is offered for a user-declared development server.
/// Audit-token, path and running-code binding plus the per-preview declaration authorize a signal; these rules never do.
public enum DeclaredServerEligibility {
    public enum Outcome: Equatable, Sendable {
        case eligible(exposedToNetwork: Bool)
        case readOnly(String)
    }

    public static func evaluate(process: ProcessSample, snapshot: Snapshot, uid: uid_t = getuid()) -> Outcome {
        guard process.identity.uid == uid else { return .readOnly(localized("Read-only: this process belongs to another user.")) }
        guard ["Node.js", "Python"].contains(Sampler.runtime(process.executable) ?? "") else {
            return .readOnly(localized("Read-only: this runtime has no development-server stop."))
        }
        guard !insideApplicationBundle(process.executable) || isFrameworkPythonInterpreter(process.executable) else {
            return .readOnly(localized("Read-only: this process belongs to an application bundle."))
        }
        guard process.parentPID > 1 else {
            return .readOnly(localized("Read-only: launchd manages or adopted this process, so a supervisor may restart it."))
        }
        guard let project = process.projectPath.map(canonical), let directory = process.workingDirectory.map(canonical),
              directory == project || directory.hasPrefix(project + "/") else {
            return .readOnly(localized("Read-only: no detected project contains its working directory."))
        }
        guard !process.endpoints.isEmpty, process.portAvailability == .available else {
            return .readOnly(localized("Read-only: project and listening endpoint ownership are not fully available."))
        }
        guard process.endpoints.allSatisfy({ isLoopback($0.address) || isWildcard($0.address) }) else {
            return .readOnly(localized("Read-only: it listens on a specific network address."))
        }
        let ports = Set(process.endpoints.map(\.port))
        guard !snapshot.processes.contains(where: { $0.identity != process.identity && $0.endpoints.contains { ports.contains($0.port) } }) else {
            return .readOnly(localized("Read-only: another process also owns this port."))
        }
        return .eligible(exposedToNetwork: process.endpoints.contains { isWildcard($0.address) })
    }

    /// Framework Python builds run their interpreter from Python.app inside Python.framework. Discovery only:
    /// the layout must not sit inside another application, except Xcode's developer frameworks.
    static func isFrameworkPythonInterpreter(_ path: String) -> Bool {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count >= 8, parts.suffix(4) == ["Python.app", "Contents", "MacOS", "Python"] else { return false }
        let frameworkParts = parts.dropLast(4)
        guard frameworkParts.last == "Resources", frameworkParts.dropLast().dropLast().last == "Versions" else { return false }
        let framework = frameworkParts.dropLast(3).last ?? ""
        guard framework == "Python.framework" || framework == "Python3.framework" else { return false }
        let enclosing = Array(frameworkParts.dropLast(4))
        guard enclosing.contains(where: { $0.hasSuffix(".app") }) else { return true }
        return enclosing.count == 6 && enclosing[0] == "Applications" && enclosing[1].hasPrefix("Xcode") && enclosing[1].hasSuffix(".app")
            && Array(enclosing[2...]) == ["Contents", "Developer", "Library", "Frameworks"]
    }

    static func insideApplicationBundle(_ path: String) -> Bool {
        path.split(separator: "/").contains { $0.hasSuffix(".app") }
    }

    static func isLoopback(_ address: String) -> Bool { address.hasPrefix("127.") || address == "::1" }
    static func isWildcard(_ address: String) -> Bool { address == "0.0.0.0" || address == "::" }
    private static func canonical(_ path: String) -> String { URL(fileURLWithPath: path).resolvingSymlinksInPath().path }
}
