import SwiftUI
import AmidCore

struct OnboardingScreen: View {
    @Bindable var model: AppModel
    @State private var retention: HistoryRetention = .week
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 16) {
                Image(systemName: "circle.hexagongrid.fill").font(.system(size: 48)).foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 5) {
                    Text("A little clarity for your Mac.").font(.system(size: 28, weight: .semibold, design: .rounded))
                    Text("Welcome to Amid by Made Ordinary.").foregroundStyle(.secondary)
                }
            }
            Text("Amid connects observed processes to applications, accessible projects and listening ports. It works offline, without an account.").font(.body)
            Notice(title: localized("Metadata, with a clear boundary"), detail: localized("Amid reads process identity, executable paths, resource counters, accessible working directories and project-marker existence. It never reads arguments, environment variables, source contents, prompts, credentials or network payloads."), symbol: "hand.raised")
            VStack(alignment: .leading, spacing: 12) {
                Text("Choose your local history").font(.headline)
                Picker("History duration", selection: $retention) {
                    ForEach(HistoryRetention.allCases, id: \.rawValue) { option in Text(option == .week ? "7 days · recommended" : option.title).tag(option) }
                }.pickerStyle(.segmented).labelsHidden().frame(height: 30)
                Text(retention == .off ? "Off keeps a 15-minute memory ring only, cleared on lock or quit. Your preferences and aliases are encrypted locally." : "Only compact aggregates are retained, encrypted with a per-install Keychain key. Change retention or clear history at any time.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Text("Notifications, launch at login and update checks start off. You can choose notifications and launch at login in Settings. This local build makes no update requests.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Text("Nothing is sampled before you continue.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Start observing") { Task { await model.acceptHistory(retention) } }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(32).frame(width: 680).fixedSize(horizontal: false, vertical: true)
    }
}

