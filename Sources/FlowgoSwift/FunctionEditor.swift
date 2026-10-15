import SwiftUI
import FlowCore

struct FunctionProperties {
    static func parameters(_ function: Element) -> [Element] { function.child("parameters")?.children ?? [] }

    static func setParameters(_ parameters: [Element], in function: inout Element) {
        if let index = function.children.firstIndex(where:{ $0.tag == "parameters" }) { function.children[index].children = parameters }
        else { function.children.insert(Element("parameters",[:],parameters),at:0) }
    }

    static func validateParameter(_ parameter: Element, others: [Element]) throws {
        try FlowIdentifier.validate(parameter["name"])
        guard !others.contains(where:{ $0.id != parameter.id && FlowIdentifier.key($0["name"]) == FlowIdentifier.key(parameter["name"]) }) else { throw FlowError("Duplicate parameter: \(parameter["name"])") }
        guard ["Integer","Real","String","Boolean"].contains(parameter["type"]) else { throw FlowError("Invalid parameter type.") }
    }

    static func validated(_ function: Element, in program: Program, original: Element) throws -> Element {
        var result = function
        result["name"] = result["name"].trimmingCharacters(in:.whitespacesAndNewlines)
        try FlowIdentifier.validate(result["name"])
        if FlowIdentifier.key(original["name"]) == "main" {
            guard result["name"] == original["name"], result["type"].lowercased() == "none", parameters(result).isEmpty else { throw FlowError("Main's signature cannot be changed.") }
        }
        guard !program.functions.contains(where:{ $0.id != original.id && FlowIdentifier.key($0["name"]) == FlowIdentifier.key(result["name"]) }) else { throw FlowError("Duplicate function: \(result["name"])") }
        for parameter in parameters(result) { try validateParameter(parameter,others:parameters(result)) }
        return result
    }

    static func moveParameter(_ id: UUID, by delta: Int, in function: inout Element) {
        var values = parameters(function)
        guard let index = values.firstIndex(where:{ $0.id == id }), values.indices.contains(index + delta) else { return }
        values.swapAt(index,index + delta)
        setParameters(values,in:&function)
    }
}

struct ParameterEdit: Identifiable {
    let id = UUID()
    let node: Element
}

struct ParameterEditor: View {
    @State var draft: Element
    let others: [Element]
    let save: (Element) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFocused: Bool
    @State private var error: String?

    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Text("Parameter Properties").font(.title3.bold())
            Divider()
            Text("Name:")
            TextField("Name",text:binding("name")).textFieldStyle(.roundedBorder).focused($nameFocused)
            HStack(alignment:.top,spacing:40) {
                Picker("Type:",selection:binding("type")) {
                    ForEach(["Integer","Real","String","Boolean"],id:\.self) { Text($0).tag($0) }
                }.pickerStyle(.radioGroup)
                Toggle("Array?",isOn:Binding(get:{ draft["array"].lowercased() == "true" },set:{ draft["array"] = $0 ? "True" : "False" })).padding(.top,20)
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("OK") {
                    do {
                        draft["name"] = draft["name"].trimmingCharacters(in:.whitespacesAndNewlines)
                        try FunctionProperties.validateParameter(draft,others:others)
                        save(draft); dismiss()
                    } catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(22).frame(width:430).onAppear { nameFocused = true }
            .alert("Cannot save parameter",isPresented:Binding(get:{ error != nil },set:{ if !$0 { error = nil } })) { Button("OK") {} } message: { Text(error ?? "") }
    }
    private func binding(_ key: String) -> Binding<String> { Binding(get:{ draft[key] },set:{ draft[key] = $0 }) }
}

struct FunctionEditor: View {
    @State var draft: Element
    let program: Program
    let startAddingParameter: Bool
    let save: (Element) -> Void
    private let original: Element
    @State private var selectedParameter: UUID?
    @State private var editingParameter: ParameterEdit?
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFocused: Bool
    private var isMain: Bool { FlowIdentifier.key(original["name"]) == "main" }
    private var parameters: [Element] { FunctionProperties.parameters(draft) }
    private var parameterIndex: Int? { parameters.firstIndex { $0.id == selectedParameter } }

