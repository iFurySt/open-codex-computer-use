# Mac Session Guard Consumer Map & Test Surface Scout

## 1. GUARD CONSUMERS & CALL SITES

### A. ComputerUseToolDispatcher.callTool() — Gateway for all GUI tools
**File**: packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseToolDispatcher.swift:50
**Call**: `guard.requireUnlocked(for: toolName)`
**Guarded Tools** (9 total):
  - list_apps, get_app_state, click, perform_secondary_action, scroll, drag, type_text, press_key, set_value

**Behavior on lock**:
  - requireUnlocked() checks snapshot.isLocked
  - If true → throws ComputerUseError.stateUnavailable
  - Error message includes: "macOS is locked" + policy-specific guidance (unlock machine OR set OPEN_COMPUTER_USE_ALLOW_LOCKED=1)
  - If snapshot.isUnknown=true AND policy=.blockWhileLocked → also throws (fail-closed)

### B. MCPAppRuntime.applicationDidFinishLaunching() — Startup diagnostic
**File**: apps/OpenComputerUse/Sources/OpenComputerUse/MCPAppRuntime.swift:61
**Call**: `guard.currentState()` (static instance of MacSessionGuard)
**Fields Read**:
  - snapshot.isUnknown → boolean
  - snapshot.rawKeysSeen → Set<String>

**Behavior**:
  - If isUnknown=true at startup: emits WARNING to stderr
  - Message: "[open-computer-use] WARNING: CGSSessionScreenIsLocked key absent from CGSessionCopyCurrentDictionary at startup..."
  - Appends: sorted rawKeysSeen as comma-separated list
  - Purpose: Catch macOS version skew (indicate if CGSSessionScreenIsLocked key is missing)

**User-visible impact**: This is the ONLY direct UI consumer of MacSessionSnapshot fields. No menu bar, no visual status indicator — only stderr diagnostic.

---

## 2. EXISTING GUARD TESTS + FAKES

**Test File**: packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift

### Test Block Span: lines 1907–2051

### Fake Providers (lines 2637–2652)
| Name | isLocked | isUnknown | rawKeysSeen | Purpose |
|------|----------|-----------|-------------|---------|
| FakeLockedSessionProvider | true | false | ["CGSSessionScreenIsLocked"] | Test guard blocks on genuine lock |
| FakeUnlockedSessionProvider | false | false | ["CGSSessionScreenIsLocked"] | Test guard passes on genuine unlock |
| FakeSnapshotProvider(snapshot:) | configurable | configurable | configurable | Flexible fixture for edge cases |

### Test Coverage (14 functions)
1. testMacSessionGuardBlocksWhenLocked — guard throws when isLocked=true
2. testMacSessionGuardAllowsWhenUnlocked — guard passes when isLocked=false
3. testMacSessionGuardFailsClosedOnNilDictionary — nil dict → isUnknown=true, throws
4. testMacSessionGuardFailsClosedOnEmptyDictionary — empty dict → isUnknown=true, throws
5. testMacSessionGuardFailsClosedOnParseFailed — unparseable value → isUnknown=true, throws
6. testMacSessionGuardRawKeysDiagnostics — rawKeysSeen field is accessible & correct
7. testSystemMacSessionStateProviderCachesWithinTTL — documents 200ms TTL intent (indirect test via CountingProvider)
8. testDispatcherBlocksAllGUIToolsWhenLocked — all 9 GUI tools blocked when guard.currentState().isLocked=true
9. testLockPolicyDefaultsToBlockWhenEnvironmentUnset — OPEN_COMPUTER_USE_ALLOW_LOCKED unset → .blockWhileLocked
10. testLockPolicyParsesAllowValuesFromEnvironment — accepts "1", "true", "yes", "on", "allow" (case-insensitive, with whitespace trim)
11. testGuardBlocksWhenLockedUnderDefaultPolicy — explicit .blockWhileLocked policy
12. testGuardAllowsAllToolsWhenLockedUnderOptInPolicy — explicit .allowWhileLocked allows all tools while locked
13. testGuardAllowsToolsWhenLockStateUnknownUnderOptInPolicy — isUnknown=true + .allowWhileLocked permits action (accepts degraded state)
14. testGuardStillAllowsEverythingWhenUnlockedRegardlessOfPolicy — unlocked always passes, regardless of policy setting
15. testDispatcherAllowsAXToolsWhenLockedWithOptIn — opt-in policy + list_apps succeeds (no live UI, accessibility still works)

