import Foundation

extension Element {
    public func freshCopy() -> Element {
        Element(tag,attributes,children.map { $0.freshCopy() })
    }
}

extension Program {
    @discardableResult public mutating func importFunctions(from source: Program) -> [String] {
        var names = Set(functions.map { FlowIdentifier.key($0["name"]) })
        var imported: [String] = []
        for function in source.functions where FlowIdentifier.key(function["name"]) != "main" {
            var copy = function.freshCopy()
            let original = copy["name"]
            var name = original, suffix = 2
            while names.contains(FlowIdentifier.key(name)) { name = original + String(suffix); suffix += 1 }
            copy["name"] = name
            names.insert(FlowIdentifier.key(name)); imported.append(name); root.children.append(copy)
        }
        return imported
    }
}
