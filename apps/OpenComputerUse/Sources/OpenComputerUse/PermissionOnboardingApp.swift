import AppKit
import ApplicationServices
import OpenComputerUseKit

@MainActor
enum PermissionOnboardingApp {
    static func launch() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        application.applicationIconImage = Branding.makeAppIconImage(size: 256)

        let delegate = PermissionOnboardingAppDelegate()
        application.delegate = delegate
        application.run()
    }
}

@MainActor
final class PermissionOnboardingAppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: PermissionWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = PermissionWindowController()
        windowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@MainActor
final class PermissionWindowController: NSWindowController {
    private let contentController = PermissionContentController()
    private let accessoryPanelController = PermissionAccessoryPanelController()

    init() {
        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: PermissionOnboardingLayout.windowWidth,
                height: PermissionOnboardingLayout.windowHeight
            ),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.title = PermissionSupport.bundleDisplayName
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)

        contentViewController = contentController
        contentController.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}

@MainActor
extension PermissionWindowController: PermissionContentControllerDelegate {
    func permissionContentController(_ controller: PermissionContentController, didRequestPermission permission: SystemPermissionKind) {
        if permission == .accessibility {
            PermissionSupport.requestAccessibilityPrompt()
        }

        PermissionSupport.openSystemSettings(for: permission)
        accessoryPanelController.show(for: permission)
        contentController.setActiveGuidance(permission)
    }

    func permissionContentControllerDidResolveGuidance(_ controller: PermissionContentController) {
        accessoryPanelController.hide()
    }
}

@MainActor
protocol PermissionContentControllerDelegate: AnyObject {
    func permissionContentController(_ controller: PermissionContentController, didRequestPermission permission: SystemPermissionKind)
    func permissionContentControllerDidResolveGuidance(_ controller: PermissionContentController)
}

private enum PermissionOnboardingLayout {
    static let windowWidth: CGFloat = 880
    static let windowHeight: CGFloat = 648
    static let outerHorizontalInset: CGFloat = 48
    static let outerTopInset: CGFloat = 40
    static let outerBottomInset: CGFloat = 32
    static let headerIconSize: CGFloat = 96
    static let cardWidth: CGFloat = 744
    static let cardHeight: CGFloat = 106
    static let cardCornerRadius: CGFloat = 24
    static let cardHorizontalInset: CGFloat = 20
    static let cardVerticalInset: CGFloat = 18
    static let cardIconSize: CGFloat = 54
    static let actionButtonWidth: CGFloat = 104
    static let actionButtonHeight: CGFloat = 44
}

@MainActor
final class PermissionContentController: NSViewController {
    weak var delegate: PermissionContentControllerDelegate?

    private let backgroundView = GradientBackgroundView()
    private let stackView = NSStackView()
    private let iconView = AppGlyphView()
    private let titleLabel = NSTextField(labelWithString: "Enable Open Computer Use")
    private let subtitleLabel = NSTextField(wrappingLabelWithString: "Open Computer Use needs these permissions to use apps on your Mac.\nThese permissions are only used when you ask it to perform tasks.")
    private let cardsContainer = NSStackView()
    private let completionLabel = NSTextField(labelWithString: "All required permissions are enabled.")
    private let refreshTimerInterval: TimeInterval = 0.25

