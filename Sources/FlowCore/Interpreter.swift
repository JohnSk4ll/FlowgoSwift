import Foundation

public struct Variable {
    public let name: String
    public let type: String
    public var value: Value
}

public struct StackFrame {
    public let name: String
    public let variables: [Variable]
    public let parameterNames: Set<String>
}

public struct Trace {
    public let nodeID: UUID
    public let function: String
    public let depth: Int
    public let breakpoint: Bool
    public let variables: [Variable]
}

private final class Frame {
    let name: String
    var parameterNames = Set<String>()
    var scopes: [[String: Variable]] = [[:]]
    var variables: [String: Variable] { scopes.reduce(into: [:]) { $0.merge($1) { _, new in new } } }
    init(_ name: String) { self.name = name }
}

public final class Interpreter {
    public let program: Program
    public var input: (String, String) throws -> String = { _, _ in readLine() ?? "" }
    public var output: (String) -> Void = { print($0, terminator: "") }
    public var breakpointsEnabled: () -> Bool = { true }
    public var trace: (Trace) throws -> Void = { _ in }
    public var instructionLimit = 1_000_000
    public var recursionLimit = 128
    public var baseDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    public var drawing: (TurtleState) -> Void = { _ in }
    public private(set) var turtle = TurtleState()
    private var readLines: [String]?
    private var readPosition = 0
    private var writer: FileHandle?
    private var remaining = 0
    private var frames: [Frame] = []
    private var cache: [String: Expression] = [:]
    private var lastNode: Element?
    public init(_ program: Program) { self.program = program }
    public func run() throws {
        try program.validate()
        remaining = instructionLimit; frames = []; lastNode = nil; turtle = TurtleState()
        readLines = nil; readPosition = 0
        defer { try? writer?.close(); writer = nil; readLines = nil }
        do { _ = try call("Main", []) }
        catch let error as FlowError {
            let context = lastNode.map { "\($0.tag.capitalized): \($0.label)\n" } ?? ""
            throw FlowError(context + error.message)
        }
    }
    public var callStack: [StackFrame] {
        frames.map { StackFrame(name:$0.name,variables:$0.variables.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },parameterNames:$0.parameterNames) }
    }
    private var frame: Frame { frames[frames.count - 1] }
    private func tick(_ node: Element) throws {
        remaining -= 1
        guard remaining >= 0 else { throw FlowError("Execution limit reached. Check for an infinite loop.") }
        lastNode = node
        let shouldBreak = try node.tag == "breakpoint" && breakpointsEnabled() && (node["always"].lowercased() != "false" || (try expression(node["expression"]).bool()))
        try trace(Trace(nodeID: node.id, function: frame.name, depth: frames.count, breakpoint: shouldBreak,
                        variables: frame.variables.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }))
    }
    private func expression(_ source: String) throws -> Value {
        let parsed: Expression
        if let stored = cache[source] { parsed = stored }
        else { parsed = try Expression.parse(source); cache[source] = parsed }
        return try evaluate(parsed)
    }
    private func lookup(_ name: String) throws -> Variable {
        guard let variable = frame.variables[FlowIdentifier.key(name)] else { throw FlowError("Undeclared variable: \(name)") }
        return variable
    }
    private func subscriptIndex(_ value: Value, _ array: ArrayValue) throws -> Int {
        let number = try value.number()
        let i = try value.integer()
        guard number.isFinite, i >= 0, i < array.values.count else { throw FlowError("Array index \(value) is out of bounds (size \(array.values.count)).") }
        return Int(i)
    }
    private func assign(_ target: String, value: Value) throws {
        try assign(Expression.parse(target), value: value)
    }
    private func assign(_ target: Expression, value: Value) throws {
        switch target {
        case .variable(let name):
            var variable = try lookup(name)
            guard case .array = variable.value else {
                variable.value = try value.converted(to: variable.type)
                let key = FlowIdentifier.key(name)
                if let index = frame.scopes.indices.reversed().first(where: { frame.scopes[$0][key] != nil }) { frame.scopes[index][key] = variable }; return
            }
            throw FlowError("Assign an array element, rather than the whole array.")
        case .index(let base, let index):
            guard case .array(let array) = try evaluate(base) else { throw FlowError("Subscript requires an array.") }
            let i = try subscriptIndex(evaluate(index), array)
            array.values[i] = try value.converted(to: array.type)
        default: throw FlowError("Invalid assignment target.")
        }
    }
    private func execute(_ nodes: [Element], scoped: Bool = true) throws {
        if scoped { frame.scopes.append([:]) }
        defer { if scoped { frame.scopes.removeLast() } }
        for node in nodes {
            try tick(node)
            switch node.tag {
            case "comment": break
            case "declare":
                let names = node["name"].isEmpty ? node["variables"] : node["name"]
                for raw in names.split(separator: ",") {
                    let entry = raw.trimmingCharacters(in: .whitespaces)
                    let name = String(entry.prefix { $0 != "[" }).trimmingCharacters(in: .whitespaces)
                    guard FlowIdentifier.isValid(name) else { throw FlowError("Invalid variable name: \(name)") }
                    let nameKey = FlowIdentifier.key(name)
                    guard frame.variables[nameKey] == nil else { throw FlowError("Variable already declared: \(name)") }
                    guard node["type"].lowercased() != "none" else { throw FlowError("A variable cannot have type None.") }
                    let initial = try Value.initial(node["type"])
                    var value = initial
                    if node["array"].lowercased() == "true" || entry.contains("[") {
                        var size = node["size"]
                        if size.isEmpty, let left = entry.firstIndex(of: "["), let right = entry.lastIndex(of: "]") { size = String(entry[entry.index(after: left)..<right]) }
                        let sizeValue = try expression(size)
                        let count = try sizeValue.integer()
                        guard count > 0, count <= 1_000_000 else { throw FlowError("Invalid array size.") }
                        value = .array(ArrayValue(Array(repeating: initial, count: Int(count)), type: node["type"]))
                    }
                    frame.scopes[frame.scopes.count - 1][nameKey] = Variable(name: name, type: node["type"], value: value)
                }
            case "assign": try assign(node["variable"], value: expression(node["expression"]))
            case "output":
                let value = try expression(node["expression"])
                output(value.description + (node["newline"].lowercased() == "false" ? "" : "\n"))
            case "input":
                let target = try Expression.parse(node["variable"])
                let current = try reference(target)
                let type = try inputType(current)
                let text = try input(node["variable"], type)
                let value = try Self.parseInput(text, type: type)
                try assign(target, value: value)
            case "if":
                let branch = try expression(node["expression"]).bool() ? "then" : "else"
                try execute(node.child(branch)?.children ?? [])
            case "while":
                while try expression(node["expression"]).bool() {
                    try execute(node.children); try tick(node)
                }
            case "do":
                repeat { try execute(node.children); try tick(node) } while try expression(node["expression"]).bool()
            case "for":
                let start = try expression(node["start"]).number()
                _ = try expression(node["end"]).number()
                let step = try expression(node["step"].isEmpty ? "1" : node["step"]).number()
                guard step.isFinite, step > 0, start.isFinite else { throw FlowError("For step must be a positive number.") }
                let delta = node["direction"].lowercased() == "dec" ? -step : step
                try assign(node["variable"], value: .real(start))
                while true {
                    let current = try expression(node["variable"]).number()
                    let end = try expression(node["end"]).number()
                    if delta > 0 ? current > end : current < end { break }
                    try execute(node.children)
                    let updated = try expression(node["variable"]).number()
                    let amount = try expression(node["step"].isEmpty ? "1" : node["step"]).number()
                    guard amount.isFinite, amount > 0 else { throw FlowError("For step must be positive.") }
                    let next = updated + (delta > 0 ? amount : -amount)
                    guard next != updated else { throw FlowError("For step does not advance the loop variable.") }
                    try assign(node["variable"], value: .real(next)); try tick(node)
                }
            case "call": _ = try expression(node["expression"])
            case "breakpoint": break
            case "open":
                let path = try expression(node["expression"]).text()
                let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : baseDirectory.appendingPathComponent(path)
                if node["mode"].lowercased() == "write" {
                    guard writer == nil else { throw FlowError("A file is already open for writing.") }
                    try Data().write(to: url)
                    writer = try FileHandle(forWritingTo: url)
                } else {
                    guard readLines == nil else { throw FlowError("A file is already open for reading.") }
                    let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
                    guard size <= 16_000_000 else { throw FlowError("The input file exceeds 16 MB.") }
                    var content = try String(contentsOf: url, encoding: .utf8)
                    if content.hasPrefix("\u{feff}") { content.removeFirst() }
                    content = content.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
                    var lines = content.components(separatedBy: "\n")
                    if lines.last == "" { lines.removeLast() }
                    readLines = lines; readPosition = 0
                }
            case "close":
                if node["mode"].lowercased() == "write" { try writer?.close(); writer = nil }
                else { readLines = nil; readPosition = 0 }
            case "read":
                guard let lines = readLines else { throw FlowError("Open a file for reading first.") }
                guard readPosition < lines.count else { throw FlowError("Read past the end of the file.") }
                let target = try Expression.parse(node["variable"])
                let type = try inputType(reference(target))
                let value = try Self.parseInput(lines[readPosition], type: type)
                readPosition += 1; try assign(target, value: value)
            case "write":
                guard let writer else { throw FlowError("Open a file for writing first.") }
                let value = try expression(node["expression"])
                if case .array = value { throw FlowError("Write requires a scalar value.") }
                try writer.write(contentsOf: Data((value.description + "\n").utf8))
            case "forward":
                try turtle.forward(expression(node["expression"]).number(), penDown: node["pen"].lowercased() != "up")
                drawing(turtle)
            case "turn":
                let degrees = try expression(node["expression"]).number()
                try turtle.turn(node["rotate"].lowercased() == "left" ? degrees : -degrees)
                drawing(turtle)
            case "pen": turtle.setPen(node["color"]); drawing(turtle)
            case "home": turtle.home(); drawing(turtle)
            case "clear": turtle.clear(); drawing(turtle)
            default: throw FlowError("Unsupported statement: \(node.tag). This program was not executed beyond this point.")
            }
        }
    }
    private func call(_ name: String, _ arguments: [Value]) throws -> Value {
        if let result = try builtin(name, arguments) { return result }
        guard let function = program.functions.first(where: { FlowIdentifier.key($0["name"]) == FlowIdentifier.key(name) }) else { throw FlowError("Unknown function: \(name)") }
        guard frames.count < recursionLimit else { throw FlowError("Recursion limit reached.") }
        let parameters = function.child("parameters")?.children ?? []
        guard parameters.count == arguments.count else { throw FlowError("\(name) expects \(parameters.count) arguments, received \(arguments.count).") }
        let next = Frame(function["name"])
        for (parameter, value) in zip(parameters, arguments) {
            let converted: Value
            if parameter["array"].lowercased() == "true" {
                guard case .array(let array) = value, array.type.lowercased() == parameter["type"].lowercased() else { throw FlowError("Array parameter type mismatch: \(parameter["name"])") }
                converted = value
            } else { converted = try value.converted(to: parameter["type"]) }
            let key = FlowIdentifier.key(parameter["name"])
            guard next.variables[key] == nil else { throw FlowError("Duplicate parameter: \(parameter["name"])") }
            next.parameterNames.insert(key)
            next.scopes[0][key] = Variable(name: parameter["name"], type: parameter["type"], value: converted)
        }
        frames.append(next)
        defer { frames.removeLast() }
        try execute(function.child("body")?.children ?? [], scoped: false)
        try tick(function)
        if function["type"].lowercased() == "none" { return .none }
        return try initialized(lookup(function["variable"]).value, function["variable"]).converted(to: function["type"])
    }
    private func inputType(_ value: Value) throws -> String {
        switch value {
        case .uninitialized(let type): return type
        case .integer: return "Integer"
        case .real: return "Real"
        case .string: return "String"
        case .boolean: return "Boolean"
        default: throw FlowError("Input requires a scalar variable.")
        }
    }
    public static func parseInput(_ text: String, type: String) throws -> Value {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch type.lowercased() {
        case "integer":
            if Self.canConvertReal(trimmed) { return .integer(try Value.real(Double(trimmed) ?? 0).integer()) }
            throw FlowError("Invalid Integer input: \(text)")
        case "real":
            guard Self.canConvertReal(trimmed) else { throw FlowError("Invalid Real input: \(text)") }
            let n = Double(trimmed) ?? 0
            guard n.isFinite else { throw FlowError("Invalid Real input: \(text)") }
            return .real(n)
        case "boolean":
            guard ["true", "false"].contains(trimmed.lowercased()) else { throw FlowError("Enter True or False.") }
            return .boolean(trimmed.lowercased() == "true")
        default: return .string(text)
        }
    }
    private func initialized(_ value: Value, _ name: String) throws -> Value {
        if case .uninitialized = value { throw FlowError("Variable has not been initialized: \(name)") }
        return value
    }
    private func reference(_ target: Expression) throws -> Value {
        switch target {
        case .variable(let name): return try lookup(name).value
        case .index(let base, let index):
            guard case .array(let array) = try evaluate(base) else { throw FlowError("Subscript requires an array.") }
            return try array.values[subscriptIndex(evaluate(index), array)]
        default: throw FlowError("Expected a variable or array element.")
        }
    }
    private func evaluate(_ expression: Expression) throws -> Value {
        switch expression {
        case .literal(let value): return value
        case .variable(let name): return try initialized(lookup(name).value, name)
        case .index(let base, let index):
            guard case .array(let array) = try evaluate(base) else { throw FlowError("Subscript requires an array.") }
            return try initialized(array.values[subscriptIndex(evaluate(index), array)], "array element")
        case .call(let name, let args): return try call(name, args.map { try evaluate($0) })
        case .unary(let op, let operand):
            let value = try evaluate(operand)
            if op == "not" || op == "!" { return .boolean(try !value.bool()) }
            if op == "+" { _ = try value.number(); return value }
            if case .integer(let n) = value {
                let result = Int64.zero.subtractingReportingOverflow(n)
                guard !result.overflow else { throw FlowError("Integer overflow.") }; return .integer(result.partialValue)
            }
            return .real(try -value.number())
        case .binary(let op, let left, let right):
            let a = try evaluate(left)
            let b = try evaluate(right)
            if op == "and" || op == "&&" { let x = try a.bool(), y = try b.bool(); return .boolean(x && y) }
            if op == "or" || op == "||" { let x = try a.bool(), y = try b.bool(); return .boolean(x || y) }
            if op == "&" {
                guard a.canConvertString, b.canConvertString else { throw FlowError("Concatenation requires scalar values.") }
                return .string(a.description + b.description)
            }
            if ["=", "==", "!=", "<>", "<", ">", "<=", ">="].contains(op) {
                let comparison: Int
                switch (a, b) {
                case (.string(let x), .string(let y)): comparison = Self.ordinalCompare(x, y)
                case (.boolean(let x), .boolean(let y)):
                    guard ["=", "==", "!=", "<>"].contains(op) else { throw FlowError("Booleans support only equality comparisons.") }
                    comparison = x == y ? 0 : 1
                default:
                    let x = try a.number(), y = try b.number()
                    comparison = x == y ? 0 : (x < y ? -1 : 1)
                }
                switch op {
                case "=", "==": return .boolean(comparison == 0)
                case "!=", "<>": return .boolean(comparison != 0)
                case "<": return .boolean(comparison < 0)
                case ">": return .boolean(comparison > 0)
                case "<=": return .boolean(comparison <= 0)
                default: return .boolean(comparison >= 0)
                }
            }
            if case .integer(let x) = a, case .integer(let y) = b, ["+", "-", "*", "%", "mod"].contains(op) {
                let result: (partialValue: Int64, overflow: Bool)
                switch op {
                case "+": result = x.addingReportingOverflow(y)
                case "-": result = x.subtractingReportingOverflow(y)
                case "*": result = x.multipliedReportingOverflow(by: y)
                default:
                    guard x >= 0, y > 0 else { throw FlowError("Invalid modulo divisor.") }
                    return .integer(x % y)
                }
                guard !result.overflow else { throw FlowError("Integer overflow.") }
                return .integer(result.partialValue)
            }
            let x = try a.number(), y = try b.number()
            let result: Double
            switch op {
            case "+": result = x + y
            case "-": result = x - y
            case "*": result = x * y
            case "/": guard y != 0 else { throw FlowError("Division by zero.") }; result = x / y
            case "%", "mod": guard x >= 0, y > 0 else { throw FlowError("Modulo requires nonnegative operands and a positive divisor.") }; result = x.truncatingRemainder(dividingBy: y)
            case "^", "**": result = pow(x, y)
            default: throw FlowError("Unknown operator: \(op)")
            }
            guard result.isFinite else { throw FlowError("Numeric result is not finite.") }
            return .real(result)
        }
    }
    private func builtin(_ name: String, _ args: [Value]) throws -> Value? {
        let key = FlowIdentifier.key(name)
        let unary: [String: (Double) -> Double] = ["abs":abs, "sqrt":sqrt, "sin":sin, "cos":cos, "tan":tan, "arcsin":asin, "arccos":acos, "arctan":atan, "log":log, "ln":log, "sinh":sinh, "cosh":cosh, "tanh":tanh, "arcsinh":asinh, "arccosh":acosh, "arctanh":atanh, "log10":log10]
        func count(_ n: Int) throws { guard args.count == n else { throw FlowError("\(name) expects \(n) arguments.") } }
        if let operation = unary[key] {
            try count(1); let value = operation(try args[0].number())
            guard value.isFinite else { throw FlowError("Invalid argument to \(name).") }
                        return .real(value)
        }
        switch key {
        case "tostring": try count(1); return .string(args[0].description)
        case "tointeger", "toreal":
            try count(1)
            if case .integer(let value) = args[0] { return key == "tointeger" ? .integer(value) : .real(Double(value)) }
            if case .real(let value) = args[0] { return key == "tointeger" ? .integer(try Value.real(value).integer()) : .real(value) }
            if case .string(let text) = args[0], Self.canConvertReal(text) {
                let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                guard value.isFinite else { throw FlowError("Cannot convert '\(args[0])' using \(name).") }
                return key == "tointeger" ? .integer(try Value.real(value).integer()) : .real(value)
            }
            throw FlowError("Cannot convert '\(args[0])' using \(name).")
        case "eof": try count(0); return .boolean(readLines == nil || readPosition >= (readLines?.count ?? 0))
        case "turtlex": try count(0); return .real(turtle.position.x)
        case "turtley": try count(0); return .real(-turtle.position.y)
        case "sgn": try count(1); let n = try args[0].number(); return .integer(n == 0 ? 0 : (n > 0 ? 1 : -1))
        case "tofixed":
            try count(2)
            guard case .real(let n) = args[0] else { throw FlowError("ToFixed argument 1 must be Real.") }
            guard case .integer(let places) = args[1] else { throw FlowError("ToFixed argument 2 must be Integer.") }
            guard places >= 1, places <= 100 else { throw FlowError("ToFixed precision must be between 1 and 100.") }
            return .string(String(format: "%.*f", locale: Locale(identifier: "en_US_POSIX"), Int(places), n))
        case "int":
            try count(1)
            let number = try args[0].number()
            guard number.isFinite, number >= Double(Int32.min), number <= Double(Int32.max) else { throw FlowError("Int argument is outside the 32-bit range.") }
            return .integer(Int64(Int32(number)))
        case "len": try count(1); return .integer(Int64(try args[0].text().utf16.count))
        case "size":
            try count(1); guard case .array(let a) = args[0] else { throw FlowError("Size requires an array.") }; return .integer(Int64(a.values.count))
        case "char":
            try count(2); let s = Array(try args[0].text().utf16); let i = try args[1].integer()
            guard i >= 0, i < s.count else { throw FlowError("Char index out of bounds.") }
            return .string(String(decoding: [s[Int(i)]], as: UTF16.self))
        case "tocode":
            try count(1); guard let code = try args[0].text().utf16.first else { throw FlowError("ToCode requires a nonempty string.") }; return .integer(Int64(code))
        case "tochar":
            try count(1); let code = try args[0].integer()
            guard code >= 0, code <= 65535 else { throw FlowError("ToChar requires a UTF-16 code unit (0...65535).") }
            return .string(String(decoding: [UInt16(code)], as: UTF16.self))
        case "random":
            try count(1); let maximum = try args[0].integer()
            guard maximum > 0 else { throw FlowError("Random requires a positive maximum.") }
            return .integer(Int64.random(in: 0..<maximum))
        default: return nil
        }
    }
    private static func ordinalCompare(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs.utf16), right = Array(rhs.utf16)
        for index in 0..<min(left.count, right.count) where left[index] != right[index] {
            return left[index] < right[index] ? -1 : 1
        }
        return left.count == right.count ? 0 : (left.count < right.count ? -1 : 1)
    }
    private static func canConvertReal(_ text: String) -> Bool {
        let scalars = Array(text.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars)
        guard !scalars.isEmpty else { return false }
        var dots = 0
        for (index, scalar) in scalars.enumerated() {
            if scalar == "." { dots += 1; if dots > 1 { return false } }
            else if scalar == "+" || scalar == "-" { if index != 0 { return false } }
            else if scalar.properties.generalCategory != .decimalNumber { return false }
        }
        return true
    }
}
