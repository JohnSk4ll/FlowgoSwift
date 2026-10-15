import Foundation

public enum FlowIdentifier {
    public static let reservedNames: Set<String> = ["abs", "sqrt", "sin", "cos", "tan", "arcsin", "arccos", "arctan", "sinh", "cosh", "tanh", "arcsinh", "arccosh", "arctanh", "log", "ln", "log10", "sgn", "int", "len", "char", "random", "tostring", "tointeger", "toreal", "tochar", "tocode", "tofixed", "eof", "turtlex", "turtley", "true", "false", "pi", "π", "newline", "and", "or", "not", "mod", "integer", "real", "string", "boolean"]

    public static func validate(_ name: String) throws {
        guard isValid(name), !reservedNames.contains(key(name)) else { throw FlowError("Invalid or reserved identifier: \(name)") }
    }

    public static func key(_ value: String) -> String {
        value.lowercased(with: Locale(identifier: "en_US"))
    }

    public static func isValid(_ value: String) -> Bool {
        let scalars = Array(value.unicodeScalars)
        guard let first = scalars.first, scalars.allSatisfy({ $0.value <= 0xFFFF }) else { return false }
        func letter(_ scalar: Unicode.Scalar) -> Bool {
            switch scalar.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter: return true
            default: return false
            }
        }
        func number(_ scalar: Unicode.Scalar) -> Bool {
            switch scalar.properties.generalCategory {
            case .decimalNumber, .letterNumber, .otherNumber: return true
            default: return false
            }
        }
        return letter(first) && scalars.dropFirst().allSatisfy { letter($0) || number($0) }
    }
}

public struct FlowError: Error, LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct Element: Equatable, Identifiable {
    public var id = UUID()
    public var tag: String
    public var attributes: [String: String]
    public var children: [Element]
    public init(_ tag: String, _ attributes: [String: String] = [:], _ children: [Element] = []) {
        self.tag = tag; self.attributes = attributes; self.children = children
    }
    public subscript(_ key: String) -> String {
        get { attributes[key] ?? "" }
        set { attributes[key] = newValue }
    }
    public func child(_ tag: String) -> Element? { children.first { $0.tag == tag } }
    public func element(at path: [Int]) -> Element? {
        guard let first = path.first else { return self }
        guard children.indices.contains(first) else { return nil }
        return children[first].element(at: Array(path.dropFirst()))
    }
    public mutating func update(at path: [Int], _ body: (inout Element) -> Void) {
        guard let first = path.first else { body(&self); return }
        guard children.indices.contains(first) else { return }
        children[first].update(at: Array(path.dropFirst()), body)
    }
    public var label: String {
        switch tag {
        case "function": return self["name"]
        case "parameter": return "\(self["type"])\(self["array"].lowercased() == "true" ? " Array" : "") \(self["name"])"
        case "declare": return "\(self["type"]) \(self["name"].isEmpty ? self["variables"] : self["name"])"
        case "assign": return "\(self["variable"]) = \(self["expression"])"
        case "read": return "Read \(self["variable"])"
        case "input": return "Input \(self["variable"])"
        case "output": return "Output \(self["expression"])"
        case "forward": return "\(self["pen"].lowercased() == "up" ? "Move" : "Draw") \(self["expression"])"
        case "turn": return "Turn \(self["rotate"].lowercased() == "left" ? "left" : "right") \(self["expression"])"
        case "for": return "\(self["variable"]) = \(self["start"]) to \(self["end"])"
        case "comment": return self["text"]
        case "if", "while", "do", "call", "open", "write": return self["expression"]
        default: return tag.capitalized
        }
    }
    public static func statement(_ tag: String) -> Element {
        switch tag {
        case "declare": return Element(tag, ["name":"x", "type":"Integer", "array":"False", "size":""])
        case "assign": return Element(tag, ["variable":"x", "expression":"0"])
        case "input": return Element(tag, ["variable":"x"])
        case "output": return Element(tag, ["expression":"\"Hello\"", "newline":"True"])
        case "if": return Element(tag, ["expression":"True"], [Element("then"), Element("else")])
        case "while", "do": return Element(tag, ["expression":"False"])
        case "for": return Element(tag, ["variable":"i", "start":"0", "end":"9", "step":"1", "direction":"inc"])
        case "forward": return Element(tag, ["expression":"100", "pen":"down"])
        case "turn": return Element(tag, ["expression":"90", "rotate":"right"])
        case "pen": return Element(tag,["color":"black"])
        case "home", "clear": return Element(tag)
        case "open": return Element(tag, ["expression":"\"data.txt\"", "mode":"read"])
        case "close": return Element(tag, ["mode":"read"])
        case "read": return Element(tag, ["variable":"x"])
        case "write": return Element(tag, ["expression":"x"])
        case "breakpoint": return Element(tag, ["always":"True", "expression":"True"])
        case "call": return Element(tag, ["expression":"MyFunction()"])
        default: return Element("comment", ["text":"Comment"])
        }
    }
}

