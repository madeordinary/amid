import SwiftUI
import AppKit
import AmidCore

@main
struct AmidApplication: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()
    var body: some Scene {
        WindowGroup("Amid", id: "main") {
            MainWindow(model: model)
                .preferredColorScheme(model.verificationColorScheme)
                .frame(minWidth: 960, minHeight: 640)
                .task { delegate.model = model; await model.start() }
        }
        .defaultSize(width: 1180, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Monitor") {
                Button(model.paused ? localized("Resume Monitoring") : localized("Pause Monitoring")) { model.togglePause() }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Refresh Now") { Task { await model.refresh() } }
                    .keyboardShortcut("r", modifiers: .command)
                Divider()
                ForEach(Destination.allCases) { destination in
                    Button(destination.title) { model.destination = destination }
                        .keyboardShortcut(destination.shortcut, modifiers: .command)
                }
            }
        }
        MenuBarExtra {
            MenuPanel(model: model).preferredColorScheme(model.verificationColorScheme).task { await model.start() }
        } label: {
            Label(model.menuTitle, systemImage: model.pressureAttention ? "waveform.path.ecg.rectangle" : "circle.hexagongrid")
                .accessibilityLabel("Amid")
                .accessibilityValue(model.menuTitle)
        }
        .menuBarExtraStyle(.window)
        Settings { SettingsScreen(model: model).preferredColorScheme(model.verificationColorScheme).frame(width: 740, height: 670) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { await model?.prepareToQuit(); sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

enum Destination: String, CaseIterable, Identifiable {
    case overview = "Overview", applications = "Applications", projects = "Projects", ports = "Ports"
    case history = "History", alerts = "Alerts", settings = "Settings"
    var id: String { rawValue }
    var title: String { localized(rawValue) }
    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .applications: "app.dashed"
        case .projects: "folder"
        case .ports: "network"
        case .history: "clock.arrow.circlepath"
        case .alerts: "bell"
        case .settings: "slider.horizontal.3"
        }
    }
    var shortcut: KeyEquivalent { KeyEquivalent(Character(String(Self.allCases.firstIndex(of: self)! + 1))) }
    var subtitle: String {
        let key: String = switch self {
        case .overview: "A clear view of what your Mac is doing."
        case .applications: "Observed processes, grouped by their application evidence."
        case .projects: "Native workloads connected to accessible project roots."
        case .ports: "Listening TCP endpoints and the processes that own them."
        case .history: "Measured activity, with coverage and gaps kept visible."
        case .alerts: "Sustained changes worth a closer look."
        case .settings: "Your data, your defaults."
        }
        return localized(key)
    }
}
