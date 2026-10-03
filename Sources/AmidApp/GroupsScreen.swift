import SwiftUI
import AmidCore

struct GroupsScreen: View {
    @Bindable var model: AppModel
    let projects: Bool
    @State private var search = ""
    private var groups: [ResourceGroup] {
        (projects ? model.projects : model.applications).filter {
            search.isEmpty || model.alias($0.id, fallback: $0.name).localizedCaseInsensitiveContains(search) ||
            $0.processes.contains { $0.name.localizedCaseInsensitiveContains(search) || $0.endpoints.contains { String($0.port).contains(search) } }
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                TextField(projects ? "Search projects or ports" : "Search applications", text: $search)
                    .textFieldStyle(.roundedBorder).accessibilityLabel(projects ? "Search projects or ports" : "Search applications")
                Text("\(groups.count) groups").font(.caption).foregroundStyle(.secondary)
            }
            if groups.isEmpty {
                EmptyState(title: search.isEmpty ? (projects ? "No project roots observed" : "No applications observed") : "No matches", detail: projects ? "Project attribution uses accessible working directories and nearby marker existence. Add a root boundary in Settings to resolve a workspace." : "Accessible processes appear after the first sample. Protected processes remain outside coverage.", symbol: projects ? "folder.badge.questionmark" : "app.dashed")
            } else {
                Table(groups, selection: $model.selectedGroupID) {
                    TableColumn(projects ? "Project" : "Application") { group in
                        HStack(spacing: 8) {
                            Image(systemName: projects ? "folder" : "app").foregroundStyle(.teal)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: model.alias(group.id, fallback: group.name)).fontWeight(.medium)
                                if projects {
                                    let ports = Array(Set(group.processes.flatMap(\.endpoints).map(\.port))).sorted()
                                    if !ports.isEmpty {
                                        Text(verbatim: "TCP " + ports.map(String.init).joined(separator: " · "))
                                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                                    } else {
                                        Text(group.processes.allSatisfy { $0.portAvailability == .available } ? "No observed listeners" : "Listener coverage unavailable")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }.width(min: 150, ideal: 240)
                    TableColumn("CPU · 100% = 1 core") { group in Text(percent(group.cpuPercent)).monospacedDigit() }.width(min: 140, ideal: 150)
                    TableColumn("Memory") { group in Text(bytes(group.memoryBytes)).monospacedDigit() }.width(min: 90, ideal: 110)
                    TableColumn("Processes") { group in Text(String(group.processes.count)) }.width(75)
                    TableColumn("Coverage") { group in Text(group.partial ? "Partial" : "Observed").foregroundStyle(.secondary) }.width(90)
                }.frame(minHeight: 180)
                if let group = groups.first(where: { $0.id == model.selectedGroupID }) {
                    GroupInspector(model: model, group: group, projects: projects).frame(maxHeight: 340)
                } else {
                    Text("Select a row to inspect grouping, measurements and process identities.").font(.callout).foregroundStyle(.secondary)
                }
            }
            Text("Application and project views overlap; do not add their totals. Unknown activity is excluded from observed totals.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(24)
            .onChange(of: model.groupNavigationRevision) { _, _ in search = "" }
    }
}

struct GroupInspector: View {
    @Bindable var model: AppModel
    let group: ResourceGroup
    let projects: Bool
    @State private var aliasText = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeading(title: model.alias(group.id, fallback: group.name), subtitle: localized(group.memoryMethod.rawValue) + " · " + percent(group.cpuPercent.map { $0 / Double(model.snapshot.system.logicalCPUCount) }) + " of total CPU capacity")
                Spacer()
                Button("View history") { model.historyEntity = (projects ? "project:" : "app:") + group.id; model.destination = .history }
            }
            HStack {
                TextField("Custom name", text: $aliasText).textFieldStyle(.roundedBorder).frame(maxWidth: 240)
                Button("Save name") { model.setAlias(group.id, value: aliasText) }.disabled(aliasText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Toggle("Exclude from saved history", isOn: Binding(get: {
                    projects ? model.settings.excludedProjects.contains(group.id) : model.settings.excludedApplications.contains(group.id)
                }, set: { model.exclude(group.id, projects: projects, excluded: $0) }))
            }
            if projects { Text(group.id).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled) }
            GroupHistorySummary(model: model, entityID: (projects ? "project:" : "app:") + group.id)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(group.processes) { process in
                        Button { model.selectedProcess = process } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(process.name).font(.callout.weight(.medium))
                                    Text(process.groupingReason).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Spacer()
                                Text("PID \(process.identity.pid)").font(.caption.monospaced()).foregroundStyle(.secondary)
                                Text(percent(process.cpuPercent)).font(.caption.monospacedDigit()).frame(width: 70, alignment: .trailing)
                                Text(bytes(process.memoryBytes)).font(.caption.monospacedDigit()).frame(width: 90, alignment: .trailing)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }.padding(.vertical, 9).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Divider()
                    }
                }
            }
        }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 10))
            .onAppear { aliasText = model.alias(group.id, fallback: group.name) }
            .onChange(of: group.id) { _, _ in aliasText = model.alias(group.id, fallback: group.name) }
    }
}

