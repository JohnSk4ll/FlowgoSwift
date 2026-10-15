import SwiftUI
import FlowCore

struct EditorView: View {
    @Environment(\.colorScheme) private var scheme
    @Binding var document: FlowDocument
    let sourceURL: URL?
    @StateObject private var execution = ExecutionController()
    @StateObject private var sourceViewer = SourceViewerModel()
    @State private var functionIndex = 1
    @State private var selection: [Int] = []
    @State private var selectedPaths = Set<[Int]>()
    @State private var selectionRectangle: CGRect?
    @State private var breakpoints = Set<UUID>()
    @State private var ignoreBreakpoints = false
    @State private var input = ""
    @State private var showConsole = false
    @State private var showVariables = false
    @State private var showFunctions = false
    @State private var showAttributes = false
    @State private var showSource = false
    @State private var showTurtle = false
    @State private var showOutline = false
    @State private var editing: ShapeEdit?
    @State private var managerEditing: ShapeEdit?
    @StateObject private var chartCoordinates = ChartCoordinateSpace()
    @State private var speed = "Full Speed"
    @State private var showXML = false
    @State private var xmlDraft = ""
    @State private var error: String?
    @State private var zoom: CGFloat = 1
    @State private var history: [Program] = []
    @State private var future: [Program] = []
    private let statements = ["declare", "assign", "input", "output", "if", "while", "do", "for", "call", "comment", "breakpoint", "open", "close", "read", "write", "forward", "turn", "home", "clear", "pen"]
    private var root: Element { document.program.root }
    private var functions: [(Int, Element)] { root.children.enumerated().filter { $0.element.tag == "function" }.map { ($0.offset, $0.element) } }
    private var selected: Element? { selection.isEmpty ? nil : root.element(at: selection) }
    private var function: Element? { root.children.indices.contains(functionIndex) ? root.children[functionIndex] : nil }
    private var bodyPath: [Int] {
        guard let index = function?.children.firstIndex(where: { $0.tag == "body" }) else { return [] }
        return [functionIndex, index]
    }
    private var chartLayout: ChartLayout {
        ChartLayout(function: function ?? document.program.functions[0], path: [functionIndex])
    }
    var body: some View {
        VStack(spacing: 0) {
            attributionBar
            Divider()
            classicMenuBar
            editorToolbar
            Divider()
            HSplitView {
                if showOutline { sidebar.frame(minWidth:200,idealWidth:240,maxWidth:300) }
                GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView([.vertical,.horizontal]) {
                        ClassicChart(layout:chartLayout, selection:selection, selectedPaths:selectedPaths, currentID:execution.currentID,
                                     breakpoints:breakpoints, zoom:zoom, editable:!execution.running,
                                     choose:choose, edit:editShape, insert:insert,
                                     remove:{ chooseForAction($0); remove() }, copy:{ chooseForAction($0); copySelection() },paste:pasteStatements)
                            .background(ChartCoordinateAnchor(space:chartCoordinates))
                            .padding(.horizontal,30).padding(.bottom,35)
                            .frame(minWidth:max(760,geometry.size.width),minHeight:max(500,geometry.size.height),alignment:.top)
                    }.background(Color(nsColor:.textBackgroundColor))
                        .onChange(of:execution.currentID) { id in if let id { proxy.scrollTo(id,anchor:.center) } }
                }
                .overlay {
                    WorkspaceSelectionControl(layout:chartLayout,coordinateSpace:chartCoordinates,zoom:zoom,enabled:!execution.running,select:selectMany,rectangle:{ selectionRectangle = $0 }).allowsHitTesting(false)
                }
                .overlay(alignment:.topLeading) {
                    if let rectangle = selectionRectangle {
                        Rectangle().fill(Color.accentColor.opacity(0.12)).overlay(Rectangle().stroke(Color.accentColor,lineWidth:1))
                            .frame(width:rectangle.width,height:rectangle.height).position(x:rectangle.midX,y:rectangle.midY).allowsHitTesting(false)
                    }
                }
                }
            }
            Divider()
            HStack {
                Text(execution.status).lineLimit(2).textSelection(.enabled)
                Spacer()
                Text("EN")
            }.font(.custom("Arial",size:13)).padding(.horizontal,14).padding(.vertical,9)
                .background(Color(nsColor:.controlBackgroundColor))
        }.background(Color(nsColor:.controlBackgroundColor))
        .background(DocumentWindowTitle(title:sourceURL?.deletingPathExtension().lastPathComponent ?? "(Untitled)").frame(width:0,height:0))
        .background(ToolWindow(presented:$showConsole,title:"Console",size:CGSize(width:620,height:440),actions:flowActions) { console }.frame(width:0,height:0))
        .background(ToolWindow(presented:$showVariables,title:"Variable Watch",size:CGSize(width:330,height:480),actions:flowActions) { VariableWatch(execution:execution) }.frame(width:0,height:0))
        .background(ToolWindow(presented:$showSource,title:"Source Code Viewer",size:CGSize(width:1000,height:650),actions:flowActions) { sourceCode }.frame(width:0,height:0))
        .background(ToolWindow(presented:$showXML,title:"XML Editor",size:CGSize(width:800,height:600),actions:flowActions) { xmlEditor }.frame(width:0,height:0))
        .background(ToolWindow(presented:$showTurtle,title:"Turtle Graphics",size:CGSize(width:550,height:470),actions:flowActions) { TurtleView(execution:execution,transport:AnyView(transport)) }.frame(width:0,height:0))
        .sheet(item:$editing) { item in
            if item.node.tag == "function" { functionEditor(item) }
            else {
                StatementEditor(draft:item.node) { replacement in
                    edit { $0.root.update(at:item.path) { $0 = replacement } }
                }
            }
        }
        .sheet(isPresented:$showAttributes) {
            ProgramAttributesEditor(attributes:root.child("attributes") ?? Element("attributes")) { attributes in
                edit { program in
                    if let index = program.root.children.firstIndex(where:{ $0.tag == "attributes" }) { program.root.children[index] = attributes }
                    else { program.root.children.insert(attributes,at:0) }
                }
            }
        }
        .sheet(isPresented:$showFunctions) {
            VStack(spacing:0) {
                HStack { Text("Function Manager").font(.headline); Spacer(); Button("Import…",action:importFunctions).disabled(execution.running); Button("Done") { showFunctions = false }.keyboardShortcut(.defaultAction) }.padding(14)
                Divider()
                HSplitView { sidebar.frame(width:240); inspector.frame(width:330) }
            }.frame(width:620,height:540)
                .sheet(item:$managerEditing) { item in functionEditor(item) }
        }
        .focusedSceneValue(\.flowActions,flowActions)
        .background(CommandWindowActions(actions:flowActions).frame(width:0,height:0))
        .onAppear {
            if let main = functions.first(where: { FlowIdentifier.key($0.1["name"]) == "main" }) { functionIndex = main.0 }
            selection = []
        }
        .onDisappear { execution.stop() }
        .onChange(of:selection) { path in
            if !selectedPaths.contains(path) { selectedPaths = path.isEmpty ? [] : [path] }
        }
        .onChange(of:functionIndex) { _ in selectedPaths = [] }
        .onChange(of:execution.function) { name in
            if let next = functions.first(where: { $0.1["name"] == name }) { functionIndex = next.0 }
        }
        .onChange(of:ignoreBreakpoints) { execution.setIgnoreBreakpoints($0) }
        .onChange(of:execution.waitingForInput) { waiting in if waiting { showConsole = true } }
        .alert("Cannot complete action", isPresented:Binding(get:{ error != nil },set:{ if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
    private var flowActions: FlowActions {
        FlowActions(
            running:execution.running, paused:execution.paused, selected:selected != nil,
            run:{ startOrResume() }, step:{ singleStep() }, pause:{ execution.pause() }, stop:{ execution.stop() },
            functions:{ showFunctions = true; selection = [functionIndex] }, console:{ showConsole.toggle() },
            variables:{ showVariables.toggle() }, source:{ showSource.toggle() }, turtle:{ showTurtle.toggle() },
            zoomIn:{ zoom = min(2,zoom + 0.1) }, zoomOut:{ zoom = max(0.4,zoom - 0.1) },
            edit:{ editShape(selection) }, delete:{ remove() }, undo:undo, redo:redo,
            ignoreBreakpoints:ignoreBreakpoints,setIgnoreBreakpoints:{ ignoreBreakpoints = $0 },
            removeBreakpoints:{ breakpoints = []; removeBreakpointShapes() },attributes:{ showAttributes = true },importFunctions:importFunctions,print:printChart,copy:copySelection,paste:pasteSelection,cut:{ if !execution.running { copySelection(); remove() } })
    }
    private var attributionBar: some View {
        HStack(spacing: 4) {
            Link("Flowgorithm", destination: URL(string: "https://www.flowgorithm.org/")!)
            Text("was created by")
                .foregroundStyle(.secondary)
            Link("Devin Cook", destination: URL(string: "https://devincook.com/")!)
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
    private var classicMenuBar: some View {
        HStack(spacing:18) {
            Menu("File") {
                Button("New") { documentAction("newDocument:") }
                Button("Open…") { documentAction("openDocument:") }
                Button("Save") { documentAction("saveDocument:") }
                Button("Save As…") { documentAction("saveDocumentAs:") }
                Button("Print…",action:printChart)
                Divider()
                Button("Export Image…") { exportChart(pdf:false) }
                Button("Export PDF…") { exportChart(pdf:true) }
            }.fixedSize()
            Menu("Edit") {
                Button("Undo",action:undo).disabled(history.isEmpty || execution.running)
                Button("Redo",action:redo).disabled(future.isEmpty || execution.running)
                Divider()
                Button("Edit Shape") { editShape(selection) }.disabled(selected == nil || execution.running)
                Button("Cut") { copySelection(); remove() }.disabled(selection.count < 3 || execution.running)
                Button("Copy",action:copySelection).disabled(selected == nil)
                Button("Paste",action:pasteSelection).disabled(execution.running)
                Button("Delete",action:remove).disabled(selection.count < 3 || execution.running)
            }.fixedSize()
            Menu("Appearance") {
                Button("Zoom In") { zoom = min(2,zoom + 0.1) }
                Button("Zoom Out") { zoom = max(0.4,zoom - 0.1) }
                Button("Actual Size") { zoom = 1 }
                Toggle("Show Outline",isOn:$showOutline)
            }.fixedSize()
            Menu("Program") {
                Button("Run",action:startOrResume).disabled(execution.running && !execution.paused)
                Button("Step",action:singleStep).disabled(execution.running && !execution.paused)
                Button("Pause") { execution.pause() }.disabled(!execution.running || execution.paused)
                Button("Stop") { execution.stop() }.disabled(!execution.running)
                Divider()
                Button("Import Functions…",action:importFunctions).disabled(execution.running)
                Button("Function Manager…") { selection = [functionIndex]; showFunctions = true }
                Button("Program Attributes…") { showAttributes = true }.disabled(execution.running)
                Toggle("Ignore Breakpoints",isOn:$ignoreBreakpoints)
                Button("Remove Breakpoints") { breakpoints = []; removeBreakpointShapes() }.disabled(execution.running)
            }.fixedSize()
            Menu("Tools") {
                Toggle("Console",isOn:$showConsole)
                Toggle("Variable Watch",isOn:$showVariables)
                Toggle("Source Code Viewer",isOn:$showSource)
                Button("XML Editor…") { xmlDraft = document.program.xml; showXML = true }
                Toggle("Turtle Graphics",isOn:$showTurtle)
                Divider()
                Button("Export Python…",action:exportPython)
                Button("Export Turtle SVG…",action:exportTurtle)
            }.fixedSize()
            Menu("Help") { Button("About FlowgoSwift") { NSApplication.shared.orderFrontStandardAboutPanel(nil) } }.fixedSize()
            Spacer()
        }.font(.custom("Arial",size:13)).menuStyle(.borderlessButton).menuIndicator(.hidden)
            .fixedSize(horizontal:false,vertical:true).padding(.horizontal,14).padding(.top,6).padding(.bottom,3)
    }
    private var xmlEditor: some View {
        VStack {
            TextEditor(text:$xmlDraft).font(.system(size:13,design:.monospaced)).disabled(execution.running)
            HStack { Spacer(); Button("Apply XML",action:applyXML).disabled(execution.running) }.padding(10)
        }
    }
    private var sourceCode: some View {
        SourceCodeViewer(program:document.program,selectedID:selected?.id,choose:{ id in
            if let path = findPath(root,id:id) { functionIndex = path.first ?? functionIndex; selection = path }
        },run:startOrResume,step:singleStep,execution:execution,model:sourceViewer)
    }
    private func findPath(_ node: Element, id: UUID, path: [Int] = []) -> [Int]? {
        if node.id == id { return path }
        for (index,child) in node.children.enumerated() { if let found = findPath(child,id:id,path:path + [index]) { return found } }
        return nil
    }
    private func documentAction(_ selector: String) { NSApp.sendAction(Selector(selector),to:nil,from:nil) }
    private func startOrResume() { if execution.running { execution.resume() } else { run(stepping:false) } }
    private func singleStep() { if execution.running { execution.step() } else { run(stepping:true) } }
    private func editShape(_ path: [Int]) {
        guard !execution.running, let node = root.element(at:path), !path.isEmpty else { return }
        selection = path
        if node.tag == "function" { presentFunctionEditor(ShapeEdit(path:path,node:node)) }
        else if !["home","clear"].contains(node.tag) { editing = ShapeEdit(path:path,node:node) }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("FUNCTIONS").font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                Button { addFunction() } label: { Image(systemName: "plus") }.disabled(execution.running)
            }.padding(.horizontal, 12).padding(.top, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(functions, id: \.0) { index, item in
                        Button {
                            functionIndex = index; choose([index])
                        } label: {
                            HStack {
                                Image(systemName: "function")
                                Text(item["name"])
                                Spacer()
                                Text(item["type"]).font(.caption).foregroundStyle(.secondary)
                            }.padding(8).contentShape(Rectangle()).background(functionIndex == index ? Color.accentColor.opacity(0.14) : Color.clear).cornerRadius(6)
                        }.buttonStyle(.plain)
                            .simultaneousGesture(TapGesture(count:2).onEnded {
                                functionIndex = index; choose([index]); presentFunctionEditor(ShapeEdit(path:[index],node:item))
                            })
                    }
                    Divider().padding(.vertical, 8)
                    if let item = function {
                        OutlineNode(node: item, path: [functionIndex], selected: selection, choose: choose)
                    }
                }.padding(.horizontal, 8)
            }
            Divider()
            HStack {
                Button { undo() } label: { Image(systemName: "arrow.uturn.backward") }.help("Undo chart edit").disabled(history.isEmpty || execution.running)
                Button { redo() } label: { Image(systemName: "arrow.uturn.forward") }.help("Redo chart edit").disabled(future.isEmpty || execution.running)
                Spacer()
                Menu("Export") {
                    Button("Python Source") { exportPython() }
                    Button("Turtle SVG") { exportTurtle() }
                    Button("Flowchart PDF") { exportChart(pdf: true) }
                    Button("Flowchart PNG") { exportChart(pdf: false) }
                }.disabled(execution.running)
            }.padding(10)
        }.background(Color(nsColor: .controlBackgroundColor))
    }
    private var editorToolbar: some View {
        HStack(spacing:1) {
            tool("open","Open") { documentAction("openDocument:") }
            tool("save","Save") { documentAction("saveDocument:") }
            toolbarDivider
            transport
            toolbarDivider
            Menu {
                ForEach(["Slow", "Medium", "Fast", "Full Speed"],id:\.self) { value in
                    Button(value) {
                        speed = value
                        execution.setSpeed(["Slow":1.0,"Medium":0.3,"Fast":0.08,"Full Speed":0][value] ?? 0)
                    }
                }
            } label: { ClassicGlyph(name:"speed") }.menuStyle(.borderlessButton).frame(width:43,height:38).help("Execution Speed: " + speed).accessibilityLabel("Speed")
            toolbarDivider
            Picker("Function",selection:$functionIndex) {
                ForEach(functions,id:\.0) { index,item in Text(item["name"]).tag(index) }
            }.labelsHidden().frame(width:108).padding(.horizontal,6)
                .onChange(of:functionIndex) { index in if selection.first != index { selection = showFunctions ? [index] : [] } }
            tool("functions","Function Manager") { selection = [functionIndex]; showFunctions = true }
            toolbarDivider
            tool("zoomIn","Zoom In") { zoom = min(2,zoom + 0.1) }
            tool("zoomOut","Zoom Out") { zoom = max(0.4,zoom - 0.1) }
            tool("appearance","Actual Size") { zoom = 1 }
            toolbarDivider
            tool("variables","Variable Watch",selected:showVariables) { showVariables.toggle() }
            tool("console","Console",selected:showConsole) { showConsole.toggle() }
            tool("source","Source Code Viewer",selected:showSource) { showSource.toggle() }
            Spacer(minLength:0)
        }.padding(.horizontal,8).padding(.vertical,5).background(Color(nsColor:.controlBackgroundColor))
    }
    private var toolbarDivider: some View { Rectangle().fill(Color(hex:0xAAAAAA)).frame(width:1,height:30).padding(.horizontal,6) }
    private var transport: some View {
        HStack(spacing:1) {
            tool("run","Run",action:startOrResume).disabled(execution.running && !execution.paused)
            tool("step","Step",action:singleStep).disabled(execution.running && !execution.paused)
            tool("pause","Pause") { execution.pause() }.disabled(!execution.running || execution.paused)
            tool("stop","Stop") { execution.stop() }.disabled(!execution.running)
        }
    }
    private func tool(_ icon: String, _ title: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action:action) { ClassicGlyph(name:icon) }.buttonStyle(ClassicToolbarStyle(selected:selected)).help(title).accessibilityLabel(title)
    }
    private var inspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(selected?.tag == "function" ? "Function Properties" : selected?.tag == "parameter" ? "Edit Parameter" : "Properties").font(.headline)
            if let item = selected {
                Text(item.tag == "assign" ? "Assignment" : item.tag.capitalized).font(.title3.bold())
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if item.tag == "function" {
                            Text(item["name"]).font(.headline)
                            Text("Return Type: " + item["type"])
                            ForEach(FunctionProperties.parameters(item)) { Text($0.label) }
                            Button("Edit…") { presentFunctionEditor(ShapeEdit(path:selection,node:item)) }
                        }
                        ForEach(item.tag == "function" ? [] : item.attributes.keys.sorted(), id: \.self) { key in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(inspectorLabel(key,item:item)).font(.caption).foregroundStyle(.secondary)
                                if key == "type" {
                                    Picker(key, selection: attribute(key)) {
                                        ForEach(item.tag == "function" ? ["None", "Integer", "Real", "String", "Boolean"] : ["Integer", "Real", "String", "Boolean"], id: \.self) { Text($0).tag($0) }
                                    }.labelsHidden().disabled(item.tag == "function" && FlowIdentifier.key(item["name"]) == "main")
                                } else if key == "array" || key == "newline" {
                                    Toggle(inspectorLabel(key,item:item),isOn:Binding(get:{ item[key].lowercased() == "true" },set:{ attribute(key).wrappedValue = $0 ? "True" : "False" })).labelsHidden()
                                } else {
                                    TextField(inspectorLabel(key,item:item), text: attribute(key), axis: .vertical).textFieldStyle(.roundedBorder).disabled(item.tag == "function" && (FlowIdentifier.key(item["name"]) == "main" || key == "variable" && item["type"].lowercased() == "none"))
                                }
                            }
                        }
                        if item.tag == "declare" {
                            if item.attributes["array"] == nil { Button("Make Array") { edit { $0.root.update(at: selection) { $0["array"] = "True"; $0["size"] = "10" } } } }
                        }
                        if item.tag == "function" {
                            Button("Add Parameter") { addParameter() }.disabled(FlowIdentifier.key(item["name"]) == "main")
                            Button("Edit Body") { selection = bodyPath }
                        }
                        if !["function", "body", "then", "else", "parameters", "parameter"].contains(item.tag) {
                            Toggle("Breakpoint", isOn: Binding(get: { breakpoints.contains(item.id) }, set: { value in
                                if value { breakpoints.insert(item.id) } else { breakpoints.remove(item.id) }
                            }))
                        }
                        HStack {
                            Button("Copy") { copySelection() }
                            Button("Paste") { pasteSelection() }
                        }
                        if ["body", "then", "else", "while", "do", "for"].contains(item.tag) {
                            Menu("Add Statement Inside") {
                                ForEach(statements, id: \.self) { tag in Button(tag.capitalized) { insert(selection, item.children.count, tag) } }
                            }
                        } else if selection.count > 2 {
                            Menu("Insert After") {
                                ForEach(statements, id: \.self) { tag in Button(tag.capitalized) { insert(Array(selection.dropLast()), (selection.last ?? 0) + 1, tag) } }
                            }
                        }
                        HStack {
                            Button { move(-1) } label: { Image(systemName: "arrow.up") }
                            Button { move(1) } label: { Image(systemName: "arrow.down") }
                            Spacer()
                            if !["body", "then", "else", "parameters"].contains(item.tag) && !(item.tag == "function" && FlowIdentifier.key(item["name"]) == "main") {
                                Button(role: .destructive) { remove() } label: { Image(systemName: "trash") }
                            }
                        }
                    }.disabled(execution.running)
                }
            } else { Text("Select a shape or a function to edit its properties.").foregroundStyle(.secondary) }
        }.padding(14).background(Color(nsColor:.controlBackgroundColor))
    }
    private func inspectorLabel(_ key: String,item: Element) -> String {
        if key == "name" { return item.tag == "function" ? "Function Name:" : "Name:" }
        if key == "type" { return item.tag == "function" ? "Return Type:" : "Type:" }
        if key == "variable", item.tag == "function" { return "Return Variable:" }
        if key == "array" { return "Array?" }
        return key.capitalized + ":"
    }
    private var console: some View {
        ConsoleView(execution:execution,input:$input,transport:AnyView(transport),
                    variables:{ showVariables.toggle() },source:{ showSource.toggle() },
                    turtle:{ showTurtle.toggle() },submit:submit)
    }
    private func attribute(_ key: String) -> Binding<String> {
        Binding(get: { root.element(at: selection)?[key] ?? "" }, set: { value in
            edit { $0.root.update(at: selection) { $0[key] = value } }
        })
    }
    private func edit(_ mutation: (inout Program) -> Void) {
        guard !execution.running else { return }
        let activeFunctionID = function?.id
        let selectedID = selected?.id
        let selectedIDs = selectedPaths.compactMap { root.element(at:$0)?.id }
        var next = document.program
        mutation(&next)
        guard next != document.program else { return }
        history.append(document.program)
        if history.count > 100 { history.removeFirst() }
        future = []; document.program = next
        selectedPaths = Set(selectedIDs.compactMap { findPath(next.root,id:$0) })
        if let activeFunctionID, let path = findPath(next.root,id:activeFunctionID) { functionIndex = path.first ?? functionIndex }
        else { functionIndex = next.root.children.enumerated().first(where:{ $0.element.tag == "function" && FlowIdentifier.key($0.element["name"]) == "main" })?.offset ?? next.root.children.firstIndex(where:{ $0.tag == "function" }) ?? 1 }
        if let selectedID, let path = findPath(next.root,id:selectedID) { selection = path }
        else if selectedID != nil { selection = [] }
    }
    private func insert(_ path: [Int], _ index: Int, _ tag: String) {
        edit { program in program.root.update(at: path) { $0.children.insert(Element.statement(tag), at: min(index, $0.children.count)) } }
        selection = path + [index]
        editShape(selection)
    }
    private func removeBreakpointShapes() {
        func strip(_ node: inout Element) {
            node.children.removeAll { $0.tag == "breakpoint" }
            for index in node.children.indices { strip(&node.children[index]) }
        }
        edit { strip(&$0.root) }
        selection = []
    }
    private func choose(_ path: [Int]) {
        selection = path
        selectedPaths = path.isEmpty ? [] : [path]
    }
    private func chooseForAction(_ path: [Int]) {
        if !selectedPaths.contains(path) { choose(path) }
        else { selection = path }
    }
    private func selectMany(_ paths: Set<[Int]>) {
        guard !execution.running else { return }
        selectedPaths = paths
        selection = paths.sorted { $0.lexicographicallyPrecedes($1) }.first ?? []
    }
    private func remove() {
        guard !execution.running else { return }
        if selectedPaths.count > 1 {
            let paths = selectedPaths
            edit { ChartSelection.remove(paths,from:&$0) }
            choose([])
            return
        }
        guard !(selected?.tag == "function" && FlowIdentifier.key(selected?["name"] ?? "") == "main"), selected?.tag != "body", selected?.tag != "parameters" else { return }
        guard let index = selection.last else { return }
        let parent = Array(selection.dropLast())
        edit { $0.root.update(at: parent) { if $0.children.indices.contains(index) { $0.children.remove(at: index) } } }
        if parent.isEmpty { functionIndex = functions.first(where:{ FlowIdentifier.key($0.1["name"]) == "main" })?.0 ?? functions.first?.0 ?? 1; selection = bodyPath }
        else { selection = parent }
    }
    private func move(_ delta: Int) {
        guard let index = selection.last else { return }
        let parent = Array(selection.dropLast()), next = index + delta
        guard let container = root.element(at: parent), container.children.indices.contains(next) else { return }
        edit { $0.root.update(at: parent) { $0.children.swapAt(index, next) } }
        selection = parent + [next]
        if parent.isEmpty { functionIndex = next }
    }
    private func presentFunctionEditor(_ item: ShapeEdit) {
        guard !execution.running else { return }
        if showFunctions { managerEditing = item }
        else { editing = item }
    }
    private func functionEditor(_ item: ShapeEdit) -> some View {
        FunctionEditor(draft:item.node,program:document.program,startAddingParameter:item.addParameter) { replacement in
            edit { program in
                if item.path.isEmpty { program.root.children.append(replacement) }
                else if let path = findPath(program.root,id:item.node.id) { program.root.update(at:path) { $0 = replacement } }
            }
            if let path = findPath(root,id:replacement.id) { functionIndex = path[0]; choose(path) }
        }
    }
    private func addFunction() {
        let draft = Element("function",["name":"","type":"None","variable":""],[Element("parameters"),Element("body")])
        presentFunctionEditor(ShapeEdit(path:[],node:draft))
    }
    private func addParameter() {
        guard let function, FlowIdentifier.key(function["name"]) != "main" else { return }
        presentFunctionEditor(ShapeEdit(path:[functionIndex],node:function,addParameter:true))
    }
    private func restore(_ program: Program) {
        let activeFunctionID = function?.id
        let selectedID = selected?.id
        let selectedIDs = selectedPaths.compactMap { root.element(at:$0)?.id }
        document.program = program
        selectedPaths = Set(selectedIDs.compactMap { findPath(program.root,id:$0) })
        if let activeFunctionID, let path = findPath(program.root,id:activeFunctionID) { functionIndex = path.first ?? functionIndex }
        else { functionIndex = functions.first(where:{ FlowIdentifier.key($0.1["name"]) == "main" })?.0 ?? functions.first?.0 ?? 1 }
        if let selectedID, let path = findPath(program.root,id:selectedID) { selection = path }
        else { selection = showFunctions ? [functionIndex] : bodyPath }
    }
    private func undo() { guard let prior = history.popLast() else { return }; future.append(document.program); restore(prior) }
    private func redo() { guard let next = future.popLast() else { return }; history.append(document.program); restore(next) }
    private func applyXML() {
        do {
            let parsed = try Program(data: Data(xmlDraft.utf8))
            edit { $0 = parsed }; functionIndex = functions.first(where:{ FlowIdentifier.key($0.1["name"]) == "main" })?.0 ?? functions.first?.0 ?? 1; selection = bodyPath
        } catch { self.error = error.localizedDescription }
    }
    private func run(stepping: Bool) {
        showConsole = true
        if showXML && xmlDraft != document.program.xml { applyXML(); if error != nil { return } }
        input = ""
        if document.program.functions.contains(where:{ containsTurtle($0) }) { showTurtle = true }
        execution.setIgnoreBreakpoints(ignoreBreakpoints)
        execution.start(document.program, stepping: stepping, breakpoints: breakpoints, baseDirectory: sourceURL?.deletingLastPathComponent())
    }
    private func exportTurtle() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "turtle.svg"
        if panel.runModal() == .OK, let url = panel.url {
            do { try execution.turtle.svg.write(to: url, atomically: true, encoding: .utf8) }
            catch { self.error = error.localizedDescription }
        }
    }
    private func submit() { execution.submit(input); input = "" }
    private func copySelection() {
        guard let item = selected else { return }
        var program = Program()
        if selectedPaths.count > 1 {
            program.root.children[1].children[1].children = ChartSelection.roots(selectedPaths).compactMap { root.element(at:$0) }
        }
        else if item.tag == "function" { program.root.children.append(item) }
        else if ["body", "then", "else"].contains(item.tag) { program.root.children[1].children[1].children = item.children }
        else { program.root.children[1].children[1].children = [item] }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(program.xml, forType: .string)
    }
    private func containsTurtle(_ node: Element) -> Bool {
        ["forward","turn","home","clear","pen"].contains(node.tag) || node.children.contains(where:containsTurtle)
    }
    private func importFunctions() {
        guard !execution.running else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.flowgorithm,.xml]
        panel.allowsOtherFileTypes = true
        panel.prompt = "Import Functions"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let source = try Program(data:Data(contentsOf:url))
            guard source.functions.contains(where:{ FlowIdentifier.key($0["name"]) != "main" }) else { throw FlowError("This file contains no functions to import.") }
            edit { $0.importFunctions(from:source) }
        } catch { self.error = error.localizedDescription }
    }
    private func pasteStatements(_ path: [Int], _ index: Int) {
        guard let text = NSPasteboard.general.string(forType:.string), !execution.running else { return }
        do {
            let pasted = try Program(data:Data(text.utf8))
            let statements = pasted.functions.first(where:{ FlowIdentifier.key($0["name"]) == "main" })?.child("body")?.children ?? []
            guard !statements.isEmpty else { throw FlowError("The clipboard contains no statements.") }
            edit { $0.root.update(at:path) { $0.children.insert(contentsOf:statements.map { $0.freshCopy() },at:min(index,$0.children.count)) } }
        } catch { self.error = error.localizedDescription }
    }
    private func pasteSelection() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        do {
            let pasted = try Program(data: Data(text.utf8))
            let imported = pasted.functions.filter { FlowIdentifier.key($0["name"]) != "main" }
            if !imported.isEmpty {
                edit { $0.importFunctions(from:pasted) }
                return
            }
            let statements = pasted.functions.first?.child("body")?.children ?? []
            let container = selected.map { ["body", "then", "else", "while", "do", "for"].contains($0.tag) } ?? false
            let path = container ? selection : (selection.count > 2 ? Array(selection.dropLast()) : bodyPath)
            let index = container || selection.count <= 2 ? (root.element(at: path)?.children.count ?? 0) : (selection.last ?? 0) + 1
            edit { $0.root.update(at: path) { $0.children.insert(contentsOf: statements.map { $0.freshCopy() }, at: min(index, $0.children.count)) } }
        } catch { self.error = error.localizedDescription }
    }
    private func printChart() {
        let chart = ClassicChart(layout:chartLayout,editable:false).padding(20).background(Color.white).environment(\.colorScheme,.light)
        let renderer = ImageRenderer(content:chart)
        guard let image = renderer.nsImage else { error = "Could not render flowchart."; return }
        let view = NSImageView(frame:CGRect(origin:.zero,size:image.size)); view.image = image
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.horizontalPagination = .fit; info.verticalPagination = .automatic; info.isHorizontallyCentered = true
        NSPrintOperation(view:view,printInfo:info).run()
    }
    private func exportChart(pdf: Bool) {
        let chart = ClassicChart(layout:chartLayout,editable:false).padding(20).background(Color.white).environment(\.colorScheme,.light)
        let renderer = ImageRenderer(content: chart)
        let panel = NSSavePanel(); panel.nameFieldStringValue = "flowchart." + (pdf ? "pdf" : "png")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if pdf {
            var wrote = false
            renderer.render { size, render in
                var box = CGRect(origin: .zero, size: size)
                if let consumer = CGDataConsumer(url: url as CFURL), let context = CGContext(consumer: consumer, mediaBox: &box, nil) {
                    context.beginPDFPage(nil); render(context); context.endPDFPage(); context.closePDF(); wrote = true
                }
            }
            if !wrote { error = "Could not write PDF." }
        } else {
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff), let data = bitmap.representation(using: .png, properties: [:]) else {
                error = "Could not render PNG."; return
            }
            do { try data.write(to: url) } catch { self.error = error.localizedDescription }
        }
    }
    private func exportPython() {
        do {
            let code = try PythonExporter.generate(document.program)
            let panel = NSSavePanel(); panel.nameFieldStringValue = "flowchart.py"
            if panel.runModal() == .OK, let url = panel.url { try code.write(to: url, atomically: true, encoding: .utf8) }
        } catch { self.error = error.localizedDescription }
    }
}

struct OutlineNode: View {
    let node: Element
    let path: [Int]
    let selected: [Int]
    let choose: ([Int]) -> Void
    var body: some View {
        if node.children.isEmpty {
            row
        } else {
            DisclosureGroup {
                ForEach(Array(node.children.enumerated()), id: \.element.id) { index, child in
                    AnyView(OutlineNode(node: child, path: path + [index], selected: selected, choose: choose))
                }
            } label: { row }
        }
    }
    private var row: some View {
        Button { choose(path) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(node.tag.capitalized).font(.caption.bold()).foregroundStyle(.secondary)
                if !["body", "parameters", "then", "else"].contains(node.tag) { Text(node.label).font(.caption).lineLimit(2) }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(5).contentShape(Rectangle())
                .background(selected == path ? Color.accentColor.opacity(0.13) : .clear).cornerRadius(4)
        }.buttonStyle(.plain)
    }
}
