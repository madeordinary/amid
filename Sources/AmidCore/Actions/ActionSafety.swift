import Foundation

public struct StopPreview: Sendable {
    public let process: ProcessSample
    public let descendants: [ProcessIdentity]
    public let createdAt: Date
    public let disabledReason: String
    public let canStop: Bool
    public let operationID: UUID?
    public var requiresDevelopmentConfirmation: Bool = false
    /// Non-empty only for a user-declared development server: the statement the user must tick.
    public var declaration: String = ""
    public var exposedToNetwork: Bool = false
    /// Executable basenames of observed ancestors, outermost first.
    public var ancestors: [String] = []
    public var identities: [ProcessIdentity] { [process.identity] + descendants }
    public var endpoints: [Endpoint] { process.endpoints }
    public static func unavailable(process: ProcessSample, reason: String) -> StopPreview {
        StopPreview(process: process, descendants: [], createdAt: Date(), disabledReason: reason, canStop: false, operationID: nil)
    }
}

public enum TargetValidation: String, Sendable {
    case unchanged, alreadyExited, programChanged, identityChanged, metadataChanged, sharedEndpoint, descendantsChanged, stale
}

public struct StopResult: Sendable {
    public let targetID: String
    public let validation: TargetValidation
    public let message: String
    public let signalsSent: Int
    public var remainingIdentities: [ProcessIdentity] = []
    public var remainingEndpoints: [Endpoint] = []
    /// False means the remaining arrays cannot support a measured count, including zero.
    public var remainingObservationAvailable: Bool = false
    /// Previewed descendants still observed by identity; they were never signalled.
    public var remainingDescendants: [ProcessIdentity] = []
    public var descendantsUnknown: Bool = false
}

/// Display grouping never authorizes a process action. There is deliberately no signal path.
public enum ActionSafety {
    public static let previewValidity: TimeInterval = 120
    public static var identityBlocker: String { localized("Stop unavailable: no enrolled trusted development-server adapter. PID checks alone cannot prevent reuse; generic runtime metadata cannot establish server intent.") }
    public static func preview(process: ProcessSample, snapshot: Snapshot) -> StopPreview {
        let reason: String
        switch DeclaredServerEligibility.evaluate(process: process, snapshot: snapshot) {
        case .readOnly(let readOnly): reason = readOnly
        case .eligible: reason = localized("Review required: Amid checks this exact process and asks you to declare it as your development server before any signal.")
        }
        return StopPreview(process: process, descendants: descendants(of: process.identity.pid, in: snapshot),
                           createdAt: snapshot.timestamp, disabledReason: reason, canStop: false, operationID: nil)
    }

    public static func validate(preview: StopPreview, current: Snapshot) -> TargetValidation {
        let age = current.timestamp.timeIntervalSince(preview.createdAt)
        guard age >= 0 && age <= previewValidity, current.availability == .available else { return .stale }
        guard let process = current.processes.first(where: { $0.identity.pid == preview.process.identity.pid }) else {
            return current.inaccessibleCount == 0 ? .alreadyExited : .stale
        }
        guard process.identity == preview.process.identity else { return .identityChanged }
        guard process.executable == preview.process.executable,
              process.parentPID == preview.process.parentPID,
              process.runtime == preview.process.runtime,
              process.workingDirectory == preview.process.workingDirectory,
              process.projectPath == preview.process.projectPath,
              process.portAvailability == .available,
              Set(process.endpoints) == Set(preview.endpoints) else { return .metadataChanged }
        let ports = Set(preview.endpoints.map(\.port))
        if current.processes.contains(where: { $0.identity != process.identity && $0.endpoints.contains { ports.contains($0.port) } }) {
            return .sharedEndpoint
        }
        guard Set(descendants(of: process.identity.pid, in: current)) == Set(preview.descendants) else { return .descendantsChanged }
        return .unchanged
    }

    public static func confirm(preview: StopPreview, current: Snapshot, confirmed: Bool) -> StopResult {
        let validation = validate(preview: preview, current: current)
        return StopResult(targetID: preview.process.id, validation: validation,
                          message: confirmed ? preview.disabledReason : localized("Cancelled; no action taken."), signalsSent: 0)
    }

    private static func descendants(of pid: Int32, in snapshot: Snapshot) -> [ProcessIdentity] {
        var parents: Set<Int32> = [pid]
        var found: [ProcessIdentity] = []
        var changed = true
        while changed {
            changed = false
            for process in snapshot.processes where !parents.contains(process.identity.pid) && parents.contains(process.parentPID) {
                parents.insert(process.identity.pid); found.append(process.identity); changed = true
            }
        }
        return found.sorted { $0.id < $1.id }
    }
}
