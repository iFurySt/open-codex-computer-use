# Compact workspace Dock

- Request: make the Dock fit a small number of icons and tighten its spacing, using the system Dock as visual reference. User asked not to create displays during development and will perform the live check.
- Cause: ScrollView followed by maxWidth expanded the visible material surface to the width limit even with two items.
- Change: visible surface explicitly fits the icon count, capped by the preview width and 480 points. Two items occupy 104 points; icon hit areas are 44 points with 4-point gaps and 6-point side padding. Height is 60 points; overflow scrolls horizontally, with material/clipping applied to the fitted surface rather than the outer centering container.
- Validation: Developer ID release App/helper build and strict signature verification passed; own runtime with no owned displays safely restarted. No displays or test sessions created. Screenshot comparison is left to the user as requested; no new tests for this layout-only adjustment.
- Files: WorkspaceAppDock.swift and frontend notes.

## Follow-up: tighter icon padding

- User compared the fitted Dock with the system Dock; button and surface padding were still too large.
- Kept 36-point native icons, reduced button padding from 4 to 1, item spacing from 4 to 2, outer side padding from 6 to 4 and vertical padding from 5 to 4. Indicator is 3 points with a 1-point gap. Two-item surface is now 86×50 points instead of 104×60; corner radius is 12.
- No displays/test sessions are created during development, per user instruction. Live screenshot comparison remains user-led; only signed builds and normal App lifecycle checks are run.
- Developer ID release and dev bundles/helpers built and strictly verified. The currently used own Dev runtime exited through normal cleanup and restarted into the updated Dev build. Existing test session/display ended during normal cleanup; no new display was created. Other worktree runtimes were left alone.
