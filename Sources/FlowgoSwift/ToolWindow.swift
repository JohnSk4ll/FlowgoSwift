import SwiftUI

struct ToolWindow<Content: View>: NSViewRepresentable {
    @Binding var presented: Bool
    let title: String
    let size: CGSize
    var actions: FlowActions? = nil
    @ViewBuilder let content: () -> Content
    func makeCoordinator() -> Coordinator { Coordinator(presented:$presented) }
    func makeNSView(context: Context) -> NSView { NSView(frame:.zero) }
    func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        coordinator.presented = $presented
        if presented {
            if coordinator.window == nil {
                let window = NSWindow(contentRect:CGRect(origin:.zero,size:size), styleMask:[.titled,.closable,.miniaturizable,.resizable], backing:.buffered, defer:false)
                window.title = title; window.isReleasedWhenClosed = false; window.delegate = coordinator
                window.minSize = CGSize(width:title == "Source Code Viewer" ? 820 : min(size.width,300),height:title == "Source Code Viewer" ? 400 : 250)
                window.appearance = nil
                coordinator.window = window
                if let parent = view.window, let screen = parent.screen {
                    let visible = screen.visibleFrame
                    let x = min(parent.frame.maxX + 12, visible.maxX - size.width)
                    let y = max(visible.minY, parent.frame.maxY - size.height - 40)
                    window.setFrameOrigin(CGPoint(x:max(visible.minX,x),y:y))
                } else { window.center() }
            }
            if let actions, let window = coordinator.window { FlowCommandRegistry.shared.register(actions,for:window) }
            if let hosting = coordinator.hosting {
                hosting.rootView = AnyView(content())
            } else {
                let hosting = NSHostingView(rootView:AnyView(content()))
                coordinator.hosting = hosting
                coordinator.window?.contentView = hosting
            }
            if coordinator.window?.isVisible != true { coordinator.window?.makeKeyAndOrderFront(nil) }
        } else { coordinator.window?.orderOut(nil) }
    }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        if let window = coordinator.window { FlowCommandRegistry.shared.remove(window); window.orderOut(nil); window.delegate = nil }
    }
    final class Coordinator: NSObject, NSWindowDelegate {
        var presented: Binding<Bool>
        var window: NSWindow?
        var hosting: NSHostingView<AnyView>?
        init(presented: Binding<Bool>) { self.presented = presented }
        func windowShouldClose(_ sender: NSWindow) -> Bool { presented.wrappedValue = false; return true }
    }
}

struct DocumentWindowTitle: NSViewRepresentable {
    let title: String
    func makeNSView(context: Context) -> NSView { NSView(frame:.zero) }
    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { view.window?.title = title + " - FlowgoSwift" }
    }
}
