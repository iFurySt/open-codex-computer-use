import AppKit
import SwiftUI

struct WorkspaceSessionHeader: View {
    let name: String
    let sessionID: String
    let phase: String
    @State private var hovering = false
    private var color: Color {
        switch phase {
        case "ready", "attached": .green
        case "error", "failed": .red
        default: .yellow
        }
    }
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 7, height: 7)
                .help(phase.capitalized).accessibilityLabel("Session status: \(phase)")
            Text(name).font(.headline).lineLimit(1)
            Text(sessionID).font(.caption.monospaced()).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle).frame(maxWidth: 220)
                .help("Session ID: \(sessionID)")
            WorkspaceCopyButton(value: sessionID, label: "Copy session ID", visible: hovering)
        }
        .contentShape(Rectangle()).onHover { hovering = $0 }
        .id(sessionID)
    }
}

private struct WorkspaceCopyButton: View {
    let value: String
    let label: String
    var visible = true
    @State private var copied = false
    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            copied = NSPasteboard.general.setString(value, forType: .string)
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .frame(width: 18, height: 20)
        }
        .buttonStyle(WorkspaceIconButtonStyle(tint: copied ? .green : nil)).help(copied ? "Copied" : label)
        .accessibilityLabel(copied ? "Copied" : label)
        .opacity(visible || copied ? 1 : 0)
        .disabled(value.isEmpty)
        .task(id: copied) {
            if copied {
                do { try await Task.sleep(for: .seconds(1.5)); copied = false } catch { }
            }
        }
    }
}

struct WorkspaceCodeBlock: View {
    @Binding var text: String
    let title: String
    let editable: Bool
    @State private var hovering = false
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.caption.weight(.medium))
                Text("JSON").font(.caption2.monospaced()).foregroundStyle(.tertiary)
                Spacer()
                WorkspaceCopyButton(value: text, label: "Copy \(title.lowercased())", visible: hovering)
            }.foregroundStyle(.secondary).padding(.horizontal, 10).padding(.vertical, 5)
            Divider()
            WorkspaceCodeTextView(text: $text, editable: editable)
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.1)))
        .contentShape(Rectangle()).onHover { hovering = $0 }
    }
}

private struct WorkspaceCodeTextView: NSViewRepresentable {
    @Binding var text: String
    let editable: Bool
    @Environment(\.colorScheme) private var colorScheme
    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.drawsBackground = false
        let editor = NSTextView()
        editor.isRichText = false
        editor.isSelectable = true
        editor.allowsUndo = true
        editor.drawsBackground = false
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = true
        editor.textContainer?.widthTracksTextView = false
        editor.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainerInset = NSSize(width: 8, height: 8)
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isContinuousSpellCheckingEnabled = false
        editor.delegate = context.coordinator
        scroll.documentView = editor
        updateNSView(scroll, context: context)
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? NSTextView else { return }
        context.coordinator.text = $text
        editor.isEditable = editable
        if editor.string != text {
            editor.string = text
            context.coordinator.highlight(editor)
        } else if context.coordinator.colorScheme != colorScheme {
            context.coordinator.highlight(editor)
        }
        context.coordinator.colorScheme = colorScheme
    }
    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var colorScheme: ColorScheme?
        private var updating = false
        private static let tokens = try? NSRegularExpression(pattern: #""(?:\\.|[^"\\])*"\s*:|"(?:\\.|[^"\\])*"|\b(?:true|false|null)\b|-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#)
        init(text: Binding<String>) { self.text = text }
        func textDidChange(_ notification: Notification) {
            guard !updating, let editor = notification.object as? NSTextView else { return }
            text.wrappedValue = editor.string
            highlight(editor)
        }
        func highlight(_ editor: NSTextView) {
            guard let storage = editor.textStorage else { return }
            updating = true; defer { updating = false }
            let selected = editor.selectedRanges
            let source = editor.string as NSString
            let range = NSRange(location: 0, length: source.length)
            let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            storage.beginEditing()
            storage.setAttributes([.font: font, .foregroundColor: NSColor.labelColor], range: range)
            // Coloring changes attributes only: the original JSON and undo history stay intact.
            if source.length <= 200_000 {
                for token in Self.tokens?.matches(in: editor.string, range: range) ?? [] {
                    let value = source.substring(with: token.range)
                    let color: NSColor = value.hasPrefix("\"")
                        ? (value.hasSuffix(":") ? .systemPurple : .systemOrange)
                        : (["true", "false", "null"].contains(value) ? .systemPink : .systemBlue)
                    storage.addAttribute(.foregroundColor, value: color, range: token.range)
                }
            }
            storage.endEditing()
            editor.selectedRanges = selected
            editor.typingAttributes = [.font: font, .foregroundColor: NSColor.labelColor]
        }
    }
}
