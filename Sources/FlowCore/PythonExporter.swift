import Foundation

public enum PythonExporter {
    public static func generate(_ program: Program) throws -> String {
        var generator = Generator(program: program)
        return try generator.generate()
    }
}

private struct Generator {
    let program: Program
    var types: [String: String] = [:]
    var arrays = Set<String>()
    var lines: [String] = []
    var loopCount = 0
    mutating func generate() throws -> String {
        lines = [Self.prelude]
        for function in program.functions {
            types = [:]; arrays = []
            func collect(_ node: Element, _ types: inout [String: String], _ arrays: inout Set<String>) {
                if node.tag == "declare" || node.tag == "parameter" {
                    let names = node["name"].isEmpty ? node["variables"] : node["name"]
                    for raw in names.split(separator: ",") {
                        let name = String(raw.prefix { $0 != "[" }).trimmingCharacters(in: .whitespaces).lowercased()
                        types[name] = node["type"]
                        if node["array"].lowercased() == "true" || raw.contains("[") { arrays.insert(name) }
                    }
                }
                for child in node.children { collect(child, &types, &arrays) }
            }
            collect(function, &types, &arrays)
            let parameters = function.child("parameters")?.children ?? []
            let name = try identifier(function["name"], prefix: "f_")
            let args = try parameters.map { try identifier($0["name"], prefix: "v_") }.joined(separator: ", ")
            lines.append("def \(name)(\(args)):")
            for parameter in parameters where parameter["array"].lowercased() != "true" {
                let variable = try identifier(parameter["name"], prefix: "v_")
                emit("\(variable) = \(cast(variable, parameter["type"]))", 1)
            }
            try block(function.child("body")?.children ?? [], 1)
            if function["type"].lowercased() != "none" {
                emit("return \(cast(try expr(.variable(function["variable"])), function["type"]))", 1)
            }
            lines.append("")
        }
        lines.append("if __name__ == '__main__':\n    f_main()\n")
        return lines.joined(separator: "\n")
    }
    func identifier(_ name: String, prefix: String) throws -> String {
        guard !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { throw FlowError("Invalid identifier: \(name)") }
        return prefix + name.lowercased()
    }
    func cast(_ expression: String, _ type: String) -> String {
        switch type.lowercased() {
        case "integer": return "fg_int(\(expression))"
        case "real": return "fg_real(\(expression))"
        case "boolean": return "fg_bool(\(expression))"
        case "string": return "fg_string(\(expression))"
        default: return expression
        }
    }
    func expr(_ source: String) throws -> String { try expr(Expression.parse(source)) }
    func expr(_ value: Expression) throws -> String {
        switch value {
        case .literal(let value):
            switch value {
            case .string(let s): return quote(s)
            case .boolean(let b): return b ? "True" : "False"
            case .real(let n): return String(n)
            case .integer(let n): return String(n)
            default: throw FlowError("Cannot export this literal.")
            }
        case .variable(let name): return "fg_value(\(try identifier(name, prefix: "v_")))"
        case .index(let base, let index): return "fg_get(\(try expr(base)), \(try expr(index)))"
        case .unary(let op, let value): return "(\(op == "!" || op == "not" ? "not " : op)\(try expr(value)))"
        case .binary(let op, let left, let right):
            let a = try expr(left), b = try expr(right)
            if op == "and" || op == "&&" { return "fg_and(\(a), \(b))" }
            if op == "or" || op == "||" { return "fg_or(\(a), \(b))" }
            if op == "&" { return "(fg_text(\(a)) + fg_text(\(b)))" }
            let mapped = ["=":"==", "<>":"!=", "&&":"and", "||":"or", "^":"**", "mod":"%"]
            return "(\(a) \(mapped[op] ?? op) \(b))"
        case .call(let name, let args):
            let builtin = ["abs":"abs", "sqrt":"math.sqrt", "sin":"math.sin", "cos":"math.cos", "tan":"math.tan", "arcsin":"math.asin", "arccos":"math.acos", "arctan":"math.atan", "log":"math.log", "ln":"math.log", "log10":"math.log10", "int":"fg_int", "len":"fg_len", "size":"len", "char":"fg_char", "tostring":"fg_text", "tointeger":"fg_to_int", "toreal":"float", "tocode":"fg_code", "tochar":"fg_chr", "random":"random.randrange", "tofixed":"fg_fixed", "sgn":"fg_sgn", "eof":"fg_eof", "turtlex":"fg_turtlex", "turtley":"fg_turtley", "sinh":"math.sinh", "cosh":"math.cosh", "tanh":"math.tanh", "arcsinh":"math.asinh", "arccosh":"math.acosh", "arctanh":"math.atanh"]
            let target = try builtin[name.lowercased()] ?? identifier(name, prefix: "f_")
            return "\(target)(\(try args.map { try expr($0) }.joined(separator: ", ")))"
        }
    }
    func quote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r").replacingOccurrences(of: "\t", with: "\\t") + "\""
    }
    mutating func emit(_ s: String, _ depth: Int) { lines.append(String(repeating: "    ", count: depth) + s) }
    func target(_ source: String) throws -> (String, String) {
        let parsed = try Expression.parse(source)
        switch parsed {
        case .variable(let name): return (try identifier(name, prefix: "v_"), types[name.lowercased()] ?? "")
        case .index(.variable(let name), let index): return ("\(try identifier(name, prefix: "v_"))[fg_index(\(try expr(index)))]", types[name.lowercased()] ?? "")
        default: throw FlowError("Invalid assignment target: \(source)")
        }
    }
    mutating func block(_ nodes: [Element], _ depth: Int) throws {
        if nodes.isEmpty { emit("pass", depth) }
        for node in nodes {
            switch node.tag {
            case "comment", "breakpoint": emit("pass", depth)
            case "declare":
                let names = node["name"].isEmpty ? node["variables"] : node["name"]
                for raw in names.split(separator: ",") {
                    let entry = raw.trimmingCharacters(in: .whitespaces)
                    let name = String(entry.prefix { $0 != "[" }).trimmingCharacters(in: .whitespaces)
                    let variable = try identifier(name, prefix: "v_")
                    if arrays.contains(name.lowercased()) {
                        var size = node["size"]
                        if size.isEmpty, let left = entry.firstIndex(of: "["), let right = entry.lastIndex(of: "]") { size = String(entry[entry.index(after: left)..<right]) }
                        emit("\(variable) = [None] * fg_int(\(try expr(size)))", depth)
                    } else { emit("\(variable) = None", depth) }
                }
            case "assign":
                let (target, type) = try target(node["variable"])
                emit("\(target) = \(cast(try expr(node["expression"]), type))", depth)
            case "input":
                let (target, type) = try target(node["variable"])
                let input = "input()"
                let converted: String
                switch type.lowercased() {
                case "integer": converted = "fg_to_int(\(input))"
                case "real": converted = "float(\(input))"
                case "boolean": converted = "fg_to_bool(\(input))"
                default: converted = input
                }
                emit("\(target) = \(converted)", depth)
            case "output": emit("print(fg_text(\(try expr(node["expression"]))), end=\(quote(node["newline"].lowercased() == "false" ? "" : "\n")))", depth)
            case "if":
                emit("if fg_bool(\(try expr(node["expression"]))):", depth)
                try block(node.child("then")?.children ?? [], depth + 1)
                if let branch = node.child("else"), !branch.children.isEmpty { emit("else:", depth); try block(branch.children, depth + 1) }
            case "while": emit("while fg_bool(\(try expr(node["expression"]))):", depth); try block(node.children, depth + 1)
            case "do":
                emit("while True:", depth); try block(node.children, depth + 1)
                emit("if not fg_bool(\(try expr(node["expression"]))):", depth + 1); emit("break", depth + 2)
            case "for":
                let (variable, type) = try target(node["variable"])
                let start = try expr(node["start"]), end = try expr(node["end"]), step = try expr(node["step"].isEmpty ? "1" : node["step"])
                let descending = node["direction"].lowercased() == "dec"
                emit("\(variable) = \(cast(start, type))", depth)
                emit("while \(variable) \(descending ? ">=" : "<=") \(end):", depth)
                try block(node.children, depth + 1)
                emit("\(variable) = \(cast("\(variable) \(descending ? "-" : "+") fg_step(\(step))", type))", depth + 1)
            case "open": emit("fg_open(\(try expr(node["expression"])), \(quote(node["mode"].isEmpty ? "read" : node["mode"])))", depth)
            case "close": emit("fg_close(\(quote(node["mode"].isEmpty ? "read" : node["mode"])))", depth)
            case "read":
                let (target, type) = try target(node["variable"])
                let conversions = ["integer":"fg_to_int", "real":"float", "boolean":"fg_to_bool", "string":"fg_string"]
                emit("\(target) = \(conversions[type.lowercased()] ?? "fg_string")(fg_read())", depth)
            case "write": emit("fg_write(\(try expr(node["expression"])))", depth)
            case "forward":
                emit("fg_turtle().\(node["pen"].lowercased() == "up" ? "penup" : "pendown")()", depth)
                emit("fg_turtle().forward(\(try expr(node["expression"])))", depth)
            case "turn": emit("fg_turtle().\(node["rotate"].lowercased() == "left" ? "left" : "right")(\(try expr(node["expression"])))", depth)
            case "pen":
                let color = TurtleState.colors.contains(node["color"].lowercased()) ? node["color"].lowercased() : "black"
                emit("fg_turtle().pencolor(\(quote(TurtleState.ink[color] ?? "#101010")))",depth)
            case "home": emit("fg_turtle().penup()", depth); emit("fg_turtle().home()", depth); emit("fg_turtle().setheading(90)", depth)
            case "clear": emit("fg_turtle().clear()", depth); emit("fg_turtle().penup()", depth); emit("fg_turtle().home()", depth); emit("fg_turtle().setheading(90)", depth)
            case "call": emit(try expr(node["expression"]), depth)
            default: throw FlowError("Python export does not support \(node.tag).")
            }
        }
    }
    static let prelude = """
import math
import random


def fg_value(value):
    if value is None:
        raise ValueError('Variable has not been initialized')
    return value


def fg_real(value):
    if type(value) not in (int, float):
        raise TypeError('Expected a number')
    return float(value)


def fg_int(value):
    result = int(fg_real(value))
    if not -(2 ** 63) <= result < 2 ** 63:
        raise OverflowError('Integer overflow')
    return result


def fg_bool(value):
    if type(value) is not bool:
        raise TypeError('Expected Boolean')
    return value


def fg_string(value):
    if type(value) is not str:
        raise TypeError('Expected String')
    return value


def fg_text(value):
    if type(value) is bool:
        return 'True' if value else 'False'
    if type(value) is float and value.is_integer() and abs(value) < 1e16:
        return str(int(value))
    return str(fg_value(value))


def fg_index(value):
    index = fg_int(value)
    if index < 0:
        raise IndexError('Negative array index')
    return index


def fg_get(array, index):
    return fg_value(array[fg_index(index)])


def fg_step(value):
    if fg_real(value) <= 0:
        raise ValueError('For step must be positive')
    return value


def fg_to_int(value):
    return fg_int(float(fg_string(value)))


def fg_to_bool(value):
    if value.lower() not in ('true', 'false'):
        raise ValueError('Enter True or False')
    return value.lower() == 'true'


def fg_len(value):
    return len(fg_string(value).encode('utf-16-le', errors='surrogatepass')) // 2


def fg_char(value, index):
    data = fg_string(value).encode('utf-16-le', errors='surrogatepass')
    index = fg_index(index)
    if index >= len(data) // 2:
        raise IndexError('Char index out of bounds')
    return data[index * 2:index * 2 + 2].decode('utf-16-le', errors='surrogatepass')


def fg_code(value):
    return int.from_bytes(fg_string(value).encode('utf-16-le', errors='surrogatepass')[:2], 'little')


def fg_chr(value):
    return fg_int(value).to_bytes(2, 'little').decode('utf-16-le', errors='surrogatepass')


def fg_fixed(value, places):
    return format(fg_real(value), '.' + str(fg_int(places)) + 'f')


def fg_and(left, right):
    return fg_bool(left) & fg_bool(right)


def fg_or(left, right):
    return fg_bool(left) | fg_bool(right)


_fg_files = {}
_fg_pen = None


def fg_open(path, mode):
    if mode in _fg_files:
        raise ValueError('File already open')
    _fg_files[mode] = open(path, 'w' if mode == 'write' else 'r', encoding='utf-8-sig' if mode == 'read' else 'utf-8')


def fg_close(mode):
    if mode in _fg_files:
        _fg_files.pop(mode).close()


def fg_read():
    value = _fg_files['read'].readline()
    if not value:
        raise EOFError('Read past end of file')
    return value.rstrip('\\r\\n')


def fg_write(value):
    _fg_files['write'].write(fg_text(value) + '\\n')
    _fg_files['write'].flush()


def fg_eof():
    if 'read' not in _fg_files:
        return True
    stream = _fg_files['read']
    position = stream.tell()
    result = stream.read(1) == ''
    stream.seek(position)
    return result


def fg_turtle():
    global _fg_pen
    if _fg_pen is None:
        import turtle
        _fg_pen = turtle.Turtle()
        _fg_pen.setheading(90)
    return _fg_pen


def fg_turtlex():
    return fg_turtle().xcor()


def fg_turtley():
    return fg_turtle().ycor()


def fg_sgn(value):
    return (fg_real(value) > 0) - (fg_real(value) < 0)

"""
}
