import Foundation
import FlowCore

struct ChartSelection {
    static func rectangle(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(x:min(start.x,end.x),y:min(start.y,end.y),width:abs(end.x - start.x),height:abs(end.y - start.y))
    }

    static func roots(_ paths: Set<[Int]>) -> [[Int]] {
        paths.sorted { $0.lexicographicallyPrecedes($1) }.filter { path in
            !paths.contains { other in other.count < path.count && path.starts(with:other) }
        }
    }

    static func paths(in rectangle: CGRect, layout: ChartLayout) -> Set<[Int]> {
        Set(layout.items.filter {
            $0.path.count > 2 && $0.node.tag != "connector" && $0.rect.intersects(rectangle)
        }.map(\.path))
    }

    static func remove(_ paths: Set<[Int]>, from program: inout Program) {
        for path in roots(paths).reversed() {
            guard let index = path.last, path.count > 2,
                  let node = program.root.element(at:path),
                  !["body","parameters","parameter","then","else","function"].contains(node.tag) else { continue }
            program.root.update(at:Array(path.dropLast())) { parent in
                if parent.children.indices.contains(index) { parent.children.remove(at:index) }
            }
        }
    }
}
