import SwiftUI

struct FlowActions {
    var running: Bool
    var paused: Bool
    var selected: Bool
    var run: () -> Void
    var step: () -> Void
    var pause: () -> Void
    var stop: () -> Void
    var functions: () -> Void
    var console: () -> Void
    var variables: () -> Void
    var source: () -> Void
    var turtle: () -> Void
    var zoomIn: () -> Void
    var zoomOut: () -> Void
    var edit: () -> Void
    var delete: () -> Void
    var undo: () -> Void
    var redo: () -> Void
    var ignoreBreakpoints: Bool
    var setIgnoreBreakpoints: (Bool) -> Void
    var removeBreakpoints: () -> Void
    var attributes: () -> Void
    var importFunctions: () -> Void
    var print: () -> Void
    var copy: () -> Void
    var paste: () -> Void
    var cut: () -> Void
}

private struct FlowActionsKey: FocusedValueKey { typealias Value = FlowActions }

extension FocusedValues {
    var flowActions: FlowActions? {
        get { self[FlowActionsKey.self] }
        set { self[FlowActionsKey.self] = newValue }
    }
}

struct FlowCommands: Commands {
    @FocusedValue(\.flowActions) private var focusedActions
    @ObservedObject private var registry = FlowCommandRegistry.shared
    private var actions: FlowActions? { registry.current ?? focusedActions }
    var body: some Commands {
        CommandGroup(replacing:.printItem) {
            Button("Print…") { actions?.print() }.keyboardShortcut("p",modifiers:.command).disabled(actions == nil)
        }
        CommandGroup(replacing:.undoRedo) {
            Button("Undo") { if let text = NSApp.keyWindow?.firstResponder as? NSTextView { text.undoManager?.undo() } else { actions?.undo() } }.keyboardShortcut("z",modifiers:.command)
            Button("Redo") { if let text = NSApp.keyWindow?.firstResponder as? NSTextView { text.undoManager?.redo() } else { actions?.redo() } }.keyboardShortcut("z",modifiers:[.command,.shift])
        }
        CommandGroup(replacing:.pasteboard) {
            Button("Cut") { if let text = NSApp.keyWindow?.firstResponder as? NSTextView { text.cut(nil) } else { actions?.cut() } }.keyboardShortcut("x",modifiers:.command)
            Button("Copy") { if let text = NSApp.keyWindow?.firstResponder as? NSTextView { text.copy(nil) } else { actions?.copy() } }.keyboardShortcut("c",modifiers:.command)
            Button("Paste") { if let text = NSApp.keyWindow?.firstResponder as? NSTextView { text.paste(nil) } else { actions?.paste() } }.keyboardShortcut("v",modifiers:.command)
        }
        CommandGroup(after:.pasteboard) {
            Divider()
            Button("Edit Shape") { actions?.edit() }.disabled(actions?.selected != true || actions?.running == true)
            Button("Delete Shape") { actions?.delete() }.disabled(actions?.selected != true || actions?.running == true)
        }
        CommandMenu("Appearance") {
            Button("Zoom In") { actions?.zoomIn() }.keyboardShortcut("+",modifiers:.command)
            Button("Zoom Out") { actions?.zoomOut() }.keyboardShortcut("-",modifiers:.command)
        }
        CommandMenu("Program") {
            Button("Run") { actions?.run() }.keyboardShortcut(KeyEquivalent("\u{F708}"),modifiers:[]).disabled(actions == nil || (actions?.running == true && actions?.paused != true))
            Button("Step") { actions?.step() }.keyboardShortcut(KeyEquivalent("\u{F709}"),modifiers:[]).disabled(actions == nil || (actions?.running == true && actions?.paused != true))
            Button("Pause") { actions?.pause() }.keyboardShortcut(KeyEquivalent("\u{F70A}"),modifiers:[]).disabled(actions?.running != true || actions?.paused == true)
            Button("Stop") { actions?.stop() }.keyboardShortcut(KeyEquivalent("\u{F70B}"),modifiers:[]).disabled(actions?.running != true)
            Divider()
            Button("Function Manager…") { actions?.functions() }.disabled(actions == nil)
            Button("Import Functions…") { actions?.importFunctions() }.disabled(actions == nil || actions?.running == true)
            Button("Program Attributes…") { actions?.attributes() }.disabled(actions == nil || actions?.running == true)
            Divider()
            Toggle("Ignore Breakpoints",isOn:Binding(get:{ actions?.ignoreBreakpoints ?? false },set:{ actions?.setIgnoreBreakpoints($0) })).disabled(actions == nil)
            Button("Remove Breakpoints") { actions?.removeBreakpoints() }.disabled(actions == nil || actions?.running == true)
        }
        CommandMenu("Tools") {
            Button("Console") { actions?.console() }.keyboardShortcut(KeyEquivalent("\u{F70D}"),modifiers:[])
            Button("Variable Watch") { actions?.variables() }.keyboardShortcut(KeyEquivalent("\u{F70C}"),modifiers:[])
            Button("Source Code Viewer") { actions?.source() }.keyboardShortcut(KeyEquivalent("\u{F70F}"),modifiers:[])
            Button("Turtle Graphics") { actions?.turtle() }.keyboardShortcut(KeyEquivalent("\u{F70E}"),modifiers:[])
        }
    }
}
