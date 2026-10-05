# Example window spacing

- Request: TextEdit covers too much of Calculator in the virtual-display example.
- Change: the prepare cell arranges the dedicated, already-managed TextEdit document to the right of Calculator, with a 40-point gap where space permits. The document remains inside the display, AX placement is read back, layout version advances, and old cursor targets clear. Other applications and generic attachment placement remain unchanged.
- Validation: 32 virtual-display tests, 1 skipped, zero failures; Developer ID release App/helper build and strict signature verification passed. New signed App launched in a separate runtime namespace because the default socket currently belongs to another worktree's Dev App. No display hotplug was required; live example placement has not been rerun this round.
- Files: VirtualDisplayExample.swift, VirtualDisplaySession.swift and virtual-display design notes.