    private var activeGuidance: SystemPermissionKind?
    private var refreshTimer: Timer?
    private var diagnostics = PermissionDiagnostics.current()

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureUI()
        refreshUI()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshTimerInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshState()
            }
        }
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        refreshTimer?.invalidate()
    }

    func setActiveGuidance(_ permission: SystemPermissionKind?) {
        activeGuidance = permission
        refreshUI()
    }

    private func refreshState() {
        let updated = PermissionDiagnostics.current()
        let previousGuidance = activeGuidance
        diagnostics = updated

        if let activeGuidance, updated.isGranted(activeGuidance) {
            self.activeGuidance = nil
        }

        refreshUI()

        if previousGuidance != nil, activeGuidance == nil {
            delegate?.permissionContentControllerDidResolveGuidance(self)
        }
    }

    private func configureUI() {
        view.wantsLayer = true

        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(backgroundView)

        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stackView)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 38, weight: .bold)
        titleLabel.textColor = NSColor(calibratedWhite: 0.18, alpha: 1)
        titleLabel.maximumNumberOfLines = 1
        subtitleLabel.font = NSFont.systemFont(ofSize: 15, weight: .regular)
        subtitleLabel.textColor = NSColor(calibratedWhite: 0.42, alpha: 1)
        subtitleLabel.alignment = .center
        subtitleLabel.maximumNumberOfLines = 2

        cardsContainer.orientation = .vertical
        cardsContainer.alignment = .centerX
        cardsContainer.spacing = 14
        cardsContainer.translatesAutoresizingMaskIntoConstraints = false

        completionLabel.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        completionLabel.textColor = NSColor(calibratedRed: 0.16, green: 0.50, blue: 0.23, alpha: 1)
        completionLabel.isHidden = true

        stackView.addArrangedSubview(iconView)
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(subtitleLabel)
        stackView.addArrangedSubview(cardsContainer)
        stackView.addArrangedSubview(completionLabel)
        stackView.setCustomSpacing(16, after: iconView)
        stackView.setCustomSpacing(8, after: titleLabel)
        stackView.setCustomSpacing(24, after: subtitleLabel)
        stackView.setCustomSpacing(14, after: cardsContainer)

        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: PermissionOnboardingLayout.outerHorizontalInset),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -PermissionOnboardingLayout.outerHorizontalInset),
            stackView.topAnchor.constraint(equalTo: view.topAnchor, constant: PermissionOnboardingLayout.outerTopInset),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -PermissionOnboardingLayout.outerBottomInset),

            iconView.widthAnchor.constraint(equalToConstant: PermissionOnboardingLayout.headerIconSize),
            iconView.heightAnchor.constraint(equalToConstant: PermissionOnboardingLayout.headerIconSize),
            cardsContainer.widthAnchor.constraint(equalToConstant: PermissionOnboardingLayout.cardWidth),
        ])
    }

    private func refreshUI() {
        cardsContainer.arrangedSubviews.forEach { subview in
            cardsContainer.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }

        let orderedPermissions = SystemPermissionKind.allCases
        for permission in orderedPermissions {
            if activeGuidance == permission, !diagnostics.isGranted(permission) {
                let placeholder = GuidancePlaceholderView()
                cardsContainer.addArrangedSubview(placeholder)
                placeholder.widthAnchor.constraint(equalToConstant: PermissionOnboardingLayout.cardWidth).isActive = true
                continue
            }

            let card = PermissionCardView(permission: permission, diagnostics: diagnostics)
            card.onAllow = { [weak self] requestedPermission in
                guard let self else {
                    return
                }
                self.delegate?.permissionContentController(self, didRequestPermission: requestedPermission)
            }
            cardsContainer.addArrangedSubview(card)
            card.widthAnchor.constraint(equalToConstant: PermissionOnboardingLayout.cardWidth).isActive = true
        }

        completionLabel.isHidden = !diagnostics.allGranted
    }
}

@MainActor
final class PermissionCardView: NSView {
    var onAllow: ((SystemPermissionKind) -> Void)?

    private let permission: SystemPermissionKind
    private let diagnostics: PermissionDiagnostics

