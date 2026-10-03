import Foundation
import Darwin
import CryptoKit
import Security

/// Narrow trust for an owned fixture or independently pinned reviewed native server.
/// Generic executable allowlisting and runtime-name authorization are not supported.
public struct TrustedServerAdapter: Sendable {
    enum Kind: Sendable { case ownedFixture, reviewedDarkHTTPD }
    let kind: Kind
    public let executable: String
    public let projectRoot: String
    public let sha256: String
    public let codeDirectoryHash: String
    public init(ownedFixtureExecutable: String, projectRoot: String, expectedSHA256: String, expectedCodeDirectoryHash: String = "") {
        kind = .ownedFixture
        executable = URL(fileURLWithPath: ownedFixtureExecutable).resolvingSymlinksInPath().path
        self.projectRoot = URL(fileURLWithPath: projectRoot).resolvingSymlinksInPath().path
        sha256 = expectedSHA256.lowercased()
        codeDirectoryHash = expectedCodeDirectoryHash.lowercased()
    }
    init(reviewedExecutable: String, projectRoot: String) {
        kind = .reviewedDarkHTTPD
        executable = URL(fileURLWithPath: reviewedExecutable).resolvingSymlinksInPath().path
        self.projectRoot = URL(fileURLWithPath: projectRoot).resolvingSymlinksInPath().path
        sha256 = SupportedServerBuilds.darkHTTPDSHA256
        codeDirectoryHash = SupportedServerBuilds.darkHTTPDCodeDirectoryHash
    }

}

