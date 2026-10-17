import Foundation
import Darwin
import CryptoKit
import Security

/// Narrow trust for an owned fixture, an independently pinned reviewed native server, or a user-declared
/// development server. Runtime names only decide when Stop is offered; they never authorize a signal.
public struct TrustedServerAdapter: Sendable {
    enum Kind: Sendable { case ownedFixture, reviewedDarkHTTPD, declaredDevelopmentServer }
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
    /// The running-code hash is captured per preview, never pinned in advance.
    init(declaredExecutable: String, projectRoot: String) {
        kind = .declaredDevelopmentServer
        executable = URL(fileURLWithPath: declaredExecutable).resolvingSymlinksInPath().path
        self.projectRoot = URL(fileURLWithPath: projectRoot).resolvingSymlinksInPath().path
        sha256 = ""; codeDirectoryHash = ""
    }

}

public actor ActionController {
    private struct Authorization {
        let preview: StopPreview
        let adapter: TrustedServerAdapter
        var token: audit_token_t
        let codeDirectoryHash: String
    }
    private let adapters: [TrustedServerAdapter]
    private let sampler: Sampler
    private(set) var observationGeneration: UInt64 = 0
    private var resettingObservation = false
    private var pending: [UUID: Authorization] = [:]
    private var beforeDispatch: (@Sendable () async -> Void)?
    /// Test seam between the final checks and dispatch; production never sets it.
    func setBeforeDispatchForTesting(_ hook: @escaping @Sendable () async -> Void) { beforeDispatch = hook }
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
        let adapter: TrustedServerAdapter
        if let pinned = candidates.first(where: { matches(process, adapter: $0) }) {
            adapter = pinned
        } else if case .eligible = DeclaredServerEligibility.evaluate(process: process, snapshot: snapshot), let project = process.projectPath {
            adapter = TrustedServerAdapter(declaredExecutable: process.executable, projectRoot: project)
        } else { return readOnly }
        let declared = adapter.kind == .declaredDevelopmentServer
        // Pinned builds are known not to fork; a declared server keeps its listed children, which are never signalled.
        guard declared || readOnly.descendants.isEmpty, process.identity.uid == getuid(),
              !process.endpoints.isEmpty, process.portAvailability == .available,
              Self.endpointsAllowed(process.endpoints, adapter: adapter) else {
            return disabled(localized("Trusted server scope or endpoint ownership is incomplete."))
        }
        guard let token = Self.auditToken(pid: process.identity.pid) else {
            return disabled(localized("Public task audit-token acquisition is unavailable for this target."))
        }
        let current = await sampleForValidation()
        guard isCurrentObservation(generation) else { return disabled(localized("Observation reset; review a new preview. No signal sent.")) }
        let validation = ActionSafety.validate(preview: readOnly, current: current)
        guard validation == .unchanged else { return disabled(localizedFormat("Target validation failed: %@.", validation.rawValue)) }
        if declared, !Self.stillEligible(process.identity, executable: adapter.executable, in: current) {
            return disabled(localized("The process no longer meets the development-server rules."))
        }
        guard Self.tokenPath(token) == process.executable else { return disabled(localized("Token-bound executable path validation failed.")) }
        guard let codeDirectoryHash = declared ? Self.runningCodeDirectoryHash(token) : adapter.codeDirectoryHash,
              Self.matchesRunningCode(token, codeDirectoryHash: codeDirectoryHash) else {
            return disabled(declared ? localized("Running code identity is unavailable for this target.")
                                     : localized("Running code signature does not match the trusted server build."))
        }
        let id = UUID()
        var enabled = StopPreview(process: process, descendants: declared ? readOnly.descendants : [], createdAt: current.timestamp,
                                  disabledReason: "", canStop: true, operationID: id,
                                  requiresDevelopmentConfirmation: adapter.kind != .ownedFixture)
        if declared {
            let project = URL(fileURLWithPath: adapter.projectRoot).lastPathComponent
            let ports = Array(Set(process.endpoints.map(\.port))).sorted().map(String.init).joined(separator: ", ")
            enabled.declaration = localizedFormat("This is my development server for %@ (%@ on port %@), and I want to stop it. Open requests will be interrupted.",
                                                  project, URL(fileURLWithPath: process.executable).lastPathComponent, ports)
            enabled.exposedToNetwork = process.endpoints.contains { DeclaredServerEligibility.isWildcard($0.address) }
            enabled.ancestors = Self.ancestors(of: process, in: current)
        }
        pending = pending.filter { current.timestamp.timeIntervalSince($0.value.preview.createdAt) <= ActionSafety.previewValidity }
        pending[id] = Authorization(preview: enabled, adapter: adapter, token: token, codeDirectoryHash: codeDirectoryHash)
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
        let target = authorization.preview.process.identity
        let declared = authorization.adapter.kind == .declaredDevelopmentServer
        // A vanished token means exit, or an exec that replaced the program under the same identity.
        let validation = Self.tokenState(authorization.token) == .gone ? Self.goneValidation(target)
            : ActionSafety.validate(preview: authorization.preview, current: current)
        guard validation == .unchanged else {
            return Self.refusal(preview: preview, current: current, validation: validation)
        }
        if declared {
            guard Self.stillEligible(target, executable: authorization.adapter.executable, in: current) else {
                return Self.refusal(preview: preview, current: current, validation: .metadataChanged,
                                    reason: "The process no longer meets the development-server rules; no signal sent.")
            }
        } else {
            guard matches(authorization.preview.process, adapter: authorization.adapter) else {
                return Self.refusal(preview: preview, current: current, validation: .metadataChanged,
                                    reason: "Trusted executable metadata no longer matches; no signal sent.")
            }
        }
        guard Self.tokenPath(authorization.token) == authorization.preview.process.executable else {
            return Self.refusal(preview: preview, current: current, validation: .metadataChanged,
                                reason: "Token-bound executable path could not be validated; no signal sent.")
        }
        guard Self.matchesRunningCode(authorization.token, codeDirectoryHash: authorization.codeDirectoryHash) else {
            return Self.refusal(preview: preview, current: current, validation: .metadataChanged,
                                reason: declared ? "Running code no longer matches the previewed program; no signal sent."
                                                 : "Running code signature does not match the trusted server build; no signal sent.")
        }
        if let beforeDispatch {
            await beforeDispatch()
            guard isCurrentObservation(generation) else { return invalidatedResult(preview: preview) }
        }
        // Token-bound kernel lookup checks process incarnation. Never fall back to kill(pid).
        let sent = proc_signal_with_audittoken(&authorization.token, SIGTERM)
        guard sent == 0 else {
            let refused = await sampleForValidation()
            guard isCurrentObservation(generation) else { return invalidatedResult(preview: preview) }
            return Self.refusal(preview: preview, current: refused, validation: sent == ESRCH ? Self.goneValidation(target) : validation,
                                reason: sent == ESRCH ? nil : localizedFormat("Identity-bound signal was rejected (code %ld); no retry.", sent))
        }
        let verificationClock = ContinuousClock()
        let deadline = verificationClock.now.advanced(by: .seconds(10))
        var observed = current
        repeat {
            try? await Task.sleep(for: .milliseconds(200))
            guard isCurrentObservation(generation) else { return invalidatedResult(preview: preview, signalsSent: 1) }
            observed = await sampleForValidation()
            guard isCurrentObservation(generation) else { return invalidatedResult(preview: preview, signalsSent: 1) }
            // A declared server is watched for the whole window so a delayed replacement listener is seen.
            if !declared && Self.tokenState(authorization.token) == .gone { break }
        } while verificationClock.now < deadline
        let originalPresent = observed.processes.contains { $0.identity == target }
        let ports = Set(preview.endpoints.map(\.port))
        let remainingPorts = observed.processes.flatMap(\.endpoints).filter { ports.contains($0.port) }
        let finalTokenState = Self.tokenState(authorization.token)
        let message: String
        var result: StopResult
        if declared {
            // A vanished token alone cannot distinguish exit from exec; look the incarnation up directly.
            let gone = finalTokenState == .gone ? Self.goneValidation(target) : nil
            let remainingAvailable = Self.remainingObservationAvailable(in: observed, target: target, originalKnownGone: gone == .alreadyExited)
                && finalTokenState != .unknown && gone != .stale && (finalTokenState != .alive || originalPresent)
            let stillPresent = finalTokenState == .alive || gone == .programChanged
            let descendants = Self.remainingDescendants(authorization.preview.descendants, in: observed)
            if !remainingAvailable { message = localized("SIGTERM sent once; original-target verification is unavailable.") }
            else if finalTokenState == .alive { message = localized("Still running after SIGTERM; no retry or force kill.") }
            else if gone == .programChanged { message = localized("The process switched to another program after the signal. Amid sent one signal and will not retry.") }
            else if !remainingPorts.isEmpty {
                message = localizedFormat("Another process now owns port %@, possibly restarted by a supervisor. Amid will not retry; stop the parent in its terminal.",
                                          Array(Set(remainingPorts.map(\.port))).sorted().map(String.init).joined(separator: ", "))
            } else { message = localized("Server exited; no remaining observed endpoint owner.") }
            result = StopResult(targetID: target.id, validation: .unchanged, message: message, signalsSent: 1,
                                remainingIdentities: remainingAvailable && stillPresent ? [target] : [],
                                remainingEndpoints: remainingAvailable ? remainingPorts : [], remainingObservationAvailable: remainingAvailable)
            result.remainingDescendants = descendants.observed
            result.descendantsUnknown = descendants.unknown
        } else {
            let remainingAvailable = Self.remainingObservationAvailable(in: observed, target: target, originalKnownGone: finalTokenState == .gone)
                && finalTokenState != .unknown && (finalTokenState != .alive || originalPresent)
            let remaining = observed.processes.filter { $0.identity == target || (originalPresent && $0.parentPID == target.pid) }.map(\.identity)
            if !remainingAvailable { message = localized("SIGTERM sent once; original-target verification is unavailable.") }
            else if finalTokenState == .alive || !remaining.isEmpty { message = localized("Still running after SIGTERM; no retry or force kill.") }
            else { message = remainingPorts.isEmpty ? localized("Previewed server exited; no remaining observed endpoint owner.") : localized("Previewed server exited; an endpoint has a current observed owner.") }
            result = StopResult(targetID: target.id, validation: .unchanged, message: message, signalsSent: 1,
                                remainingIdentities: remainingAvailable ? remaining : [], remainingEndpoints: remainingAvailable ? remainingPorts : [],
                                remainingObservationAvailable: remainingAvailable)
        }
        return result
    }
    /// Exit and exec both invalidate the token; only exec leaves the same PID, user and start time behind.
    /// Read-only lookup at the moment of loss, so an exit after the last sample is not mistaken for exec.
    nonisolated static func goneValidation(_ target: ProcessIdentity) -> TargetValidation {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        errno = 0
        guard proc_pidinfo(target.pid, PROC_PIDTBSDINFO, 0, &info, size) == size else {
            return errno == ESRCH ? .alreadyExited : .stale
        }
        let same = info.pbi_uid == target.uid && UInt64(info.pbi_start_tvsec) == target.startSeconds
            && UInt64(info.pbi_start_tvusec) == target.startMicroseconds
        return same ? .programChanged : .alreadyExited
    }
    /// Descendants are matched by recorded identity, so reparented children are still found.
    nonisolated static func remainingDescendants(_ previewed: [ProcessIdentity], in snapshot: Snapshot) -> (observed: [ProcessIdentity], unknown: Bool) {
        let present = Set(snapshot.processes.map(\.identity))
        let observed = previewed.filter { present.contains($0) }
        let missing = previewed.count - observed.count
        return (observed, missing > 0 && (snapshot.availability != .available || snapshot.inaccessibleCount > 0))
    }
    nonisolated static func stillEligible(_ target: ProcessIdentity, executable: String, in snapshot: Snapshot) -> Bool {
        guard let process = snapshot.processes.first(where: { $0.identity == target }),
              URL(fileURLWithPath: process.executable).resolvingSymlinksInPath().path == executable,
              case .eligible = DeclaredServerEligibility.evaluate(process: process, snapshot: snapshot) else { return false }
        return true
    }
    /// Executable basenames of observed ancestors, outermost first. Display context only.
    nonisolated static func ancestors(of process: ProcessSample, in snapshot: Snapshot) -> [String] {
        var names: [String] = []
        var pid = process.parentPID
        var seen: Set<Int32> = [process.identity.pid]
        while pid > 1, names.count < 8, seen.insert(pid).inserted,
              let parent = snapshot.processes.first(where: { $0.identity.pid == pid }) {
            names.append(URL(fileURLWithPath: parent.executable).lastPathComponent)
            pid = parent.parentPID
        }
        return names.reversed()
    }
    /// Refusal reports only the original incarnation observed in the fresh snapshot.
    nonisolated static func refusal(preview: StopPreview, current: Snapshot, validation: TargetValidation,
                                    reason: String? = nil) -> StopResult {
        let message: String
        switch validation {
        case .stale: message = localized("Preview expired or current validation is unavailable; review a new preview. No signal sent.")
        case .alreadyExited: message = localized("Target already exited; no signal sent.")
        case .programChanged: message = localized("The process switched to another program; no signal sent.")
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
            switch adapter.kind {
            case .reviewedDarkHTTPD: $0.address == "127.0.0.1" && $0.family == "IPv4"
            case .ownedFixture: ["127.0.0.1", "::1"].contains($0.address)
            case .declaredDevelopmentServer: DeclaredServerEligibility.isLoopback($0.address) || DeclaredServerEligibility.isWildcard($0.address)
            }
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
    nonisolated static func matchesRunningCode(_ supplied: audit_token_t, codeDirectoryHash: String) -> Bool {
        guard codeDirectoryHash.count == 40,
              codeDirectoryHash.allSatisfy({ $0.isHexDigit }) else { return false }
        var token = supplied
        let tokenData = withUnsafeBytes(of: &token) { Data($0) }
        let attributes = [kSecGuestAttributeAudit as String: tokenData] as CFDictionary
        var guest: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &guest) == errSecSuccess,
              let guest else { return false }
        var requirement: SecRequirement?
        let expression = "cdhash H\"\(codeDirectoryHash)\"" as CFString
        guard SecRequirementCreateWithString(expression, [], &requirement) == errSecSuccess,
              let requirement else { return false }
        // Dynamic validity binds the requirement to the running guest, not a replaced path's bytes.
        return SecCodeCheckValidity(guest, [], requirement) == errSecSuccess
    }
    /// The running guest's CodeDirectory hash. SecCode.h requires a successful validity check before
    /// signing information can be trusted; any failure leaves the target read-only.
    nonisolated static func runningCodeDirectoryHash(_ supplied: audit_token_t) -> String? {
        var token = supplied
        let tokenData = withUnsafeBytes(of: &token) { Data($0) }
        let attributes = [kSecGuestAttributeAudit as String: tokenData] as CFDictionary
        var guest: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &guest) == errSecSuccess, let guest,
              SecCodeCheckValidity(guest, [], nil) == errSecSuccess else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(unsafeBitCast(guest, to: SecStaticCode.self), [], &information) == errSecSuccess,
              let unique = (information as? [String: Any])?[kSecCodeInfoUnique as String] as? Data, unique.count == 20 else { return nil }
        return unique.map { String(format: "%02x", $0) }.joined()
    }
    nonisolated static func auditToken(pid: Int32) -> audit_token_t? {
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
    enum TokenState { case alive, gone, unknown }
    nonisolated static func tokenState(_ supplied: audit_token_t) -> TokenState {
        var token = supplied
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        errno = 0
        let size = path.withUnsafeMutableBytes { proc_pidpath_audittoken(&token, $0.baseAddress, UInt32($0.count)) }
        if size > 0 { return .alive }
        return errno == ESRCH ? .gone : .unknown
    }
    nonisolated static func tokenPath(_ supplied: audit_token_t) -> String? {
        var token = supplied
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let size = path.withUnsafeMutableBytes { proc_pidpath_audittoken(&token, $0.baseAddress, UInt32($0.count)) }
        return size > 0 ? String(decoding: path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self) : nil
    }
}
