import SwiftUI
import Foundation

struct ToolbarSVG {
    struct Shape {
        let path: Path
        let fill: String
        let stroke: String
        let width: CGFloat
        let round: Bool
    }

    static let names = ["open", "save", "run", "step", "pause", "stop", "speed", "functions", "zoomIn", "zoomOut", "appearance", "variables", "console", "source"]
    static let icons: [String: ToolbarSVG] = Dictionary(uniqueKeysWithValues:names.map { name in
        guard let url = Bundle.module.url(forResource:name,withExtension:"svg",subdirectory:"Icons"),
              let data = try? Data(contentsOf:url), let icon = ToolbarSVG(data:data) else {
            preconditionFailure("Cannot load toolbar SVG: \(name)")
        }
        return (name,icon)
    })

    static let palette: [String: (UInt32, UInt32)] = [
        "outline": (0x62666B, 0xA4A7AD), "green": (0x438955, 0x75CE92),
        "green-fill": (0x65C58B, 0x65C58B), "green-edge": (0x3A5A48, 0x9ADBAB),
        "red": (0xB05050, 0xE68080), "blue": (0x283C71, 0xA4BFF3),
        "cyan": (0x5289AA, 0x7FB7D6), "gray": (0x8A8E94, 0xA4A7AD),
        "paper": (0xF4F5F7, 0x31343A), "save": (0x137DBD, 0x388BC2),
        "save-edge": (0x16476C, 0x81B9DF), "folder": (0xFFF6A8, 0x857E36),
        "folder-front": (0xF7DB60, 0xCCAE54), "purple": (0xF0C8FF, 0x794B83),
        "purple-edge": (0x90669F, 0xCA98D5), "output": (0xD0FFD0, 0x286639),
        "input": (0xD0E0FF, 0x35547D)
    ]

    static let images: [String: (NSImage, NSImage)] = icons.mapValues { ($0.image(scheme:.light),$0.image(scheme:.dark)) }

    let size: CGSize
    let shapes: [Shape]

    init?(data: Data) {
        let delegate = SVGIconParser()
        let parser = XMLParser(data:data)
        parser.delegate = delegate
        guard parser.parse(), !delegate.invalid, !delegate.shapes.isEmpty else { return nil }
        size = delegate.size
        shapes = delegate.shapes
    }

    private static func color(_ paint: String, scheme: ColorScheme) -> CGColor? {
        guard paint != "none" else { return nil }
        let role = paint.replacingOccurrences(of:"var(--",with:"").replacingOccurrences(of:")",with:"")
        guard let values = palette[role] else { preconditionFailure("Unknown SVG paint: \(paint)") }
        let value = scheme == .dark ? values.1 : values.0
        return CGColor(srgbRed:CGFloat((value >> 16) & 255) / 255,green:CGFloat((value >> 8) & 255) / 255,blue:CGFloat(value & 255) / 255,alpha:1)
    }

    private func image(scheme: ColorScheme) -> NSImage {
        NSImage(size:CGSize(width:27,height:27),flipped:true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            defer { context.restoreGState() }
            context.translateBy(x:rect.minX,y:rect.minY)
            context.scaleBy(x:rect.width / size.width,y:rect.height / size.height)
            for shape in shapes {
                if let fill = Self.color(shape.fill,scheme:scheme) {
                    context.setFillColor(fill)
                    context.addPath(shape.path.cgPath)
                    context.fillPath()
                }
                if let stroke = Self.color(shape.stroke,scheme:scheme) {
                    context.setStrokeColor(stroke)
                    context.setLineWidth(shape.width)
                    context.setLineCap(shape.round ? .round : .butt)
                    context.setLineJoin(shape.round ? .round : .miter)
                    context.addPath(shape.path.cgPath)
                    context.strokePath()
                }
            }
            return true
        }
    }
}

private final class SVGIconParser: NSObject, XMLParserDelegate {
    var size = CGSize(width:32,height:32)
    var shapes: [ToolbarSVG.Shape] = []
    var invalid = false

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        func number(_ key: String, _ fallback: Double = 0) -> CGFloat { CGFloat(Double(attributes[key] ?? "") ?? fallback) }
        var path: Path
        switch name {
        case "svg":
            size = CGSize(width:number("width",32),height:number("height",32))
            invalid = size.width <= 0 || size.height <= 0
            return
        case "style", "title": return
        case "path":
            guard let parsed = Self.path(attributes["d"] ?? "") else { invalid = true; return }
            path = parsed
        case "rect":
            let rect = CGRect(x:number("x"),y:number("y"),width:number("width"),height:number("height"))
            path = Path(roundedRect:rect,cornerRadius:number("rx"))
        case "circle":
            let r = number("r")
            path = Path(ellipseIn:CGRect(x:number("cx") - r,y:number("cy") - r,width:r * 2,height:r * 2))
        default: invalid = true; return
        }
        let fill = attributes["fill"] ?? "none"
        let stroke = attributes["stroke"] ?? "none"
        for paint in [fill,stroke] where paint != "none" {
            let role = paint.replacingOccurrences(of:"var(--",with:"").replacingOccurrences(of:")",with:"")
            if ToolbarSVG.palette[role] == nil { invalid = true }
        }
        shapes.append(ToolbarSVG.Shape(path:path,fill:fill,stroke:stroke,width:number("stroke-width",1.5),round:attributes["stroke-linecap"] == "round"))
    }

    private static let tokens = try! NSRegularExpression(pattern:"[MLHVQCZ]|[-+]?(?:[0-9]*\\.)?[0-9]+(?:[eE][-+]?[0-9]+)?")

    static func path(_ data: String) -> Path? {
        let source = data as NSString
        let values = tokens.matches(in:data,range:NSRange(location:0,length:source.length)).map { source.substring(with:$0.range) }
        var index = 0
        var result = Path()
        func number() -> CGFloat? {
            guard index < values.count, let value = Double(values[index]) else { return nil }
            index += 1
            return CGFloat(value)
        }
        func point() -> CGPoint? {
            guard let x = number(), let y = number() else { return nil }
            return CGPoint(x:x,y:y)
        }
        while index < values.count {
            let command = values[index]
            index += 1
            switch command {
            case "M": guard let p = point() else { return nil }; result.move(to:p)
            case "L": guard let p = point() else { return nil }; result.addLine(to:p)
            case "H": guard let x = number(), let p = result.currentPoint else { return nil }; result.addLine(to:CGPoint(x:x,y:p.y))
            case "V": guard let y = number(), let p = result.currentPoint else { return nil }; result.addLine(to:CGPoint(x:p.x,y:y))
            case "Q": guard let c = point(), let p = point() else { return nil }; result.addQuadCurve(to:p,control:c)
            case "C": guard let c1 = point(), let c2 = point(), let p = point() else { return nil }; result.addCurve(to:p,control1:c1,control2:c2)
            case "Z": result.closeSubpath()
            default: return nil
            }
        }
        return result.isEmpty ? nil : result
    }
}