    init(permission: SystemPermissionKind, diagnostics: PermissionDiagnostics) {
        self.permission = permission
        self.diagnostics = diagnostics
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func configure() {
        wantsLayer = true
        layer?.cornerRadius = PermissionOnboardingLayout.cardCornerRadius
        layer?.backgroundColor = NSColor(calibratedWhite: 0.99, alpha: 0.92).cgColor
        layer?.shadowColor = NSColor.black.withAlphaComponent(0.1).cgColor
        layer?.shadowOpacity = 1
        layer?.shadowRadius = 16
        layer?.shadowOffset = CGSize(width: 0, height: -2)

        let content = NSStackView()
        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = 16
        content.translatesAutoresizingMaskIntoConstraints = false

        let iconBackground = NSView()
        iconBackground.translatesAutoresizingMaskIntoConstraints = false
        iconBackground.wantsLayer = true
        iconBackground.layer?.cornerRadius = PermissionOnboardingLayout.cardIconSize / 2
        iconBackground.layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.92).cgColor
        iconBackground.layer?.borderWidth = 2
        iconBackground.layer?.borderColor = (
            permission == .accessibility
            ? NSColor.systemBlue.withAlphaComponent(0.28)
            : NSColor(calibratedWhite: 0.82, alpha: 1)
        ).cgColor

        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.contentTintColor = permission == .accessibility ? NSColor.systemBlue : NSColor.systemGray
        icon.image = NSImage(systemSymbolName: permission.symbolName, accessibilityDescription: permission.title)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
        iconBackground.addSubview(icon)

        let labels = NSStackView()
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 2

        let title = NSTextField(labelWithString: permission.title)
        title.font = NSFont.systemFont(ofSize: 20, weight: .bold)
        title.textColor = NSColor(calibratedWhite: 0.18, alpha: 1)

        let subtitle = NSTextField(labelWithString: permission.subtitle)
        subtitle.font = NSFont.systemFont(ofSize: 14, weight: .regular)
        subtitle.textColor = NSColor(calibratedWhite: 0.42, alpha: 1)

        labels.addArrangedSubview(title)
        labels.addArrangedSubview(subtitle)

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        content.addArrangedSubview(iconBackground)
        content.addArrangedSubview(labels)
        content.addArrangedSubview(spacer)

        if diagnostics.isGranted(permission) {
            let done = StatusChipView(text: "Done", foreground: NSColor(calibratedRed: 0.16, green: 0.50, blue: 0.23, alpha: 1), background: NSColor(calibratedRed: 0.93, green: 0.98, blue: 0.94, alpha: 1))
            content.addArrangedSubview(done)
        } else {
            let button = PrimaryActionButton(title: "Allow", target: self, action: #selector(handleAllow))
            content.addArrangedSubview(button)
            button.widthAnchor.constraint(equalToConstant: PermissionOnboardingLayout.actionButtonWidth).isActive = true
            button.heightAnchor.constraint(equalToConstant: PermissionOnboardingLayout.actionButtonHeight).isActive = true
        }

        addSubview(content)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: PermissionOnboardingLayout.cardHeight),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: PermissionOnboardingLayout.cardHorizontalInset),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -PermissionOnboardingLayout.cardHorizontalInset),
            content.topAnchor.constraint(equalTo: topAnchor, constant: PermissionOnboardingLayout.cardVerticalInset),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -PermissionOnboardingLayout.cardVerticalInset),

            iconBackground.widthAnchor.constraint(equalToConstant: PermissionOnboardingLayout.cardIconSize),
            iconBackground.heightAnchor.constraint(equalToConstant: PermissionOnboardingLayout.cardIconSize),
            icon.centerXAnchor.constraint(equalTo: iconBackground.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconBackground.centerYAnchor),
            spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 12),
        ])
    }

    @objc
    private func handleAllow() {
        onAllow?(permission)
    }
}

@MainActor
final class GuidancePlaceholderView: NSView {
    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = PermissionOnboardingLayout.cardCornerRadius
        layer?.backgroundColor = NSColor(calibratedWhite: 0.98, alpha: 0.6).cgColor

