# Current Status

## Snapshot

`VERIFIED`: Tracker Free's production implementation and isolated automated suites are complete and passing on macOS 26.6 build 25G70 with Xcode 26.6 build 17F113.

`VERIFIED`: The settled Debug run reported 79 top-level tests: 78 passed and one Release-only performance case was intentionally skipped. Expanded device/configuration reporting recorded 150 passes and zero failures across XCTest and Swift Testing engine, rule, coordinator, named-pasteboard, lifecycle, race, persistence, and static-architecture cases. The isolated XCUITest verifies the menu-extra status inventory and Settings focus for the dockless app.

`VERIFIED`: Release acceptance passed 4 of 4 tests with all 74 numbered fixtures, exact 64 KiB structural cases, 8 MiB early rejection, a maximum 512-rule shape, and 10,000 synthetic coordinator events. The observed worst 64 KiB median was 9.089834 ms, the long-name/512-rule median was 5.48 ms, and retained resident growth was 49,152 bytes.

`VERIFIED`: The settled Release is installed at `/Applications/Tracker Free.app`. Its executable is byte-identical to the verified build (SHA-256 `c507d4de0e53fd0fdeedbee4517465e675c0de68652fd9b68442a76a310b27f1`), passes strict code-signature verification, and launches successfully.

`OPEN`: Real General-pasteboard permission behavior, App Intent execution through Shortcuts, Launch at Login, ten-minute runtime network/energy observation, and the cross-application manual matrix still require current evidence before release.

`RECOMMENDATION`: Treat this file as the current authority. Preserve dated entries in [Project log](LOG.md) as history rather than rewriting them.

## Release gates

- `VERIFIED`: Debug build/full tests and Release acceptance tests pass with Xcode 26.6.
- `VERIFIED`: Swift 6 strict-concurrency compilation passes without `@unchecked Sendable` or unsafe concurrency suppression.
- `VERIFIED`: Pure-engine, coordinator, named-pasteboard, isolated UI, Release performance, and deterministic fuzz/property tests pass.
- `VERIFIED`: All 74 required numbered fixtures pass; additional encoded-path and structural-bound variants also pass.
- `VERIFIED`: Decoded classification paths fail closed as ambiguous when they contain dot segments, a residual percent sign, C0/DEL bytes, or decoded slash/backslash separators.
- `VERIFIED`: Ordinary automated tests use fake or uniquely named pasteboards; a static allowlist isolates `NSPasteboard.general` to the production adapter.
- `VERIFIED`: The installed Release has `LSUIElement=true`, bundle identifier `com.vishal.TrackerFree`, macOS 13.0 minimum, and launches as the expected menu-bar process. A direct installed visual Dock/menu inspection remains open because the desktop-control service timed out for the windowless app.
- `VERIFIED`: Automatic and manual cleaning are demonstrated on fake and uniquely named synthetic pasteboards; installed General-pasteboard demonstration remains open.
- `VERIFIED`: Rich, multiple, remote, sensitive, protected, malformed, and ambiguous synthetic values remain unchanged.
- `VERIFIED`: Skip Next, timed and indefinite pause, undo, stale undo, sleep/wake, session loss, termination, and relaunch semantics pass deterministic tests. Conflict pause survives sleep/wake and session round-trips and permits only explicit resume.
- `OPEN`: Permission-required states are truthful on macOS 26.6.
- `OPEN`: App Intent works through a user-created Shortcut without Accessibility permission.
- `OPEN`: `SMAppService.mainApp` is verified from the installed app or a precise blocker is recorded.
- `VERIFIED`: The installed app's ad-hoc signature has Hardened Runtime enabled. Its only entitlements are App Sandbox and user-selected file read/write; network client/server and `get-task-allow` are absent.
- `VERIFIED`: Static scans find no network APIs, and a bounded post-launch `lsof` snapshot found no open network sockets for the installed process. A longer installed observation remains open.
- `VERIFIED`: Static architecture checks reject network/global-input APIs and confine logging to privacy-safe metadata; installed runtime log/persistence sentinel observation remains open.
- `VERIFIED`: Release acceptance meets the less-than-5-MiB retained-growth and less-than-10-ms transform targets. Ten-minute installed idle CPU and energy observation remains open.
- `OPEN`: Safari, Firefox, Chrome, X, Mail, Messages, Notes, Terminal, and an existing clipboard manager are checked where available.
- `OPEN`: Universal Clipboard and Clipboard History limitations are checked using synthetic content only.
- `VERIFIED`: XCUITest confirms Settings focus and status-menu inventory under `LSUIElement`; full installed menu behavior remains open.
- `VERIFIED`: Final documentation parity passes for all 14 canonical Markdown sources, including root `AGENTS.md`; integration safeguards and HTML parsing also pass.
- `VERIFIED`: The repository is public at [vdoshi96/tracker-free](https://github.com/vdoshi96/tracker-free). `origin` uses that GitHub repository, local `main` tracks `origin/main`, and repository closeout requires exact local/remote `main` parity.

## Implemented safety bounds

- Clipboard/URL input: 64 KiB combined UTF-8.
- Raw path and fragment: 8 KiB each.
- Raw query: 256 fields.
- Whole-link protection inspection: 128 path components and 128 fragment fields.
- Rule import: 256 KiB; 512 user rules; 2,048 total rules.
- Rule ID/name: 128 bytes; explanation: 1,024 bytes; provenance URL: 2,048 bytes.
- Rule scope: 64 hosts; literal path constraint: 512 bytes.
- Lazy representation duration: reject after a return later than 100 ms.

`VERIFIED`: A persisted user-rule set that collides with a newer built-in ID is rejected at load, built-ins remain active, and Settings surfaces the validation warning instead of silently dropping the condition.

`VERIFIED`: User-rule documents persist the optional built-in revision reviewed for preserve/removal overlaps. Confirmed overrides survive relaunch at the same revision; a changed bundled revision disables only affected enabled user removals and requires individual acknowledgement before re-enabling.

`VERIFIED`: The installed bundle contains App Intent metadata for “Clean Current Clipboard.” End-to-end execution from a user-created Shortcut remains open.

`OPEN`: A synchronous `NSPasteboardItem.data(forType:)` provider cannot be preempted through the public API. The 110 ms late-provider test proves post-return rejection, not cancellation or a bound on allocations performed inside AppKit.

## Empirical questions

Keep conservative behavior while these remain unresolved:

1. `OPEN`: Exact `.default`, `.ask`, `.alwaysAllow`, and `.alwaysDeny` alert and Settings behavior on macOS 26.6.
2. `OPEN`: Whether count or type inspection itself can prompt in tested flows.
3. `OPEN`: Whether App Intent clipboard access receives user-originated treatment.
4. `OPEN`: Whether `SMAppService.mainApp` remains reliable across installed ad-hoc rebuilds.
5. `OPEN`: Whether Personal Team signing materially improves local identity stability.
6. `OPEN`: Exact Safari, Firefox, and Chrome representation inventories for address-bar, Copy Link, and rich-link copies.
7. `OPEN`: Whether any proven inert browser metadata type should enter the allowlist.
8. `OPEN`: Measured 250 ms versus 500 ms energy behavior.
9. `OPEN`: Runtime behavior on macOS 13, 14, 15.3, and 15.4/15.5.
10. `OPEN`: Whether a future opt-in should allow rewritten values to participate in Universal Clipboard.

## Non-actions

`VERIFIED`: The original application QA did not inspect or capture the current clipboard, change privacy settings, or contact a network service. Public GitHub publication was separately authorized and completed on 2026-07-24 without inspecting clipboard contents, changing the installed application, or rerunning application QA.
