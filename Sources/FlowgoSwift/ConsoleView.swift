import SwiftUI
import FlowCore
import UniformTypeIdentifiers

struct ConsoleView: View {
    @ObservedObject var execution: ExecutionController
    @Binding var input: String
    let transport: AnyView
    let variables: () -> Void
    let source: () -> Void
    let turtle: () -> Void
    let submit: () -> Void
    @AppStorage("consoleChatBubbles") private var bubbles = true
    @AppStorage("consoleShowBreakpoints") private var showBreakpoints = true
    @AppStorage("consoleFontSize") private var fontSize = 14.0
    @Environment(\.colorScheme) private var scheme
    @State private var error: String?
    var body: some View {
        VStack(spacing:0) {
            HStack(spacing:5) {
                control("Chat Bubbles",icon:"bubble.left.and.bubble.right",selected:bubbles) { bubbles.toggle() }
                Divider().frame(height:30)
                transport
                Spacer(minLength:0)
                Menu {
                    Button("Save…",action:save)
                    Button("Copy to Clipboard") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(execution.consoleText,forType:.string) }
                    Button("Clear Window") { execution.clearConsole() }
                    Divider()
                    Button("Zoom In") { fontSize = min(32,fontSize + 1) }
                    Button("Zoom Out") { fontSize = max(9,fontSize - 1) }
                    Toggle("Show Breakpoints",isOn:$showBreakpoints)
                } label: { Image(systemName:"ellipsis.circle").font(.system(size:22)) }.menuStyle(.borderlessButton).fixedSize().help("Console Options")
                control("Variable Watch",icon:"x.squareroot",action:variables)
                control("Source Code Viewer",icon:"doc.text",action:source)
                control("Turtle Graphics",icon:"tortoise",action:turtle)
            }.padding(8).background(Color(nsColor:.controlBackgroundColor))
            Divider()
            GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView([.vertical,.horizontal]) {
                    VStack(alignment:.leading,spacing:18) {
                        if bubbles {
                            ForEach(execution.consoleLines(showBreakpoints:showBreakpoints)) { line in
                                let palette = ChartPalette(Element(line.breakpoint ? "breakpoint" : line.input ? "input" : "output"),dark:scheme == .dark)
                                HStack {
                                    if line.input { Spacer(minLength:45) }
                                    Text(line.text.isEmpty ? " " : line.text).font(.custom("Arial",size:fontSize))
                                        .foregroundColor(palette.text).textSelection(.enabled).padding(10)
                                        .background(palette.fill).overlay(Rectangle().stroke(palette.border,lineWidth:1))
                                    if !line.input { Spacer(minLength:45) }
                                }.id(line.id)
                            }
                        } else {
                            Text(execution.consoleLines(showBreakpoints:showBreakpoints).map(\.text).joined(separator:"\n"))
                                .font(.system(size:fontSize,design:.monospaced)).textSelection(.enabled)
                                .frame(maxWidth:.infinity,alignment:.topLeading)
                        }
                        Color.clear.frame(height:1).id("consoleEnd")
                    }.frame(minWidth:max(420,geometry.size.width - 36),minHeight:200,alignment:.topLeading).padding(18)
                }.onChange(of:execution.console) { _ in proxy.scrollTo("consoleEnd",anchor:.bottom) }
            }
            }.background(Color(nsColor:.textBackgroundColor))
            Divider()
            HStack(spacing:14) {
                VStack(alignment:.leading,spacing:4) {
                    if execution.waitingForInput { Text(execution.inputPrompt).font(.caption) }
                    TextField("",text:$input).textFieldStyle(.roundedBorder).onSubmit(submit).disabled(!execution.waitingForInput)
                }
                Button("Enter",action:submit).disabled(!execution.waitingForInput)
            }.padding(14).background(Color(nsColor:.controlBackgroundColor))
        }.frame(minWidth:540,minHeight:300)
            .alert("Cannot save console",isPresented:Binding(get:{ error != nil },set:{ if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
    }
    private func control(_ title: String,icon: String,selected: Bool = false,action: @escaping () -> Void) -> some View {
        Button(action:action) { Image(systemName:icon).font(.system(size:22)).frame(width:32,height:32) }
            .buttonStyle(ClassicToolbarStyle(selected:selected)).help(title).accessibilityLabel(title)
    }
    private func save() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.plainText]; panel.nameFieldStringValue = "Console.txt"
        if panel.runModal() == .OK, let url = panel.url {
            do { try execution.consoleText.write(to:url,atomically:true,encoding:.utf8) } catch { self.error = error.localizedDescription }
        }
    }
}
