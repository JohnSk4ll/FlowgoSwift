import Foundation
import FlowCore

let arguments = Array(CommandLine.arguments.dropFirst())
do {
    guard let path = arguments.first else { throw FlowError("Usage: flow <program.fprg> [--validate | --xml | --python | --source python|java|c++ | --template file.fpgt | --turtle-svg output.svg] [--aligned]") }
    for option in ["--source", "--template", "--turtle-svg"] where arguments.contains(option) {
        let index = arguments.firstIndex(of:option)!
        guard arguments.indices.contains(index + 1), !arguments[index + 1].hasPrefix("--") else { throw FlowError("Missing value for " + option) }
    }
    let program = try Program(data: Data(contentsOf: URL(fileURLWithPath: path)))
    let options: Set<String> = arguments.contains("--aligned") ? ["aligned"] : []
    if let index = arguments.firstIndex(of:"--template"), arguments.indices.contains(index + 1) {
        let template = try SourceTemplate(String(contentsOfFile:arguments[index + 1],encoding:.utf8))
        print(try TemplateExporter.generate(program,template:template,options:options).text,terminator:"")
    } else if let index = arguments.firstIndex(of:"--source"), arguments.indices.contains(index + 1) {
        guard let template = try SourceLanguages.builtIns().first(where:{ $0.name.lowercased() == arguments[index + 1].lowercased() }) else { throw FlowError("Choose python, java, or c++.") }
        print(try TemplateExporter.generate(program,template:template,options:options).text,terminator:"")
    } else if arguments.contains("--python") { print(try PythonExporter.generate(program), terminator: "") }
    else if arguments.contains("--xml") { print(program.xml, terminator: "") }
    else if arguments.contains("--validate") {
        try program.validate()
        print("Valid: \(program.functions.count) functions")
    } else {
        let interpreter = Interpreter(program)
        interpreter.baseDirectory = URL(fileURLWithPath: path).deletingLastPathComponent()
        try interpreter.run()
        if let index = arguments.firstIndex(of: "--turtle-svg"), arguments.indices.contains(index + 1) {
            try interpreter.turtle.svg.write(toFile: arguments[index + 1], atomically: true, encoding: .utf8)
        }
    }
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(1)
}
