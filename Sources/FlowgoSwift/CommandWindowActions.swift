import SwiftUI

final class FlowCommandRegistry: ObservableObject {
    static let shared = FlowCommandRegistry()
    private var contexts: [ObjectIdentifier:FlowActions] = [:]
    private var observers: [NSObjectProtocol] = []
    var current: FlowActions? { NSApp.keyWindow.flatMap(actions) }
    private init() {
        for name in [NSWindow.didBecomeKeyNotification,NSWindow.didResignKeyNotification] {
            observers.append(NotificationCenter.default.addObserver(forName:name,object:nil,queue:.main) { [weak self] _ in
                DispatchQueue.main.async { self?.objectWillChange.send() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName:NSWindow.willCloseNotification,object:nil,queue:.main) { [weak self] event in
            if let window = event.object as? NSWindow { self?.remove(window) }
        })
    }
    func actions(for window: NSWindow) -> FlowActions? { contexts[ObjectIdentifier(window)] }
    func register(_ actions: FlowActions,for window: NSWindow) {
        let previous = contexts[ObjectIdentifier(window)]
        contexts[ObjectIdentifier(window)] = actions
        if window == NSApp.keyWindow && (previous == nil || previous?.running != actions.running || previous?.paused != actions.paused || previous?.selected != actions.selected || previous?.ignoreBreakpoints != actions.ignoreBreakpoints) {
            DispatchQueue.main.async { [weak self] in self?.objectWillChange.send() }
        }
    }
    func remove(_ window: NSWindow) { contexts.removeValue(forKey:ObjectIdentifier(window)) }
}

struct CommandWindowActions: NSViewRepresentable {
    let actions: FlowActions
    func makeNSView(context: Context) -> NSView { NSView(frame:.zero) }
    func updateNSView(_ view: NSView,context: Context) {
        DispatchQueue.main.async { if let window = view.window { FlowCommandRegistry.shared.register(actions,for:window) } }
    }
    static func dismantleNSView(_ view: NSView,coordinator: ()) {
        if let window = view.window { FlowCommandRegistry.shared.remove(window) }
    }
}
