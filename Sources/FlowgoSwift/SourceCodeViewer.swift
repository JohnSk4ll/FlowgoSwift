import SwiftUI
import UniformTypeIdentifiers
import FlowCore

final class SourceViewerModel: ObservableObject {
    @Published var templates: [SourceTemplate] = []
    @Published var selected = ""
    @Published var error: String?
    @Published var numbers = true
    @Published var colors = true
    @Published var compact = false
    @Published var support = true
    @Published var fontSize: CGFloat = 14
    @Published var aligned = false
    init() {
        do {
            templates = try SourceLanguages.builtIns()
            for source in UserDefaults.standard.stringArray(forKey:"sourceTemplates") ?? [] {
                if let template = try? SourceTemplate(source) { install(template,persist:false) }
            }
            selected = templates.first?.id ?? ""
        } catch { self.error = error.localizedDescription }
    }
    var template: SourceTemplate? { templates.first { $0.id == selected } }
    func install(_ template: SourceTemplate, persist: Bool = true) {
        if let index = templates.firstIndex(where:{ $0.id == template.id }) { templates[index] = template }
        else { templates.append(template) }
        if persist {
            var saved = UserDefaults.standard.stringArray(forKey:"sourceTemplates") ?? []
            saved.removeAll { (try? SourceTemplate($0).id) == template.id }
            saved.append(template.source); UserDefaults.standard.set(saved,forKey:"sourceTemplates")
            selected = template.id
        }
    }
    func load() {
        let panel = NSOpenPanel(); panel.prompt = "Load Template"; panel.allowedContentTypes = [.data]; panel.allowsOtherFileTypes = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf:url)
            guard data.count <= 1_048_576 else { throw FlowError("Templates must be smaller than 1 MB.") }
            let source: String
            if let value = String(data:data,encoding:.utf8) { source = value }
            else if let value = String(data:data,encoding:.utf16) { source = value }
            else { throw FlowError("Use UTF-8 or UTF-16 text for templates.") }
            install(try SourceTemplate(source))
        } catch { self.error = error.localizedDescription }
    }
    func save(_ text: String, filename: String) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = filename
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try text.write(to:url,atomically:true,encoding:.utf8) }
        catch { self.error = error.localizedDescription }
    }
}

