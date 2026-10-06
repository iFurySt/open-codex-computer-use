import AppKit
import OpenComputerUseKit
import SwiftUI

/// Workspace chrome, independent of captured pixels and viewing zoom.
struct WorkspaceAppDock: View {
    let state: VirtualDisplayState
    let busy: Bool
    let show: (UInt32) -> Void
    @State private var icons: [Int32: NSImage] = [:]

    // ScrollView has no useful intrinsic width; size its visible surface explicitly.
    private var contentWidth: CGFloat {
        let count = state.dockApplications.count
        return CGFloat(count * 44 + max(0, count - 1) * 4 + 12)
    }

    var body: some View {
        if !state.dockApplications.isEmpty {
            GeometryReader { geometry in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(state.dockApplications) { app in
                            let windows = state.windows.filter { $0.pid == app.pid && state.frame.contains($0.frame) }
                            let target = windows.first { $0.id == app.selectedWindowID } ?? windows.first
                            Button {
                                if let target { show(target.id) }
                            } label: {
                                VStack(spacing: 2) {
                                    if let icon = icons[app.pid] {
                                        Image(nsImage: icon).resizable().scaledToFit().frame(width: 36, height: 36)
                                    } else {
                                        Image(systemName: "app.dashed").font(.system(size: 30)).frame(width: 36, height: 36)
                                    }
                                    Circle().fill(state.pid == app.pid ? Color.primary : Color.clear).frame(width: 4, height: 4)
                                }.padding(4)
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
                    }.padding(.horizontal, 6).padding(.vertical, 5)
                }
                .frame(width: min(contentWidth, geometry.size.width), height: 60)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.15)))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: 480).frame(height: 60)
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