/// Keeps retained interval measurements beside the current process breakdown.
struct GroupHistorySummary: View {
    @Bindable var model: AppModel
    let entityID: String
    @State private var recentPoints: [HistoryAggregate] = []
    private var points: [HistoryAggregate] {
        if model.settings.retention == .off { return recentPoints }
        let cutoff = Date().addingTimeInterval(-model.historyHours * 3600)
        return model.aggregates.filter { $0.entityID == entityID && $0.start >= cutoff }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(model.settings.retention == .off ? "Last 15 minutes · memory only" : "Recorded interval").font(.caption.weight(.semibold))
                if model.settings.retention != .off {
                Picker("History range beside process breakdown", selection: $model.historyHours) {
                    Text("1 hour").tag(1.0); Text("24 hours").tag(24.0)
                    Text("7 days").tag(168.0); Text("30 days").tag(720.0)
                }.labelsHidden().frame(width: 150)
                }
                Spacer()
            }
            if points.isEmpty {
                Text("No measurements in this interval. Processes below are current observations.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                let cpu = points.compactMap(\.cpu.maximum).max()
                let memory = points.compactMap(\.memory.maximum).max()
                Text(localizedFormat("Recorded CPU peak: %@ · memory peak: %@ · %ld records", percent(cpu), bytes(memory.map { UInt64(max(0, $0)) }), points.count))
                    .font(.caption.monospacedDigit())
                Text("Missing intervals stay gaps. Processes below are current observations; View history shows this same range with metric methods and coverage.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .task(id: entityID + ":\(model.snapshot.timestamp.timeIntervalSince1970):\(model.settings.retention?.rawValue ?? ""):\(model.memoryHistoryRevision)") {
            let values = await model.recentHistory(for: entityID)
            if !Task.isCancelled { recentPoints = values }
        }
    }
}

struct PortRow: Identifiable {
    let process: ProcessSample
    let endpoint: Endpoint
    var id: String { process.id + endpoint.id }
}
struct PortsScreen: View {
    @Bindable var model: AppModel
    @State private var search = ""
    @State private var selected: String?
    private var rows: [PortRow] {
        model.snapshot.processes.flatMap { process in process.endpoints.map { PortRow(process: process, endpoint: $0) } }
            .filter { search.isEmpty || String($0.endpoint.port).contains(search) || $0.process.name.localizedCaseInsensitiveContains(search) || ($0.process.projectPath.map { model.alias($0, fallback: URL(fileURLWithPath: $0).lastPathComponent).localizedCaseInsensitiveContains(search) } ?? false) }
            .sorted { $0.endpoint.port < $1.endpoint.port }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Search a port, executable or project", text: $search).textFieldStyle(.roundedBorder)
            Notice(title: localized("Listening endpoints only"), detail: localized("Amid reads local socket metadata. It does not connect to services, inspect traffic or infer ownership from a port number."), symbol: "network")
            Text("Socket metadata available for \(model.snapshot.processes.filter { $0.portAvailability == .available }.count) of \(model.snapshot.processes.count) observed processes. Other owners and incomplete reads remain outside coverage.")
                .font(.caption).foregroundStyle(.secondary)
            if rows.isEmpty {
                EmptyState(title: localized("No matching listeners observed"), detail: localized("Inaccessible socket ownership remains unknown. Containers and hidden owners are outside coverage."), symbol: "network.slash")
            } else {
                Table(rows, selection: $selected) {
                    TableColumn("Port") { row in Text(String(row.endpoint.port)).fontWeight(.semibold).monospacedDigit() }.width(65)
                    TableColumn("Listener") { row in Text(row.process.name) }.width(min: 110, ideal: 170)
                    TableColumn("Address") { row in Text(row.endpoint.address).font(.caption.monospaced()) }.width(min: 110, ideal: 140)
                    TableColumn("Family / scope") { row in Text("\(row.endpoint.family) · \(row.endpoint.scope)").font(.caption) }.width(min: 130, ideal: 160)
                    TableColumn("Project") { row in Text(row.process.projectPath.map { model.alias($0, fallback: URL(fileURLWithPath: $0).lastPathComponent) } ?? "Unknown") }.width(min: 100, ideal: 140)
                    TableColumn("Owner") { row in Text("UID \(row.process.identity.uid) · PID \(row.process.identity.pid)").font(.caption.monospaced()) }
                }.frame(minHeight: 180, maxHeight: .infinity)
                if let row = rows.first(where: { $0.id == selected }) {
                    HStack {
                        Text("TCP \(row.endpoint.address):\(row.endpoint.port) · \(row.process.name)").font(.callout)
                        Spacer()
                        Button("Inspect listener") { model.selectedProcess = row.process }.buttonStyle(.borderedProminent)
                    }
                }
            }
            Text("Each listener stays attached to its observed identity. Stop requires a supported server build, current ownership checks and your confirmation. Other listeners remain read-only.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(24)
    }
}

struct ProcessDetail: View {
    @Bindable var model: AppModel
    let process: ProcessSample
    @Environment(\.dismiss) private var dismiss
    @State private var stopPreview: StopPreview?
    @State private var showStopConfirmation = false
    @State private var stopResult: StopResult?
    @State private var actionBusy = false
    @State private var developmentConfirmed = false
    private var live: ProcessSample? { model.snapshot.processes.first { $0.identity == process.identity } }
    // A discovery hint only. The controller validates the exact disk and running build.
    private var canReviewServer: Bool {
        let path = (live ?? process).executable
        return URL(fileURLWithPath: path).lastPathComponent == "AmidFixture" || SupportedServerBuilds.canReview(executablePath: path)
    }
    var body: some View {
        let process = live ?? self.process
        let preview = ActionSafety.preview(process: process, snapshot: model.snapshot)
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "terminal").font(.title).foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 4) {
                    Text(process.name).font(.title2.weight(.semibold))
                    Text(process.runtime ?? "Unrecognized runtime").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    KeyValue(name: localized("Identity"), value: "UID \(process.identity.uid) · PID \(process.identity.pid)")
                    KeyValue(name: localized("Process start"), value: Date(timeIntervalSince1970: Double(process.identity.startSeconds)).formatted())
                    KeyValue(name: localized("Observed since"), value: process.observedSince.formatted())
                    KeyValue(name: localized("CPU · one core = 100%"), value: percent(process.cpuPercent))
                    KeyValue(name: localized("Normalized CPU capacity"), value: percent(process.cpuPercent.map { $0 / Double(model.snapshot.system.logicalCPUCount) }))
                    KeyValue(name: localized(process.memoryMethod.rawValue), value: bytes(process.memoryBytes))
                    KeyValue(name: localized("Executable"), value: process.executable)
                    KeyValue(name: localized("Project"), value: process.projectPath ?? "Unknown / inaccessible")
                    Text("Grouping evidence").font(.headline)
                    Text(process.groupingReason).font(.callout).textSelection(.enabled)
                    Text("Listening endpoints").font(.headline)
                    if process.endpoints.isEmpty { Text("No endpoints observed · \(process.portAvailability.rawValue)").foregroundStyle(.secondary) }
                    ForEach(process.endpoints) { endpoint in
                        Text("TCP \(endpoint.family) \(endpoint.address):\(endpoint.port) · \(endpoint.scope)").font(.callout.monospaced())
                    }
                    if live == nil {
                        Notice(title: localized("No current observation"), detail: localized("This identity is no longer in the latest accessible sample. It may have exited or become inaccessible. Values above are the last captured reading."), symbol: "clock.badge.questionmark")
                    }
                    if let stopResult {
                        Notice(title: localized("Stop result"), detail: stopResultDetail(stopResult))
                    } else if canReviewServer {
                        Notice(title: localized("Server validation required"), detail: localized("Review checks this exact running build, ownership, project association and endpoints. A familiar executable name alone does not enable Stop."))
                    } else { Notice(title: localized("Read-only process"), detail: preview.disabledReason, symbol: "lock") }
                    if canReviewServer, live != nil {
                        Button(actionBusy ? "Validating…" : "Review graceful stop…") {
                            actionBusy = true
                            developmentConfirmed = false
                            Task {
                                let reviewed = await model.previewStop(process)
                                stopPreview = reviewed; actionBusy = false
                                showStopConfirmation = true
                            }
                        }.disabled(actionBusy)
                    }
                    Text("A signal requires a valid target and your confirmation. Active requests can be interrupted; no force-kill fallback is available.").font(.caption).foregroundStyle(.secondary)
                    Button("Open Activity Monitor") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")) }
                }
            }
        }.padding(26).frame(width: 690, height: 680)
            .sheet(isPresented: $showStopConfirmation) {
                if let stopPreview {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Review this server stop").font(.title2.weight(.semibold))
                        Text("Active requests may be interrupted. Only the exact previewed identity receives one SIGTERM. No retry or force kill.")
                        Text(stopPreview.process.name).font(.headline)
                        Text("UID \(stopPreview.process.identity.uid) · PID \(stopPreview.process.identity.pid) · start \(stopPreview.process.identity.startSeconds).\(stopPreview.process.identity.startMicroseconds)").font(.caption.monospaced()).textSelection(.enabled)
                        Text(stopPreview.process.projectPath ?? "Unknown project").font(.caption.monospaced())
                        ForEach(stopPreview.endpoints) { endpoint in Text("TCP \(endpoint.family) \(endpoint.address):\(endpoint.port)") }
                        Text("Validated children: \(stopPreview.descendants.count)")
                        if stopPreview.requiresDevelopmentConfirmation {
                            Text("The project comes from the observed working directory. It does not establish the served directory or whether clients are connected. Active downloads can be interrupted.")
                                .font(.callout).foregroundStyle(.secondary)
                            Text("Supported use: foreground static-file serving, without daemon, chroot, user/group switching, PID-file, syslog or redirect options. Amid does not inspect launch arguments; this declaration is yours.")
                                .font(.caption).foregroundStyle(.secondary)
                            Toggle("This server uses the supported development mode above, and I intend to stop it.", isOn: $developmentConfirmed)
                                .toggleStyle(.checkbox).disabled(actionBusy)
                        }
                        if !stopPreview.canStop { Notice(title: localized("Stop unavailable"), detail: stopPreview.disabledReason) }
                        HStack {
                            Button("Cancel") { Task { _ = await model.confirmStop(stopPreview, confirmed: false); showStopConfirmation = false } }.keyboardShortcut(.cancelAction)
                            Spacer()
                            Button("Confirm graceful stop", role: .destructive) {
                                actionBusy = true
                                let declaration = developmentConfirmed
                                Task {
                                    stopResult = await model.confirmStop(stopPreview, confirmed: true, developmentConfirmed: declaration)
                                    actionBusy = false; showStopConfirmation = false
                                }
                            }.disabled(!stopPreview.canStop || actionBusy || (stopPreview.requiresDevelopmentConfirmation && !developmentConfirmed))
                        }
                        Text("Preview expires after two minutes; an expired or changed target is refused.").font(.caption).foregroundStyle(.secondary)
                    }.padding(26).frame(width: 630)
                }
            }
    }
}
