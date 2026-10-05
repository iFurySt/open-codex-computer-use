import AppKit
import OpenComputerUseKit
import SwiftUI

/// Workspace chrome, independent of captured pixels and viewing zoom.
struct WorkspaceAppDock: View {
    let state: VirtualDisplayState
    let busy: Bool
    let show: (UInt32) -> Void
    @State private var icons: [Int32: NSImage] = [:]

    var body: some View {
        if !state.dockApplications.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(state.dockApplications) { app in
                        let windows = state.windows.filter { $0.pid == app.pid && state.frame.contains($0.frame) }
                        let target = windows.first { $0.id == app.selectedWindowID } ?? windows.first
                        Button {
                            if let target { show(target.id) }
                        } label: {
                            VStack(spacing: 4) {
                                if let icon = icons[app.pid] {
                                    Image(nsImage: icon).resizable().scaledToFit().frame(width: 36, height: 36)
                                } else {
                                    Image(systemName: "app.dashed").font(.system(size: 30)).frame(width: 36, height: 36)
                                }
                                Circle().fill(state.pid == app.pid ? Color.primary : Color.clear).frame(width: 4, height: 4)
                            }.padding(6)
                        }
                        .buttonStyle(DockIconButtonStyle())
                        .disabled(busy || target == nil)
                        .help(app.name).accessibilityLabel("Show \(app.name)")
                        .contextMenu {
                            ForEach(windows) { window in
                                Button(window.title.isEmpty ? app.name : window.title) { show(window.id) }
                                    .disabled(busy)
                            }
                        }
                    }
                }.padding(6)
            }
            .fixedSize(horizontal: true, vertical: true)
            .frame(maxWidth: 480)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.15)))
            .task(id: state.dockApplications.map(\.pid)) {
                let pids = Set(state.dockApplications.map(\.pid))
                icons = icons.filter { pids.contains($0.key) }
                for app in state.dockApplications where icons[app.pid] == nil {
                    icons[app.pid] = NSRunningApplication(processIdentifier: app.pid)?.icon
                }
            }
        }
    }
}

private struct DockIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        DockIconFeedback(configuration: configuration)
    }
    private struct DockIconFeedback: View {
        let configuration: ButtonStyle.Configuration
        @Environment(\.isEnabled) private var enabled
        @State private var hovered = false
        var body: some View {
            configuration.label
                .background(hovered && enabled ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 12))
                .opacity(enabled ? (configuration.isPressed ? 0.65 : 1) : 0.45)
                .contentShape(Rectangle())
                .onHover { hovered = $0 }
        }
    }
}
