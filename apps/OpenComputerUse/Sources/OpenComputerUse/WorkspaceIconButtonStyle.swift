import SwiftUI

/// A shared affordance for workspace icon actions, without changing their layout or hit area.
struct WorkspaceIconButtonStyle: ButtonStyle {
    var tint: Color?
    func makeBody(configuration: Configuration) -> some View {
        Feedback(configuration: configuration, tint: tint)
    }
    private struct Feedback: View {
        let configuration: ButtonStyleConfiguration
        let tint: Color?
        @Environment(\.isEnabled) private var enabled
        @State private var hovering = false
        var body: some View {
            configuration.label
                .foregroundStyle(enabled ? tint ?? (hovering || configuration.isPressed ? Color.primary : .secondary) : .secondary.opacity(0.4))
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}