public actor ActionController {
    private struct Authorization {
        let preview: StopPreview
        let adapter: TrustedServerAdapter
        var token: audit_token_t
    }
    private let adapters: [TrustedServerAdapter]
    private let sampler: Sampler
    private(set) var observationGeneration: UInt64 = 0
    private var resettingObservation = false
    private var pending: [UUID: Authorization] = [:]
    public init(adapters: [TrustedServerAdapter] = [], sampler: Sampler = Sampler()) {
        self.adapters = adapters; self.sampler = sampler
    }
    public func expirePreviews(now: Date = Date()) {
        pending = pending.filter { now.timeIntervalSince($0.value.preview.createdAt) <= ActionSafety.previewValidity }
    }
    private func sampleForValidation() async -> Snapshot {
        let snapshot = await sampler.sample()
        await sampler.resetBaselines()
        return snapshot
    }
    /// Invalidate authorization before awaiting the sampler's baseline reset.
    public func resetObservation() async {
        observationGeneration &+= 1
        let generation = observationGeneration
        resettingObservation = true
        pending.removeAll()
        await sampler.resetBaselines()
        if observationGeneration == generation { resettingObservation = false }
    }
    func isCurrentObservation(_ generation: UInt64) -> Bool {
        generation == observationGeneration && !resettingObservation
    }
    private func invalidatedResult(preview: StopPreview, signalsSent: Int = 0) -> StopResult {
        StopResult(targetID: preview.process.id, validation: .stale,
                   message: localized(signalsSent == 0 ? "Observation reset; review a new preview. No signal sent." : "SIGTERM was sent once; observation ended after reset. No retry."), signalsSent: signalsSent)
    }
    public func preview(process: ProcessSample, snapshot: Snapshot) async -> StopPreview {
        let generation = observationGeneration
        let readOnly = ActionSafety.preview(process: process, snapshot: snapshot)
        func disabled(_ reason: String) -> StopPreview {
            StopPreview(process: process, descendants: readOnly.descendants, createdAt: snapshot.timestamp,
                        disabledReason: reason, canStop: false, operationID: nil)
        }
        guard isCurrentObservation(generation) else { return disabled(localized("Observation reset; review a new preview. No signal sent.")) }
        var candidates = adapters
        if SupportedServerBuilds.canReview(executablePath: process.executable), let project = process.projectPath {
            candidates.append(SupportedServerBuilds.reviewedDarkHTTPD(executablePath: process.executable, projectRoot: project))
        }
        guard let adapter = candidates.first(where: { matches(process, adapter: $0) }) else { return readOnly }
        guard readOnly.descendants.isEmpty, process.identity.uid == getuid(),
              !process.endpoints.isEmpty, process.portAvailability == .available,
              Self.endpointsAllowed(process.endpoints, adapter: adapter) else {
            return disabled(localized("Trusted server scope or endpoint ownership is incomplete."))
        }
        guard let token = auditToken(pid: process.identity.pid) else {
            return disabled(localized("Public task audit-token acquisition is unavailable for this target."))
        }
        let current = await sampleForValidation()
        guard isCurrentObservation(generation) else { return disabled(localized("Observation reset; review a new preview. No signal sent.")) }
        let validation = ActionSafety.validate(preview: readOnly, current: current)
        guard validation == .unchanged else { return disabled(localizedFormat("Target validation failed: %@.", validation.rawValue)) }
        guard tokenPath(token) == process.executable else { return disabled(localized("Token-bound executable path validation failed.")) }
        guard matchesRunningCode(token, adapter: adapter) else { return disabled(localized("Running code signature does not match the trusted server build.")) }
        let id = UUID()
        let enabled = StopPreview(process: process, descendants: [], createdAt: current.timestamp,
                                  disabledReason: "", canStop: true, operationID: id,
                                  requiresDevelopmentConfirmation: adapter.kind == .reviewedDarkHTTPD)
        pending = pending.filter { current.timestamp.timeIntervalSince($0.value.preview.createdAt) <= ActionSafety.previewValidity }
        pending[id] = Authorization(preview: enabled, adapter: adapter, token: token)
        return enabled
    }
    public func confirm(preview: StopPreview, confirmed: Bool, developmentConfirmed: Bool = false) async -> StopResult {
        let generation = observationGeneration
        guard isCurrentObservation(generation) else { return invalidatedResult(preview: preview) }
        guard let id = preview.operationID, var authorization = pending.removeValue(forKey: id), confirmed else {
            return Self.refusal(preview: preview, current: Snapshot(processes: []), validation: .stale,
                                reason: confirmed ? (preview.disabledReason.isEmpty ? nil : preview.disabledReason) : "Cancelled; no action taken.")
        }
        guard Self.declarationAllows(adapter: authorization.adapter, developmentConfirmed: developmentConfirmed) else {
            return Self.refusal(preview: authorization.preview, current: Snapshot(processes: []), validation: .stale,
                                reason: "Development-server declaration was not confirmed; no signal sent.")
        }
        let current = await sampleForValidation()
        guard isCurrentObservation(generation) else { return invalidatedResult(preview: preview) }
        let validation = tokenState(authorization.token) == .gone ? TargetValidation.alreadyExited : ActionSafety.validate(preview: authorization.preview, current: current)
        guard validation == .unchanged else {
            return Self.refusal(preview: preview, current: current, validation: validation)
        }
        guard matches(authorization.preview.process, adapter: authorization.adapter) else {
            return Self.refusal(preview: preview, current: current, validation: .metadataChanged,
                                reason: "Trusted executable metadata no longer matches; no signal sent.")
        }
        guard tokenPath(authorization.token) == authorization.preview.process.executable else {
            return Self.refusal(preview: preview, current: current, validation: .metadataChanged,
                                reason: "Token-bound executable path could not be validated; no signal sent.")
        }
        guard matchesRunningCode(authorization.token, adapter: authorization.adapter) else {
            return Self.refusal(preview: preview, current: current, validation: .metadataChanged,
                                reason: "Running code signature does not match the trusted server build; no signal sent.")
        }
        // Token-bound kernel lookup checks process incarnation. Never fall back to kill(pid).
        let sent = proc_signal_with_audittoken(&authorization.token, SIGTERM)
        guard sent == 0 else {
            let refused = await sampleForValidation()
            guard isCurrentObservation(generation) else { return invalidatedResult(preview: preview) }
            return Self.refusal(preview: preview, current: refused, validation: sent == ESRCH ? .alreadyExited : validation,
                                reason: sent == ESRCH ? localized("Target already exited; no signal sent.") : localizedFormat("Identity-bound signal was rejected (code %ld); no retry.", sent))
        }
        let verificationClock = ContinuousClock()
        let deadline = verificationClock.now.advanced(by: .seconds(10))
        var observed = current
        repeat {
            try? await Task.sleep(for: .milliseconds(200))
            guard isCurrentObservation(generation) else { return invalidatedResult(preview: preview, signalsSent: 1) }
            observed = await sampleForValidation()
            guard isCurrentObservation(generation) else { return invalidatedResult(preview: preview, signalsSent: 1) }
            if tokenState(authorization.token) == .gone { break }
        } while verificationClock.now < deadline
        let target = authorization.preview.process.identity
        let originalPresent = observed.processes.contains { $0.identity == target }
        let remaining = observed.processes.filter { $0.identity == target || (originalPresent && $0.parentPID == target.pid) }.map(\.identity)
        let ports = Set(preview.endpoints.map(\.port))
        let remainingPorts = observed.processes.flatMap(\.endpoints).filter { ports.contains($0.port) }
        let finalTokenState = tokenState(authorization.token)
        let remainingAvailable = Self.remainingObservationAvailable(in: observed, target: target, originalKnownGone: finalTokenState == .gone)
            && finalTokenState != .unknown && (finalTokenState != .alive || originalPresent)
        let message: String
        if !remainingAvailable { message = localized("SIGTERM sent once; original-target verification is unavailable.") }
        else if finalTokenState == .alive || !remaining.isEmpty { message = localized("Still running after SIGTERM; no retry or force kill.") }
        else { message = remainingPorts.isEmpty ? localized("Previewed server exited; no remaining observed endpoint owner.") : localized("Previewed server exited; an endpoint has a current observed owner.") }
        return StopResult(targetID: target.id, validation: .unchanged, message: message, signalsSent: 1,
                          remainingIdentities: remainingAvailable ? remaining : [], remainingEndpoints: remainingAvailable ? remainingPorts : [],
                          remainingObservationAvailable: remainingAvailable)
    }
    /// Refusal reports only the original incarnation observed in the fresh snapshot.
    nonisolated static func refusal(preview: StopPreview, current: Snapshot, validation: TargetValidation,
                                    reason: String? = nil) -> StopResult {
        let message: String
        switch validation {
        case .stale: message = localized("Preview expired or current validation is unavailable; review a new preview. No signal sent.")
        case .alreadyExited: message = localized("Target already exited; no signal sent.")
        case .identityChanged: message = localized("Original target identity no longer matches; no signal sent.")
        case .metadataChanged: message = localized("Target metadata changed or is unavailable; no signal sent.")
        case .sharedEndpoint: message = localized("An endpoint has another observed owner; no signal sent.")
        case .descendantsChanged: message = localized("Observed descendants changed; no signal sent.")
        case .unchanged: message = localized("Action refused; no signal sent.")
        }
        let available = remainingObservationAvailable(in: current, target: preview.process.identity, originalKnownGone: validation == .alreadyExited)
        let original = available ? current.processes.first { $0.identity == preview.process.identity } : nil
        return StopResult(targetID: preview.process.id, validation: validation,
                          message: localized(reason ?? message), signalsSent: 0,
                          remainingIdentities: original.map { [$0.identity] } ?? [],
                          remainingEndpoints: original?.endpoints ?? [], remainingObservationAvailable: available)
    }
    nonisolated static func remainingObservationAvailable(in snapshot: Snapshot, target: ProcessIdentity, originalKnownGone: Bool = false) -> Bool {
        guard snapshot.availability == .available else { return false }
        if let original = snapshot.processes.first(where: { $0.identity == target }) {
            return original.portAvailability == .available
        }
        // A replacement incarnation proves the original is absent; inaccessible targets do not.
        return originalKnownGone || snapshot.inaccessibleCount == 0 || snapshot.processes.contains { $0.identity.pid == target.pid }
    }
    nonisolated static func endpointsAllowed(_ endpoints: [Endpoint], adapter: TrustedServerAdapter) -> Bool {
        !endpoints.isEmpty && endpoints.allSatisfy {
            adapter.kind == .reviewedDarkHTTPD ? ($0.address == "127.0.0.1" && $0.family == "IPv4") : ["127.0.0.1", "::1"].contains($0.address)
        }
    }
    nonisolated static func declarationAllows(adapter: TrustedServerAdapter, developmentConfirmed: Bool) -> Bool {
        adapter.kind == .ownedFixture || developmentConfirmed
    }
    private func matches(_ process: ProcessSample, adapter: TrustedServerAdapter) -> Bool {
        guard URL(fileURLWithPath: adapter.executable).lastPathComponent == (adapter.kind == .ownedFixture ? "AmidFixture" : "darkhttpd"),
              URL(fileURLWithPath: process.executable).resolvingSymlinksInPath().path == adapter.executable, process.projectPath.map({ URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }) == adapter.projectRoot,
              process.workingDirectory.map({ URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }) == adapter.projectRoot,
              adapter.sha256.count == 64,
              let bytes = try? Data(contentsOf: URL(fileURLWithPath: adapter.executable), options: .mappedIfSafe) else { return false }
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() == adapter.sha256
    }
    private func matchesRunningCode(_ supplied: audit_token_t, adapter: TrustedServerAdapter) -> Bool {
        guard adapter.codeDirectoryHash.count == 40,
              adapter.codeDirectoryHash.allSatisfy({ $0.isHexDigit }) else { return false }
        var token = supplied
        let tokenData = withUnsafeBytes(of: &token) { Data($0) }
        let attributes = [kSecGuestAttributeAudit as String: tokenData] as CFDictionary
        var guest: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &guest) == errSecSuccess,
              let guest else { return false }
        var requirement: SecRequirement?
        let expression = "cdhash H\"\(adapter.codeDirectoryHash)\"" as CFString
        guard SecRequirementCreateWithString(expression, [], &requirement) == errSecSuccess,
              let requirement else { return false }
        // Dynamic validity binds the requirement to the running guest, not a replaced path's bytes.
        return SecCodeCheckValidity(guest, [], requirement) == errSecSuccess
    }
    private func auditToken(pid: Int32) -> audit_token_t? {
        guard pid > 0 else { return nil }
        var task: mach_port_name_t = 0
        guard task_name_for_pid(mach_task_self_, pid, &task) == KERN_SUCCESS else { return nil }
        defer { mach_port_deallocate(mach_task_self_, task) }
        var token = audit_token_t()
        let tokenCount = MemoryLayout<audit_token_t>.size / MemoryLayout<natural_t>.size
        var count = mach_msg_type_number_t(tokenCount)
        let result = withUnsafeMutablePointer(to: &token) {
            $0.withMemoryRebound(to: integer_t.self, capacity: tokenCount) {
                task_info(task, task_flavor_t(TASK_AUDIT_TOKEN), $0, &count)
            }
        }
        return result == KERN_SUCCESS && Int(count) == tokenCount ? token : nil
    }
    private enum TokenState { case alive, gone, unknown }
    private func tokenState(_ supplied: audit_token_t) -> TokenState {
        var token = supplied
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        errno = 0
        let size = path.withUnsafeMutableBytes { proc_pidpath_audittoken(&token, $0.baseAddress, UInt32($0.count)) }
        if size > 0 { return .alive }
        return errno == ESRCH ? .gone : .unknown
    }
    private func tokenPath(_ supplied: audit_token_t) -> String? {
        var token = supplied
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let size = path.withUnsafeMutableBytes { proc_pidpath_audittoken(&token, $0.baseAddress, UInt32($0.count)) }
        return size > 0 ? String(decoding: path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self) : nil
    }
}
