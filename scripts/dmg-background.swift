import AppKit

let canvas = NSSize(width: 760, height: 500)
let image = NSImage(size: canvas)
image.lockFocus()
let bounds = NSRect(origin: .zero, size: canvas)
NSColor(white: 0.10, alpha: 1).setFill()
bounds.fill()
let panel = NSBezierPath(roundedRect: NSRect(x: 65, y: 155, width: 630, height: 225), xRadius: 32, yRadius: 32)
NSColor(white: 0.84, alpha: 1).setFill()
panel.fill()
NSColor(white: 0.92, alpha: 1).setStroke()
panel.lineWidth = 1
panel.stroke()
func text(_ value: String, y: CGFloat, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat = 1) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    (value as NSString).draw(in: NSRect(x: 30, y: y, width: 700, height: size + 12), withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: NSColor.white.withAlphaComponent(alpha), .paragraphStyle: paragraph])
}
text("FlowgoSwift", y: 420, size: 32, weight: .semibold)
text("Drag the app into Applications to install.", y: 390, size: 15, weight: .regular, alpha: 0.78)
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 342, y: 275))
arrow.line(to: NSPoint(x: 417, y: 275))
arrow.move(to: NSPoint(x: 400, y: 291))
arrow.line(to: NSPoint(x: 418, y: 275))
arrow.line(to: NSPoint(x: 400, y: 259))
arrow.lineWidth = 5
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
NSColor(white: 0.22, alpha: 1).setStroke()
arrow.stroke()
text("Enjoy the true native experience.", y: 110, size: 24, weight: .medium)
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
