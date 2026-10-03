import SwiftUI
import AppKit

/// SwiftUI appearance alone does not change when a window is hidden or minimized.
struct WindowVisibilityReader: NSViewRepresentable {
    var changed: @MainActor (Bool) -> Void
    func makeNSView(context: Context) -> VisibilityView { VisibilityView(changed: changed) }
    func updateNSView(_ view: VisibilityView, context: Context) { view.changed = changed }
    static func dismantleNSView(_ view: VisibilityView, coordinator: ()) { view.stopObserving() }

    @MainActor final class VisibilityView: NSView {
        var changed: @MainActor (Bool) -> Void
        private var observers: [NSObjectProtocol] = []
        init(changed: @escaping @MainActor (Bool) -> Void) {
            self.changed = changed
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError("Programmatic view only") }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopObserving()
            guard let window else { return }
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.report() }
                })
            }
            for name in [NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.report() }
                })
            }
            report()
        }
        func stopObserving() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            changed(false)
        }
        private func report() {
            changed(window.map { $0.isVisible && !$0.isMiniaturized && !NSApplication.shared.isHidden && $0.occlusionState.contains(.visible) } ?? false)
        }
    }
}
