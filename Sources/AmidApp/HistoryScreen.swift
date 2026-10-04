import SwiftUI
import Charts
import AmidCore

struct HistoryScreen: View {
    @Bindable var model: AppModel
    private var points: [HistoryAggregate] {
        if model.settings.retention == .off { return model.recentHistoryPoints }
        return model.aggregates
    }
    private var entities: [(String, String)] {
        var values = ["system": "System"]
        if model.settings.retention == .off { values.merge(model.recentHistoryNames) { _, new in new } }
        else { values.merge(model.retainedHistoryNames) { _, new in new } }
        // After a privacy clear, retain the selected tag without retaining its former identifying label.
        if values[model.historyEntity] == nil { values[model.historyEntity] = localized("Selected resource") }
        return values.map { ($0.key, $0.value) }.sorted { $0.1 < $1.1 }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Picker("Resource", selection: $model.historyEntity) {
                    ForEach(entities, id: \.0) { item in Text(verbatim: model.historyDisplayName(entityID: item.0, fallback: item.1)).tag(item.0) }
                }.frame(maxWidth: 300)
                Spacer()
                if model.settings.retention == .off {
                    Text("Last 15 minutes · memory only").font(.callout).foregroundStyle(.secondary)
                } else {
                Picker("Range", selection: $model.historyHours) {
                    Text("1 hour").tag(1.0); Text("24 hours").tag(24.0); Text("7 days").tag(168.0); Text("30 days").tag(720.0)
                }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 330).frame(height: 30)
                }
            }
            if model.settings.retention == .off {
                Notice(title: localized("Saved history is off"), detail: localized("Live samples stay in a bounded 15-minute memory ring and are cleared on lock or quit. Choose retention in Settings to begin saving aggregates."))
            }
            if model.shortenedByCap { Notice(title: localized("Storage cap shortened this history"), detail: localized("Amid enforced its 250 MiB cap after retention and rollups. Older aggregates were removed.")) }
            if points.isEmpty && model.historyQueryPending { ProgressView("Loading history…") }
            else if let queryError = model.historyQueryError { Text(verbatim: queryError).foregroundStyle(.secondary) }
            else if points.isEmpty {
                EmptyState(title: model.settings.retention == .off ? localized("No observations in the memory window") : localized("No saved measurements in this range"), detail: localized("History begins after your choice. Sleep, quit and missing samples are gaps; no earlier activity is reconstructed."), symbol: "clock.arrow.circlepath")
            } else {
                SectionHeading(title: localized("CPU over time"), subtitle: model.settings.retention == .off ? localized("Each mark is one observation from the memory window. Missing intervals remain gaps.") : localized("Each mark represents a measured bucket. Height shows its average; whiskers retain the recorded range."))
                Chart(points) { point in
                    if let average = point.cpu.average {
                        RuleMark(x: .value("Time", point.start), yStart: .value("Minimum", point.cpu.minimum ?? average), yEnd: .value("Maximum", point.cpu.maximum ?? average))
                            .foregroundStyle(.teal.opacity(0.4))
                        PointMark(x: .value("Time", point.start), y: .value("CPU percent", average)).foregroundStyle(.teal)
                            .accessibilityLabel(point.start.formatted())
                            .accessibilityValue("CPU average \(percent(average)); coverage \(Int(point.cpuCoverage * 100)) percent")
                    }
                }.chartYAxisLabel(model.historyEntity == "system" ? "% total capacity" : "% · 100 = one core")
                    .frame(height: 180)
                Text(model.settings.retention == .off ? localizedFormat("No line is drawn across gaps. %ld raw observations in memory; cleared on lock or quit.", points.count) : localizedFormat("No line is drawn across gaps. One-minute buckets through 24 hours; hourly buckets after that. %ld retained buckets.", points.count))
                    .font(.caption).foregroundStyle(.secondary)
                Table(points.suffix(250).reversed()) {
                    TableColumn("Time") { p in Text(p.start.formatted(date: .abbreviated, time: .shortened)) }.width(min: 120, ideal: 170)
                    TableColumn("CPU avg / max") { p in Text("\(percent(p.cpu.average)) / \(percent(p.cpu.maximum))").monospacedDigit() }.width(min: 130, ideal: 160)
                    TableColumn("Memory avg / max") { p in Text("\(bytes(p.memory.average.map { UInt64(max(0,$0)) })) / \(bytes(p.memory.maximum.map { UInt64(max(0,$0)) }))").font(.caption.monospacedDigit()) }
                    TableColumn("CPU / memory coverage") { p in Text("\(Int(p.cpuCoverage * 100))% / \(Int(p.memoryCoverage * 100))%\(p.metricCoverageEstimated ? " est." : "")\(p.partial ? " · partial" : "")").font(.caption) }.width(155)
                    TableColumn("Actual cadence") { p in Text(historyCadence(p.cadences)).monospacedDigit() }.width(125)
                    TableColumn("Recorded gap") { p in
                        Text(localizedFormat("%@ s", p.gapSeconds.formatted(.number.precision(.fractionLength(1))))).monospacedDigit()
                            .help("Interrupted time is recorded at the next observation and may span earlier buckets. Empty periods remain gaps.")
                    }.width(125)
                    TableColumn("Memory method") { p in Text(p.entityID == "system" ? "Active pages" : p.memoryMethods.isEmpty ? "Unknown" : p.memoryMethods.map(\.rawValue).sorted().joined(separator: " / ")).font(.caption) }.width(145)
                    TableColumn("Load · 1 / 5 / 15 min") { p in Text([p.load1.average, p.load5.average, p.load15.average].map { $0.map { $0.formatted(.number.precision(.fractionLength(2))) } ?? "—" }.joined(separator: " / ")) }.width(160)
                    TableColumn("Samples") { p in Text(String(p.samples)) }.width(70)
                }.frame(minHeight: 180, maxHeight: .infinity)
            }
        }.padding(24)
    }
}

