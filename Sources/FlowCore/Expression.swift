import Foundation

public final class ArrayValue {
    public var values: [Value]
    public let type: String
    public init(_ values: [Value], type: String) { self.values = values; self.type = type }
}

public enum Value: CustomStringConvertible {
    case integer(Int64), real(Double), string(String), boolean(Bool), array(ArrayValue), uninitialized(String), none
    public var description: String {
        switch self {
        case .integer(let n): return String(n)
        case .real(let n): return n.isFinite && n.rounded() == n && abs(n) < 1e16 ? String(format: "%.0f", n) : String(n)
        case .string(let s): return s
        case .boolean(let b): return b ? "True" : "False"
        case .array: return "[...]"
        case .uninitialized: return "(uninitialized)"
        case .none: return ""
        }
    }
    public var canConvertString: Bool {
        switch self {
        case .integer, .real, .string, .boolean: return true
        default: return false
        }
    }
    public func number() throws -> Double {
        switch self {
        case .integer(let n): return Double(n)
        case .real(let n): return n
        default: throw FlowError("Expected a number, got \(description).")
        }
    }
    public func integer() throws -> Int64 {
        if case .integer(let n) = self { return n }
        let n = try number()
        guard n.isFinite, n >= Double(Int64.min), n < Double(Int64.max) else { throw FlowError("Integer is outside its supported range.") }
        return Int64(n)
    }
    public func bool() throws -> Bool {
        guard case .boolean(let b) = self else { throw FlowError("Expected a Boolean, got \(description).") }
        return b
    }
    public func text() throws -> String {
        guard case .string(let s) = self else { throw FlowError("Expected a String, got \(description).") }
        return s
    }
    public static func initial(_ type: String) throws -> Value {
        switch type.lowercased() {
        case "integer": return .uninitialized("Integer")
        case "real": return .uninitialized("Real")
        case "string": return .uninitialized("String")
        case "boolean": return .uninitialized("Boolean")
        case "none": return .none
        default: throw FlowError("Unknown type: \(type)")
        }
    }
    public func converted(to type: String) throws -> Value {
        switch type.lowercased() {
        case "integer": return .integer(try integer())
        case "real": return .real(try number())
        case "string": return .string(try text())
        case "boolean": return .boolean(try bool())
        case "none": return .none
        default: throw FlowError("Unknown type: \(type)")
        }
    }
}

public indirect enum Expression {
    case literal(Value), variable(String), index(Expression, Expression), call(String, [Expression]), unary(String, Expression), binary(String, Expression, Expression)
    public static func parse(_ source: String) throws -> Expression {
        var parser = try ExpressionParser(source)
        return try parser.parse()
    }
}

private enum Token: Equatable {
    case number(String), string(String), name(String), symbol(String), end
}

