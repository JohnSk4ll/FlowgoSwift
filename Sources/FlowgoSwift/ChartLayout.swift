import AppKit
import FlowCore

struct ChartItem: Identifiable {
    let node: Element
    let path: [Int]
    var rect: CGRect
    var id: UUID { node.id }
}

struct ChartEdge {
    var points: [CGPoint]
    var arrow = true
}

struct ChartInsertion: Identifiable {
    let path: [Int]
    let index: Int
    var point: CGPoint
    var points: [CGPoint] = []
    var id: String { path.map(String.init).joined(separator: ".") + ":\(index)" }
}

struct ChartLabel {
    let text: String
    var point: CGPoint
}

struct ChartFragment {
    var items: [ChartItem] = []
    var edges: [ChartEdge] = []
    var insertions: [ChartInsertion] = []
    var labels: [ChartLabel] = []
    var exitPoints: [CGPoint] = []
    var height: CGFloat = 0
    var left: CGFloat = 0
    var right: CGFloat = 0
    mutating func include(_ other: ChartFragment, x: CGFloat = 0, y: CGFloat = 0) {
        items += other.items.map { var item = $0; item.rect = item.rect.offsetBy(dx: x, dy: y); return item }
        edges += other.edges.map { edge in ChartEdge(points: edge.points.map { CGPoint(x: $0.x + x, y: $0.y + y) }, arrow: edge.arrow) }
        insertions += other.insertions.map { var item = $0; item.point.x += x; item.point.y += y; item.points = item.points.map { CGPoint(x:$0.x + x,y:$0.y + y) }; return item }
        labels += other.labels.map { var label = $0; label.point.x += x; label.point.y += y; return label }
        left = max(left, other.left - x); right = max(right, other.right + x)
    }
}

struct ChartLayout {
    var items: [ChartItem]
    var edges: [ChartEdge]
    var insertions: [ChartInsertion]
    var labels: [ChartLabel]
    var size: CGSize
    static let font = NSFont(name: "Arial", size: 13) ?? NSFont.systemFont(ofSize: 13)
    static let spacing: CGFloat = 26