struct AlertsScreen: View {
    @Bindable var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Notice(title: localized("Evidence, not a diagnosis"), detail: localized("Rules require sustained measurements. Notifications are limited to one per category and entity per hour. Exclude expected build or render workloads in Applications."), symbol: "bell")
                if model.alertEvents.isEmpty {
                    EmptyState(title: localized("No recorded alerts"), detail: localized("Missing or stale measurements do not trigger events. In-app alerts work without notification permission."), symbol: "checkmark.circle")
                }
                ForEach(model.alertEvents) { event in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label(event.title, systemImage: event.recoveredAt == nil ? "exclamationmark.circle" : "checkmark.circle").font(.headline)
                            Spacer()
                            Text(event.observationSuspended ? "Observation interrupted" : event.recoveredAt == nil ? "Active" : "Recovered").font(.caption.weight(.medium))
                            Button("Dismiss") { model.dismissAlert(event) }
                        }
                        Text(event.detail).font(.callout).textSelection(.enabled)
                        Text("Observed \(event.startedAt.formatted()) · Updated \(event.updatedAt.formatted())").font(.caption).foregroundStyle(.secondary)
                    }.padding(18).background(.background, in: RoundedRectangle(cornerRadius: 10))
                }
                SectionHeading(title: localized("Published rules"))
                ForEach(AlertCategory.allCases, id: \.rawValue) { category in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(localized(category.title)).font(.callout.weight(.semibold))
                        Text(ruleDescription(category)).font(.callout).foregroundStyle(.secondary)
                    }.padding(.vertical, 6)
                }
            }.padding(24)
        }
    }
}
func ruleDescription(_ category: AlertCategory) -> String {
    switch category {
    case .memoryPressure: localized("Warning or critical pressure for 60 seconds. Recover after five minutes of normal pressure.")
    case .appCPU: localized("At least 25% of total logical CPU capacity on average for five minutes. Raw CPU uses 100% per logical core.")
    case .appMemoryGrowth: localized("At least 1 GiB and 25% growth over 30 continuously observed minutes using a consistent memory method. This is not a leak diagnosis.")
    case .swapGrowth: localized("At least 1 GiB swap growth over 15 minutes while pressure is warning or critical. Swap alone does not establish trouble.")
    case .diskCapacity: localized("Startup available capacity below your threshold (10 GiB by default) for five minutes.")
    case .lowActivityServer: localized("A recognized native listener observed continuously for two hours, with average CPU below 1% of one core over the last 30 minutes. In-app only; this does not mean unused or safe to stop.")
    }
}
