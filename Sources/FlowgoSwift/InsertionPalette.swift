import SwiftUI
import FlowCore

struct InsertionPalette: View {
    let insert: (String) -> Void
    let paste: () -> Void
    var canPaste = false
    var body: some View {
        HStack(alignment:.top,spacing:20) {
            VStack(spacing:18) {
                HStack(alignment:.top,spacing:18) {
                    VStack(alignment:.leading,spacing:16) {
                        header("Clipboard")
                        Button(action:paste) { Image(systemName:"doc.on.clipboard").font(.system(size:30)).frame(width:90,height:52) }
                            .buttonStyle(.plain).disabled(!canPaste).help("Paste statements").accessibilityLabel("Paste statements")
                    }.frame(width:205)
                    VStack(spacing:16) {
                        header("Miscellaneous")
                        HStack { tile("comment"); tile("breakpoint") }
                    }.frame(width:285)
                }
                header("Statement")
                HStack(alignment:.top,spacing:10) {
                    column("Input / Output",["input","output"])
                    column("Variables",["declare","assign"])
                    column("Control",["if","call"])
                    column("Looping",["while","for","do"])
                }
            }.frame(width:508)
            VStack(spacing:18) {
                header("Turtle Graphics")
                HStack { tile("forward"); tile("turn") }
                HStack { tile("clear"); tile("home") }
                tile("pen")
                header("Files")
                HStack { tile("read"); tile("open") }
                HStack { tile("write"); tile("close") }
            }.frame(width:240)
        }.padding(20).background(Color(nsColor:.windowBackgroundColor))
    }
    private func header(_ title: String) -> some View {
        Text(title).font(.custom("Arial",size:13)).frame(maxWidth:.infinity,alignment:.leading).padding(9)
            .background(Color(nsColor:.separatorColor).opacity(0.3)).overlay(Rectangle().stroke(Color.secondary.opacity(0.5),lineWidth:1))
    }
    private func column(_ title: String, _ tags: [String]) -> some View {
        VStack(spacing:16) { Text(title).font(.custom("Arial",size:12)); ForEach(tags,id:\.self) { tile($0) } }.frame(width:118)
    }
    private func tile(_ tag: String) -> some View {
        Button { insert(tag) } label: {
            PaletteTile(tag:tag).frame(width:112,height:44)
        }.buttonStyle(.plain).help("Insert " + tag.capitalized).accessibilityLabel("Insert " + tag.capitalized)
    }
}

private struct PaletteTile: View {
    let tag: String
    @Environment(\.colorScheme) private var scheme
    @State private var hover = false
    var body: some View {
        let palette = ChartPalette(Element(tag),selected:hover,dark:scheme == .dark)
        ZStack {
            FlowShape(tag:tag).fill(palette.fill)
            FlowShape(tag:tag).stroke(palette.border,style:StrokeStyle(lineWidth:1,dash:tag == "comment" ? [2,2] : []))
            if tag == "declare" {
                Path { p in p.move(to:CGPoint(x:9,y:0)); p.addLine(to:CGPoint(x:9,y:44)); p.move(to:CGPoint(x:0,y:9)); p.addLine(to:CGPoint(x:112,y:9)) }.stroke(palette.border,lineWidth:1)
            }
            Text(tag.capitalized).font(.custom("Arial",size:13)).foregroundColor(palette.text)
        }.contentShape(Rectangle()).onHover { hover = $0 }
    }
}

struct ArrowHitShape: Shape {
    let points: [CGPoint]
    func path(in rect: CGRect) -> Path {
        var path = Path()
        if let first = points.first { path.move(to:first); for point in points.dropFirst() { path.addLine(to:point) } }
        return path.strokedPath(StrokeStyle(lineWidth:16,lineCap:.round,lineJoin:.round))
    }
}

struct ArrowHitControl: NSViewRepresentable {
    let points: [CGPoint]
    let identifier: String
    let action: () -> Void
    let hover: (Bool) -> Void
    func makeNSView(context: Context) -> ArrowHitButton { ArrowHitButton(frame:.zero) }
    func updateNSView(_ view: ArrowHitButton, context: Context) {
        view.points = points
        view.insertionIdentifier = identifier
        view.activate = action
        view.hover = hover
        view.setAccessibilityLabel("Insert a statement")
        view.setAccessibilityIdentifier(identifier)
    }
}

final class ArrowHitButton: NSButton {
    var insertionIdentifier = ""
    var points: [CGPoint] = []
    var activate: () -> Void = {}
    var hover: (Bool) -> Void = { _ in }
    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame:frame)
        title = ""; isBordered = false
        target = self; action = #selector(pressed)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {}
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point,from:superview)
        return ArrowHitShape(points:points).path(in:bounds).contains(local) ? self : nil
    }
    override func updateTrackingAreas() {
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect:bounds,options:[.mouseEnteredAndExited,.mouseMoved,.activeInKeyWindow,.inVisibleRect],owner:self,userInfo:nil))
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { mouseMoved(with:event) }
    override func mouseMoved(with event: NSEvent) {
        hover(ArrowHitShape(points:points).path(in:bounds).contains(convert(event.locationInWindow,from:nil)))
    }
    override func mouseExited(with event: NSEvent) { hover(false) }
    @objc private func pressed() { activate() }
}

struct ArrowInsertionControl: View {
    let insertion: ChartInsertion
    let insert: (String) -> Void
    let paste: () -> Void
    let hover: (Bool) -> Void
    @State private var presented = false
    private var bounds: CGRect {
        let x = insertion.points.map(\.x), y = insertion.points.map(\.y)
        return CGRect(x:(x.min() ?? 0) - 8,y:(y.min() ?? 0) - 8,width:(x.max() ?? 0) - (x.min() ?? 0) + 16,height:(y.max() ?? 0) - (y.min() ?? 0) + 16)
    }
    var body: some View {
        let local = insertion.points.map { CGPoint(x:$0.x - bounds.minX,y:$0.y - bounds.minY) }
        ArrowHitControl(points:local,identifier:"insert-" + insertion.id,action:{ presented = true },hover:{ hover(presented || $0) })
            .frame(width:bounds.width,height:bounds.height)
            .help("Insert a statement").accessibilityLabel("Insert a statement")
            .accessibilityIdentifier("insert-" + insertion.id)
            .popover(isPresented:$presented,arrowEdge:.trailing) {
                InsertionPalette(insert:{ tag in presented = false; hover(false); insert(tag) },paste:{ presented = false; hover(false); paste() },canPaste:NSPasteboard.general.string(forType:.string) != nil)
            }
            .onChange(of:presented) { hover($0) }
            .position(x:bounds.midX,y:bounds.midY)
    }
}
