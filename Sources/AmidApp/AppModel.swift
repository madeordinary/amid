import SwiftUI
import AppKit
import Observation
import AmidCore
import UserNotifications
import ServiceManagement

@MainActor @Observable
final class AppModel {
    var destination: Destination = .overview
    var snapshot = Snapshot.empty {
        didSet {
            let attention = snapshot.availability == .available && [.warning, .critical].contains(snapshot.system.memory.pressure)
            if pressureAttention != attention { pressureAttention = attention }
        }
    }
    var settings = HistorySettings() { didSet { settingsRevision += 1 } }
    var aggregates: [HistoryAggregate] = []
    var recentHistoryPoints: [HistoryAggregate] = []
    var recentHistoryNames: [String: String] = ["system": "System"]
    var memoryHistoryRevision = 0
    var alertEvents: [AlertEvent] = []
    var storageBytes = 0
    var shortenedByCap = false
    var error: String?
    var showOnboarding = false
    var selectedGroupID: String?
    var selectedProcess: ProcessSample?
    var historyEntity = "system"
    var historyHours = 24.0
    let benchmarkPresentationMode = GUIBenchmarkEvidence.presentationMode(arguments: CommandLine.arguments)
    var shouldSuppressHiddenOverview: Bool {
        benchmarkPresentationMode.suppressesOverview(windowVisible: fullWindowVisible, isOverview: destination == .overview)
    }
    private(set) var overviewPresentation = OverviewPresentation()
    private var overviewSourceCleared = false
    var fullWindowVisible = false {
        didSet { if fullWindowVisible && !oldValue { updateOverviewPresentation() } }
    }
    func updateOverviewPresentation(now: Date = Date()) {
        guard fullWindowVisible else { return }
        guard !overviewSourceCleared, !locked, !sleeping, !clearingHistory, now.timeIntervalSince(snapshot.timestamp) <= 900 else {
            overviewPresentation = OverviewPresentation(); return
        }
        overviewPresentation = OverviewPresentation(snapshot: snapshot, applications: applications, projects: projects)
    }
    func expireOverviewPresentation(now: Date = Date()) {
        if let timestamp = overviewPresentation.timestamp, now.timeIntervalSince(timestamp) > 900 {
            overviewPresentation = OverviewPresentation()
        }
    }
    var overviewStatusTitle: String {
        if settings.retention == nil { return localized("Awaiting your choice") }
        if locked { return localized("Session locked") }
        if sleeping { return localized("Sleeping") }
        if paused { return localized("Monitoring paused") }
        let system = overviewPresentation.system
        let presentedCadence = SamplingPolicy.cadence(detailVisible: detailVisible, onBattery: system.battery?.onBattery == true, thermal: system.thermalState)
        if let timestamp = overviewPresentation.timestamp, Date().timeIntervalSince(timestamp) > max(30, presentedCadence * 3) { return localized("Sample stale") }
        return overviewPresentation.availability == .available ? localized("Monitoring locally") : localized("Measurements unavailable")
    }
    var detailVisible: Bool { fullWindowVisible && (destination != .overview || selectedProcess != nil) }
    private var sessionInactive = false
    private var screenLocked = false
    private var generation = 0
    private var settingsRevision = 0
    private var savingSettings = false
    private var clearingHistory = false
    var sleeping = false
    var locked: Bool { sessionInactive || screenLocked }
    var busy = false
    let isVerification = CommandLine.arguments.contains("--verification") || CommandLine.arguments.contains("--performance-verification")
    private let verificationOwnedServer = AppModel.verificationOwnedServerPath(arguments: CommandLine.arguments)
    nonisolated static func verificationOwnedServerPath(arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: "--verification-owned-server"), arguments.indices.contains(index + 1) else { return nil }
        return URL(fileURLWithPath: arguments[index + 1]).resolvingSymlinksInPath().path
    }
    nonisolated static func matchesVerificationOwnedServer(executable: String, expected: String?) -> Bool {
        guard let expected else { return false }
        return URL(fileURLWithPath: executable).resolvingSymlinksInPath().path
            == URL(fileURLWithPath: expected).resolvingSymlinksInPath().path
    }
    var verificationColorScheme: ColorScheme? { isVerification && CommandLine.arguments.contains("--light-appearance") ? .light : nil }
    private let isPerformanceVerification = CommandLine.arguments.contains("--performance-verification")
    private var benchmarkTask: Task<Void, Never>?
    private var benchmarkSession: GUIBenchmarkSession?
    private var pipelineProfile: AppPipelineProfile?
    private let sampler = Sampler()
    private let alerts = AlertEngine()
    private let actions = ActionController(adapters: bundledFixtureAdapters())
    private var store: HistoryStore?
    private var started = false
    private var loop: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var dismissedAlertIDs: Set<UUID> = []
    private var lastRefresh: Date?
    init(store: HistoryStore? = nil) { self.store = store }
    var paused: Bool { settings.paused }
    private(set) var applications: [ResourceGroup] = []
    private(set) var projects: [ResourceGroup] = []
    private(set) var pressureAttention = false
    var statusTitle: String {
        if settings.retention == nil { return localized("Awaiting your choice") }
        if locked { return localized("Session locked") }
        if sleeping { return localized("Sleeping") }
        if paused { return localized("Monitoring paused") }
        if let lastRefresh, Date().timeIntervalSince(lastRefresh) > max(30, cadence * 3) { return localized("Sample stale") }
        if snapshot.availability == .available { return localized("Monitoring locally") }
        return localized("Measurements unavailable")
    }
    var cadence: Double {
        SamplingPolicy.cadence(detailVisible: detailVisible, onBattery: snapshot.system.battery?.onBattery == true, thermal: snapshot.system.thermalState)
    }
    var menuTitle: String {
        switch settings.numericMenuMetric {
        case "cpu": percent(snapshot.system.cpuPercent)
        case "memory": snapshot.system.memory.pressure.rawValue.capitalized
        default: ""
        }
    }
    var coverageDescription: String { localizedFormat("%ld observed · %ld inaccessible · %ld enumerated", snapshot.processes.count, snapshot.inaccessibleCount, snapshot.enumeratedCount) }
    var cadenceDescription: String {
        guard let lastRefresh else { return localized("No sample yet") }
        return localizedFormat("%@s actual cadence · %@", snapshot.cadence.formatted(.number.precision(.fractionLength(1))), lastRefresh.formatted(date: .omitted, time: .standard))
    }
    func alias(_ id: String, fallback: String) -> String { settings.aliases[id] ?? fallback }
    func start() async {
        guard !started else { return }; started = true
        let directory: URL
        if isVerification {
            directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("amid-ui-verification-\(ProcessInfo.processInfo.processIdentifier)")
            store = HistoryStore(directory: directory, keyProvider: EphemeralHistoryKeyProvider())
        } else {
            directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Amid", isDirectory: true)
            store = HistoryStore(directory: directory)
        }
        let loadingRevision = settingsRevision
        await store?.load()
        await syncStore(importSettingsAt: loadingRevision)
        showOnboarding = settings.retention == nil
        await configureAlerts()
        await alerts.restore(events: alertEvents)
        installLifecycleObservers()
        if isPerformanceVerification,
           let index = CommandLine.arguments.firstIndex(of: "--benchmark-retention"),
           CommandLine.arguments.indices.contains(index + 1),
           let choice = HistoryRetention(rawValue: CommandLine.arguments[index + 1]) {
            // Explicit test-run choice; never inferred for a normal launch.
            await acceptHistory(choice)
        }
        if settings.retention != nil { startRequestedBenchmark() }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                await self.refresh()
                let wait = self.cadence
                do { try await Task.sleep(for: .seconds(wait)) } catch { break }
            }
        }
    }
    func refresh() async {
        let expiryToken = pipelineProfile?.begin(.expiry)
        await expireMemoryHistory()
        await actions.expirePreviews()
        pipelineProfile?.end(expiryToken)
        guard settings.retention != nil, !paused, !sleeping, !locked, !busy, !clearingHistory else { return }
        let activeGeneration = generation
        busy = true
        defer { busy = false }
        let requestedCadence = cadence
        let collectionToken = pipelineProfile?.begin(.collection)
        var collected: Snapshot
        if pipelineProfile?.isMeasuring == true {
            let result = await sampler.profiledSample(cadence: requestedCadence, projectBoundaries: settings.projectBoundaries)
            collected = result.snapshot
            pipelineProfile?.recordCollectionThread(result.measurement)
            pipelineProfile?.recordSamplerBreakdown(result.breakdown)
        } else { collected = await sampler.sample(cadence: requestedCadence, projectBoundaries: settings.projectBoundaries) }
        pipelineProfile?.end(collectionToken)
        guard activeGeneration == generation, !sleeping, !locked, !paused else { await sampler.resetBaselines(); return }
        collected.expectedCadence = requestedCadence
        if let lastRefresh { collected.cadence = collected.timestamp.timeIntervalSince(lastRefresh) }
        if isVerification && !isPerformanceVerification {
            collected.processes = collected.processes.filter {
                $0.identity.pid == ProcessInfo.processInfo.processIdentifier || ["Amid", "AmidFixture", "amid-probe"].contains($0.name)
                    || Self.matchesVerificationOwnedServer(executable: $0.executable, expected: verificationOwnedServer)
            }
            collected.enumeratedCount = collected.processes.count; collected.inaccessibleCount = 0
            collected.notes.append("Verification display filters process metadata to Amid executables and an explicitly named owned test server.")
        }
        let acceptedSnapshot = collected
        let groupingToken = pipelineProfile?.begin(.grouping)
        let groups = await Task.detached(priority: .utility) {
            (ResourceGroup.applications(acceptedSnapshot), ResourceGroup.projects(acceptedSnapshot))
        }.value
        pipelineProfile?.end(groupingToken)
        guard activeGeneration == generation, !sleeping, !locked, !paused else { return }
        let publicationToken = pipelineProfile?.begin(.publication)
        snapshot = collected
        applications = groups.0; projects = groups.1
        lastRefresh = collected.timestamp
        overviewSourceCleared = false
        updateOverviewPresentation()
        pipelineProfile?.end(publicationToken)
        let ingestToken = pipelineProfile?.begin(.historyIngest)
        if pipelineProfile?.isMeasuring == true {
            if let threadReport = await store?.profiledIngest(collected) { pipelineProfile?.recordIngestionThread(threadReport) }
        } else { await store?.ingest(collected) }
        pipelineProfile?.end(ingestToken)
        guard activeGeneration == generation, !sleeping, !locked, !paused else { return }
        let alertsToken = pipelineProfile?.begin(.alerts)
        let events = await alerts.evaluate(collected)
        pipelineProfile?.end(alertsToken)
        guard activeGeneration == generation, !sleeping, !locked, !paused else { return }
        let recordToken = pipelineProfile?.begin(.alertRecord)
        await store?.recordAlerts(events)
        pipelineProfile?.end(recordToken)
        let syncToken = pipelineProfile?.begin(.storeSync)
        await syncStore()
        pipelineProfile?.end(syncToken)
        guard activeGeneration == generation, !sleeping, !locked, !paused else { return }
        benchmarkSession?.observe(available: collected.availability == .available && error == nil,
                                  cadence: requestedCadence, processCount: collected.processes.count)
        let notificationToken = pipelineProfile?.begin(.notifications)
        await deliverNotifications(events, generation: activeGeneration) { [weak self] event in await self?.deliver(event) }
        pipelineProfile?.end(notificationToken)
    }
    func deliverNotifications(_ events: [AlertEvent], generation activeGeneration: Int, delivery: (AlertEvent) async -> Void) async {
        for event in events where event.notificationEligible && event.category != .lowActivityServer {
            guard activeGeneration == generation, settings.notificationsEnabled, !sleeping, !locked, !paused else { break }
            guard settings.alertEnabledRules.contains(event.category.rawValue) else { continue }
            if [.appCPU, .appMemoryGrowth].contains(event.category), settings.excludedApplications.contains(event.entityID) { continue }
            await delivery(event)
        }
    }
    func acceptHistory(_ retention: HistoryRetention) async {
        settings.retention = retention
        await saveSettings()
        showOnboarding = false
        await refresh()
        startRequestedBenchmark()
    }
    private func startRequestedBenchmark() {
        let args = CommandLine.arguments
        guard isPerformanceVerification, benchmarkTask == nil,
              let i = args.firstIndex(of: "--benchmark"), args.indices.contains(i + 1),
              let seconds = Double(args[i + 1]), seconds.isFinite, seconds >= 30,
              let p = args.firstIndex(of: "--benchmark-output"), args.indices.contains(p + 1) else { return }
        let output = URL(fileURLWithPath: args[p + 1])
        let session = GUIBenchmarkSession(seconds: seconds, output: output, retention: settings.retention?.rawValue ?? "unknown", presentationMode: benchmarkPresentationMode)
        benchmarkSession = session
        let profileOutputInvalid: Bool
        switch AppPipelineProfile.outputChoice(arguments:args,benchmarkOutput:output) {
        case .disabled: profileOutputInvalid = false
        case .configured(let profileOutput):
            pipelineProfile = AppPipelineProfile(output:profileOutput); profileOutputInvalid = false
        case .invalid:
            profileOutputInvalid = true
            FileHandle.standardError.write(Data("Pipeline profile disabled: requires an absolute output path distinct from benchmark report and status.\n".utf8))
        }
        benchmarkTask = Task {
            do {
                try await Task.sleep(for: .seconds(30))
                if args.contains("--benchmark-hidden") { NSApplication.shared.hide(nil) }
                session.begin(active: !paused && !sleeping && !locked && !clearingHistory && error == nil && store != nil)
                guard session.evidence.phase == .measuring else { session.finish(active: false); return }
                pipelineProfile?.start()
                try await Task.sleep(for: .seconds(seconds))
                session.finish(active: !paused && !sleeping && !locked && !clearingHistory && error == nil && store != nil)
            } catch { session.invalidate("The benchmark was cancelled before completion."); session.finish(active: false) }
            pipelineProfile?.finish(benchmarkPhase:session.evidence.phase.rawValue)
            if session.writeFailed || pipelineProfile?.writeFailed == true || profileOutputInvalid { self.error = localized("The requested local performance report could not be completed.") }
        }
    }
    func saveSettings() async {
        benchmarkSession?.invalidate("Settings changed during the run.")
        guard !savingSettings else { return }
        savingSettings = true
        defer { savingSettings = false }
        repeat {
            let revision = settingsRevision
            let requested = settings
            await store?.updateSettings(requested)
            await syncStore()
            await configureAlerts()
            if revision == settingsRevision { break }
        } while true
    }
    private func configureAlerts() async {
        await alerts.updateSettings(AlertSettings(enabledRules: Set(settings.alertEnabledRules.compactMap(AlertCategory.init(rawValue:))), excludedApplications: settings.excludedApplications, diskThresholdBytes: settings.diskThresholdBytes))
    }
    private func syncStore(importSettingsAt revision: Int? = nil) async {
        guard !clearingHistory else { return }
        let activeGeneration = generation
        guard let state = await store?.state() else { return }
        guard activeGeneration == generation, !clearingHistory else { return }
        if let revision, settingsRevision == revision { settings = state.settings }
        if fullWindowVisible && (destination == .history || selectedGroupID != nil) {
            aggregates = state.aggregates
        } else { aggregates = [] }
        alertEvents = state.alerts.filter { $0.dismissedAt == nil && !dismissedAlertIDs.contains($0.id) }.sorted { $0.updatedAt > $1.updatedAt }
        storageBytes = state.storageBytes; shortenedByCap = state.shortenedByCap; error = state.error.map { localized($0) }
        let entity = historyEntity
        if settings.retention == .off && fullWindowVisible && destination == .history && !locked && !sleeping {
            let names = await store?.recentHistoryEntities() ?? [:]
            guard activeGeneration == generation, !clearingHistory else { return }
            if entity != "system" && names[entity] == nil {
                historyEntity = "system"; recentHistoryPoints = []; recentHistoryNames = names
                return
            }
            let points = await recentHistory(for: entity)
            guard activeGeneration == generation, historyEntity == entity, settings.retention == .off,
                  fullWindowVisible, destination == .history, !locked, !sleeping else { return }
            recentHistoryNames = names; recentHistoryPoints = points
        } else { recentHistoryPoints = []; recentHistoryNames = ["system": "System"] }
    }
    func refreshHistoryPresentation() async { await syncStore() }
    func expireMemoryHistory(now: Date = Date()) async {
        expireOverviewPresentation(now: now)
        guard await store?.expireRecent(now: now) == true else { return }
        memoryHistoryRevision += 1
        if settings.retention == .off && now.timeIntervalSince(snapshot.timestamp) > 900 {
            snapshot = .empty; snapshot.availability = .stale
            applications = []; projects = []
            selectedProcess = nil; selectedGroupID = nil; historyEntity = "system"
        }
        await syncStore()
    }
    func recentHistory(for entity: String) async -> [HistoryAggregate] {
        let activeGeneration = generation
        guard settings.retention == .off, !locked, !sleeping, !clearingHistory else { return [] }
        let points = await store?.recentHistory(entityID: entity) ?? []
        guard activeGeneration == generation, settings.retention == .off, !locked, !sleeping, !clearingHistory else { return [] }
        return points
    }
    func togglePause() {
        benchmarkSession?.invalidate("Monitoring pause changed during the run.")
        generation += 1
        settings.paused.toggle()
        Task {
            await sampler.resetBaselines(); lastRefresh = nil
            await actions.resetObservation()
            await store?.suspendObservation()
            await alerts.suspendObservation()
            await saveSettings()
            if !paused { await refresh() }
        }
    }
    func setAlias(_ id: String, value: String) {
        let name = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        if name.isEmpty { settings.aliases.removeValue(forKey: id) } else { settings.aliases[id] = name }
        Task { await saveSettings() }
    }
    func exclude(_ id: String, projects: Bool, excluded: Bool) {
        if projects { if excluded { settings.excludedProjects.insert(id) } else { settings.excludedProjects.remove(id) } }
        else { if excluded { settings.excludedApplications.insert(id) } else { settings.excludedApplications.remove(id) } }
        Task { await saveSettings() }
    }
    func clearHistory() async {
        benchmarkSession?.invalidate("History was cleared during the run.")
        generation += 1
        clearingHistory = true
        overviewSourceCleared = true
        overviewPresentation = OverviewPresentation()
        snapshot = .empty
        applications = []; projects = []
        recentHistoryPoints = []; recentHistoryNames = ["system": "System"]
        selectedProcess = nil; selectedGroupID = nil
        historyEntity = "system"
        await sampler.resetBaselines(); lastRefresh = nil
        await actions.resetObservation()
        await store?.clear(); await alerts.reset(); dismissedAlertIDs.removeAll()
        clearingHistory = false
        await syncStore()
    }
    func retryStore() async {
        let loadingRevision = settingsRevision
        await store?.load()
        await syncStore(importSettingsAt: loadingRevision)
        await configureAlerts()
        await alerts.restore(events: alertEvents)
    }
    func dismissAlert(_ event: AlertEvent) {
        dismissedAlertIDs.insert(event.id); alertEvents.removeAll { $0.id == event.id }
        Task { if let dismissed = await alerts.dismiss(event.id) { await store?.recordAlerts([dismissed]) }; await syncStore() }
    }
    func previewStop(_ process: ProcessSample) async -> StopPreview {
        let activeGeneration = generation
        await refresh()
        guard activeGeneration == generation, !paused, !sleeping, !locked, !clearingHistory else {
            return .unavailable(process: process, reason: localized("Monitoring is suspended; review after resuming."))
        }
        return await actions.preview(process: snapshot.processes.first { $0.identity == process.identity } ?? process, snapshot: snapshot)
    }
    func confirmStop(_ preview: StopPreview, confirmed: Bool, developmentConfirmed: Bool = false) async -> StopResult {
        await finishStop(preview, confirmed: confirmed) {
            await actions.confirm(preview: preview, confirmed: confirmed, developmentConfirmed: developmentConfirmed)
        }
    }
    func finishStop(_ preview: StopPreview, confirmed: Bool, operation: () async -> StopResult) async -> StopResult {
        let activeGeneration = generation
        guard !paused, !sleeping, !locked, !clearingHistory else {
            let refused = StopPreview.unavailable(process: preview.process, reason: localized("Monitoring is suspended; review after resuming."))
            return ActionSafety.confirm(preview: refused, current: .empty, confirmed: confirmed)
        }
        let result = await operation()
        guard activeGeneration == generation, !paused, !sleeping, !locked, !clearingHistory else { return result }
        if confirmed {
            await store?.recordAction(ActionRecord(operation: "gracefulStop", result: result.message, targetID: result.targetID))
            await refresh()
        }
        return result
    }
    func notifications(_ enabled: Bool) async {
        if enabled {
            do {
                let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                settings.notificationsEnabled = allowed
                await saveSettings()
                if !allowed { error = localized("Notifications were not allowed. In-app alerts remain available.") }
            } catch { self.error = localized("Notification permission is unavailable. In-app alerts remain available.") }
        } else { settings.notificationsEnabled = false; await saveSettings() }
    }
    func launchAtLogin(_ enabled: Bool) async {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try await SMAppService.mainApp.unregister() }
            settings.launchAtLogin = enabled; await saveSettings()
        } catch { self.error = localized("Launch at login could not be changed. Review Login Items in System Settings.") }
    }
    private func deliver(_ event: AlertEvent) async {
        let content = UNMutableNotificationContent()
        content.title = "Amid · " + event.title
        content.body = event.detail
        do { try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: event.id.uuidString, content: content, trigger: nil)) }
        catch { self.error = localized("Notification delivery failed. The event remains in Alerts.") }
    }
    private func installLifecycleObservers() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in await self?.setSuspension("sleep", enabled: true) } })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in await self?.setSuspension("sleep", enabled: false) } })
        observers.append(center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in await self?.setSuspension("session", enabled: true) } })
        observers.append(center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in await self?.setSuspension("session", enabled: false) } })
        observers.append(DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in Task { @MainActor in await self?.setSuspension("screen", enabled: true) } })
        observers.append(DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in Task { @MainActor in await self?.setSuspension("screen", enabled: false) } })
    }
    func setSuspension(_ reason: String, enabled: Bool) async {
        if enabled { benchmarkSession?.invalidate("Monitoring suspended: " + reason) }
        generation += 1
        switch reason {
        case "sleep": sleeping = enabled
        case "screen": screenLocked = enabled
        default: sessionInactive = enabled
        }
        if sleeping || locked { overviewSourceCleared = true; overviewPresentation = OverviewPresentation() }
        await sampler.resetBaselines(); lastRefresh = nil
        await actions.resetObservation()
        if sleeping || locked {
            await store?.clearMemory()
            if settings.retention == .off { await alerts.reset() }
            else { await alerts.suspendObservation() }
            snapshot = .empty; snapshot.availability = sleeping ? .sleeping : .unavailable
            applications = []; projects = []
            recentHistoryPoints = []; recentHistoryNames = ["system": "System"]
            selectedProcess = nil; selectedGroupID = nil
            historyEntity = "system"
            await syncStore()
        } else { await refresh() }
    }
    func prepareToQuit() async {
        overviewSourceCleared = true
        overviewPresentation = OverviewPresentation()
        benchmarkSession?.invalidate("The application quit before benchmark completion.")
        benchmarkSession?.finish(active: false)
        if let phase = benchmarkSession?.evidence.phase { pipelineProfile?.finish(benchmarkPhase:phase.rawValue) }
        generation += 1; loop?.cancel(); benchmarkTask?.cancel()
        selectedProcess = nil; selectedGroupID = nil
        historyEntity = "system"
        await actions.resetObservation()
        await store?.flush(); await store?.clearMemory(); await alerts.reset()
    }
    var diagnosticPreview: String {
        Diagnostics.preview(snapshot: snapshot, settings: settings, storageBytes: storageBytes, alerts: alertEvents)
    }
    func exportDiagnostics(_ preview: String) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Amid-diagnostics.json"; panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try preview.write(to: url, atomically: true, encoding: .utf8) }
        catch { self.error = localized("Diagnostics could not be saved at the selected location.") }
    }
}

/// Only this app's packaged, known server is enrolled. No user executable allowlist.
private func bundledFixtureAdapters() -> [TrustedServerAdapter] {
    guard let root = Bundle.main.resourceURL?.appendingPathComponent("DevelopmentFixture"),
          let sha = try? String(contentsOf: root.appendingPathComponent("sha256.txt"), encoding: .utf8),
          let cdhash = try? String(contentsOf: root.appendingPathComponent("cdhash.txt"), encoding: .utf8) else { return [] }
    return [TrustedServerAdapter(ownedFixtureExecutable: root.appendingPathComponent("AmidFixture").path, projectRoot: root.path,
                                 expectedSHA256: sha.trimmingCharacters(in: .whitespacesAndNewlines),
                                 expectedCodeDirectoryHash: cdhash.trimmingCharacters(in: .whitespacesAndNewlines))]
}
