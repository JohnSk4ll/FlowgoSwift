import SwiftUI
import FlowCore

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
}

struct FlowShape: Shape {
    let tag: String
    func path(in rect: CGRect) -> Path {
        let x = rect.minX, y = rect.minY, w = rect.width, h = rect.height
        switch tag {
        case "terminal": return Capsule().path(in: rect)
        case "connector": return Circle().path(in: rect)
        case "if": return polygon([CGPoint(x:x + w / 2,y:y), CGPoint(x:x + w,y:y + h / 2), CGPoint(x:x + w / 2,y:y + h), CGPoint(x:x,y:y + h / 2)])
        case "for", "while", "do":
            let cut = h / 2
            return polygon([CGPoint(x:x + cut,y:y), CGPoint(x:x + w - cut,y:y), CGPoint(x:x + w,y:y + h / 2), CGPoint(x:x + w - cut,y:y + h), CGPoint(x:x + cut,y:y + h), CGPoint(x:x,y:y + h / 2)])
        case "forward":
            return polygon([CGPoint(x:x,y:y),CGPoint(x:x+w-h/3,y:y),CGPoint(x:x+w,y:y+h/2),CGPoint(x:x+w-h/3,y:y+h),CGPoint(x:x,y:y+h),CGPoint(x:x+h/4,y:y+h/2)])
        case "turn":
            let cut = h/3
            return polygon([CGPoint(x:x,y:y+h/2),CGPoint(x:x+cut,y:y),CGPoint(x:x+cut,y:y+h/5),CGPoint(x:x+w-cut,y:y+h/5),CGPoint(x:x+w-cut,y:y),CGPoint(x:x+w,y:y+h/2),CGPoint(x:x+w-cut,y:y+h),CGPoint(x:x+w-cut,y:y+h*4/5),CGPoint(x:x+cut,y:y+h*4/5),CGPoint(x:x+cut,y:y+h)])
        case "home":
            return polygon([CGPoint(x:x,y:y+h/4),CGPoint(x:x+w/2,y:y),CGPoint(x:x+w,y:y+h/4),CGPoint(x:x+w,y:y+h),CGPoint(x:x,y:y+h)])
        case "clear", "pen":
            return polygon([CGPoint(x:x,y:y),CGPoint(x:x+w-h/3,y:y),CGPoint(x:x+w,y:y+h/2),CGPoint(x:x+w-h/3,y:y+h),CGPoint(x:x,y:y+h)])
        case "input", "output":
            let cut = h / 2
            return polygon([CGPoint(x:x + cut,y:y), CGPoint(x:x + w,y:y), CGPoint(x:x + w - cut,y:y + h), CGPoint(x:x,y:y + h)])
        case "read", "write":
            return Path { p in
                p.move(to:CGPoint(x:x+h/4,y:y)); p.addLine(to:CGPoint(x:x+w,y:y))
                p.addQuadCurve(to:CGPoint(x:x+w,y:y+h),control:CGPoint(x:x+w-h/2,y:y+h/2))
                p.addLine(to:CGPoint(x:x+h/4,y:y+h)); p.addQuadCurve(to:CGPoint(x:x+h/4,y:y),control:CGPoint(x:x-h/4,y:y+h/2)); p.closeSubpath()
            }
        case "open", "close":
            return polygon([CGPoint(x:x+h/3,y:y),CGPoint(x:x+w-h/3,y:y),CGPoint(x:x+w,y:y+h/3),CGPoint(x:x+w,y:y+h),CGPoint(x:x,y:y+h),CGPoint(x:x,y:y+h/3)])
        case "breakpoint":
            let c = min(w,h)*0.3
            return polygon([CGPoint(x:x+c,y:y),CGPoint(x:x+w-c,y:y),CGPoint(x:x+w,y:y+c),CGPoint(x:x+w,y:y+h-c),CGPoint(x:x+w-c,y:y+h),CGPoint(x:x+c,y:y+h),CGPoint(x:x,y:y+h-c),CGPoint(x:x,y:y+c)])
        default: return Rectangle().path(in: rect)
        }
    }
    private func polygon(_ points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first); for point in points.dropFirst() { path.addLine(to: point) }; path.closeSubpath()
        }
    }
}

