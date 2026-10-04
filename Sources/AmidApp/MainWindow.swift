import SwiftUI
import AmidCore

struct MainWindow: View {
    @Bindable var model: AppModel
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "circle.hexagongrid.fill").font(.system(size: 26)).foregroundStyle(.teal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Amid").font(.title2.weight(.semibold))
                        Text("BY MADE ORDINARY").font(.system(size: 8, weight: .medium, design: .rounded)).tracking(1.4).foregroundStyle(.secondary)
                    }
                }.padding(.horizontal, 20).padding(.vertical, 24)
                List(Destination.allCases, selection: $model.destination) { item in
                    Label(item.title, systemImage: item.symbol).tag(item).padding(.vertical, 5)
                }.listStyle(.sidebar)
                TimelineView(.periodic(from: .now, by: 5)) { _ in
                  VStack(alignment: .leading, spacing: 7) {
                    Label(model.statusTitle, systemImage: model.paused ? "pause.circle" : "circle.dotted")
                        .font(.caption.weight(.medium))
                    Text("Local. Private. On your Mac.").font(.caption2).foregroundStyle(.secondary)
                  }.padding(20)
                }
            }.navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 250)
        } detail: {
            VStack(spacing: 0) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.destination.title).font(.system(size: 29, weight: .semibold, design: .rounded))
                        Text(model.destination.subtitle).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.isVerification { Text("VERIFICATION").font(.caption2.weight(.semibold)).padding(7).background(.quaternary, in: Capsule()) }
                    Button { model.togglePause() } label: { Image(systemName: model.paused ? "play" : "pause") }
                        .help(model.paused ? "Resume monitoring" : "Pause monitoring")
                        .accessibilityLabel(model.paused ? "Resume monitoring" : "Pause monitoring")
                    Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                        .help("Refresh now").accessibilityLabel("Refresh now")
                }.padding(26)
                Divider()
                if let error = model.error {
                    HStack {
                        Notice(title: localized("Some data is unavailable"), detail: error, symbol: "exclamationmark.triangle")
                        Button("Retry history access") { Task { await model.retryStore() } }
                    }.padding([.horizontal, .top], 20)
                }
                GeometryReader { geometry in
                  Group {
                    switch model.destination {
                    case .overview:
                        if model.shouldSuppressHiddenOverview { Color.clear }
                        else { OverviewScreen(model: model) }
                    case .applications: GroupsScreen(model: model, projects: false)
                    case .projects: GroupsScreen(model: model, projects: true)
                    case .ports: PortsScreen(model: model)
                    case .history: HistoryScreen(model: model)
                    case .alerts: AlertsScreen(model: model)
                    case .settings: SettingsScreen(model: model)
                    }
                  }.frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                }.clipped()
                Divider()
                HStack {
                    Text(model.coverageDescription)
                    Spacer()
                    Text(model.cadenceDescription)
                }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 22).padding(.vertical, 11)
            }.background(Color(nsColor: .windowBackgroundColor))
        }
        .sheet(isPresented: $model.showOnboarding) { OnboardingScreen(model: model).interactiveDismissDisabled() }
        .sheet(item: $model.selectedProcess) { ProcessDetail(model: model, process: $0) }
        .background(WindowVisibilityReader { model.fullWindowVisible = $0 }.frame(width: 0, height: 0))
        .task(id: model.destination) { await model.refreshHistoryPresentation() }
        .task(id: model.selectedGroupID) { await model.refreshHistoryPresentation() }
        .task(id: model.fullWindowVisible) { await model.refreshHistoryPresentation() }
    }
}

