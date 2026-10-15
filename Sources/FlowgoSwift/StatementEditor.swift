import SwiftUI
import FlowCore

struct StatementProperties {
    static func normalized(_ node: Element) -> Element {
        var result = node
        if node.tag == "declare", result["name"].isEmpty, !result["variables"].isEmpty {
            result["name"] = result["variables"]
            result.attributes.removeValue(forKey:"variables")
        }
        for (key,value) in Element.statement(node.tag).attributes where result.attributes[key] == nil { result[key] = value }
        return result
    }
    static func title(_ tag: String) -> String { "\(tag == "assign" ? "Assignment" : tag.capitalized) Properties" }
    static func fields(_ tag: String) -> [String] {
        switch tag {
        case "declare": return ["name","type","array","size"]
        case "assign": return ["variable","expression"]
        case "input","read": return ["variable"]
        case "output": return ["expression","newline"]
        case "for": return ["variable","start","end","direction","step"]
        case "forward": return ["expression","pen"]
        case "turn": return ["expression","rotate"]
        case "open": return ["expression","mode"]
        case "close": return ["mode"]
        case "pen": return ["color"]
        case "comment": return ["text"]
        case "breakpoint": return ["always","expression"]
        case "if","while","do","call","write": return ["expression"]
        default: return []
        }
    }
    static func enabled(_ key: String, in node: Element) -> Bool {
        if key == "size" { return node["array"].lowercased() == "true" }
        if key == "expression", node.tag == "breakpoint" { return node["always"].lowercased() == "false" }
        return true
    }
}

struct StatementEditor: View {
    @State var draft: Element
    let save: (Element) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    init(draft: Element, save: @escaping (Element) -> Void) {
        _draft = State(initialValue:StatementProperties.normalized(draft))
        self.save = save
    }
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack(spacing:20) {
                let palette = ChartPalette(draft,dark:scheme == .dark)
                Text(draft.tag == "assign" ? "Assign" : draft.tag.capitalized)
                    .font(.custom("Arial",size:16)).foregroundColor(palette.text)
                    .frame(width:150,height:56).background(FlowShape(tag:draft.tag).fill(palette.fill))
                    .overlay(FlowShape(tag:draft.tag).stroke(palette.border,lineWidth:1))
                Text(StatementProperties.title(draft.tag)).font(.system(size:17,weight:.semibold))
            }
            Divider()
            ForEach(StatementProperties.fields(draft.tag),id:\.self) { key in
                field(key).disabled(!StatementProperties.enabled(key,in:draft))
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("OK") { save(draft); dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(22).frame(width:560).fixedSize(horizontal:false,vertical:true)
    }
    @ViewBuilder private func field(_ key: String) -> some View {
        switch key {
        case "always":
            Picker("",selection:binding(key)) {
                Text("Always break").tag("True")
                Text("Only break when this expression is true:").tag("False")
            }.pickerStyle(.radioGroup).labelsHidden()
        case "array","newline":
            Toggle(["array":"Array?","newline":"New Line","always":"Always break"][key]!,isOn:boolean(key))
        case "pen": Toggle("Pen Down",isOn:Binding(get:{ draft["pen"].lowercased() != "up" },set:{ draft["pen"] = $0 ? "down" : "up" }))
        case "type","direction","rotate","mode":
            Picker(label(key),selection:binding(key)) {
                ForEach(choices(key),id:\.0) { value,text in Text(text).tag(value) }
            }.pickerStyle(.radioGroup)
        case "color":
            Picker("Color:",selection:binding(key)) { ForEach(TurtleState.colors,id:\.self) { Text($0.capitalized).tag($0) } }
        case "text":
            Text("Enter any text. You don't have to use double quotes.")
            TextEditor(text:binding(key)).frame(height:140).border(Color.gray.opacity(0.5))
        default:
            VStack(alignment:.leading,spacing:6) {
                if draft.tag != "breakpoint" { Text(label(key)) }
                TextField(label(key),text:binding(key)).textFieldStyle(.roundedBorder)
            }
        }
    }
    private func binding(_ key: String) -> Binding<String> { Binding(get:{ draft[key] },set:{ draft[key] = $0 }) }
    private func boolean(_ key: String) -> Binding<Bool> { Binding(get:{ draft[key].lowercased() == "true" },set:{ draft[key] = $0 ? "True" : "False" }) }
    private func choices(_ key: String) -> [(String,String)] {
        switch key {
        case "type": return ["Integer","Real","String","Boolean"].map { ($0,$0) }
        case "direction": return [("inc","Increasing"),("dec","Decreasing")]
        case "rotate": return [("left","Left"),("right","Right")]
        default: return [("read","Read"),("write","Write")]
        }
    }
    private func label(_ key: String) -> String {
        if key == "expression" {
            switch draft.tag {
            case "if","while","do": return "Enter a conditional expression below:"
            case "call": return "Enter a function name. Delimit arguments with parenthesis."
            case "breakpoint": return "Only break when this expression is true:"
            case "assign": return "Expression:"
            default: return "Enter an expression below:"
            }
        }
        if key == "variable", ["input","read"].contains(draft.tag) { return "Enter a variable name below:" }
        return ["name":"Variable Names:","variable":"Variable:","size":"Array Size:","start":"Start Value:","end":"End Value:","step":"Step By:","type":"Type:","direction":"Direction:","rotate":"Direction:","mode":"Mode:"][key] ?? key.capitalized
    }
}

struct ShapeEdit: Identifiable {
    let id = UUID()
    let path: [Int]
    let node: Element
    var addParameter = false
}