        let label = NSTextField(labelWithString: "COMPLETE IN SYSTEM SETTINGS")
        label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        label.textColor = NSColor(calibratedWhite: 0.55, alpha: 1)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 82),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let borderRect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(
            roundedRect: borderRect,
            xRadius: PermissionOnboardingLayout.cardCornerRadius,
            yRadius: PermissionOnboardingLayout.cardCornerRadius
        )
        path.setLineDash([6, 6], count: 2, phase: 0)
        path.lineWidth = 1.5
        NSColor(calibratedWhite: 0.82, alpha: 1).setStroke()
        path.stroke()
    }
}

@MainActor
final class PermissionAccessoryPanelController {
    private let trackingInterval: TimeInterval = 0.12
    private var panel: NSPanel?
    private var currentPermission: SystemPermissionKind?
    private var trackingTimer: Timer?
    private var workspaceObserver: NSObjectProtocol?
    private var globalDragMonitor: Any?
    private var localDragMonitor: Any?

    private enum Layout {
        static let screenHorizontalInset: CGFloat = 16
        static let screenBottomInset: CGFloat = 12
        static let windowBottomOverlap: CGFloat = 6
        static let controlsBottomGap: CGFloat = 12
        static let contentLeadingInset: CGFloat = 26
        static let contentTrailingInset: CGFloat = 28
        static let sidebarWidthRatio: CGFloat = 0.29
        static let sidebarWidthMin: CGFloat = 214
        static let sidebarWidthMax: CGFloat = 272
    }

    private struct PanelAnchor {
        let windowBounds: CGRect
        let contentTrackRect: CGRect
        let accessoryAnchorRect: CGRect?
    }

    func show(for permission: SystemPermissionKind) {
        currentPermission = permission

        let panel = panel ?? makePanel()
        self.panel = panel

        if let contentView = panel.contentView as? PermissionAccessoryPanelView {
            contentView.configure(permission: permission)
        }

        installObserversIfNeeded()
        startTracking()
        position(panel: panel)
        updatePanelVisibility()
    }

