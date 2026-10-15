import Foundation

public enum SourceLanguages {
    public static func builtIns() throws -> [SourceTemplate] {
        try ["Python","Java","CPP"].map { name in
            guard let url = Bundle.module.url(forResource:name,withExtension:"fpgt",subdirectory:"Templates") else { throw FlowError("Missing \(name) template resource.") }
            return try SourceTemplate(String(contentsOf:url,encoding:.utf8))
        }
    }
}
