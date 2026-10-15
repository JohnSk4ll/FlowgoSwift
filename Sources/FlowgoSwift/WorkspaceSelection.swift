import SwiftUI

final class ChartCoordinateSpace: ObservableObject {
    weak var anchor: NSView?
}

struct ChartCoordinateAnchor: NSViewRepresentable {
    let space: ChartCoordinateSpace
    func makeNSView(context: Context) -> ChartAnchorView {
        let view = ChartAnchorView()
        space.anchor = view
        return view
    }
    func updateNSView(_ view: ChartAnchorView, context: Context) { space.anchor = view }
}

final class ChartAnchorView: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct WorkspaceSelectionControl: NSViewRepresentable {
    let layout: ChartLayout
    var coordinateSpace: ChartCoordinateSpace? = nil
    let zoom: CGFloat
    let enabled: Bool
    let select: (Set<[Int]>) -> Void
    let rectangle: (CGRect?) -> Void

    func makeNSView(context: Context) -> WorkspaceSelectionView { WorkspaceSelectionView() }
    func updateNSView(_ view: WorkspaceSelectionView, context: Context) {
        view.layout = layout; view.coordinateSpace = coordinateSpace; view.zoom = zoom; view.enabled = enabled
        view.select = select; view.rectangle = rectangle
    }
}

final class WorkspaceSelectionView: NSView {
    var layout: ChartLayout?
    var chartOrigin = CGPoint.zero
    var coordinateSpace: ChartCoordinateSpace?
    var zoom: CGFloat = 1
    var enabled = true
    var select: (Set<[Int]>) -> Void = { _ in }
    var rectangle: (CGRect?) -> Void = { _ in }
    private var start: CGPoint?
    private var dragging = false
    private var eventMonitor: Any?
    private weak var pressedArrow: ArrowHitButton?
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func chartPoint(_ point: CGPoint) -> CGPoint {
        let origin = coordinateSpace?.anchor.map { convert(.zero,from:$0) } ?? chartOrigin
        return CGPoint(x:(point.x - origin.x) / zoom,y:(point.y - origin.y) / zoom)
    }
    func canStart(at point: CGPoint) -> Bool {
        guard enabled, let layout else { return false }
        let local = chartPoint(point)
        return !layout.items.contains { FlowShape(tag:$0.node.tag).path(in:$0.rect).contains(local) }
            && !layout.insertions.contains { ArrowHitShape(points:$0.points).path(in:.zero).contains(local) }
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point,from:superview)
        return bounds.contains(local) && canStart(at:local) ? self : nil
    }
    func begin(at point: CGPoint) { start = point; dragging = false }
    func update(to point: CGPoint) {
        guard enabled, let start, let layout else { return }
        if hypot(point.x - start.x,point.y - start.y) < 4 && !dragging { return }
        dragging = true
        rectangle(ChartSelection.rectangle(from:start,to:point))
        let rect = ChartSelection.rectangle(from:chartPoint(start),to:chartPoint(point))
        select(ChartSelection.paths(in:rect,layout:layout))
    }
    func end(at point: CGPoint) {
        update(to:point)
        if !dragging { select([]) }
        start = nil; dragging = false; rectangle(nil)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor); self.eventMonitor = nil }
        guard window != nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching:[.leftMouseDown,.leftMouseDragged,.leftMouseUp]) { [weak self] event in
            guard let self else { return event }
            return self.handleMouse(event)
        }
    }
    func handleMouse(_ event: NSEvent) -> NSEvent? {
        guard enabled, let window, event.window === window else { return event }
        let point = convert(event.locationInWindow,from:nil)
        switch event.type {
        case .leftMouseDown:
            guard bounds.contains(point) else { return event }
            if let insertion = layout?.insertions.reversed().first(where:{ ArrowHitShape(points:$0.points).path(in:.zero).contains(chartPoint(point)) }),
               let root = window.contentView, let arrow = insertionButton(in:root,identifier:"insert-" + insertion.id) {
                pressedArrow = arrow
                return nil
            }
            guard canStart(at:point) else { return event }
            if let root = window.contentView {
                var target = root.hitTest(root.convert(event.locationInWindow,from:nil))
                while let view = target {
                    if view is NSScroller { return event }
                    target = view.superview
                }
            }
            begin(at:point)
        case .leftMouseDragged:
            if pressedArrow != nil { return nil }
            guard start != nil else { return event }
            update(to:point)
        case .leftMouseUp:
            if let arrow = pressedArrow {
                pressedArrow = nil
                if ArrowHitShape(points:arrow.points).path(in:arrow.bounds).contains(arrow.convert(event.locationInWindow,from:nil)) { arrow.performClick(nil) }
                return nil
            }
            guard start != nil else { return event }
            end(at:point)
        default: return event
        }
        return nil
    }
    private func insertionButton(in view: NSView, identifier: String) -> ArrowHitButton? {
        if let arrow = view as? ArrowHitButton, arrow.insertionIdentifier == identifier { return arrow }
        for child in view.subviews { if let arrow = insertionButton(in:child,identifier:identifier) { return arrow } }
        return nil
    }
    deinit { if let eventMonitor { NSEvent.removeMonitor(eventMonitor) } }
    override func mouseDown(with event: NSEvent) { begin(at:convert(event.locationInWindow,from:nil)) }
    override func mouseDragged(with event: NSEvent) { update(to:convert(event.locationInWindow,from:nil)) }
    override func mouseUp(with event: NSEvent) { end(at:convert(event.locationInWindow,from:nil)) }
}