private struct ExpressionParser {
    var tokens: [Token] = []
    var position = 0
    init(_ source: String) throws {
        let aliases: [String: String] = ["∨":"||", "∧":"&&", "≤":"<=", "≥":">=", "≠":"!=", "×":"*", "∗":"*", "÷":"/", "⁄":"/", "∕":"/", "↑":"^", "⭡":"^", "−":"-", "¬":"!"]
        let chars = Array(source.unicodeScalars)
        func text(_ values: ArraySlice<Unicode.Scalar>) -> String {
            String(String.UnicodeScalarView(values))
        }
        func isLetter(_ value: Unicode.Scalar) -> Bool {
            guard value.value <= 0xFFFF else { return false }
            switch value.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter: return true
            default: return false
            }
        }
        func isNumber(_ value: Unicode.Scalar) -> Bool {
            guard value.value <= 0xFFFF else { return false }
            switch value.properties.generalCategory {
            case .decimalNumber, .letterNumber, .otherNumber: return true
            default: return false
            }
        }
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.properties.isWhitespace { i += 1; continue }
            if c == "\"" {
                i += 1
                var s = ""
                var closed = false
                while i < chars.count {
                    if chars[i] == "\"" {
                        i += 1; closed = true; break
                    }
                    if chars[i] == "\n" { break }
                    s.unicodeScalars.append(chars[i]); i += 1
                }
                guard closed else { throw FlowError("Unterminated string literal.") }
                tokens.append(.string(s)); continue
            }
            if isNumber(c) || (c == "." && i + 1 < chars.count && isNumber(chars[i + 1])) {
                let start = i; i += 1
                while i < chars.count && (isNumber(chars[i]) || chars[i] == ".") { i += 1 }
                let number = text(chars[start..<i])
                guard number.filter({ $0 == "." }).count <= 1, number.last != "." else { throw FlowError("Invalid number: \(number)") }
                tokens.append(.number(number)); continue
            }
            if isLetter(c) {
                let start = i; i += 1
                while i < chars.count && (isLetter(chars[i]) || isNumber(chars[i])) { i += 1 }
                let name = text(chars[start..<i])
                if ["and", "or", "not", "mod"].contains(name.lowercased()) { tokens.append(.symbol(name.lowercased())) }
                else { tokens.append(.name(name)) }
                continue
            }
            if i + 1 < chars.count {
                let pair = text(chars[i...i+1])
                if ["<=", ">=", "==", "!=", "<>", "&&", "||"].contains(pair) {
                    tokens.append(.symbol(pair)); i += 2; continue
                }
            }
            if let mapped = aliases[String(c)] { tokens.append(.symbol(mapped)); i += 1; continue }
            guard "+-*/%^&=<>!()[],".unicodeScalars.contains(c) else { throw FlowError("Unexpected character: \(c)") }
            tokens.append(.symbol(String(c))); i += 1
        }
        tokens.append(.end)
    }
    var current: Token { tokens[position] }
    mutating func take() -> Token { defer { position += 1 }; return current }
    mutating func expect(_ s: String) throws {
        guard take() == .symbol(s) else { throw FlowError("Expected '\(s)'.") }
    }
    mutating func parse() throws -> Expression {
        let expression = try binary(0)
        guard current == .end else { throw FlowError("Unexpected text after expression.") }
        return expression
    }
    func precedence(_ op: String) -> Int? {
        switch op {
        case "or", "||": return 1
        case "and", "&&": return 2
        case "=", "==", "!=", "<>", "<", ">", "<=", ">=": return 3
        case "&": return 4
        case "+", "-": return 5
        case "*", "/", "%", "mod": return 6
        case "^": return 7
        default: return nil
        }
    }
    mutating func binary(_ minimum: Int) throws -> Expression {
        var left = try primary()
        while case .symbol(let op) = current, let prec = precedence(op), prec >= minimum {
            _ = take()
            let right = try binary(prec + 1)
            left = .binary(op, left, right)
        }
        return left
    }
    mutating func primary() throws -> Expression {
        var result: Expression
        switch take() {
        case .number(let s):
            if let n = Int64(s) { result = .literal(.integer(n)) }
            else if let n = Double(s), n.isFinite { result = .literal(.real(n)) }
            else { throw FlowError("Invalid number: \(s)") }
        case .string(let s): result = .literal(.string(s))
        case .name(let name):
            let constant = FlowIdentifier.key(name)
            if constant == "true" { result = .literal(.boolean(true)) }
            else if constant == "false" { result = .literal(.boolean(false)) }
            else if constant == "newline" || constant == "lf" { result = .literal(.string("\n")) }
            else if constant == "pi" || constant == "π" { result = .literal(.real(.pi)) }
            else if current == .symbol("(") {
                _ = take(); var args: [Expression] = []
                if current != .symbol(")") {
                    while true {
                        args.append(try binary(0))
                        if current != .symbol(",") { break }
                        _ = take()
                    }
                }
                try expect(")"); result = .call(name, args)
            } else { result = .variable(name) }
        case .symbol("("):
            result = try binary(0); try expect(")")
        case .symbol(let op) where ["-", "+", "!", "not"].contains(op):
            result = .unary(op, try binary(8))
        default: throw FlowError("Expected an expression.")
        }
        while current == .symbol("[") {
            _ = take(); let index = try binary(0); try expect("]")
            result = .index(result, index)
        }
        return result
    }
}
