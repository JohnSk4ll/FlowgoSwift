import SwiftUI
import FlowCore

struct TurtleView: View {
    @ObservedObject var execution: ExecutionController
    let transport: AnyView
    private var state: TurtleState { execution.turtle }
    @State private var error: String?
    @AppStorage("turtleShowGrid") private var showGrid = true
    @AppStorage("turtleShowTurtle") private var showTurtle = true
    @AppStorage("turtleBlackAndWhite") private var monochrome = false
    @AppStorage("turtlePenSizeIndex") private var penSizeIndex = 2
    private let penSizes = [1.0,2.0,3.0,4.0,5.0,6.0,8.0,10.0,12.0,16.0,20.0]
    private var penWidth: Double { penSizes[min(max(penSizeIndex,0),penSizes.count - 1)] }
    @Environment(\.colorScheme) private var scheme
    private func ink(_ name: String) -> Color {
        if monochrome { return scheme == .dark ? .white : .black }
        if name == "black" && scheme == .dark { return .white }
        let hex = String((TurtleState.ink[name] ?? "#101010").dropFirst())
        return Color(hex:UInt32(hex,radix:16) ?? 0x101010)
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                transport
                Spacer()
                Button(action:saveImage) { Image(systemName:"square.and.arrow.down") }.help("Save").accessibilityLabel("Save").disabled(execution.running)
                Button(action:copyImage) { Image(systemName:"doc.on.doc") }.help("Copy").accessibilityLabel("Copy")
                Button("Clear Window") { execution.turtle.clear() }.disabled(execution.running)
            }.padding(8).background(Color(nsColor:.controlBackgroundColor))
            Divider()
            HStack {
                Toggle(isOn:$showTurtle) { Image(systemName:"tortoise") }.toggleStyle(.button).help("Show Turtle").accessibilityLabel("Show Turtle")
                Toggle(isOn:$showGrid) { Image(systemName:"grid") }.toggleStyle(.button).help("Show Grid").accessibilityLabel("Show Grid")
                Toggle(isOn:$monochrome) { Image(systemName:"circle.lefthalf.filled") }.toggleStyle(.button).help("Black and White").accessibilityLabel("Black and White")
                Button { penSizeIndex = max(0,penSizeIndex - 1) } label: { Image(systemName:"minus") }.help("Thinner Pen").accessibilityLabel("Thinner Pen").disabled(penSizeIndex <= 0)
                Button { penSizeIndex = min(penSizes.count - 1,penSizeIndex + 1) } label: { Image(systemName:"plus") }.help("Thicker Pen").accessibilityLabel("Thicker Pen").disabled(penSizeIndex >= penSizes.count - 1)
                Spacer()
                Text(String(format: "x %.2f  y %.2f  angle %.1f°", state.position.x, -state.position.y, state.angle)).font(.system(.caption, design: .monospaced))
            }.foregroundStyle(.secondary).padding(12)
            drawing
        }.alert("Cannot save image",isPresented:Binding(get:{ error != nil },set:{ if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
    }
    private var drawing: some View {
            Canvas { context, size in
                let points = state.segments.flatMap { [$0.start, $0.end] } + [state.position]
                let left = min(-60, points.map(\.x).min() ?? -60) - 20
                let right = max(60, points.map(\.x).max() ?? 60) + 20
                let top = min(-60, points.map(\.y).min() ?? -60) - 20
                let bottom = max(60, points.map(\.y).max() ?? 60) + 20
                let scale = min(size.width / (right - left), size.height / (bottom - top))
                let offsetX = (size.width - (right - left) * scale) / 2
                let offsetY = (size.height - (bottom - top) * scale) / 2
                func point(_ p: TurtlePoint) -> CGPoint {
                    CGPoint(x: (p.x - left) * scale + offsetX, y: (p.y - top) * scale + offsetY)
                }
                var grid = Path()
                for i in -10...10 {
                    let x = point(TurtlePoint(x: Double(i) * 25, y: 0)).x
                    grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height))
                    let y = point(TurtlePoint(x: 0, y: Double(i) * 25)).y
                    grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y))
                }
                if showGrid { context.stroke(grid, with: .color(.gray.opacity(0.15)), lineWidth: 1) }
                for segment in state.segments {
                    var drawing = Path()
                    drawing.move(to:point(segment.start)); drawing.addLine(to:point(segment.end))
                    context.stroke(drawing,with:.color(ink(segment.color)),style:StrokeStyle(lineWidth:penWidth,lineCap:.round))
                }
                let center = point(state.position)
                let radians = state.angle * .pi / 180
                var turtle = Path()
                for (index, angle) in [radians, radians + 2.5, radians - 2.5].enumerated() {
                    let p = CGPoint(x: center.x + cos(angle) * 10, y: center.y - sin(angle) * 10)
                    if index == 0 { turtle.move(to: p) } else { turtle.addLine(to: p) }
                }
                turtle.closeSubpath(); if showTurtle { context.fill(turtle, with: .color(monochrome ? ink("black") : .green)) }
            }.background(Color(nsColor: .textBackgroundColor))
    }
    private func image() -> NSImage? {
        let renderer = ImageRenderer(content:drawing.frame(width:800,height:600).environment(\.colorScheme,scheme))
        renderer.scale = 2
        return renderer.nsImage
    }
    private func copyImage() {
        guard let image = image() else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([image])
    }
    private func saveImage() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Turtle.png"; panel.allowedContentTypes = [.png]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let image = image(), let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data:tiff), let data = bitmap.representation(using:.png,properties:[:]) else { error = "Could not render turtle graphics."; return }
        do { try data.write(to:url) } catch { self.error = error.localizedDescription }
    }
}
