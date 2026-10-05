# Workspace app Dock

- Request: add a lightweight Dock showing only applications in the selected virtual display; click an icon to bring its window forward. Manual preview takeover is deferred.
- Implementation: fixed preview-bottom native material Dock, native app icons cached by PID, hover/pressed feedback and selection dot; right-click lists managed windows. Apps awaiting window authorization or with no complete in-display managed window are excluded.
- GUI-only showManagedWindow uses the shared serial registry, verifies process birth/window/frame, raises the selected AX window and checks overlapping managed-window order. Snapshot layout version advances and stale cursor clears. It never calls application.activate or global input. An app changing system focus pauses automation. Agent secondary-action restrictions remain unchanged.
- Verification: full Swift suite 202 tests, 2 skipped, zero failures; final focused suite 34 tests, 1 skipped, zero failures. Signed release App/helper built and strictly verified; own runtime safely quit/restarted in its existing isolated namespace.
- Limitation: Mac was locked; Computer Use could not validate the actual Dock visual layout, two-app clicking or foreground preservation. Unlock was requested. No display hotplug stress or force termination was performed.
- Documentation: architecture, frontend, virtual-display design, quality notes and completed implementation plan synchronized.
