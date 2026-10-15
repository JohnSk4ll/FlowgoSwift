import SwiftUI

struct ClassicToolbarStyle: ButtonStyle {
    var selected = false
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        let highlighted = configuration.isPressed || selected
        configuration.label.padding(5).frame(width:38,height:38)
            .background(RoundedRectangle(cornerRadius:4).fill(highlighted ? Color.accentColor.opacity(scheme == .dark ? 0.25 : 0.14) : .clear))
            .overlay(RoundedRectangle(cornerRadius:4).stroke(highlighted ? Color.accentColor.opacity(0.65) : .clear,lineWidth:1))
            .contentShape(Rectangle())
    }
}

struct ClassicGlyph: View {
    let name: String
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let images = ToolbarSVG.images[name]!
        Image(nsImage:scheme == .dark ? images.1 : images.0)
            .resizable().frame(width:27,height:27).opacity(enabled ? 1 : 0.35).accessibilityHidden(true)
    }
}