    func hide() {
        trackingTimer?.invalidate()
        trackingTimer = nil
        removeObservers()
        panel?.orderOut(nil)
        currentPermission = nil
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 452, height: 102),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .normal
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        panel.contentView = PermissionAccessoryPanelView()
        return panel
    }

    private func installObserversIfNeeded() {
        if workspaceObserver == nil {
            workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.updatePanelVisibility()
                    self?.refreshPosition()
                }
            }
        }

        if globalDragMonitor == nil {
            globalDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshPosition()
                }
            }
        }

        if localDragMonitor == nil {
            localDragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
                Task { @MainActor [weak self] in
                    self?.refreshPosition()
                }
                return event
            }
        }
    }

    private func removeObservers() {
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
            self.workspaceObserver = nil
        }

        if let globalDragMonitor {
            NSEvent.removeMonitor(globalDragMonitor)
            self.globalDragMonitor = nil
        }

        if let localDragMonitor {
            NSEvent.removeMonitor(localDragMonitor)
            self.localDragMonitor = nil
        }
    }

    private func startTracking() {
        trackingTimer?.invalidate()
        trackingTimer = Timer.scheduledTimer(withTimeInterval: trackingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updatePanelVisibility()
                self?.refreshPosition()
            }
        }
        trackingTimer?.tolerance = 0.05
    }

    private func refreshPosition() {
        guard let panel, currentPermission != nil, panel.isVisible else {
            return
        }

        position(panel: panel)
    }

    private func updatePanelVisibility() {
        guard let panel, currentPermission != nil else {
            return
        }

        guard isSystemSettingsFrontmost else {
            panel.orderOut(nil)
            return
        }

        if !panel.isVisible {
            panel.orderFront(nil)
        }
    }

    private func position(panel: NSPanel) {
        guard let origin = preferredPanelOrigin(for: panel.frame.size) else {
            return
        }

        if panel.frame.origin != origin {
            panel.setFrameOrigin(origin)
        }
    }

    private func preferredPanelOrigin(for panelSize: CGSize) -> CGPoint? {
        guard let anchor = preferredPanelAnchor() else {
            return nil
        }

        let referenceRect = anchor.windowBounds
        let visibleFrame = targetVisibleScreenFrame(for: referenceRect) ?? referenceRect
        let trackRect = anchor.contentTrackRect
        let x = clamp(
            trackRect.midX - (panelSize.width / 2),
            lower: visibleFrame.minX + Layout.screenHorizontalInset,
            upper: visibleFrame.maxX - panelSize.width - Layout.screenHorizontalInset
        )
        let anchorMinY = anchor.accessoryAnchorRect?.minY ?? referenceRect.minY
        let desiredY = if anchor.accessoryAnchorRect != nil {
            anchorMinY - panelSize.height - Layout.controlsBottomGap
        } else {
            anchorMinY - panelSize.height + Layout.windowBottomOverlap
        }
        let y = max(
            visibleFrame.minY + Layout.screenBottomInset,
            desiredY
        )
        return CGPoint(x: x, y: y)
    }

    private func preferredPanelAnchor() -> PanelAnchor? {
        let referenceRect = systemSettingsWindowBounds() ?? NSScreen.main?.visibleFrame
        guard let referenceRect else {
            return nil
        }

        return PanelAnchor(
            windowBounds: referenceRect,
            contentTrackRect: systemSettingsContentTrackRect(in: referenceRect),
            accessoryAnchorRect: systemSettingsControlsRowRect(in: referenceRect)
        )
    }

    private func systemSettingsContentTrackRect(in windowBounds: CGRect) -> CGRect {
        // Keep the panel centered under the content area even when the
        // vertical anchor comes from a specific controls row.
        let sidebarWidth = clamp(
            windowBounds.width * Layout.sidebarWidthRatio,
            lower: Layout.sidebarWidthMin,
            upper: Layout.sidebarWidthMax
        )
        let contentMinX = min(
            windowBounds.maxX - Layout.contentTrailingInset - 1,
            windowBounds.minX + sidebarWidth + Layout.contentLeadingInset
        )
        let contentMaxX = max(contentMinX + 1, windowBounds.maxX - Layout.contentTrailingInset)
        return CGRect(
            x: contentMinX,
            y: windowBounds.minY,
            width: contentMaxX - contentMinX,
            height: windowBounds.height
        )
    }

    private func targetVisibleScreenFrame(for rect: CGRect) -> CGRect? {
        NSScreen.screens.first(where: { $0.visibleFrame.intersects(rect) })?.visibleFrame
    }

    private var isSystemSettingsFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.systempreferences"
    }

    private func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        guard lower <= upper else {
            return lower
        }

        return min(max(value, lower), upper)
    }

    private func systemSettingsWindowBounds() -> CGRect? {
        guard let runningApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.systempreferences" }) else {
            return nil
        }

        guard let windowInfoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        let windows = windowInfoList.compactMap { info -> (CGRect, Int)? in
            guard
                let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                ownerPID == runningApp.processIdentifier,
                let layer = info[kCGWindowLayer as String] as? Int,
                layer == 0,
                let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDictionary)
            else {
                return nil
            }

            return (bounds, Int(bounds.width * bounds.height))
        }

        return windows.sorted(by: { $0.1 > $1.1 }).first?.0
    }

    private func systemSettingsControlsRowRect(in windowBounds: CGRect) -> CGRect? {
        guard let runningApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.systempreferences" }) else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(runningApp.processIdentifier)
        guard let windowElement = preferredAXWindow(for: appElement) else {
            return nil
        }

        let candidates = collectControlsRowCandidates(in: windowElement, windowBounds: windowBounds)
        guard !candidates.isEmpty else {
            return nil
        }

        switch currentPermission {
        case .screenRecording:
            return candidates.max(by: { $0.midY < $1.midY })
        default:
            return candidates.min(by: { $0.minY < $1.minY })
        }
    }

    private func preferredAXWindow(for appElement: AXUIElement) -> AXUIElement? {
        copyAXElement(appElement, attribute: kAXFocusedWindowAttribute)
            ?? copyAXElement(appElement, attribute: kAXMainWindowAttribute)
            ?? copyAXArray(appElement, attribute: kAXWindowsAttribute)?.first
    }

    private func collectControlsRowCandidates(in root: AXUIElement, windowBounds: CGRect) -> [CGRect] {
        let elements = flattenedAXDescendants(of: root, maxDepth: 8, maxNodes: 400)
        let symbolButtons = elements.compactMap { symbolButtonDescriptor(for: $0) }
        guard !symbolButtons.isEmpty else {
            return []
        }

        let contentTrackRect = systemSettingsContentTrackRect(in: windowBounds)
        let controlButtons = symbolButtons.filter { descriptor in
            let frame = descriptor.frame
            return frame.intersects(windowBounds) &&
                frame.midX >= contentTrackRect.minX - 24 &&
                frame.midX <= contentTrackRect.maxX &&
                frame.width <= 40 &&
                frame.height <= 40
        }

        let plusButtons = controlButtons.filter { $0.symbol == "+" }
        let minusButtons = controlButtons.filter { $0.symbol == "-" }

        return plusButtons.compactMap { plusButton in
            let matchingMinusButtons = minusButtons.filter { minusButton in
                abs(minusButton.frame.midY - plusButton.frame.midY) <= 10 &&
                    minusButton.frame.minX >= plusButton.frame.maxX - 4 &&
                    minusButton.frame.minX - plusButton.frame.maxX <= 28
            }

            guard let minusButton = matchingMinusButtons.min(by: {
                abs($0.frame.midY - plusButton.frame.midY) < abs($1.frame.midY - plusButton.frame.midY)
            }) else {
                return nil
            }

            return plusButton.frame.union(minusButton.frame)
        }
    }

    private func flattenedAXDescendants(of root: AXUIElement, maxDepth: Int, maxNodes: Int) -> [AXUIElement] {
        var results: [AXUIElement] = []
        var queue: [(AXUIElement, Int)] = [(root, 0)]

        while !queue.isEmpty, results.count < maxNodes {
            let (element, depth) = queue.removeFirst()
            results.append(element)

            guard depth < maxDepth else {
                continue
            }

            for child in copyAXArray(element, attribute: kAXChildrenAttribute) ?? [] {
                queue.append((child, depth + 1))
            }
        }

        return results
    }

    private func symbolButtonDescriptor(for element: AXUIElement) -> (symbol: String, frame: CGRect)? {
        guard stringAXAttribute(element, attribute: kAXRoleAttribute) == kAXButtonRole as String else {
            return nil
        }

        guard let frame = frame(of: element) else {
            return nil
        }

        let rawLabels = [
            stringAXAttribute(element, attribute: kAXTitleAttribute),
            stringAXAttribute(element, attribute: kAXDescriptionAttribute),
            stringAXAttribute(element, attribute: kAXValueAttribute)
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

        guard let symbol = rawLabels.first(where: { $0 == "+" || $0 == "-" }) else {
            return nil
        }

        return (symbol, frame)
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
            AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
            let positionValue,
            let sizeValue
        else {
            return nil
        }

        let positionAXValue = positionValue as! AXValue
        let sizeAXValue = sizeValue as! AXValue
        var position = CGPoint.zero
        var size = CGSize.zero
        guard
            AXValueGetValue(positionAXValue, .cgPoint, &position),
            AXValueGetValue(sizeAXValue, .cgSize, &size)
        else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    private func copyAXElement(_ element: AXUIElement, attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }

        return value as? AXUIElement
    }

    private func copyAXArray(_ element: AXUIElement, attribute: String) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }

        return value as? [AXUIElement]
    }

    private func stringAXAttribute(_ element: AXUIElement, attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }

        return value as? String
    }
}