**Coverage Gap**: No direct test of SystemMacSessionStateProvider.fetchFromSystem() parsing logic. Today's tests mock the provider entirely via protocol conformance. Tests cannot exercise CGSessionCopyCurrentDictionary response parsing independently.

---

## 3. BUILD & TEST COMMANDS

**Package Structure** (from Package.swift):
- Library: OpenComputerUseKit
  - Source path: packages/OpenComputerUseKit/Sources/OpenComputerUseKit
  - Test target: OpenComputerUseKitTests
  - Test path: packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests

**Makefile** (repo root, lines 12–19):
```makefile
build:
  swift build

test:
  swift test
```

**Full stack test command** (all tests, all packages):
```bash
cd /Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/fix-mac-session-guard-lock-detection
swift test
```

**Library-only test** (recommended for lock-state changes):
```bash
swift test OpenComputerUseKitTests
```

**Build only (no test)**:
```bash
swift build
```

---

## 4. SEAM FOR TESTING fetchFromSystem PARSING

### Current State
- SystemMacSessionStateProvider.fetchFromSystem() is **private static** (line 97 in MacSessionGuard.swift)
- Directly calls CGSessionCopyCurrentDictionary() → cannot mock
- Existing fakes implement MacSessionStateProvider protocol → bypass parsing entirely
- **Gap**: No unit test of the parsing logic (nil/empty dict guard, key lookup, type conversion, fail-closed on unparseable)

### Least-invasive exposure strategy
**Option A (Recommended)** — Extract internal static parse function:
- Add `internal static func parseSessionDict(_ dict: [String: Any]?, rawKeys: Set<String>) -> MacSessionSnapshot`
- Move lines 98–119 (nil guard, key lookup, Bool/NSNumber parsing, fail-closed) into this function
- Call parseSessionDict from fetchFromSystem
- Testable via `@testable import OpenComputerUseKit`
- No public API surface change
- Protocol seam (MacSessionStateProvider) unchanged

**Option B** (Lighter) — Inline helper with DEBUG gate:
- Keep fetchFromSystem as-is; add `#if DEBUG` gate with injectable parse function
- Not preferred: adds conditional compilation; leaks DEBUG-only surface

### Test cases the seam would enable
```swift
XCTAssertEqual(
  SystemMacSessionStateProvider.parseSessionDict(nil, rawKeys: []),
  MacSessionSnapshot(isLocked: true, isUnknown: true, rawKeysSeen: [])
)

XCTAssertEqual(
  SystemMacSessionStateProvider.parseSessionDict([:], rawKeys: []),
  MacSessionSnapshot(isLocked: true, isUnknown: true, rawKeysSeen: [])
)

// Key absent (the bug case on this machine)
let dictNoKey: [String: Any] = ["kCGSSessionOnConsoleKey": 1]
let result = SystemMacSessionStateProvider.parseSessionDict(dictNoKey, rawKeys: ["kCGSSessionOnConsoleKey"])
XCTAssertEqual(result.isLocked, true)
XCTAssertEqual(result.isUnknown, true)  // ← Currently true (bug), should become false (fix)

// Key present with Bool
let dictWithBool = ["CGSSessionScreenIsLocked": true]
XCTAssertEqual(
  SystemMacSessionStateProvider.parseSessionDict(dictWithBool, rawKeys: ["CGSSessionScreenIsLocked"]),
  MacSessionSnapshot(isLocked: true, isUnknown: false, rawKeysSeen: ["CGSSessionScreenIsLocked"])
)

// Key present with NSNumber
let dictWithNum = ["CGSSessionScreenIsLocked": NSNumber(1)]
XCTAssertEqual(
  SystemMacSessionStateProvider.parseSessionDict(dictWithNum, rawKeys: ["CGSSessionScreenIsLocked"]),
  MacSessionSnapshot(isLocked: true, isUnknown: false, rawKeysSeen: ["CGSSessionScreenIsLocked"])
)

// Key present with unparseable type
let dictWithString = ["CGSSessionScreenIsLocked": "invalid"]
let result = SystemMacSessionStateProvider.parseSessionDict(dictWithString, rawKeys: ["CGSSessionScreenIsLocked"])
XCTAssertEqual(result.isLocked, true)
XCTAssertEqual(result.isUnknown, true)  // Fail-closed
```

---

## Unresolved Questions
1. **API preference for parse seam**: Option A (internal static func) vs Option B (DEBUG gate)? Option A is cleaner and recommended.
2. **Should rawKeys parameter be computed from dict.keys or passed in?** Currently dict is optional; rawKeys would be computed inside parse for nil/empty dict cases. Passing as separate param gives tighter test control.
