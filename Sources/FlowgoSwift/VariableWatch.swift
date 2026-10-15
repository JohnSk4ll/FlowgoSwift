import SwiftUI

struct VariableWatch: View {
    @ObservedObject var execution: ExecutionController
    @AppStorage("watchColumns") private var columns = false
    @AppStorage("watchStack") private var stack = false
    @AppStorage("watchLabels") private var labels = true
    @AppStorage("watchFontSize") private var fontSize = 13.0
    @State private var arrayPages: [String:Int] = [:]
    private var frames: [WatchedFrame] {
        let all = execution.callStack
        return stack ? Array(all.reversed()) : Array(all.suffix(1))
    }
    var body: some View {
        VStack(spacing:0) {
            HStack(spacing:6) {
                toggle("Columns",icon:"rectangle.split.2x1",value:$columns)
                toggle("Show the Stack",icon:"square.3.layers.3d",value:$stack)
                toggle("Show labels",icon:"tag",value:$labels)
                Spacer(minLength:0)
                Button { fontSize = min(26,fontSize + 1) } label: { Image(systemName:"plus.magnifyingglass") }.help("Zoom In").accessibilityLabel("Zoom In")
                Button { fontSize = max(9,fontSize - 1) } label: { Image(systemName:"minus.magnifyingglass") }.help("Zoom Out").accessibilityLabel("Zoom Out")
            }.padding(8).background(Color(nsColor:.controlBackgroundColor))
            Divider()
            ScrollView {
                VStack(spacing:22) {
                    ForEach(frames) { frame in
                        VStack(spacing:12) {
                            Text(frame.name).font(.custom("Arial",size:fontSize)).foregroundColor(.black).frame(maxWidth:.infinity).padding(7)
                                .background(Color(hex:0xB9D5FF)).overlay(Rectangle().stroke(Color(hex:0x6F90C0),lineWidth:1))
                            group("Parameters",variables:frame.variables.filter { frame.parameterNames.contains($0.id.lowercased()) },frameID:frame.id)
                            group("Local Variables",variables:frame.variables.filter { !frame.parameterNames.contains($0.id.lowercased()) },frameID:frame.id)
                        }
                    }
                }.padding(14)
            }.background(Color(nsColor:.textBackgroundColor))
        }.frame(minWidth:280,minHeight:300)
    }
    private func toggle(_ title: String,icon: String,value: Binding<Bool>) -> some View {
        Toggle(isOn:value) { Image(systemName:icon) }.toggleStyle(.button).help(title).accessibilityLabel(title)
    }
    @ViewBuilder private func group(_ title: String,variables: [WatchedVariable],frameID: Int) -> some View {
        if !variables.isEmpty {
            if labels { Text(title).font(.custom("Arial",size:fontSize)).foregroundStyle(.secondary) }
            LazyVGrid(columns:columns ? [GridItem(.flexible()),GridItem(.flexible())] : [GridItem(.flexible())],spacing:12) {
                ForEach(variables) { variable in
                    VStack(spacing:0) {
                        Text(variable.id).font(.custom("Arial",size:fontSize)).foregroundColor(.white)
                            .frame(maxWidth:.infinity).padding(5).background(color(variable.type))
                        if let elements = variable.elements {
                            let key = "\(frameID):\(variable.id)"
                            let pageSize = 100
                            let pageCount = max(1,(elements.count + pageSize - 1) / pageSize)
                            let page = min(max(arrayPages[key] ?? 0,0),pageCount - 1)
                            let start = page * pageSize
                            let end = min(elements.count,start + pageSize)
                            LazyVGrid(columns:[GridItem(.adaptive(minimum:48),spacing:0)],spacing:0) {
                                ForEach(start..<end,id:\.self) { index in
                                    VStack(spacing:3) {
                                        if labels { Text(String(index)).font(.custom("Arial",size:max(9,fontSize - 3))).foregroundColor(.gray) }
                                        Text(elements[index]).font(.custom("Arial",size:fontSize)).textSelection(.enabled)
                                    }.frame(maxWidth:.infinity,minHeight:40).padding(3)
                                        .overlay(Rectangle().stroke(color(variable.type).opacity(0.4),lineWidth:0.5))
                                }
                            }
                            if variable.elementCount > elements.count {
                                Text("Showing the first \(elements.count) of \(variable.elementCount). Pause or step to inspect all elements.").font(.caption).padding(7)
                            }
                            if pageCount > 1 {
                                HStack {
                                    Button { arrayPages[key] = max(0,page - 1) } label: { Image(systemName:"chevron.left") }.disabled(page == 0)
                                    Text("\(start + 1)–\(end) of \(elements.count)").font(.caption.monospacedDigit())
                                    Button { arrayPages[key] = min(pageCount - 1,page + 1) } label: { Image(systemName:"chevron.right") }.disabled(page >= pageCount - 1)
                                }.padding(5)
                            }
                        } else {
                            Text(variable.value).font(.custom("Arial",size:fontSize)).textSelection(.enabled)
                                .frame(maxWidth:.infinity,alignment:.leading).padding(7).background(Color(nsColor:.textBackgroundColor))
                        }
                    }.overlay(Rectangle().stroke(color(variable.type),lineWidth:1))
                }
            }
        }
    }
    private func color(_ type: String) -> Color {
        switch type.lowercased() {
        case "integer": return Color(hex:0x4260B8)
        case "real": return Color(hex:0x804080)
        case "string": return Color(hex:0xA04040)
        default: return Color(hex:0x408080)
        }
    }
}