struct ChartPalette {
    var fill: Color
    var border: Color
    var text = Color.black
    init(_ node: Element, selected: Bool = false, executing: Bool = false, dark: Bool = false) {
        if executing { fill = Color(hex:0x00A060); border = Color(hex:0x005030); text = .white; return }
        if selected { fill = Color(hex:0x2080D0); border = Color(hex:0x104070); text = .white; return }
        if dark {
            text = Color(hex:0xE6E6E6)
            switch node.tag {
            case "terminal", "call": fill = Color(hex:0x743D7D); border = Color(hex:0xC58ACC)
            case "if": fill = Color(hex:0x713F3F); border = Color(hex:0xD49B9B)
            case "for", "while", "do", "connector": fill = Color(hex:0x784320); border = Color(hex:0xD99548)
            case "input", "read": fill = Color(hex:0x284A7E); border = Color(hex:0x6EA5EF)
            case "output", "write", "forward", "clear": fill = Color(hex:0x236D28); border = Color(hex:0x68C56D)
            case "comment": fill = Color(nsColor:.textBackgroundColor); border = .gray
            case "breakpoint": fill = Color(hex:0x901F1F); border = .red
            default: fill = Color(hex:0x77751E); border = Color(hex:0xD8D56A)
            }
            return
        }
        switch node.tag {
        case "terminal", "call": fill = Color(hex:0xF0D0FF); border = Color(hex:0x9070A0)
        case "if": fill = Color(hex:0xFFD0D0); border = Color(hex:0xA07070)
        case "for", "while", "do": fill = Color(hex:0xFFE0A0); border = Color(hex:0xA08040)
        case "connector":
            fill = Color(hex:node["kind"] == "if" ? 0xFFD0D0 : 0xFFE0A0)
            border = Color(hex:node["kind"] == "if" ? 0xA07070 : 0xA08040)
        case "input", "read": fill = Color(hex:0xD0E0FF); border = Color(hex:0x7080A0)
        case "output", "write", "forward", "clear": fill = Color(hex:0xD0FFD0); border = Color(hex:0x70A070)
        case "comment", "breakpoint": fill = .white; border = Color(hex:0x808080); text = Color(hex:0x505050)
        default: fill = Color(hex:0xFFFFD0); border = Color(hex:0xA0A070)
        }
    }
}