@MainActor
final class PermissionAccessoryPanelView: NSView {
    private let instructionLabel = NSTextField(labelWithString: "")
    private let dragTileView = DraggableAppTileView()

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 20
        layer?.backgroundColor = NSColor(calibratedWhite: 0.98, alpha: 0.96).cgColor
        layer?.shadowColor = NSColor.black.withAlphaComponent(0.14).cgColor
        layer?.shadowOpacity = 1
        layer?.shadowRadius = 18
        layer?.shadowOffset = CGSize(width: 0, height: -5)

        let arrow = NSImageView()
        arrow.translatesAutoresizingMaskIntoConstraints = false
        arrow.image = NSImage(systemSymbolName: "arrow.up", accessibilityDescription: "Drag upward")
        arrow.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 26, weight: .bold)
        arrow.contentTintColor = NSColor.systemBlue

        instructionLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        instructionLabel.textColor = NSColor(calibratedWhite: 0.4, alpha: 1)
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        instructionLabel.lineBreakMode = .byTruncatingTail
        instructionLabel.maximumNumberOfLines = 1
        instructionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        dragTileView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(arrow)
        addSubview(instructionLabel)
        addSubview(dragTileView)

        NSLayoutConstraint.activate([
            arrow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            arrow.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            arrow.widthAnchor.constraint(equalToConstant: 32),
            arrow.heightAnchor.constraint(equalToConstant: 32),

            instructionLabel.leadingAnchor.constraint(equalTo: arrow.trailingAnchor, constant: 12),
            instructionLabel.centerYAnchor.constraint(equalTo: arrow.centerYAnchor),
            instructionLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -18),

            dragTileView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 54),
            dragTileView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            dragTileView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            dragTileView.heightAnchor.constraint(equalToConstant: 42),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func configure(permission: SystemPermissionKind) {
        instructionLabel.stringValue = permission.dragInstruction
    }
}

