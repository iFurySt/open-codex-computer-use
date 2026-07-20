## Scout Report: MacSessionGuard Lock-Detection Fix — Documented Constraints

### 1. Lock-Policy Guarantees (Must Hold)

**Fail-closed default (immutable):**
- README.md:42 — "By default, Computer Use is blocked while macOS is locked (fail-closed)."
- RELIABILITY.md: "fail-closed behavior is **default** **expected** design, not a bug"
- Tests enforce: `testGuardBlocksWhenLockedUnderDefaultPolicy()` (line 2019)
- Broken contract: any fix that allows tool calls while genuinely locked without `OPEN_COMPUTER_USE_ALLOW_LOCKED=1` violates security guarantee

**Opt-in `.allowWhileLocked` (OPEN_COMPUTER_USE_ALLOW_LOCKED=1):**
- README.md:44–46 documents this as best-effort, not equivalent to unlocked session
- Lines 45–46 list hard limits: "window screenshots return blank (macOS blocks capture for security)" + "coordinate-only paths unreliable — prefer element_index"
- ARCHITECTURE.md: explains process-targeted delivery (AX / postToPid) keeps working while login window owns screen
- Documented intention: "explicit opt-in" for unattended agents only; user must understand degraded contract

### 2. Prior Decisions (ALLOW_LOCKED Design)

**Decision source:** Merge history file `/docs/histories/2026-07/20260718-1044-merge-upstream-v020-work-while-locked.md`

- Line 16: "锁屏守卫为 fail-closed，**阻止**全部工具——与目标相反。" (lock guard is fail-closed, blocks all tools — opposite of goal)
- Line 17: "改为显式 opt-in，并如实记录限制" (changed to explicit opt-in, document limitations truthfully)
- Line 22: "本次不推翻该决定：默认不变，仅提供显式 opt-in" (do not overturn this decision: default unchanged, only provide explicit opt-in)
- Security design: "安全敏感开关只走启动 env，避免 per-call socket 伪造" (security-sensitive flag only via launch env, avoid per-call socket spoofing)

**Tests enforcing design:**
- testLockPolicyDefaultsToBlockWhenEnvironmentUnset (line 2002)
- testLockPolicyParsesAllowValuesFromEnvironment (line 2009)
- testGuardAllowsToolsWhenLockStateUnknownUnderOptInPolicy (line 2034) — **unknown state = unknown policy allows it, block policy rejects it**

### 3. Documented Supported macOS Versions

- README.md:57 — "The macOS runtime requires macOS 14.0 or later."
- MacSessionGuard.swift:4 — File-top comment claims "verified on macOS 12–15 (Monterey–Sequoia) and macOS 26" — **THIS CLAIM IS INCORRECT on this machine** (bug context: key is absent when unlocked on macOS 26)

### 4. CI/Test Commands

| Command | Purpose |
|---------|---------|
| `make test` → `swift test` | Unit tests (line 19 Makefile) |
| `make smoke` → `./scripts/run-tool-smoke-tests.sh` | Tool smoke tests |
| `make check-docs` → `./scripts/check-docs.sh` | Doc linting |
| `make check-repo` | Full repo checks (docs + hygiene) |
| `make ci` → `./scripts/ci.sh` | CI pipeline |
| `make agent-smoke AGENTS=claude,codex SCENARIO=list-apps` | Agent integration tests |

**Lock-policy tests (must pass):**
- testMacSessionGuardBlocksWhenLocked (line 1909) — blocks when dict says locked
- testMacSessionGuardAllowsWhenUnlocked (line 1918) — allows when dict says unlocked
- testDispatcherBlocksAllGUIToolsWhenLocked (line 1985) — all non-list tools rejected when locked
- testLockPolicyDefaultsToBlockWhenEnvironmentUnset (line 2002) — fail-closed by default
- testLockPolicyParsesAllowValuesFromEnvironment (line 2009) — env parsing
- testGuardBlocksWhenLockedUnderDefaultPolicy (line 2019)
- testGuardAllowsAllToolsWhenLockedUnderOptInPolicy (line 2025)
- testGuardAllowsToolsWhenLockStateUnknownUnderOptInPolicy (line 2034) — **critical: unknown state behavior**

### 5. Docs That MUST Update If Lock-Detection Semantics Change

| File | Section | Change Trigger |
|------|---------|-----------------|
| README.md | Lines 42–47 (Limitations > Lock Screen) | If behavior of missing dict key / nil dict / unparseable key changes |
| ARCHITECTURE.md | Section "4. Lock Screen Guard" | If fail-closed semantics, dict parsing logic, or policy behavior changes |
| RELIABILITY.md | "Lock Screen / Stale-Target / 状态菜单排查" section | If troubleshooting symptoms or solutions change |
| MacSessionGuard.swift | Line 4 file-top comment | **If verified macOS versions or key behavior differs** |
| SECURITY.md | (if exists) | If threat model or trust boundary of peer auth changes |
| docs/SECURITY.md | (if exists) | If trust boundary assumptions change |

### 6. Critical Constraint From Bug Context

**The bug (empirically verified on Darwin 27 / macOS 26):**
- **Current code (MacSessionGuard.swift:107–109):** treats ABSENT `CGSSessionScreenIsLocked` key as locked (`isUnknown=true`)
- **Empirical fact:** key is omitted (absent) when genuinely UNLOCKED; key is present (true) only when LOCKED
- **Impact:** every tool call blocked by default on unlocked machine — opposite of intent

**Fix constraints (HARD):**
1. Fail-closed posture MUST remain for:
   - nil/empty dict from `CGSessionCopyCurrentDictionary()`
   - Unparseable values (neither Bool nor NSNumber)
2. OPEN_COMPUTER_USE_ALLOW_LOCKED opt-in design UNCHANGED
3. Fix MUST NOT create false "unlocked" signal while genuinely locked
4. MacSessionStateProvider protocol + test fakes (FakeLockedSessionProvider / FakeUnlockedSessionProvider) API compatibility preferred — tests depend on them

---

**Status: DONE (scout read-only, file modifications: NONE)**

/Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/fix-mac-session-guard-lock-detection/README.md:42–47 | /Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/fix-mac-session-guard-lock-detection/ARCHITECTURE.md (section 4) | /Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/fix-mac-session-guard-lock-detection/RELIABILITY.md | /Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/fix-mac-session-guard-lock-detection/MacSessionGuard.swift:1–120 | /Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/fix-mac-session-guard-lock-detection/packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift:2002–2051