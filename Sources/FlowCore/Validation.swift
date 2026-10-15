import Foundation

extension Program {
    public func validate() throws {
        var names = Set<String>()
        func identifier(_ name: String) throws { try FlowIdentifier.validate(name) }
        for function in functions {
            let name = function["name"]
            try identifier(name)
            guard names.insert(FlowIdentifier.key(name)).inserted else { throw FlowError("Duplicate function: \(name)") }
            guard ["none", "integer", "real", "string", "boolean"].contains(function["type"].lowercased()) else { throw FlowError("Invalid return type for \(name).") }
            guard let body = function.child("body"), let parameters = function.child("parameters") else { throw FlowError("\(name) must have parameters and a body.") }
            var parameterNames = Set<String>()
            for parameter in parameters.children {
                try identifier(parameter["name"])
                guard parameterNames.insert(FlowIdentifier.key(parameter["name"])).inserted else { throw FlowError("Duplicate parameter: \(parameter["name"])") }
                guard ["integer", "real", "string", "boolean"].contains(parameter["type"].lowercased()) else { throw FlowError("Invalid parameter type: \(parameter["type"])") }
            }
            if FlowIdentifier.key(name) == "main" {
                guard parameters.children.isEmpty, function["type"].lowercased() == "none" else { throw FlowError("Main must have no parameters and return None.") }
            } else if function["type"].lowercased() != "none" { try identifier(function["variable"]) }
            func validate(_ node: Element) throws {
                switch node.tag {
                case "assign", "input", "read":
                    let target = try Expression.parse(node["variable"])
                    switch target {
                    case .variable, .index(.variable, _): break
                    default: throw FlowError("Invalid assignment target: \(node["variable"])")
                    }
                case "declare":
                    guard ["integer", "real", "string", "boolean"].contains(node["type"].lowercased()) else { throw FlowError("Invalid variable type: \(node["type"])") }
                    let names = node["name"].isEmpty ? node["variables"] : node["name"]
                    for raw in names.split(separator: ",", omittingEmptySubsequences: false) {
                        let name = String(raw.prefix { $0 != "[" }).trimmingCharacters(in: .whitespaces)
                        try identifier(name)
                    }
                case "for": try identifier(node["variable"])
                case "if":
                    guard node.child("then") != nil, node.child("else") != nil else { throw FlowError("If must have Then and Else blocks.") }
                case "body", "then", "else", "while", "do", "output", "call", "comment", "breakpoint", "open", "close", "write", "forward", "turn", "home", "clear", "pen": break
                default: throw FlowError("Unsupported statement: \(node.tag)")
                }
                for key in ["expression", "start", "end", "step", "size"] where !node[key].isEmpty { _ = try Expression.parse(node[key]) }
                for key in requiredFields(node.tag) where node[key].isEmpty { throw FlowError("\(node.tag.capitalized) needs a \(key).") }
                for child in node.children { try validate(child) }
            }
            try validate(body)
        }
    }
    private func requiredFields(_ tag: String) -> [String] {
        switch tag {
        case "assign": return ["variable", "expression"]
        case "input", "read": return ["variable"]
        case "output", "call", "if", "while", "do", "open", "write", "forward", "turn": return ["expression"]
        case "for": return ["variable", "start", "end"]
        default: return []
        }
    }
}