    init(function: Element, path: [Int]) {
        let parameters = function.child("parameters")?.children.map(\.label).joined(separator:", ") ?? ""
        let caption = parameters.isEmpty ? function["name"] : function["name"] + "\n(" + parameters + ")"
        var start = Element("terminal", ["caption":caption]); start.id = function.id
        let finish = Element("terminal", ["caption":function["type"].lowercased() == "none" ? "End" : "Return \(function["type"]) \(function["variable"])"])
        let head = Self.simple(start, path: path)
        let foot = Self.simple(finish, path: path)
        let bodyIndex = function.children.firstIndex { $0.tag == "body" } ?? 0
        let body = Self.block(function.children.indices.contains(bodyIndex) ? function.children[bodyIndex] : Element("body"), path: path + [bodyIndex])
        var fragment = head
        let top = head.height
        fragment.include(body, y: top)
        let bottom = top + body.height
        fragment.include(foot, y: bottom)
        let x = fragment.left + 22, y: CGFloat = 16
        items = fragment.items.map { var item = $0; item.rect = item.rect.offsetBy(dx: x, dy: y); return item }
        edges = fragment.edges.map { edge in ChartEdge(points: edge.points.map { CGPoint(x: $0.x + x, y: $0.y + y) }, arrow: edge.arrow) }
        insertions = fragment.insertions.map { var item = $0; item.point.x += x; item.point.y += y; item.points = item.points.map { CGPoint(x:$0.x + x,y:$0.y + y) }; return item }
        labels = fragment.labels.map { var item = $0; item.point.x += x; item.point.y += y; return item }
        size = CGSize(width: fragment.left + fragment.right + 44, height: bottom + foot.height + 32)
    }
    static func caption(_ node: Element) -> String {
        if node.tag == "terminal" { return node["caption"] }
        if node.tag == "input" { return "Input " + node["variable"] }
        if node.tag == "output" { return "Output " + node["expression"] + (node["newline"].lowercased() == "false" ? " …" : "") }
        if node.tag == "declare" {
            let names = node["name"].isEmpty ? node["variables"] : node["name"]
            return node["array"].lowercased() == "true" ? "Declare \(node["type"]) Array \(names) [\(node["size"])]" : "Declare \(node["type"]) \(names)"
        }
        if node.tag == "for" {
            let step = node["step"].isEmpty || node["step"] == "1" ? "" : " step \(node["step"])"
            return "For " + node.label + (node["direction"].lowercased() == "dec" ? " decreasing" : "") + step
        }
        if node.tag == "breakpoint" { return node["always"].lowercased() == "false" ? "Breakpoint " + node["expression"] : "Breakpoint" }
        if node.tag == "pen" { return "Pen " + node["color"].capitalized }
        if node.tag == "open" { return "Open \(node["expression"]) \(node["mode"].lowercased() == "write" ? "write" : "read")" }
        if node.tag == "close" { return "Close \(node["mode"].lowercased() == "write" ? "write" : "read")" }
        if node.tag == "read" { return "Read " + node["variable"] }
        if node.tag == "write" { return "Write " + node["expression"] }
        if node.tag == "forward" { return node.label }
        if node.tag == "turn" { return node.label }
        if ["assign","call","if","while","do","comment"].contains(node.tag) { return node.tag.capitalized + " " + node.label }
        return node.label
    }
    static func dimensions(_ node: Element) -> CGSize {
        if node.tag == "connector" { return CGSize(width: 16, height: 16) }
        let text = caption(node) as NSString
        let measured = text.boundingRect(with: CGSize(width: node.tag == "comment" ? 230 : 220, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font:font])
        let width = ceil(measured.width), height = ceil(measured.height)
        switch node.tag {
        case "terminal": return CGSize(width: max(96, width + 44), height: max(34, height + 16))
        case "if": return CGSize(width: max(96, width * 1.65 + 36), height: max(60, height * 1.8 + 20))
        case "for", "while", "do": return CGSize(width: max(102, width + 42), height: max(34, height + 16))
        case "input", "output", "read", "write": return CGSize(width: max(88, width + 44), height: max(34, height + 16))
        case "declare": return CGSize(width: max(84, width + 34), height: max(40, height + 24))
        case "comment": return CGSize(width: max(100, width + 28), height: max(42, height + 18))
        default: return CGSize(width: max(76, width + 28), height: max(34, height + 16))
        }
    }
    private static func simple(_ node: Element, path: [Int]) -> ChartFragment {
        let size = dimensions(node)
        if node.tag == "comment" {
            return ChartFragment(items: [ChartItem(node: node, path: path, rect: CGRect(x: 30, y: 0, width: size.width, height: size.height))],
                                 edges: [ChartEdge(points: [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: size.height)], arrow: false),
                                         ChartEdge(points: [CGPoint(x: 0, y: size.height / 2), CGPoint(x: 30, y: size.height / 2)], arrow: false)],
                                 exitPoints:[CGPoint(x:0,y:0),CGPoint(x:0,y:size.height)], height: size.height, left: 0, right: size.width + 30)
        }
        return ChartFragment(items: [ChartItem(node: node, path: path, rect: CGRect(x: -size.width / 2, y: 0, width: size.width, height: size.height))], height: size.height, left: size.width / 2, right: size.width / 2)
    }
    private static func block(_ node: Element, path: [Int]) -> ChartFragment {
        var result = ChartFragment()
        var continuation: [CGPoint] = []
        for (index, child) in node.children.enumerated() {
            result.edges.append(ChartEdge(points: [CGPoint(x: 0, y: result.height), CGPoint(x: 0, y: result.height + spacing)]))
            result.insertions.append(ChartInsertion(path: path, index: index, point: CGPoint(x: 0, y: result.height + spacing / 2), points:continuation + [CGPoint(x:0,y:result.height),CGPoint(x:0,y:result.height + spacing)]))
            result.height += spacing
            let item = statement(child, path: path + [index])
            continuation = item.exitPoints.map { CGPoint(x:$0.x,y:$0.y + result.height) }
            result.include(item, y: result.height); result.height += item.height
        }
        result.edges.append(ChartEdge(points: [CGPoint(x: 0, y: result.height), CGPoint(x: 0, y: result.height + spacing)]))
        result.insertions.append(ChartInsertion(path: path, index: node.children.count, point: CGPoint(x: 0, y: result.height + spacing / 2), points:continuation + [CGPoint(x:0,y:result.height),CGPoint(x:0,y:result.height + spacing)]))
        result.height += spacing
        return result
    }
    private static func statement(_ node: Element, path: [Int]) -> ChartFragment {
        if node.tag == "if" { return conditional(node, path: path) }
        if ["for", "while"].contains(node.tag) { return loop(node, path: path) }
        if node.tag == "do" { return doLoop(node, path: path) }
        return simple(node, path: path)
    }
    private static func conditional(_ node: Element, path: [Int]) -> ChartFragment {
        var result = simple(node, path: path)
        let head = result.items[0].rect
        let thenIndex = node.children.firstIndex { $0.tag == "then" } ?? 0
        let elseIndex = node.children.firstIndex { $0.tag == "else" } ?? 1
        var yes = block(node.children.indices.contains(thenIndex) ? node.children[thenIndex] : Element("then"), path: path + [thenIndex])
        var no = block(node.children.indices.contains(elseIndex) ? node.children[elseIndex] : Element("else"), path: path + [elseIndex])
        let rx = max(head.width / 2 + 30, yes.left + 35)
        let lx = -max(head.width / 2 + 30, no.right + 35)
        let top = head.midY
        let mergeY = top + max(yes.height, no.height) + spacing
        yes.insertions[0].points.insert(CGPoint(x:head.maxX - rx,y:0),at:0)
        no.insertions[0].points.insert(CGPoint(x:head.minX - lx,y:0),at:0)
        yes.insertions[yes.insertions.count - 1].points += [CGPoint(x:0,y:mergeY - top),CGPoint(x:8 - rx,y:mergeY - top)]
        no.insertions[no.insertions.count - 1].points += [CGPoint(x:0,y:mergeY - top),CGPoint(x:-8 - lx,y:mergeY - top)]
        result.include(yes, x: rx, y: top); result.include(no, x: lx, y: top)
        result.edges += [
            ChartEdge(points: [CGPoint(x: head.maxX, y: top), CGPoint(x: rx, y: top)], arrow: false),
            ChartEdge(points: [CGPoint(x: head.minX, y: top), CGPoint(x: lx, y: top)], arrow: false),
            ChartEdge(points: [CGPoint(x: rx, y: top + yes.height), CGPoint(x: rx, y: mergeY), CGPoint(x: 8, y: mergeY)]),
            ChartEdge(points: [CGPoint(x: lx, y: top + no.height), CGPoint(x: lx, y: mergeY), CGPoint(x: -8, y: mergeY)])
        ]
        result.labels += [ChartLabel(text: "True", point: CGPoint(x: head.maxX + 27, y: top - 14)), ChartLabel(text: "False", point: CGPoint(x: head.minX - 27, y: top - 14))]
        let join = simple(Element("connector", ["kind":"if"]), path: path)
        result.include(join, y: mergeY - 8); result.height = mergeY + 8
        return result
    }
    private static func loop(_ node: Element, path: [Int]) -> ChartFragment {
        var result = simple(node, path: path)
        let head = result.items[0].rect
        var body = block(node, path: path)
        let bx = max(head.maxX + 35, body.left + 45)
        let top = head.midY
        let returnY = top + body.height
        body.insertions[0].points.insert(CGPoint(x:head.maxX - bx,y:0),at:0)
        body.insertions[body.insertions.count - 1].points += [CGPoint(x:18 - bx,y:body.height),CGPoint(x:18 - bx,y:head.maxY - top)]
        result.include(body, x: bx, y: top)
        result.edges += [
            ChartEdge(points: [CGPoint(x: head.maxX, y: top), CGPoint(x: bx, y: top)], arrow: false),
            ChartEdge(points: [CGPoint(x: bx, y: returnY), CGPoint(x: 18, y: returnY), CGPoint(x: 18, y: head.maxY)]),
            ChartEdge(points: [CGPoint(x: 0, y: head.maxY), CGPoint(x: 0, y: returnY + 10)], arrow: false)
        ]
        result.labels += [ChartLabel(text: node.tag == "for" ? "Next" : "True", point: CGPoint(x: head.maxX + 25, y: top - 14)),
                          ChartLabel(text: node.tag == "for" ? "Done" : "False", point: CGPoint(x: -25, y: head.maxY + 14))]
        result.exitPoints = [CGPoint(x:0,y:head.maxY),CGPoint(x:0,y:returnY + 10)]
        result.height = returnY + 10
        return result
    }
    private static func doLoop(_ node: Element, path: [Int]) -> ChartFragment {
        var body = block(node, path: path)
        let size = dimensions(node)
        let bx = max(size.width / 2 + 35, body.left + 45)
        var result = simple(Element("connector", ["kind":"loop"]), path: path)
        let top: CGFloat = 8
        let headY = top + body.height
        body.insertions[0].points.insert(CGPoint(x:8 - bx,y:0),at:0)
        body.insertions[body.insertions.count - 1].points += [CGPoint(x:0,y:body.height + size.height / 2),CGPoint(x:size.width / 2 - bx,y:body.height + size.height / 2)]
        result.include(body, x: bx, y: top)
        result.include(simple(node, path: path), y: headY)
        result.edges += [
            ChartEdge(points: [CGPoint(x: 8, y: top), CGPoint(x: bx, y: top)], arrow: false),
            ChartEdge(points: [CGPoint(x: bx, y: headY), CGPoint(x: bx, y: headY + size.height / 2), CGPoint(x: size.width / 2, y: headY + size.height / 2)]),
            ChartEdge(points: [CGPoint(x: 0, y: headY), CGPoint(x: 0, y: 16)])
        ]
        result.labels += [ChartLabel(text: "True", point: CGPoint(x: -24, y: headY - 14)), ChartLabel(text: "False", point: CGPoint(x: -24, y: headY + size.height + 14))]
        result.height = headY + size.height
        return result
    }
}