struct OverviewScreen: View {
    @Bindable var model: AppModel
    @State private var showSystemDetails = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 12) {
                    MetricCard(title: localized("System CPU"), value: percent(model.overviewPresentation.system.cpuPercent), detail: "Share of \(model.overviewPresentation.system.logicalCPUCount) logical cores", symbol: "cpu")
                    MetricCard(title: localized("Memory pressure"), value: model.overviewPresentation.system.memory.pressure.rawValue.capitalized, detail: "Swap used · \(bytes(model.overviewPresentation.system.memory.swapUsed))", symbol: "memorychip")
                    MetricCard(title: localized("Startup disk available"), value: bytes(model.overviewPresentation.system.volumes.first(where: \.isStartup)?.available), detail: localized("OS-reported available capacity"), symbol: "internaldrive")
                }
                if model.overviewPresentation.availability != .available {
                    Notice(title: model.overviewStatusTitle, detail: localized("Measurements resume when monitoring is available. Missing readings are never shown as zero."))
                }
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeading(title: localized("Largest observed applications"), subtitle: localized("Memory accounting may differ between processes."))
                        ForEach(model.overviewPresentation.applications) { group in
                            Button {
                                model.openGroup(group.id, projects: false)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "app.fill").font(.title3).foregroundStyle(.teal)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(model.alias(group.id, fallback: group.name)).font(.callout.weight(.medium))
                                        Text("\(group.processCount) processes · \(group.memoryMethod.rawValue)").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text(bytes(group.memoryBytes)).font(.callout.monospacedDigit())
                                        Text("\(percent(group.cpuPercent)) CPU").font(.caption).foregroundStyle(.secondary)
                                    }
                                }.padding(.vertical, 9).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Divider()
                        }
                        if model.overviewPresentation.applications.isEmpty { EmptyState(title: localized("Awaiting applications"), detail: localized("Accessible processes will appear after sampling."), symbol: "app.dashed") }
                    }.frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeading(title: localized("Projects & ports"), subtitle: localized("Connections made from observed metadata."))
                        ForEach(model.overviewPresentation.projects) { project in
                            Button {
                                model.openGroup(project.id, projects: true)
                            } label: {
                                HStack {
                                    Image(systemName: "folder").foregroundStyle(.teal)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(model.alias(project.id, fallback: project.name)).font(.callout.weight(.medium))
                                        Text(project.ports.isEmpty ? "No observed listeners" : "TCP " + project.ports)
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(bytes(project.memoryBytes)).font(.caption.monospacedDigit())
                                }.padding(13).background(.background, in: RoundedRectangle(cornerRadius: 9))
                            }.buttonStyle(.plain)
                        }
                        if model.overviewPresentation.projects.isEmpty { Text("No project roots observed. Hidden or inaccessible working directories remain unattributed.").foregroundStyle(.secondary).font(.callout) }
                    }.frame(maxWidth: .infinity)
                }
                DisclosureGroup("System details", isExpanded: $showSystemDetails) {
                    VStack(alignment: .leading, spacing: 18) {
                        KeyValue(name: localized("Physical memory"), value: bytes(model.overviewPresentation.system.memory.physical))
                        KeyValue(name: localized("Compressed memory"), value: bytes(model.overviewPresentation.system.memory.compressed))
                        KeyValue(name: localized("Thermal state"), value: model.overviewPresentation.system.thermalState)
                        KeyValue(name: localized("Load · 1 / 5 / 15 min"), value: model.overviewPresentation.system.loadAverage.map { $0.formatted(.number.precision(.fractionLength(2))) }.joined(separator: " / "))
                        if let battery = model.overviewPresentation.system.battery {
                            KeyValue(name: localized("Battery"), value: "\(percent(battery.percent)) · \(battery.isCharging ? "Charging" : battery.onBattery ? "On battery" : "External power")")
                            KeyValue(name: localized("Battery health"), value: battery.condition)
                        }
                        SectionHeading(title: localized("Physical memory categories"), subtitle: localized("OS page categories can overlap with process accounting; these are not per-app totals."))
                        HStack(spacing: 22) {
                            VStack(spacing: 10) {
                                KeyValue(name: localized("Active"), value: bytes(model.overviewPresentation.system.memory.active))
                                KeyValue(name: localized("Inactive"), value: bytes(model.overviewPresentation.system.memory.inactive))
                            }
                            VStack(spacing: 10) {
                                KeyValue(name: localized("Wired"), value: bytes(model.overviewPresentation.system.memory.wired))
                                KeyValue(name: localized("Free"), value: bytes(model.overviewPresentation.system.memory.free))
                            }
                        }
                        SectionHeading(title: localized("Local volumes"), subtitle: localized("APFS volumes may share container capacity. These capacities are never summed."))
                        if let message = collectionStatusMessage(model.overviewPresentation.system.volumeCollectionStatus, empty: model.overviewPresentation.system.volumes.isEmpty, volumes: true) { Text(message).foregroundStyle(.secondary) }
                        ForEach(model.overviewPresentation.system.volumes) { volume in
                            HStack {
                                Label(volume.name, systemImage: "internaldrive")
                                Spacer()
                                Text("\(bytes(volume.available)) available of \(bytes(volume.capacity))").monospacedDigit()
                            }.font(.callout).accessibilityElement(children: .combine)
                        }
                        SectionHeading(title: localized("Network interfaces"), subtitle: localized("Interface byte deltas only. Virtual interfaces may overlap; these rates are not added together."))
                        if let message = collectionStatusMessage(model.overviewPresentation.system.interfaceCollectionStatus, empty: model.overviewPresentation.system.interfaces.isEmpty, volumes: false) { Text(message).foregroundStyle(.secondary) }
                        ForEach(model.overviewPresentation.system.interfaces, id: \.id) { interface in
                            HStack {
                                Text(interface.id).font(.callout.monospaced())
                                if interface.isVirtual { Text("Virtual / may overlap").font(.caption).foregroundStyle(.secondary) }
                                Spacer()
                                Text("↓ \(throughput(interface.receivedBytesPerSecond))    ↑ \(throughput(interface.sentBytesPerSecond))").font(.callout.monospacedDigit())
                            }.accessibilityElement(children: .combine)
                        }
                    }.padding(.top, 12)
                }.font(.callout)
                Notice(title: localized("Coverage has a boundary"), detail: localized("Application and project totals are alternate views of the same observed processes. Shared memory and inaccessible processes mean their totals need not equal system memory. CPU is 100% per logical core; load is a separate count of runnable work."))
            }.padding(26)
        }
    }
}