public struct Program: Equatable {
    public var root: Element
    public init(root: Element) { self.root = root }
    public init() {
        root = Element("flowgorithm", ["fileversion":"4.2"], [
            Element("attributes", [:], [Element("attribute", ["name":"name", "value":"Untitled"])]),
            Element("function", ["name":"Main", "type":"None", "variable":""], [Element("parameters"), Element("body")])
        ])
    }
    public var functions: [Element] { root.children.filter { $0.tag == "function" } }
    public init(data: Data) throws {
        let parser = XMLParser(data: data)
        let delegate = ProgramParser()
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), let root = delegate.root else {
            throw FlowError(parser.parserError?.localizedDescription ?? "Invalid XML")
        }
        guard root.tag == "flowgorithm", root.children.contains(where: { $0.tag == "function" && FlowIdentifier.key($0["name"]) == "main" }) else {
            throw FlowError("The document must contain a flowgorithm root and a Main function.")
        }
        self.root = root
    }
    public var xml: String {
        var savedRoot = root
        let sourceVersion = savedRoot["fileversion"]
        let originalVersion = fileVersionRank(sourceVersion)
        let requiredVersion = minimumFileVersion(root)
        if originalVersion != 0 || sourceVersion.isEmpty { savedRoot["fileversion"] = fileVersionText(max(originalVersion,requiredVersion)) }
        return "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n" + serialize(savedRoot, depth: 0)
    }
    private func fileVersionRank(_ version: String) -> Int {
        ["1.0":100,"2.0":200,"2.6":206,"2.9":209,"2.11":211,"3.0":300,"4.0":400,"4.2":420][version] ?? 0
    }
    private func fileVersionText(_ rank: Int) -> String {
        [100:"1.0",200:"2.0",206:"2.6",209:"2.9",211:"2.11",300:"3.0",400:"4.0",420:"4.2"][rank] ?? "4.2"
    }
    private func minimumFileVersion(_ element: Element) -> Int {
        var version = 100
        func inspect(_ node: Element) {
            if ["breakpoint","forward","turn","home","open","close","read","write"].contains(node.tag) { version = max(version,300) }
            if node.tag == "clear" { version = max(version,400) }
            if node.tag == "pen" { version = max(version,420) }
            if node.tag == "output", node["newline"].lowercased() == "false" { version = max(version,209) }
            for child in node.children { inspect(child) }
        }
        inspect(element)
        return version
    }
    private func serialize(_ element: Element, depth: Int) -> String {
        let indent = String(repeating: "    ", count: depth)
        let attrs = element.attributes.keys.sorted().map { " \($0)=\"\(escape(element[$0]))\"" }.joined()
        if element.children.isEmpty { return "\(indent)<\(element.tag)\(attrs)/>\n" }
        return "\(indent)<\(element.tag)\(attrs)>\n" + element.children.map { serialize($0, depth: depth + 1) }.joined() + "\(indent)</\(element.tag)>\n"
    }
    private func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\r", with: "&#13;").replacingOccurrences(of: "\n", with: "&#10;")
            .replacingOccurrences(of: "\t", with: "&#9;")
    }
}

private final class ProgramParser: NSObject, XMLParserDelegate {
    var stack: [Element] = []
    var root: Element?
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        stack.append(Element(name.lowercased(), attributes))
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard let node = stack.popLast() else { return }
        if stack.isEmpty { root = node } else { stack[stack.count - 1].children.append(node) }
    }
}
