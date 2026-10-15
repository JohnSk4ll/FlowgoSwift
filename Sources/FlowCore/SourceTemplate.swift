import Foundation

public struct TemplateLine: Equatable {
    public let text: String
    public let flags: String
    public let indent: Int
    public func matches(_ enabled: Set<String>) -> Bool {
        flags.lowercased().split(separator:",").allSatisfy { raw in
            let flag = raw.trimmingCharacters(in:.whitespaces)
            return flag.hasPrefix("~") ? !enabled.contains(String(flag.dropFirst())) : enabled.contains(flag)
        }
    }
}

public struct SourceTemplate: Equatable, Identifiable {
    public var id: String { name + ":" + fileExtension }
    public let source: String
    private var sections: [String:[TemplateLine]] = [:]
    public var name: String { value("Language","Name") }
    public var fileExtension: String { value("Language","Extension").trimmingCharacters(in:CharacterSet(charactersIn:".")) }
    public init(_ source: String) throws {
        self.source = source
        var section = "language", previous: String?
        for (index, raw) in source.replacingOccurrences(of:"\u{FEFF}",with:"").components(separatedBy:.newlines).enumerated() {
            let line = raw.trimmingCharacters(in:.whitespaces)
            if line.isEmpty || line.hasPrefix(";") { continue }
            if line.hasPrefix("[") && line.hasSuffix("]") {
                section = String(line.dropFirst().dropLast()).lowercased(); previous = nil; continue
            }
            var declaration = line
            if !line.contains("="), let previous {
                let text = line.components(separatedBy:"|").first?.trimmingCharacters(in:.whitespaces) ?? ""
                if text.isEmpty || (previous.hasSuffix("/precedence") && Int(text) != nil) { declaration = "=" + line }
            }
            guard let equal = declaration.firstIndex(of:"=") else { throw FlowError("Template line \(index + 1): expected a section or key/value.") }
            let key = String(declaration[..<equal]).trimmingCharacters(in:.whitespaces).lowercased()
            let identifier: String
            if key.isEmpty {
                guard let previous else { throw FlowError("Template line \(index + 1): continuation has no key.") }
                identifier = previous
            } else { identifier = section + "/" + key; sections[identifier] = []; previous = identifier }
            var parts = String(declaration[declaration.index(after:equal)...]).components(separatedBy:"|")
            guard parts.count <= 3 else { throw FlowError("Template line \(index + 1): use {pipe} for a literal pipe.") }
            if parts.count == 3, ["input","output","array","files","turtle"].contains(parts[2].trimmingCharacters(in:.whitespaces).lowercased()) {
                parts[1] += "," + parts[2]; parts[2] = ""
            }
            let indentation = parts.count > 2 ? parts[2].trimmingCharacters(in:.whitespaces) : ""
            guard indentation.isEmpty || Int(indentation) != nil else { throw FlowError("Template line \(index + 1): invalid indentation.") }
            guard (-256...256).contains(Int(indentation) ?? 0) else { throw FlowError("Template line \(index + 1): indentation is too large.") }
            sections[identifier,default:[]].append(TemplateLine(text:parts[0].trimmingCharacters(in:.whitespaces),flags:parts.count > 1 ? parts[1].trimmingCharacters(in:.whitespaces) : "",indent:Int(indentation) ?? 0))
        }
        guard !name.isEmpty, !fileExtension.isEmpty, !lines("Program","Text").isEmpty, !lines("Main","Text").isEmpty else {
            throw FlowError("A template requires Language Name/Extension, Program Text, and Main Text.")
        }
        guard fileExtension.allSatisfy({ $0.isLetter || $0.isNumber }) else { throw FlowError("Invalid template file extension.") }
    }
    public func lines(_ section: String, _ key: String, flags: Set<String> = []) -> [TemplateLine] {
        (sections[section.lowercased() + "/" + key.lowercased()] ?? []).filter { $0.matches(flags) }
    }
    public func value(_ section: String, _ key: String, flags: Set<String> = []) -> String {
        lines(section,key,flags:flags).first?.text ?? ""
    }
    public func contains(_ section: String, _ key: String) -> Bool { sections[section.lowercased() + "/" + key.lowercased()] != nil }
    public static func expand(_ text: String, fields: [String:String]) throws -> String {
        let normalized = Dictionary(fields.map { ($0.key.lowercased(),$0.value) },uniquingKeysWith:{ _,new in new })
        var result = "", index = text.startIndex
        while index < text.endIndex {
            let char = text[index]; index = text.index(after:index)
            if char != "{" { result.append(char); continue }
            if index < text.endIndex, text[index] == "{" { result.append("{"); index = text.index(after:index); continue }
            guard let end = text[index...].firstIndex(of:"}") else { throw FlowError("Unclosed template field in: \(text)") }
            let key = String(text[index..<end]).lowercased()
            if key == "space" { result += " " }
            else if key == "pipe" { result += "|" }
            else if let value = normalized[key] { result += value }
            else if result.last == "$", key.range(of: #"^[A-Za-z0-9_@*?$#%./:-]+$"#, options: .regularExpression) != nil { result += "{" + text[index..<end] + "}" }
            else { throw FlowError("Unknown template field {\(key)}.") }
            index = text.index(after:end)
        }
        return result
    }
}

public struct SourceLine: Equatable, Identifiable {
    public let id: Int
    public let text: String
    public let statementID: UUID?
    public let tag: String?
    public init(id: Int, text: String, statementID: UUID? = nil, tag: String? = nil) {
        self.id = id; self.text = text; self.statementID = statementID; self.tag = tag
    }
}

public struct GeneratedSource: Equatable {
    public let language: String
    public let fileExtension: String
    public let lines: [SourceLine]
    public var text: String { lines.map(\.text).joined(separator:"\n") + "\n" }
}
