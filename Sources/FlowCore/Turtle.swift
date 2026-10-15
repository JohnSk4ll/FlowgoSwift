import Foundation

public struct TurtlePoint: Equatable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public struct TurtleSegment {
    public let start: TurtlePoint
    public let end: TurtlePoint
    public let color: String
}

public struct TurtleState {
    public var position = TurtlePoint(x: 0, y: 0)
    public var angle: Double = 90
    public var penColor = "black"
    public static let colors = ["black","gray","red","orange","yellow","green","teal","blue","violet","brown"]
    public static let ink: [String:String] = ["black":"#101010","gray":"#808080","red":"#e02030","orange":"#f07020","yellow":"#f0c020","green":"#30c080","teal":"#30c0e0","blue":"#2080e0","violet":"#a060c0","brown":"#c06c40"]
    public mutating func clear() { segments = []; position = TurtlePoint(x:0,y:0); angle = 90 }
    public mutating func setPen(_ color: String) { penColor = Self.colors.contains(color.lowercased()) ? color.lowercased() : "black" }
    public var segments: [TurtleSegment] = []
    public init() {}
    public mutating func forward(_ distance: Double, penDown: Bool) throws {
        let radians = angle * .pi / 180
        var next = TurtlePoint(x: position.x + cos(radians) * distance, y: position.y - sin(radians) * distance)
        guard next.x.isFinite, next.y.isFinite else { throw FlowError("Turtle coordinates are not finite.") }
        next.x = min(1_000_000,max(-1_000_000,next.x)); next.y = min(1_000_000,max(-1_000_000,next.y))
        if penDown {
            segments.append(TurtleSegment(start: position, end: next, color:penColor))
            if segments.count > 10_000 { segments.removeFirst() }
        }
        position = next
    }
    public mutating func turn(_ degrees: Double) throws {
        guard degrees.isFinite else { throw FlowError("Turtle angle is not finite.") }
        angle = (angle + degrees).truncatingRemainder(dividingBy: 360)
        if angle < 0 { angle += 360 }
    }
    public mutating func home() { position = TurtlePoint(x: 0, y: 0); angle = 90 }
    public var svg: String {
        let points = segments.flatMap { [$0.start, $0.end] } + [position]
        let minX = min(-50, points.map(\.x).min() ?? -50) - 15
        let minY = min(-50, points.map(\.y).min() ?? -50) - 15
        let maxX = max(50, points.map(\.x).max() ?? 50) + 15
        let maxY = max(50, points.map(\.y).max() ?? 50) + 15
        let paths = segments.map { "<path d=\"M \($0.start.x) \($0.start.y) L \($0.end.x) \($0.end.y)\" stroke=\"\(Self.ink[$0.color] ?? "#101010")\"/>" }.joined(separator: "\n")
        return """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="\(minX) \(minY) \(maxX - minX) \(maxY - minY)">
        <g fill="none" stroke="#2563eb" stroke-width="2" stroke-linecap="round">
        \(paths)
        </g>
        </svg>
        """
    }
}
