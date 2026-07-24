# Project Log

## 2026-07-23 — documentation foundation

`VERIFIED`: Added canonical project context covering product scope, current status, decisions, architecture, rules, privacy, testing, failure modes, sources, workflows, and known limitations.

`VERIFIED`: Added an Apple-framework-only deterministic Markdown-to-HTML generator with ownership markers, SHA-256 source identity, stable heading IDs, local documentation-link rewriting, Git-scoped NUL-safe discovery, collision/symlink/orphan safeguards, unsupported-format rejection, and atomic output writes.

`VERIFIED`: The temporary-repository integration suite passed deterministic output, missing/stale detection, local-link rewriting, stable heading IDs, collision refusal, marker-owned orphan cleanup, unsupported-format rejection, and source/output symlink refusal.

`OPEN`: Product build and runtime evidence must be appended after implementation and installed Release QA. This dated entry is intentional history and should not be rewritten to imply future results were known here.

## 2026-07-23 — production implementation and automated acceptance

`VERIFIED`: Implemented the native Swift 6 menu-bar application, serialized pasteboard coordinator, strict byte-preserving cleaning engine, immutable protection guards, typed built-in/user rules, permission state, pause/skip/undo/conflict lifecycle, Settings, App Intent, and Launch at Login integration.

`VERIFIED`: Added fail-closed bounds for 64 KiB URL/clipboard input, 8 KiB path and fragment, 256 query fields, 128 path components and fragment fields, 256 KiB imports, 512 user/2,048 total rules, and documented rule-field limits. Reviewed dates use actual Gregorian validation, and imported hard protections are additive.

`VERIFIED`: Corrected ownership-sensitive commit/rollback races, exact-generation suppression, explicit-only conflict recovery that survives sleep/wake and session round-trips, monotonic live timed pause, persisted pause bootstrap, rule bootstrap fail-closed behavior, persisted user/built-in ID-collision reporting, encoded protected-path ambiguity, bounded conflict history, and the URL representation's whitespace-envelope rejection.

`VERIFIED`: The settled Debug XCTest/Swift Testing run reported 79 top-level tests: 78 passed, one expected Release-only performance skip, and zero failures; expanded device/configuration reporting recorded 150 passes and zero failures. The isolated XCUITest passed the `LSUIElement` Settings focus and status-menu inventory using the correct scroll-view accessibility role.

`VERIFIED`: Final Release acceptance passed 4 of 4 tests with all 74 numbered fixtures. For exact 65,536-byte inputs, the 21-sample medians were 9.089834 ms for a large query value, 1.985042 ms for many query fields, 0.551584 ms for many fragment fields, 0.607709 ms for many path components, and 5.48 ms for a long parameter name against 512 rules. Ten thousand synthetic coordinator events retained 49,152 bytes.

`OPEN`: A synchronous lazy provider cannot be preempted with public AppKit API. The implementation rejects a provider that returns after 100 ms, and the 110 ms test confirms post-return rejection only.

`OPEN`: Final installed-Release, real permission, Shortcut, login-item, energy, runtime-network, cross-application, and system clipboard/history QA is recorded separately when observed; this entry does not imply those checks passed.

## 2026-07-23 — settled rule-review and path-classification invariants

`VERIFIED`: User-rule persistence now records an optional `reviewedBuiltInRuleSetRevision`. Confirmed built-in-preserve overrides survive relaunch when the bundled revision is unchanged; after a built-in revision change, affected enabled user removals are disabled for individual acknowledgement while unrelated user-rule state is retained.

`RECOMMENDATION`: Every reviewed change to `BuiltInRules.json` must increase its `ruleSetRevision`. Without that bump, the re-review invalidation contract cannot detect that prior user acknowledgement may be stale.

`VERIFIED`: Whole-link classification treats decoded dot segments, residual percent signs, C0/DEL bytes, and decoded slash/backslash separators as ambiguous and protects the URL. The explicit conflict-pause sleep/wake and session round-trip test remains passing.

## 2026-07-23 — installed Release verification

`VERIFIED`: Rebuilt the settled Release and installed it at `/Applications/Tracker Free.app` after moving the provisional build to a recoverable temporary backup. The installed executable exactly matches the release artifact at SHA-256 `c507d4de0e53fd0fdeedbee4517465e675c0de68652fd9b68442a76a310b27f1`. After verification, the stale backup and older temporary QA runs were removed; only the newest settled Debug, Release acceptance, UI, diagnostics, and install-artifact directories remain under `/private/tmp`.

`VERIFIED`: Strict code-signature validation passes. The signature is ad hoc with Hardened Runtime; the only entitlements are App Sandbox and user-selected file read/write. The bundle identifier is `com.vishal.TrackerFree`, `LSUIElement` is true, the deployment minimum is macOS 13.0, and App Intent metadata contains “Clean Current Clipboard.”

`VERIFIED`: The installed process launched. A bounded post-launch `lsof` observation found no open network sockets. Computer Use could not acquire the accessibility state of the windowless installed app and returned timeout `-10005`; the isolated XCUITest remains the current menu-inventory and Settings-focus evidence.

`VERIFIED`: Static safety, deterministic project generation, 14-of-14 documentation parity, documentation integration safeguards, and HTML parsing pass after the installed-release update.

`OPEN`: Real permission states, installed visual Dock/menu interaction, Shortcut execution, Launch at Login, ten-minute idle CPU/energy/network observation, cross-application behavior, Universal Clipboard, and Clipboard History remain manual gates.

`VERIFIED`: The implementation commit was fast-forwarded into clean local `main`, the completed feature branch was removed, and the repository has one worktree. No Git remote exists, so no push or remote-main reconciliation was attempted.

## 2026-07-24 — public GitHub publication

`VERIFIED`: After explicit user authorization, created the public [vdoshi96/tracker-free](https://github.com/vdoshi96/tracker-free) repository, configured it as `origin`, and pushed the existing two-commit `main` history. GitHub reported `main` at implementation commit `c47e655fddea0de56c434fd8552fd95bb09188c7` before this publication-documentation update.

`VERIFIED`: The pre-publication review found no real credentials or private files in reachable Git history. Matches for token and secret terminology were source-code guards or synthetic security-test fixtures. No license was added; public visibility alone does not grant an open-source license.

`VERIFIED`: Public publication did not alter the application implementation, installed bundle, prior QA evidence, or historical release claims. Current remote and parity state is maintained in [Current status](STATUS.md).