struct SettingsScreen: View {
    @Bindable var model: AppModel
    @State private var clearConfirm = false
    @State private var showDiagnostics = false
    @State private var boundary = ""
    private func save() { Task { await model.saveSettings() } }
    var body: some View {
        Form {
            Section("History & privacy") {
                Picker("Retain aggregate history", selection: Binding(get: { model.settings.retention ?? .week }, set: { model.settings.retention = $0; save() })) {
                    ForEach(HistoryRetention.allCases, id: \.rawValue) { option in Text(localized(option.title)).tag(option) }
                }
                KeyValue(name: localized("Encrypted storage"), value: bytes(UInt64(model.storageBytes)))
                Toggle("Pause monitoring", isOn: Binding(get: { model.paused }, set: { _ in model.togglePause() }))
                HStack {
                    Button("Clear History…", role: .destructive) { clearConfirm = true }
                    Button("Preview diagnostics…") { showDiagnostics = true }
                }
                Text("Clear removes app-managed measurements, alerts, action records and caches. It preserves preferences and aliases. Exported files, backups and OS crash dumps remain outside this deletion.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Appearance & startup") {
                Picker("Menu bar metric", selection: $model.settings.numericMenuMetric) {
                    Text("Icon only").tag("none"); Text("System CPU").tag("cpu"); Text("Memory pressure").tag("memory")
                }.onChange(of: model.settings.numericMenuMetric) { _, _ in save() }
                Toggle("Launch at login", isOn: Binding(get: { model.settings.launchAtLogin }, set: { enabled in Task { await model.launchAtLogin(enabled) } }))
                Toggle("Deliver macOS notifications", isOn: Binding(get: { model.settings.notificationsEnabled }, set: { enabled in Task { await model.notifications(enabled) } }))
                Text("In-app alerts work without notification permission. Denying permission does not disable monitoring.").font(.caption).foregroundStyle(.secondary)
                LabeledContent("Update checks", value: "Off · no update endpoint in this local build")
                Text("The app makes no update requests. A release updater requires a published domain and field list plus a separate choice before any traffic.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Alert rules") {
                ForEach(AlertCategory.allCases, id: \.rawValue) { category in
                    Toggle(localized(category.title), isOn: Binding(get: { model.settings.alertEnabledRules.contains(category.rawValue) }, set: { enabled in
                        if enabled { model.settings.alertEnabledRules.append(category.rawValue) }
                        else { model.settings.alertEnabledRules.removeAll { $0 == category.rawValue } }; save()
                    })).help(ruleDescription(category))
                }
                Stepper("Startup capacity threshold: \(model.settings.diskThresholdBytes / 1073741824) GiB", value: Binding(get: { Int(model.settings.diskThresholdBytes / 1073741824) }, set: { model.settings.diskThresholdBytes = UInt64($0) * 1073741824; save() }), in: 1...500)
                Text("Published durations, cooldown and recovery rules are listed in Alerts. Disabling a rule stops evaluation; retained events remain until their retention expires or you clear history.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Projects, aliases & exclusions") {
                Text("Rename a group or exclude it from saved history in Applications or Projects. Exclusions do not hide current live readings.").font(.callout).foregroundStyle(.secondary)
                ForEach(model.settings.aliases.keys.sorted(), id: \.self) { key in
                    HStack {
                        Text(model.settings.aliases[key] ?? "").font(.callout)
                        Spacer()
                        Button("Remove alias") { model.settings.aliases.removeValue(forKey: key); save() }
                    }
                }
                ForEach(model.settings.excludedApplications.sorted(), id: \.self) { id in
                    HStack { Text(model.alias(id, fallback: id)).lineLimit(1); Spacer(); Button("Include application") { model.exclude(id, projects: false, excluded: false) } }
                }
                ForEach(model.settings.excludedProjects.sorted(), id: \.self) { id in
                    HStack { Text(model.alias(id, fallback: URL(fileURLWithPath: id).lastPathComponent)).lineLimit(1); Spacer(); Button("Include project") { model.exclude(id, projects: true, excluded: false) } }
                }
                HStack {
                    TextField("Absolute project root boundary", text: $boundary).textFieldStyle(.roundedBorder)
                    Button("Add root") {
                        let url = URL(fileURLWithPath: boundary).standardizedFileURL
                        if boundary.hasPrefix("/") && !model.settings.projectBoundaries.contains(url.path) { model.settings.projectBoundaries.append(url.path); boundary = ""; save() }
                    }.disabled(!boundary.hasPrefix("/") || boundary == "/")
                }
                ForEach(model.settings.projectBoundaries, id: \.self) { path in
                    HStack { Text(path).font(.caption.monospaced()); Spacer(); Button("Remove") { model.settings.projectBoundaries.removeAll { $0 == path }; save() } }
                }
                Text("Root boundaries resolve nested workspace attribution without opening source files. Separate worktree paths remain distinct.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Sampling & units") {
                Text("5 seconds in the background; 2 seconds in detail; 10 seconds on battery or elevated thermal state. Sleep suspends collection. Wake starts fresh counter baselines.")
                Text("System CPU is a share of total logical capacity. Application CPU uses 100% per logical core and can exceed 100%. Physical footprint is preferred; RSS fallback is labeled. Memory pressure drives warnings, not RAM fullness.")
                Text("Local volumes are shown individually; shared APFS capacities are never added. Virtual network interfaces can overlap. GPU, temperatures, per-app I/O and container internals are outside this build's coverage.")
            }.font(.callout)
        }.formStyle(.grouped)
            .sheet(isPresented: $showDiagnostics) { DiagnosticsScreen(model: model) }
            .confirmationDialog("Clear app-managed history?", isPresented: $clearConfirm, titleVisibility: .visible) {
                Button("Clear History", role: .destructive) { Task { await model.clearHistory() } }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Measurements, alerts, action records and in-memory caches will be removed. Preferences and aliases remain. This does not erase exports or backups.") }
    }
}

struct DiagnosticsScreen: View {
    @State private var preview = ""
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Review before exporting").font(.title2.weight(.semibold))
            Text("These are the exact fields in the local JSON export. Aliases may contain names you chose; review them here. Nothing is uploaded.").foregroundStyle(.secondary)
            ScrollView { Text(preview).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                .padding(14).background(.background, in: RoundedRectangle(cornerRadius: 10))
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Choose export location…") { model.exportDiagnostics(preview) }.buttonStyle(.borderedProminent)
            }
        }.padding(26).frame(width: 650, height: 580).onAppear { preview = model.diagnosticPreview }
    }
}