    init(draft: Element, program: Program, startAddingParameter: Bool = false, save: @escaping (Element) -> Void) {
        _draft = State(initialValue:draft)
        original = draft
        self.program = program
        self.startAddingParameter = startAddingParameter
        self.save = save
    }

    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Text("Function Properties").font(.title3.bold())
            Divider()
            Text("Function Name:")
            TextField("Function Name",text:binding("name")).textFieldStyle(.roundedBorder).focused($nameFocused).disabled(isMain)
            Text("Parameters:")
            HStack(alignment:.top,spacing:12) {
                ScrollView {
                    VStack(spacing:2) {
                        ForEach(parameters) { parameter in
                            Button { selectedParameter = parameter.id } label: {
                                Text(parameter.label).frame(maxWidth:.infinity,alignment:.leading).padding(8).contentShape(Rectangle())
                                    .background(selectedParameter == parameter.id ? Color.accentColor.opacity(0.2) : Color.clear)
                            }.buttonStyle(.plain)
                                .simultaneousGesture(TapGesture(count:2).onEnded { selectedParameter = parameter.id; editingParameter = ParameterEdit(node:parameter) })
                        }
                    }.frame(maxWidth:.infinity)
                }.frame(height:140).background(Color(nsColor:.textBackgroundColor)).overlay(Rectangle().stroke(Color.secondary.opacity(0.4)))
                VStack(spacing:8) {
                    Button("Add") { addParameter() }
                    Button("Edit") { if let index = parameterIndex { editingParameter = ParameterEdit(node:parameters[index]) } }.disabled(parameterIndex == nil)
                    Button("Remove") {
                        FunctionProperties.setParameters(parameters.filter { $0.id != selectedParameter },in:&draft)
                        selectedParameter = nil
                    }.disabled(parameterIndex == nil)
                    HStack {
                        Button { move(-1) } label: { Image(systemName:"arrow.up") }.help("Move Up").accessibilityLabel("Move Up").disabled(parameterIndex == nil || parameterIndex == 0)
                        Button { move(1) } label: { Image(systemName:"arrow.down") }.help("Move Down").accessibilityLabel("Move Down").disabled(parameterIndex == nil || parameterIndex == parameters.count - 1)
                    }
                }.disabled(isMain)
            }
            HStack(alignment:.top,spacing:40) {
                Picker("Return Type:",selection:binding("type")) {
                    ForEach(["None","Integer","Real","String","Boolean"],id:\.self) { Text($0).tag($0) }
                }.pickerStyle(.radioGroup).disabled(isMain)
                if draft["type"].lowercased() != "none" {
                    VStack(alignment:.leading,spacing:8) {
                        Text("Return Variable:")
                        TextField("Return Variable",text:binding("variable")).textFieldStyle(.roundedBorder)
                    }
                }
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("OK") {
                    do { save(try FunctionProperties.validated(draft,in:program,original:original)); dismiss() }
                    catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(22).frame(width:580)
            .onAppear { nameFocused = true; if startAddingParameter { addParameter() } }
            .sheet(item:$editingParameter) { item in
                ParameterEditor(draft:item.node,others:parameters) { parameter in
                    var values = parameters
                    if let index = values.firstIndex(where:{ $0.id == parameter.id }) { values[index] = parameter }
                    else { values.append(parameter) }
                    FunctionProperties.setParameters(values,in:&draft)
                    selectedParameter = parameter.id
                }
            }
            .alert("Cannot save function",isPresented:Binding(get:{ error != nil },set:{ if !$0 { error = nil } })) { Button("OK") {} } message: { Text(error ?? "") }
    }
    private func binding(_ key: String) -> Binding<String> { Binding(get:{ draft[key] },set:{ draft[key] = $0 }) }
    private func addParameter() { editingParameter = ParameterEdit(node:Element("parameter",["name":"","type":"Integer","array":"False"])) }
    private func move(_ delta: Int) { if let id = selectedParameter { FunctionProperties.moveParameter(id,by:delta,in:&draft) } }
}
