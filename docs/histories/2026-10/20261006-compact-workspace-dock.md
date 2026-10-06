# Compact workspace Dock

- Request: make the Dock fit a small number of icons and tighten its spacing, using the system Dock as visual reference. User asked not to create displays during development and will perform the live check.
- Cause: ScrollView followed by maxWidth expanded the visible material surface to the width limit even with two items.
- Change: visible surface explicitly fits the icon count, capped by the preview width and 480 points. Two items occupy 104 points; icon hit areas are 44 points with 4-point gaps and 6-point side padding. Height is 60 points; overflow scrolls horizontally, with material/clipping applied to the fitted surface rather than the outer centering container.
- Validation: Developer ID release App/helper build and strict signature verification passed; own runtime with no owned displays safely restarted. No displays or test sessions created. Screenshot comparison is left to the user as requested; no new tests for this layout-only adjustment.
- Files: WorkspaceAppDock.swift and frontend notes.
