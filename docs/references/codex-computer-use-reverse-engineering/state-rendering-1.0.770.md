# State Rendering Notes for Computer Use 1.0.770

Date: 2026-05-07

This note records local reverse-engineering findings from the bundled official `computer-use` 1.0.770 app. The goal is to keep future `open-computer-use` state-rendering changes tied to observed evidence rather than one-off chat context.

## Evidence Sources

- Bundle inspected:
  - `Codex Computer Use.app`
  - `SkyComputerUseClient.app`
  - `SkyComputerUseService`
- Commands used:
  - `strings -a .../SkyComputerUseClient`
  - `strings -a .../SkyComputerUseService`
  - `otool -Iv .../SkyComputerUseService`
  - `nm -m .../SkyComputerUseService`

## Observed Facts

- `SkyComputerUseClient` contains the visible host wrapper prefix `Computer Use state (CUA App Version: ...)`.
  - This suggests the `<app_state>` style wrapping is at least partly client / host-side, not necessarily the raw MCP state renderer.
- `SkyComputerUseService` contains renderer-related field names:
  - `role`
  - `subrole`
  - `roleDescription`
  - `title`
  - `description`
  - `value`
  - `truncationRange`
  - `valueDescription`
  - `valueTypeName`
  - `placeholderValue`
  - `help`
  - `identifier`
  - `domClassList`
  - `actionDescriptions`
  - `isSelected`
  - `isSelectable`
  - `isFocused`
  - `isFocusable`
  - `isEnabled`
  - `isDisclosing`
  - `isDisclosable`
  - `isValueSettable`
  - `attributedString`
  - `transformedString`
- `SkyComputerUseService` contains AX attribute strings used by the renderer / tree builder:
  - `AXPlaceholderValue`
  - `AXValueDescription`
  - `AXRoleDescription`
  - `AXSelectedChildren`
  - `AXFocusedUIElement`
  - `AXManualAccessibility`
  - `AXEnhancedUserInterface`
  - `AXAttributedStringForTextMarkerRange`
  - `AXStringForTextMarkerRange`
  - `AXTextualContext`
  - `AXVisibleCharacterRange`
  - `AXVisibleChildren`
- `SkyComputerUseService` contains tree transform names:
  - `filterActions`
  - `associateTitleUIElements`
  - `flattenIntoSelectableAncestor`
  - `pruneNonDescriptiveSubtrees`
  - `pruneEmptyDisabledElements`
  - `mergeSingleItemGroups`
  - `flattenRedundantHierarchy`
  - `flattenRepetitiveStaticText`
  - `flattenLinksIntoMarkdownText`
  - `mergeTextOnlySiblings`
  - `removeElementsUnderCalendarEvents`
  - `retrieveAttributedTextFromTextAreas`
  - `retrieveAttributedTextFromWebAreas`
- `SkyComputerUseService` imports AX and window APIs used by the open implementation too:
  - `AXUIElementCopyAttributeValue`
  - `AXUIElementCopyMultipleAttributeValues`
  - `AXUIElementPerformAction`
  - `AXUIElementSetAttributeValue`
  - `CGWindowListCopyWindowInfo`
  - `kCGWindowIsOnscreen`
  - `SCWindow`
- `SkyComputerUseService` contains window error strings including:
  - `noWindowsAvailable`
  - `cgWindowNotFound`
  - `noMatchingWindow`
- `SkyComputerUseService` contains interaction / action strings including:
  - `Secondary Actions`
  - `AXRaise`
  - `AXPress`
  - `AXShowMenu`
  - `AXScrollToVisible`
  - `AXScrollLeftByPage`
  - `AXScrollRightByPage`
  - `AXScrollUpByPage`
  - `AXScrollDownByPage`

## Current Open Implementation Follow-Ups

Already aligned in recent local changes:

- Hidden Lark / Electron windows are recovered before returning `cgWindowNotFound`.
- Real AX tree root lines render at depth 0, matching official `0 standard window ...` shape.
- `AXPlaceholderValue` / `AXPlaceholder` is rendered as `Placeholder: ...` when not duplicating title, description, or value.

Promising next targets:

- Add a careful `AXValueDescription` path for controls where raw `AXValue` is missing, numeric, or not human-readable.
- Compare official link flattening with current `AXLink` rendering; official strings explicitly mention `flattenLinksIntoMarkdownText`.
- Compare text-area and web-area extraction against official `retrieveAttributedTextFromTextAreas` / `retrieveAttributedTextFromWebAreas`.
- Revisit generic tree transforms against official transform names, especially `flattenRedundantHierarchy`, `flattenRepetitiveStaticText`, and `mergeTextOnlySiblings`.

## Caution

The official binary strings identify available fields and transforms, but not the exact rendering order or all branch conditions. Treat this document as evidence for choosing the next investigation target, not as a complete source-level reconstruction.
