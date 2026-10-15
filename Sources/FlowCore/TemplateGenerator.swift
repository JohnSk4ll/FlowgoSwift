import Foundation

public enum TemplateExporter {
    public static func generate(_ program: Program, template: SourceTemplate, options: Set<String> = []) throws -> GeneratedSource {
        var generator = TemplateGenerator(program:program,template:template,options:options)
        return try generator.generate()
    }
}

private struct TemplateExpression {
    var text: String
    var type: String
    var precedence = 100
    var array = false
}

private struct TemplateGenerator {
    let program: Program
    let template: SourceTemplate
    let options: Set<String>
    var output: [SourceLine] = []
    var globalFlags = Set<String>()
    var variables: [String:Element] = [:]
    var names: [String:String] = [:]
    var functionNames: [String:String] = [:]
    var current: Element?
    var expansionDepth = 0
    let binarySections = ["or":"Or","||":"Or","and":"And","&&":"And","=":"Equals","==":"Equals","!=":"Not Equals","<>":"Not Equals","<":"Less Than","<=":"Less Equal Than",">":"Greater Than",">=":"Greater Equal Than","+":"Add","-":"Subtract","*":"Multiply","/":"Divide","%":"Modulus","mod":"Modulus","^":"Power","&":"Concatenate"]

    mutating func generate() throws -> GeneratedSource {
        globalFlags = options
        if program.functions.count > 1 { globalFlags.insert("functions") }
        scan(program.root)
        var used = Set<String>()
        for function in program.functions {
            functionNames[function["name"].lowercased()] = try identifier(function["name"],section:"Function ID",type:function["type"],used:&used)
        }
        try render("Program",flags:globalFlags,fields:[:],depth:0,node:nil,blocks:[:])
        return GeneratedSource(language:template.name,fileExtension:template.fileExtension,lines:output)
    }
    mutating func scan(_ node: Element) {
        globalFlags.insert(node.tag)
        if ["forward","turn","pen","home","clear"].contains(node.tag) { globalFlags.insert("turtle") }
        if ["open","close","read","write"].contains(node.tag) { globalFlags.insert("files") }
        if node.tag == "declare" { globalFlags.insert(node["type"].lowercased()); if node["array"].lowercased() == "true" { globalFlags.insert("array") } }
        if node.tag == "open" || node.tag == "close" { globalFlags.insert(node["mode"].lowercased() == "write" ? "write" : "read") }
        for key in ["expression","start","end","step","size"] {
            if let expression = try? Expression.parse(node[key]) { scan(expression) }
        }
        for child in node.children { scan(child) }
    }
    mutating func scan(_ expression: Expression) {
        switch expression {
        case .call(let name,let args): globalFlags.insert(name.lowercased()); for arg in args { scan(arg) }
        case .variable(let name): if ["pi","lf","newline"].contains(name.lowercased()) { globalFlags.insert(name.lowercased()) }
        case .binary(_,let left,let right): scan(left); scan(right)
        case .unary(_,let value): scan(value)
        case .index(let base,let index): scan(base); scan(index)
        case .literal(.real(let value)): if value == Double.pi { globalFlags.insert("pi") }
        case .literal(.string(let value)): if value == "\n" { globalFlags.insert("lf") }
        default: break
        }
    }
    func identifier(_ original: String, section: String, type: String, used: inout Set<String>) throws -> String {
        let convention = template.value(section,"Convention").lowercased()
        var name = original
        switch convention {
        case "lower": name = name.lowercased()
        case "upper": name = name.uppercased()
        case "camel": name = String(name.prefix(1)).lowercased() + name.dropFirst()
        case "proper": name = String(name.prefix(1)).uppercased() + name.dropFirst()
        default: break
        }
        let reserved = Set((template.lines("Language","Keywords") + template.lines("Language","Conflicts")).flatMap { $0.text.split(separator:",").map { $0.trimmingCharacters(in:.whitespaces).lowercased() } })
        let flags: Set<String> = [type.lowercased()]
        let key = reserved.contains(name.lowercased()) ? "Conflict" : "Normal"
        let format = template.value(section,key,flags:flags)
        name = try SourceTemplate.expand(format.isEmpty ? "{name}" : format,fields:["name":name])
        let base = name
        var suffix = 2
        while used.contains(name.lowercased()) { name = base + String(suffix); suffix += 1 }
        used.insert(name.lowercased())
        return name
    }
    mutating func prepare(_ function: Element) throws {
        current = function; variables = [:]; names = [:]
        var used = Set(functionNames.values.map { $0.lowercased() })
        func collect(_ node: Element, into variables: inout [String:Element]) {
            if node.tag == "declare" || node.tag == "parameter" {
                for raw in (node["name"].isEmpty ? node["variables"] : node["name"]).split(separator:",") {
                    let name = String(raw.prefix { $0 != "[" }).trimmingCharacters(in:.whitespaces)
                    var declaration = node
                    if raw.contains("[") {
                        declaration["array"] = "True"
                        if let start = raw.firstIndex(of:"["), let end = raw.lastIndex(of:"]") { declaration["size"] = String(raw[raw.index(after:start)..<end]) }
                    }
                    variables[name.lowercased()] = declaration
                }
            }
            for child in node.children { collect(child,into:&variables) }
        }
        collect(function,into:&variables)
        for key in variables.keys.sorted() { names[key] = try identifier(key,section:"Variable ID",type:variables[key]?["type"] ?? "none",used:&used) }
    }
    mutating func function(_ node: Element, section: String, depth: Int) throws {
        try prepare(node)
        var flags = globalFlags
        flags.remove("return"); flags.remove("parameters"); flags.remove("block")
        if node["type"].lowercased() != "none" { flags.insert("return") }
        let parameters = node.child("parameters")?.children ?? []
        if !parameters.isEmpty { flags.insert("parameters") }
        let body = node.child("body")?.children ?? []
        if !body.isEmpty { flags.insert("block") }
        let args = try parameters.enumerated().map { index,parameter in
            var f: Set<String> = [parameter["type"].lowercased()]
            if parameter["array"].lowercased() == "true" { f.insert("array") }
            if index == 0 { f.insert("first") }; if index == parameters.count - 1 { f.insert("last") }
            return try fieldText("Parameter",flags:f,fields:["name":names[parameter["name"].lowercased()] ?? parameter["name"],"type":typeName(parameter["type"])])
        }.joined(separator:try SourceTemplate.expand(template.value("Parameter","Separator"),fields:[:]))
        let fields = ["name":functionNames[node["name"].lowercased()] ?? node["name"],"type":typeName(node["type"]),"parameters":args,"return":names[node["variable"].lowercased()] ?? node["variable"]]
        try render(section,flags:flags,fields:fields,depth:depth,node:node,blocks:["-->BLOCK":body])
    }
    func typeName(_ type: String) -> String { template.value("Types",type) }
    func fieldText(_ section: String, key: String = "Text", flags: Set<String>, fields: [String:String]) throws -> String {
        guard let line = template.lines(section,key,flags:flags).first else { throw FlowError("\(template.name) template has no matching [\(section)] \(key).") }
        return try SourceTemplate.expand(line.text,fields:fields)
    }
    mutating func render(_ section: String, flags: Set<String>, fields: [String:String], depth: Int, node: Element?, blocks: [String:[Element]]) throws {
        expansionDepth += 1
        defer { expansionDepth -= 1 }
        guard expansionDepth < 128, output.count < 100_000 else { throw FlowError("Template expansion limit exceeded.") }
        let lines = template.lines(section,"Text",flags:flags)
        guard !lines.isEmpty else { throw FlowError("\(template.name) template has no matching [\(section)] Text.") }
        for line in lines {
            let indentation = max(0,depth + line.indent)
            switch line.text.uppercased() {
            case "-->MAIN":
                if let main = program.functions.first(where:{ $0["name"].lowercased() == "main" }) { try function(main,section:"Main",depth:indentation) }
            case "-->FUNCTIONS", "-->HEADERS":
                let saved = (current,variables,names)
                for f in program.functions where f["name"].lowercased() != "main" { try function(f,section:line.text.uppercased() == "-->HEADERS" ? "Function Header" : "Function",depth:indentation) }
                (current,variables,names) = saved
            case "-->VARIABLES":
                if let current {
                    func declarations(_ element: Element) -> [Element] { (element.tag == "declare" ? [element] : []) + element.children.flatMap(declarations) }
                    for declaration in declarations(current) { try declare(declaration,section:"Variable Header",depth:indentation,flags:flags) }
                }
            case "-->PARAMETERS":
                for (index,parameter) in (current?.child("parameters")?.children ?? []).enumerated() {
                    var f = flags
                    for flag in ["array","first","last","integer","real","string","boolean","none"] { f.remove(flag) }
                    f.insert(parameter["type"].lowercased())
                    if index == 0 { f.insert("first") }
                    if index == (current?.child("parameters")?.children.count ?? 0) - 1 { f.insert("last") }
                    if parameter["array"].lowercased() == "true" { f.insert("array") }
                    if template.lines("Parameter Header","Text",flags:f).isEmpty { continue }
                    try render("Parameter Header",flags:f,fields:["name":names[parameter["name"].lowercased()] ?? parameter["name"],"type":typeName(parameter["type"]),"0-index":String(index),"1-index":String(index + 1)],depth:indentation,node:current,blocks:[:])
                }
            case "-->BLOCK", "-->TRUEBLOCK", "-->FALSEBLOCK":
                let extra = node?.tag == "function" ? Int(template.value("Function","Block Extra",flags:flags)) ?? 0 : 0
                try block(blocks[line.text.uppercased()] ?? [],depth:indentation + extra,flags:flags)
            default:
                if line.text.hasPrefix("-->") { throw FlowError("Unsupported template directive: \(line.text)") }
                let text = try SourceTemplate.expand(line.text,fields:fields)
                let spaces = Int(template.value("Language","Indent")) ?? 4
                output.append(SourceLine(id:output.count,text:text.isEmpty ? "" : String(repeating:" ",count:min(256,indentation * max(0,min(spaces,16)))) + text,statementID:node?.id,tag:node?.tag))
            }
        }
    }
    mutating func block(_ nodes: [Element], depth: Int, flags: Set<String>) throws {
        if nodes.isEmpty, !template.lines("Empty Block","Text").isEmpty { try render("Empty Block",flags:flags,fields:[:],depth:depth,node:nil,blocks:[:]); return }
        for (index,node) in nodes.enumerated() {
            var f = flags; f.remove("first"); f.remove("last")
            if index == 0 { f.insert("first") }; if index == nodes.count - 1 { f.insert("last") }
            try statement(node,depth:depth,flags:f)
        }
    }
    mutating func declare(_ node: Element, section: String = "Declare", depth: Int, flags: Set<String>) throws {
        let rawNames = (node["name"].isEmpty ? node["variables"] : node["name"]).split(separator:",").map { String($0.prefix { $0 != "[" }).trimmingCharacters(in:.whitespaces) }
        var f = flags
        for type in ["integer","real","boolean","string","none"] { f.remove(type) }
        f.insert(node["type"].lowercased()); f.remove("array")
        let size = variables[rawNames.first?.lowercased() ?? ""]?["size"] ?? node["size"]
        if node["array"].lowercased() == "true" || node["name"].contains("[") || node["variables"].contains("[") { f.insert("array") }
        var fields = ["type":typeName(node["type"]),"size":size.isEmpty ? "0" : try expression(size).text,"name":"","variables":""]
        if Int(size) != nil { f.insert("constant-size") }
        if template.contains(section,"Text") && template.lines(section,"Text",flags:f).isEmpty { return }
        if template.value(section,"Name Mode",flags:f).lowercased() == "singular" {
            for name in rawNames { fields["name"] = names[name.lowercased()] ?? name; try render(section,flags:f,fields:fields,depth:depth,node:node,blocks:[:]) }
        } else {
            let nameSection = section == "Variable Header" ? "Variable Header Name" : "Declare Name"
            let separator = try SourceTemplate.expand(template.value(nameSection,"Separator"),fields:fields)
            fields["variables"] = try rawNames.enumerated().map { index,name in
                var nf = f; nf.remove("first"); nf.remove("last"); if index == 0 { nf.insert("first") }; if index == rawNames.count - 1 { nf.insert("last") }
                var entry = fields; entry["name"] = names[name.lowercased()] ?? name
                return try fieldText(nameSection,flags:nf,fields:entry)
            }.joined(separator:separator)
            try render(section,flags:f,fields:fields,depth:depth,node:node,blocks:[:])
        }
    }
    mutating func statement(_ node: Element, depth: Int, flags: Set<String>) throws {
        if node.tag == "declare" { try declare(node,depth:depth,flags:flags); return }
        var f = flags, fields = ["text":node["text"],"color":node["color"],"color-hex":TurtleState.ink[node["color"].lowercased()] ?? "#101010"]
        f.remove("array")
        if node.tag == "open" || node.tag == "close" { f.remove("read"); f.remove("write") }
        for flag in ["up","down","left","right"] { f.remove(flag) }
        for type in ["integer","real","boolean","string","none"] {
            for suffix in ["","-variable","-expression"] { f.remove(type + suffix) }
        }
        f.remove("literal"); f.remove("variable")
        if !node["variable"].isEmpty {
            let variable = try expression(node["variable"],target:true)
            fields["variable"] = variable.text; fields["type"] = typeName(variable.type); f.insert(variable.type); f.insert(variable.type + "-variable")
            if case .index(.variable(let name),let index) = try Expression.parse(node["variable"]) { f.insert("array"); fields["name"] = names[name.lowercased()] ?? name; fields["subscript"] = try expr(index).text }
            else { fields["name"] = variable.text; fields["subscript"] = "" }
        }
        if !node["expression"].isEmpty {
            let parsed = try Expression.parse(node["expression"])
            let e = try expr(parsed)
            if node["variable"].isEmpty { f.insert(e.type) }
            f.insert(e.type + "-expression")
            fields["expression"] = try adjusted(e,section:node.tag,key:"Needed",castKey:"Cast",flags:f)
            if ["if","while","do"].contains(node.tag) {
                fields["condition"] = e.text
                fields["not condition"] = try expr(.unary("not",parsed)).text
            }
            if case .literal = parsed { f.insert("literal") }
            if case .variable = parsed { f.insert("variable") }
            if node.tag == "call", case .call(let name,let args) = parsed { fields["name"] = functionNames[name.lowercased()] ?? name; fields["arguments"] = try arguments(args,name:name) }
            if node.tag == "output" {
                func flatten(_ value: Expression) -> [Expression] { if case .binary("&",let a,let b) = value { return flatten(a) + flatten(b) }; return [value] }
                let values = flatten(parsed)
                if values.count > 1 { f.insert("multiple") }
                if !template.lines("Output List","Text",flags:f).isEmpty {
                    fields["list"] = try values.map { try fieldText("Output List",flags:f,fields:["expression":try expr($0).text]) }.joined(separator:try SourceTemplate.expand(template.value("Output List","Separator",flags:f),fields:[:]))
                } else { fields["list"] = e.text }
            }
        }
        if node["newline"].lowercased() != "false" { f.insert("newline") } else { f.remove("newline") }
        if node.tag == "open" || node.tag == "close" { f.insert(node["mode"].lowercased() == "write" ? "write" : "read") }
        if node.tag == "forward" { f.insert(node["pen"].lowercased() == "up" ? "up" : "down") }
        if node.tag == "turn" { f.insert(node["rotate"].lowercased() == "left" ? "left" : "right") }
        if node.tag == "for" {
            for key in ["start","end","step"] { fields[key] = try expression(node[key].isEmpty && key == "step" ? "1" : node[key]).text }
            fields["condition"] = fields["end"]
            if node["direction"].lowercased() != "dec" { f.insert("inc") } else { f.remove("inc") }
            if fields["step"] != "1" { f.insert("step") } else { f.remove("step") }
        }
        let yes = node.child("then")?.children ?? [], no = node.child("else")?.children ?? []
        if !no.isEmpty { f.insert("else") } else { f.remove("else") }
        if !(node.tag == "if" ? yes : node.children).isEmpty { f.insert("block") } else { f.remove("block") }
        if node.tag == "comment" {
            for line in node["text"].components(separatedBy:.newlines) { fields["text"] = line; try render("Comment",flags:f,fields:fields,depth:depth,node:node,blocks:[:]) }
        } else if node.tag == "breakpoint", template.lines("Breakpoint","Text",flags:f).isEmpty {
            return
        } else {
            try render(node.tag,flags:f,fields:fields,depth:depth,node:node,blocks:["-->BLOCK":node.children,"-->TRUEBLOCK":yes,"-->FALSEBLOCK":no])
        }
    }
    func expression(_ source: String, target: Bool = false) throws -> TemplateExpression { try expr(Expression.parse(source),target:target) }
    func typeFlags(_ a: TemplateExpression, _ b: TemplateExpression? = nil) -> Set<String> {
        guard let b else { return [a.type,a.type + "-1"] }
        return [a.type + "-1",b.type + "-2",a.type + "-" + b.type]
    }
    func adjusted(_ value: TemplateExpression, section: String, key: String, castKey: String, flags: Set<String>) throws -> String {
        var e = value
        let target = template.value(section,castKey,flags:flags).lowercased()
        if !target.isEmpty, target != "none", target != value.type {
            let cf: Set<String> = [value.type + "-to-" + target,value.type + "-current",target + "-cast"]
            if !template.lines("Cast","Text",flags:cf).isEmpty {
                e.text = try fieldText("Cast",flags:cf,fields:["expression":parenthesize(e,needed:Int(template.value("Cast","Needed",flags:cf)) ?? 0)])
                e.precedence = Int(template.value("Cast","Precedence",flags:cf)) ?? 100
            }
        }
        return try parenthesize(e,needed:Int(template.value(section,key,flags:flags)) ?? 0)
    }
    func parenthesize(_ e: TemplateExpression, needed: Int) throws -> String {
        guard e.precedence < needed else { return e.text }
        if template.contains("Subexpression","Text") {
            return try fieldText("Subexpression",flags:[e.type],fields:["expression":e.text])
        }
        return "(" + e.text + ")"
    }
    func arguments(_ values: [Expression], name: String) throws -> String {
        let parameters = program.functions.first(where:{ $0["name"].lowercased() == name.lowercased() })?.child("parameters")?.children ?? []
        return try values.enumerated().map { index,value in
            let e = try expr(value)
            var flags = typeFlags(e); if index == 0 { flags.insert("first") }; if index == values.count - 1 { flags.insert("last") }
            var fields = ["expression":e.text,"name":functionNames[name.lowercased()] ?? name,"parameter name":""]
            if parameters.indices.contains(index) {
                let p = parameters[index]; flags.insert(p["type"].lowercased() + "-parameter")
                if p["array"].lowercased() == "true" { flags.insert("array-parameter") }
                fields["parameter name"] = p["name"]
            }
            fields["expression"] = try adjusted(e,section:"Argument",key:"Needed",castKey:"Cast",flags:flags)
            return template.lines("Argument","Text",flags:flags).isEmpty ? fields["expression"]! : try fieldText("Argument",flags:flags,fields:fields)
        }.joined(separator:try SourceTemplate.expand(template.value("Argument","Separator").isEmpty ? ",{space}" : template.value("Argument","Separator"),fields:[:]))
    }
    func expr(_ expression: Expression, target: Bool = false) throws -> TemplateExpression {
        switch expression {
        case .literal(let value):
            let type: String, section: String
            var fields: [String:String] = [:]
            switch value {
            case .integer(let n): type = "integer"; section = "Integer Literal"; fields["integral"] = String(n)
            case .real(let n):
                if n == Double.pi, template.contains("Pi","Text") { return try operation("Pi",args:[],defaultType:"real") }
                type = "real"; section = "Real Literal"
                let parts = decimalText(n).split(separator:".",maxSplits:1).map(String.init)
                fields["integral"] = parts[0]; fields["fractional"] = parts.count > 1 ? parts[1] : "0"; fields["sign"] = n < 0 ? "-" : "+"
            case .string(let s):
                if s == "\n", template.contains("LF","Text") { return try operation("LF",args:[],defaultType:"string") }
                type = "string"; section = "String Literal"
                var chars = s
                for index in [2,1] {
                    let find = template.value(section,"Replace Char \(index)")
                    if !find.isEmpty { chars = chars.replacingOccurrences(of:find,with:template.value(section,"Replace By \(index)")) }
                }
                chars = chars.replacingOccurrences(of:"\n",with:"\\n").replacingOccurrences(of:"\r",with:"\\r").replacingOccurrences(of:"\t",with:"\\t")
                fields["characters"] = chars
            case .boolean(let b): return TemplateExpression(text:template.value("Boolean Literal",b ? "true" : "false"),type:"boolean")
            default: throw FlowError("Cannot generate this literal.")
            }
            return TemplateExpression(text:try fieldText(section,flags:[],fields:fields),type:type)
        case .variable(let name):
            if ["pi","newline"].contains(name.lowercased()) {
                return try operation(name.lowercased() == "pi" ? "Pi" : "LF",args:[],defaultType:name.lowercased() == "pi" ? "real" : "string")
            }
            let declaration = variables[name.lowercased()]
            return TemplateExpression(text:try fieldText("Variable Access",flags:target ? ["target"] : [],fields:["name":names[name.lowercased()] ?? name,"subscript":""]),type:declaration?["type"].lowercased() ?? "none",array:declaration?["array"].lowercased() == "true")
        case .index(let base,let index):
            let value = try expr(base)
            var flags: Set<String> = ["subscript",value.type]
            if target { flags.insert("target") }
            return TemplateExpression(text:try fieldText("Variable Access",flags:flags,fields:["name":value.text,"subscript":try expr(index).text]),type:value.type)
        case .unary(let op,let value):
            if op == "+" { return try expr(value) }
            return try operation(op == "!" || op == "not" ? "Not" : "Negate",args:[try expr(value)],defaultType:op == "!" || op == "not" ? "boolean" : try expr(value).type)
        case .binary(let op,let left,let right):
            let a = try expr(left), b = try expr(right)
            guard let section = binarySections[op] else { throw FlowError("Unknown source operator \(op).") }
            let type = ["Or","And","Equals","Not Equals","Less Than","Less Equal Than","Greater Than","Greater Equal Than"].contains(section) ? "boolean" : section == "Concatenate" ? "string" : section == "Divide" || section == "Power" || a.type == "real" || b.type == "real" ? "real" : a.type
            return try operation(section,args:[a,b],defaultType:type)
        case .call(let name,let values):
            if let f = program.functions.first(where:{ $0["name"].lowercased() == name.lowercased() }) {
                return TemplateExpression(text:try fieldText("Function Call",flags:values.isEmpty ? [] : ["arguments"],fields:["name":functionNames[name.lowercased()] ?? name,"arguments":try arguments(values,name:name)]),type:f["type"].lowercased())
            }
            let type = ["len","size","int","tointeger","tocode","random","sgn"].contains(name.lowercased()) ? "integer" : ["char","tochar","tostring","tofixed","lf","newline"].contains(name.lowercased()) ? "string" : name.lowercased() == "eof" ? "boolean" : "real"
            return try operation(name.lowercased() == "ln" ? "Log" : name,args:try values.map { try expr($0) },defaultType:type)
        }
    }
    func decimalText(_ value: Double) -> String {
        let text = String(value)
        guard let e = text.firstIndex(of:"e"), let exponent = Int(text[text.index(after:e)...]) else { return text }
        let negative = text.hasPrefix("-")
        let significand = String(text[..<e]).replacingOccurrences(of:"-",with:"")
        let parts = significand.components(separatedBy:".")
        let digits = parts.joined(), point = parts[0].count + exponent
        let result: String
        if point <= 0 { result = "0." + String(repeating:"0",count:-point) + digits }
        else if point >= digits.count { result = digits + String(repeating:"0",count:point - digits.count) + ".0" }
        else { result = String(digits.prefix(point)) + "." + digits.dropFirst(point) }
        return (negative ? "-" : "") + result
    }
    func operation(_ section: String, args: [TemplateExpression], defaultType: String) throws -> TemplateExpression {
        let flags = args.isEmpty ? Set<String>() : typeFlags(args[0],args.count > 1 ? args[1] : nil)
        var fields: [String:String] = [:]
        for (index,arg) in args.enumerated() { fields[String(index + 1)] = try adjusted(arg,section:section,key:"Needed \(index + 1)",castKey:"Cast \(index + 1)",flags:flags) }
        if args.count == 1 { fields["expression"] = fields["1"] }
        let type = template.value(section,"Type",flags:flags)
        return TemplateExpression(text:try fieldText(section,flags:flags,fields:fields),type:type.isEmpty ? defaultType : type.lowercased(),precedence:Int(template.value(section,"Precedence",flags:flags)) ?? 100)
    }
}
