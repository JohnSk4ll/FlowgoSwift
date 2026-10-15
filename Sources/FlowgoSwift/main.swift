import SwiftUI
import UniformTypeIdentifiers
import FlowCore

extension UTType {
    static var flowgorithm: UTType {
        UTType(filenameExtension:"fprg",conformingTo:.xml) ?? UTType(importedAs:"org.flowgorithm.fprg",conformingTo:.xml)
    }
}

struct FlowDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.flowgorithm, .xml] }
    var program: Program
    init(program: Program = Program()) { self.program = program }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw FlowError("Cannot read this file.") }
        program = try Program(data: data)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(program.xml.utf8))
    }
}

@main
struct FlowgoSwiftApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: FlowDocument()) { file in
            EditorView(document: file.$document, sourceURL: file.fileURL)
                .frame(minWidth:820,minHeight:520)
        }
        .defaultSize(width:1000,height:720)
        .commands {
            FlowCommands()
            CommandGroup(replacing: .appInfo) {
                Button("About FlowgoSwift") {
                    NSApplication.shared.orderFrontStandardAboutPanel(options: [
                        .applicationName: "FlowgoSwift", .applicationVersion: Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "1.0.0",
                        .credits: NSAttributedString(string: "An independent Swift app for Flowgorithm-compatible workflows.\nFlowgorithm was created by Devin Cook: https://www.flowgorithm.org/\nhttps://github.com/JohnSk4ll/FlowgoSwift")
                    ])
                }
            }
        }
    }
}