@MainActor
final class DraggableAppTileView: NSView, NSDraggingSource {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(calibratedWhite: 0.86, alpha: 1).cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let iconRect = CGRect(x: 12, y: 8, width: 28, height: 28)
        let icon = currentIcon()
        icon.draw(in: iconRect)

        let title = currentTitle()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor(calibratedWhite: 0.26, alpha: 1),
        ]
        title.draw(at: CGPoint(x: 52, y: 12), withAttributes: attributes)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let bundleURL = PermissionSupport.currentAppBundleURL() else {
            NSSound.beep()
            return
        }

        let draggingItem = NSDraggingItem(pasteboardWriter: bundleURL as NSURL)
        draggingItem.setDraggingFrame(bounds, contents: snapshotImage())
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    private func currentIcon() -> NSImage {
        if let bundleURL = PermissionSupport.currentAppBundleURL() {
            if let bundle = Bundle(url: bundleURL), bundle.bundleIdentifier == PermissionSupport.bundleIdentifier {
                return Branding.makeAppIconImage(size: 128)
            }

            return NSWorkspace.shared.icon(forFile: bundleURL.path)
        }

        return Branding.makeAppIconImage(size: 128)
    }

    private func currentTitle() -> String {
        if let bundleURL = PermissionSupport.currentAppBundleURL() {
            if let bundle = Bundle(url: bundleURL) {
                let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                let bundleName = bundle.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String
                return displayName ?? bundleName ?? PermissionSupport.bundleDisplayName
            }

            return PermissionSupport.bundleDisplayName
        }

        return PermissionSupport.bundleDisplayName
    }

    private func snapshotImage() -> NSImage {
        let bitmap = bitmapImageRepForCachingDisplay(in: bounds) ?? NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width), pixelsHigh: Int(bounds.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        cacheDisplay(in: bounds, to: bitmap)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(bitmap)
        return image
    }
}

