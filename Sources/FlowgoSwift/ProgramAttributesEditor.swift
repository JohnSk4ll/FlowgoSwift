import SwiftUI
import FlowCore

struct ProgramAttributesEditor: View {
    @State var attributes: Element
    let save: (Element) -> Void
    @Environment(\.dismiss) private var dismiss
    private func value(_ name: String) -> Binding<String> {
        Binding(get:{ attributes.children.first(where:{ $0["name"] == name })?["value"] ?? "" },set:{ value in
            if let index = attributes.children.firstIndex(where:{ $0["name"] == name }) { attributes.children[index]["value"] = value }
            else { attributes.children.append(Element("attribute",["name":name,"value":value])) }
        })
    }
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            Text("Program Attributes").font(.headline)
            Text("Name:"); TextField("Name",text:value("name")).textFieldStyle(.roundedBorder)
            Text("Author(s):"); TextField("Author(s)",text:value("authors")).textFieldStyle(.roundedBorder)
            Text("About:"); TextEditor(text:value("about")).frame(height:120).border(Color.secondary.opacity(0.4))
            Text("Saved: \(attributes.children.first(where:{ $0["name"] == "saved" })?["value"] ?? "")").foregroundStyle(.secondary)
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("OK") { save(attributes); dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(22).frame(width:500)
    }
}