struct ClassicChart: View {
    let layout: ChartLayout
    var selection: [Int] = []
    var selectedPaths = Set<[Int]>()
    var currentID: UUID?
    var breakpoints = Set<UUID>()
    var zoom: CGFloat = 1
    var editable = true
    var choose: ([Int]) -> Void = { _ in }
    var edit: ([Int]) -> Void = { _ in }
    var insert: ([Int], Int, String) -> Void = { _, _, _ in }
    var remove: ([Int]) -> Void = { _ in }
    var copy: ([Int]) -> Void = { _ in }
    var paste: ([Int],Int) -> Void = { _,_ in }
    @Environment(\.colorScheme) private var scheme
    @State private var hoveredArrow: String?
    private let tags = ["assign", "call", "declare", "input", "output", "if", "for", "while", "do", "comment", "breakpoint", "open", "close", "read", "write", "forward", "turn", "home", "clear", "pen"]
    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { suppliedContext, _ in
                var context = suppliedContext
                for edge in layout.edges { draw(edge, in: &context) }
                if let hoveredArrow, let insertion = layout.insertions.first(where: { $0.id == hoveredArrow }) {
                    draw(ChartEdge(points:insertion.points),in:&context,color:.orange)
                }
                for item in layout.items {
                    let palette = ChartPalette(item.node, selected: editable && (selection == item.path || selectedPaths.contains(item.path)) && item.node.tag != "connector", executing: currentID == item.id,dark:scheme == .dark)
                    let shape = FlowShape(tag:item.node.tag).path(in:item.rect)
                    context.fill(shape, with:.color(palette.fill))
                    context.stroke(shape, with:.color(palette.border), style:StrokeStyle(lineWidth:0.8, dash:item.node.tag == "comment" ? [2,2] : []))
                    drawDetails(item, color: palette.border, in: &context)
                    if item.node.tag != "connector" {
                        let insetX: CGFloat = item.node.tag == "if" ? item.rect.width * 0.22 : (["input", "output", "for", "while", "do"].contains(item.node.tag) ? item.rect.height / 2 : 12)
                        let textRect = item.rect.insetBy(dx: insetX, dy: item.node.tag == "declare" ? 9 : 5)
                        let lines = ChartLayout.caption(item.node).components(separatedBy:"\n").map {
                            context.resolve(Text($0).font(.custom("Arial",size:13)).foregroundColor(palette.text))
                        }
                        let sizes = lines.map { $0.measure(in:textRect.size) }
                        var y = textRect.midY - sizes.reduce(0) { $0 + $1.height } / 2
                        for (text,size) in zip(lines,sizes) {
                            context.draw(text,in:CGRect(x:textRect.midX - size.width / 2,y:y,width:size.width,height:size.height))
                            y += size.height
                        }
                        if breakpoints.contains(item.id) {
                            context.fill(Path(ellipseIn:CGRect(x:item.rect.minX - 12,y:item.rect.midY - 4,width:8,height:8)), with:.color(.red))
                        }
                    }
                }
                for label in layout.labels {
                    context.draw(Text(label.text).font(.custom("Arial", size:13)).foregroundColor(Color(nsColor:.labelColor)), at:label.point)
                }
            }.allowsHitTesting(false)
            if editable {
                ForEach(layout.items.filter { $0.node.tag != "connector" }) { item in
                    Button { choose(item.path) } label: {
                        Color.clear.frame(width:item.rect.width,height:item.rect.height)
                            .contentShape(FlowShape(tag:item.node.tag))
                    }
                        .buttonStyle(.plain).position(x:item.rect.midX, y:item.rect.midY)
                        .accessibilityLabel(ChartLayout.caption(item.node)).help("Double-click to edit")
                        .simultaneousGesture(TapGesture(count:2).onEnded { edit(item.path) })
                        .contextMenu {
                            Button("Edit") { edit(item.path) }
                            Button("Copy") { copy(item.path) }
                            if item.path.count > 2 {
                                Menu("Insert Before") { insertionMenu(Array(item.path.dropLast()), item.path.last ?? 0) }
                                Menu("Insert After") { insertionMenu(Array(item.path.dropLast()), (item.path.last ?? 0) + 1) }
                                Button("Delete", role:.destructive) { remove(item.path) }
                            }
                        }.id(item.id)
                }
                ForEach(layout.insertions) { point in
                    ArrowInsertionControl(insertion:point,insert:{ insert(point.path,point.index,$0) },paste:{ paste(point.path,point.index) },hover:{ hovering in
                        if hovering { hoveredArrow = point.id } else if hoveredArrow == point.id { hoveredArrow = nil }
                    })
                }
            }
        }.frame(width:layout.size.width, height:layout.size.height)
            .scaleEffect(zoom, anchor:.topLeading)
            .frame(width:layout.size.width * zoom, height:layout.size.height * zoom, alignment:.topLeading)
            .background(Color(nsColor:.textBackgroundColor))
    }
    @ViewBuilder private func insertionMenu(_ path: [Int], _ index: Int) -> some View {
        ForEach(tags, id:\.self) { tag in
            Button { insert(path, index, tag) } label: { Label(tag.capitalized, systemImage:symbol(tag)) }
        }
    }
    private func symbol(_ tag: String) -> String {
        switch tag {
        case "if": return "diamond"
        case "for", "while", "do": return "hexagon"
        case "input", "output": return "rectangle"
        case "comment": return "text.bubble"
        default: return "rectangle"
        }
    }
    private func draw(_ edge: ChartEdge, in context: inout GraphicsContext, color: Color? = nil) {
        guard let start = edge.points.first, let end = edge.points.last else { return }
        var path = Path(); path.move(to:start); for point in edge.points.dropFirst() { path.addLine(to:point) }
        context.stroke(path, with:.color(color ?? (scheme == .dark ? Color(hex:0xD0D0D0) : Color(hex:0x404040))), lineWidth:1.4)
        if edge.arrow, edge.points.count > 1 {
            let previous = edge.points[edge.points.count - 2]
            let angle = atan2(end.y - previous.y, end.x - previous.x)
            var arrow = Path(); arrow.move(to:end)
            arrow.addLine(to:CGPoint(x:end.x - cos(angle - 0.48) * 8,y:end.y - sin(angle - 0.48) * 8))
            arrow.addLine(to:CGPoint(x:end.x - cos(angle + 0.48) * 8,y:end.y - sin(angle + 0.48) * 8)); arrow.closeSubpath()
            context.fill(arrow, with:.color(color ?? (scheme == .dark ? Color(hex:0xD0D0D0) : Color(hex:0x404040))))
        }
    }
    private func drawDetails(_ item: ChartItem, color: Color, in context: inout GraphicsContext) {
        var path = Path()
        let rect = item.rect
        if item.node.tag == "declare" {
            path.move(to:CGPoint(x:rect.minX + 8,y:rect.minY)); path.addLine(to:CGPoint(x:rect.minX + 8,y:rect.maxY))
            path.move(to:CGPoint(x:rect.minX,y:rect.minY + 8)); path.addLine(to:CGPoint(x:rect.maxX,y:rect.minY + 8))
        } else if item.node.tag == "call" {
            for x in [rect.minX + 8, rect.maxX - 8] { path.move(to:CGPoint(x:x,y:rect.minY)); path.addLine(to:CGPoint(x:x,y:rect.maxY)) }
        }
        context.stroke(path, with:.color(color), lineWidth:0.8)
    }
}