struct SourceCodeViewer: View {
    let program: Program
    let selectedID: UUID?
    let choose: (UUID) -> Void
    let run: () -> Void
    let step: () -> Void
    @ObservedObject var execution: ExecutionController
    @ObservedObject var model: SourceViewerModel
    @Environment(\.colorScheme) private var scheme
    @State private var generated: GeneratedSource?
    @State private var generationError: String?
    private var activeID: UUID? { execution.currentID ?? selectedID }
    @State private var contentWidth: CGFloat = 850
    private func measureContent() {
        let font = NSFont(name:"Menlo",size:model.fontSize) ?? .monospacedSystemFont(ofSize:model.fontSize,weight:.regular)
        let width = generated?.lines.map { ($0.text as NSString).size(withAttributes:[.font:font]).width }.max() ?? 0
        contentWidth = max(850,width + 130)
    }
    private var badge: String {
        switch model.template?.fileExtension.lowercased() {
        case "py": return "Py"
        case "java": return "J"
        case "cpp", "cc", "cxx": return "C++"
        default: return String((model.template?.name ?? "?").prefix(2))
        }
    }
    private var supportsAligned: Bool { model.template?.value("Language","Options").lowercased().contains("aligned") == true }
    var body: some View {
        VStack(spacing:0) {
            HStack(spacing:9) {
                ZStack {
                    Circle().fill(model.template?.name == "Python" ? Color(hex:0x3477A3) : model.template?.name == "Java" ? Color(hex:0xBC542C) : Color(hex:0x536AC1))
                    Text(badge).font(.system(size:15,weight:.bold,design:.rounded)).foregroundColor(.white)
                }.frame(width:35,height:35).accessibilityHidden(true)
                Picker("Language",selection:$model.selected) {
                    ForEach(model.templates) { Text($0.name).tag($0.id) }
                }.labelsHidden().pickerStyle(.menu).menuIndicator(.visible).frame(width:135).accessibilityLabel("Source language")
                Divider().frame(height:28)
                toggle("list.number",title:"Line Numbers",value:$model.numbers)
                toggle("square.3.layers.3d",title:"Color Highlighting",value:$model.colors)
                toggle("arrow.up.and.down.text.horizontal",title:"Pad Code",value:Binding(get:{ !model.compact },set:{ model.compact = !$0 }))
                toggle("curlybraces",title:"Aligned Brace",value:$model.aligned).disabled(!supportsAligned)
                Button { model.fontSize = min(24,model.fontSize + 1) } label: { ClassicGlyph(name:"zoomIn") }.help("Larger text").accessibilityLabel("Larger text")
                Button { model.fontSize = max(10,model.fontSize - 1) } label: { ClassicGlyph(name:"zoomOut") }.help("Smaller text").accessibilityLabel("Smaller text")
                Divider().frame(height:28)
                Button { if let generated { model.save(generated.text,filename:model.template?.fileExtension == "java" ? "Program.java" : "program." + generated.fileExtension) } } label: { ClassicGlyph(name:"save") }.disabled(generated == nil).help("Save source").accessibilityLabel("Save source")
                Button {
                    if let generated { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(generated.text,forType:.string) }
                } label: { Image(systemName:"doc.on.doc").font(.system(size:22)) }.disabled(generated == nil).help("Copy source").accessibilityLabel("Copy source")
                Divider().frame(height:28)
                Button(action:run) { ClassicGlyph(name:"run") }.disabled(execution.running && !execution.paused).help("Run").accessibilityLabel("Run")
                Button(action:step) { ClassicGlyph(name:"step") }.disabled(execution.running && !execution.paused).help("Step").accessibilityLabel("Step")
                Button { execution.pause() } label: { ClassicGlyph(name:"pause") }.disabled(!execution.running || execution.paused).help("Pause").accessibilityLabel("Pause")
                Button { execution.stop() } label: { ClassicGlyph(name:"stop") }.disabled(!execution.running).help("Stop").accessibilityLabel("Stop")
                Spacer(minLength:0)
                Menu {
                    Button("Load Template…",action:model.load)
                    Button("Save Template…") { if let template = model.template { model.save(template.source,filename:template.name.replacingOccurrences(of:"+",with:"P") + ".fpgt") } }
                    Toggle("Show Support Code",isOn:$model.support)
                } label: { Image(systemName:"ellipsis.circle").font(.system(size:21)) }.help("Template options").accessibilityLabel("Template options")
            }.buttonStyle(.plain).padding(.horizontal,12).padding(.vertical,10).background(Color(nsColor:.controlBackgroundColor))
            Divider()
            if let generationError {
                VStack(alignment:.leading,spacing:12) { Label("Source could not be generated",systemImage:"exclamationmark.triangle").font(.headline); Text(generationError).textSelection(.enabled); Button("Load another template…",action:model.load) }.padding(24).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
            } else if let generated {
                ScrollViewReader { proxy in
                    ScrollView([.horizontal,.vertical]) {
                        LazyVStack(alignment:.leading,spacing:model.compact ? 2 : 8) {
                            ForEach(generated.lines) { line in
                                if model.support || line.statementID != nil { row(line).id(line.id) }
                            }
                        }.padding(.vertical,16).frame(width:contentWidth,alignment:.leading)
                            .background(alignment:.leading) { if model.numbers { Rectangle().fill(Color.gray.opacity(0.2)).frame(width:60) } }
                    }
                    .onChange(of:execution.currentID) { id in
                        if let id, let line = generated.lines.first(where:{ $0.statementID == id }) { proxy.scrollTo(line.id,anchor:.center) }
                    }
                    .onChange(of:selectedID) { id in
                        if let id, let line = generated.lines.first(where:{ $0.statementID == id }) { proxy.scrollTo(line.id,anchor:.center) }
                    }
                }
            } else { ProgressView().frame(maxWidth:.infinity,maxHeight:.infinity) }
            Divider()
            HStack { Text(generated.map { "\($0.lines.count) lines · \($0.language)" } ?? ""); Spacer(); Text(execution.status).lineLimit(1) }.font(.system(size:11)).foregroundColor(.secondary).padding(.horizontal,12).padding(.vertical,7).background(Color(nsColor:.controlBackgroundColor))
        }.frame(minWidth:820,minHeight:400).background(Color(nsColor:.textBackgroundColor))
            .onAppear(perform:generate)
            .onChange(of:program) { _ in generate() }
            .onChange(of:model.selected) { _ in generate() }
            .onChange(of:model.templates) { _ in generate() }
            .onChange(of:model.fontSize) { _ in measureContent() }
            .onChange(of:model.aligned) { _ in generate() }
            .alert("Template",isPresented:Binding(get:{ model.error != nil },set:{ if !$0 { model.error = nil } })) { Button("OK") { model.error = nil } } message: { Text(model.error ?? "") }
    }
    private func generate() {
        do {
            guard let template = model.template else { throw FlowError("Load a source template to begin.") }
            generated = try TemplateExporter.generate(program,template:template,options:model.aligned && supportsAligned ? ["aligned"] : [])
            measureContent()
            generationError = nil
        } catch { generated = nil; generationError = error.localizedDescription }
    }
    private func toggle(_ icon: String, title: String, value: Binding<Bool>) -> some View {
        Button { value.wrappedValue.toggle() } label: {
            Image(systemName:icon).font(.system(size:20)).frame(width:30,height:32)
                .background(value.wrappedValue ? Color.accentColor.opacity(0.18) : .clear).cornerRadius(4)
        }.help(title).accessibilityLabel(title).accessibilityValue(value.wrappedValue ? "On" : "Off")
    }
    private func row(_ line: SourceLine) -> some View {
        let indent = line.text.prefix { $0 == " " }.count
        let text = String(line.text.dropFirst(indent))
        let tag = line.tag == "function" ? "terminal" : line.tag ?? "comment"
        let palette = ChartPalette(Element(tag),selected:line.statementID != nil && line.statementID == selectedID,executing:line.statementID != nil && line.statementID == execution.currentID,dark:scheme == .dark)
        return HStack(alignment:.center,spacing:0) {
            if model.numbers {
                Text(String(line.id + 1)).font(.custom("Menlo",size:model.fontSize - 2)).foregroundColor(.secondary)
                    .frame(width:48,alignment:.trailing).padding(.trailing,12).frame(height:model.fontSize + 12)
            }
            Text(text.isEmpty ? " " : text).font(.custom("Menlo",size:model.fontSize)).fixedSize(horizontal:true,vertical:false).textSelection(.enabled)
                .foregroundColor(model.colors && line.tag != nil ? palette.text : Color(nsColor:.labelColor))
                .padding(.horizontal,8).padding(.vertical,4)
                .background(model.colors && line.tag != nil && !text.isEmpty ? palette.fill : .clear)
                .overlay(Rectangle().stroke(model.colors && line.tag != nil && !text.isEmpty ? palette.border : line.statementID != nil && line.statementID == activeID ? Color.accentColor : .clear,lineWidth:1))
                .padding(.leading,16 + CGFloat(indent) * model.fontSize * 0.6)
                .onTapGesture { if let id = line.statementID { choose(id) } }
            Spacer(minLength:24)
        }.frame(height:model.fontSize + 12).accessibilityElement(children:.combine)
    }
}
