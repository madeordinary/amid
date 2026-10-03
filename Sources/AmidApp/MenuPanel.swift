import SwiftUI
import AppKit
import AmidCore

struct MenuPanel: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Amid", systemImage: "circle.hexagongrid.fill").font(.headline).foregroundStyle(.teal)
                Spacer()
                Text(verbatim: model.statusTitle).font(.caption).foregroundStyle(.secondary)
            }
            if model.settings.retention == nil {
                Text("Choose your local history preference to begin.").font(.callout)
            } else {
                KeyValue(name: localized("System CPU"), value: percent(model.snapshot.system.cpuPercent))
                KeyValue(name: localized("Memory pressure"), value: localized(model.snapshot.system.memory.pressure.rawValue.capitalized))
                KeyValue(name: localized("Swap"), value: bytes(model.snapshot.system.memory.swapUsed))
                KeyValue(name: localized("Startup available"), value: bytes(model.snapshot.system.volumes.first(where: \.isStartup)?.available))
                Divider()
                Text("TOP OBSERVED MEMORY").font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
                ForEach(model.applications.prefix(3)) { group in
                    Button {
                        model.openGroup(group.id, projects: false)
                        openWindow(id: "main")
                        NSApplication.shared.activate(ignoringOtherApps: true)
                        dismiss()
                    } label: {
                        HStack {
                            Text(verbatim: model.alias(group.id, fallback: group.name)).lineLimit(1)
                            Spacer()
                            Text(verbatim: bytes(group.memoryBytes)).monospacedDigit()
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary).accessibilityHidden(true)
                        }.font(.callout).padding(.vertical, 4).contentShape(Rectangle())
                    }.buttonStyle(.plain).help("Open application details")
                        .accessibilityHint("Open application details")
                }
                Divider()
                Text(verbatim: localizedFormat("%@ · %@ · %@",
                    localizedFormat("%ld projects", model.projects.count),
                    localizedFormat("%ld listening endpoints", model.snapshot.processes.reduce(0) { $0 + $1.endpoints.count }),
                    localizedFormat("%ld active alerts", model.alertEvents.filter { $0.recoveredAt == nil }.count)))
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Open Amid") { openWindow(id: "main"); NSApplication.shared.activate(ignoringOtherApps: true) }.buttonStyle(.borderedProminent).keyboardShortcut("o")
                Spacer()
                Button(model.paused ? localized("Resume") : localized("Pause")) { model.togglePause() }.disabled(model.settings.retention == nil)
                Button("Quit") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
            }
        }.padding(20).frame(width: 360)
    }
}
