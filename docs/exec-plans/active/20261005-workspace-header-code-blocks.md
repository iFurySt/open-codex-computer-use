# Workspace header and code blocks

- Goal: simplify creation, make loading visible, expose display availability, move session status/ID to header, and pair native code blocks.
- Scope: macOS GUI only; preserve one active session per display, exact display authorization and input boundaries. No new editor dependency.
- Steps: inspect display states and editor references; implement shared native controls; compile/test and verify UI; sign/restart/local commit.
- Evidence: current sole display is leased by Session 1. Previous chooser filtered it out; show occupied resources disabled and idle resources selectable instead.
- Reference: https://github.com/mchakravarty/CodeEditorView supports a complete TextKit 2 editor. This task uses a small NSTextView block for plain JSON, selection/editing/undo and token coloring.
- Validation: Swift tests, signed build, actual idle-display selection without repeated hotplug, header status/clipboard feedback, command editing and result rendering.
- Status: implementation, Swift regression, signed build and normal App restart complete. Live GUI verification pending manual unlock; automatic unlock failed. One online idle display was reserved for exact-ID selection testing, without a hotplug loop.
- Results: 193 Swift tests (1 skip), no failures; Developer ID bundle/helper and deep/strict verification passed. Copy feedback, editing/undo and header layout still require unlocked UI verification.