@MainActor
enum Branding {
    static func makeAppIconImage(size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        let rect = CGRect(origin: .zero, size: image.size)
        let tile = NSBezierPath(roundedRect: rect, xRadius: size * 0.22, yRadius: size * 0.22)

        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.12, green: 0.67, blue: 0.99, alpha: 1),
            NSColor(calibratedRed: 0.94, green: 0.74, blue: 0.93, alpha: 1),
        ])!
        gradient.draw(in: tile, angle: 20)

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: size * x / 256, y: size * (1 - y / 256))
        }

        func scale(_ value: CGFloat) -> CGFloat {
            size * value / 256
        }

        let arc = NSBezierPath()
        arc.move(to: point(74, 156))
        arc.curve(
            to: point(182, 88),
            controlPoint1: point(78, 112),
            controlPoint2: point(136, 72)
        )
        arc.lineWidth = scale(12)
        arc.lineCapStyle = .round
        NSColor.white.withAlphaComponent(0.72).setStroke()
        arc.stroke()

        let pointerShadow = NSBezierPath()
        pointerShadow.move(to: point(129, 102))
        pointerShadow.line(to: point(129, 181))
        pointerShadow.line(to: point(149, 162))
        pointerShadow.line(to: point(161, 193))
        pointerShadow.line(to: point(176, 186))
        pointerShadow.line(to: point(164, 157))
        pointerShadow.line(to: point(192, 152))
        pointerShadow.close()
        NSColor.white.withAlphaComponent(0.14).setFill()
        pointerShadow.fill()

        let pointer = NSBezierPath()
        pointer.move(to: point(126, 98))
        pointer.line(to: point(126, 177))
        pointer.line(to: point(146, 158))
        pointer.line(to: point(158, 189))
        pointer.line(to: point(173, 182))
        pointer.line(to: point(161, 153))
        pointer.line(to: point(189, 148))
        pointer.close()
        pointer.lineWidth = scale(6)
        pointer.lineJoinStyle = .round
        pointer.lineCapStyle = .round
        NSColor.white.withAlphaComponent(0.94).setFill()
        pointer.fill()
        NSColor.white.setStroke()
        pointer.stroke()

        image.unlockFocus()
        return image
    }
}

@MainActor
final class GradientBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let gradient = NSGradient(colors: [
            NSColor(calibratedWhite: 0.985, alpha: 1),
            NSColor(calibratedRed: 0.95, green: 0.97, blue: 1, alpha: 1),
            NSColor(calibratedRed: 0.98, green: 0.94, blue: 1, alpha: 1),
        ])!
        gradient.draw(in: bounds, angle: 15)
    }
}

@MainActor
final class AppGlyphView: NSImageView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        image = Branding.makeAppIconImage(size: PermissionOnboardingLayout.headerIconSize)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}

@MainActor
final class StatusChipView: NSView {
    init(text: String, foreground: NSColor, background: NSColor) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.backgroundColor = background.cgColor

        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        label.textColor = foreground
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        let check = NSImageView()
        check.translatesAutoresizingMaskIntoConstraints = false
        check.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: text)
        check.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .bold)
        check.contentTintColor = foreground
        addSubview(check)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 34),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            check.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            check.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            check.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}

@MainActor
final class PrimaryActionButton: NSButton {
    override var isHighlighted: Bool {
        didSet {
            updateAppearance()
        }
    }

    init(title: String, target: AnyObject?, action: Selector) {
        super.init(frame: .zero)
        self.target = target
        self.action = action
        self.title = title
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        isBordered = false
        focusRingType = .none
        setButtonType(.momentaryPushIn)
        updateAttributedTitle()
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }

    private func updateAttributedTitle() {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraphStyle,
            ]
        )
    }

    private func updateAppearance() {
        layer?.backgroundColor = (
            isHighlighted
            ? NSColor(calibratedRed: 0.05, green: 0.45, blue: 0.94, alpha: 1)
            : NSColor(calibratedRed: 0.06, green: 0.49, blue: 0.99, alpha: 1)
        ).cgColor
        alphaValue = isEnabled ? 1 : 0.45
    }
}
