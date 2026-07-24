# Testing and QA

## Test isolation

`VERIFIED`: Swift Testing covers the pure recognizer, tokenizer, protected-link classifier, rules, cleaner, parameterized fixtures, precedence order reversal, and deterministic encoding/idempotence properties.

`VERIFIED`: XCTest covers fake-pasteboard coordinator races, named `NSPasteboard.withUniqueName()` integration, timers, lifecycle, bounded imports, Release acceptance/performance, and XCUITest menu/Settings behavior.

`VERIFIED`: The settled Debug run reported 79 top-level tests: 78 passed, one expected Release-only performance skip, and zero failures. Parameterized/device-configuration expansion reported 150 passing cases and zero failures.

Ordinary automated tests must never use `NSPasteboard.general`. A static guard permits `.general` only in the production adapter and a separately isolated opt-in target.

Any General-pasteboard integration test must:

- Be excluded from CI and guarded by an explicit environment flag.
- Run only in a disposable test user/session with synthetic data.
- Seed a known generation rather than snapshotting a personal clipboard.
- Restore only while the test still owns the generation.
- Leave newer user content untouched.

`RECOMMENDATION`: Serialize any suite touching a shared pasteboard. Test diagnostics use fixture IDs and redacted assertions so a failure does not print clipboard values.

## Core deterministic properties

- `clean(clean(x)) == clean(x)`.
- No matching rule means identity and no write.
- Output never grows.
- Retained raw query fields are an exact ordered subsequence.
- Scheme, authority, raw path, fragment, and accepted envelope remain byte-identical.
- Only approved whole fields and an unnecessary query delimiter disappear.
- Every protected fixture remains byte-identical.
- Invalid Unicode, percent encoding, and delimiters never crash or trap.
- Runtime and allocation stay bounded.
- Rule ordering cannot alter precedence.
- Host fuzz includes uppercase, suffix attacks, ports, Punycode, IPv4/IPv6, and explicit subdomains.

## Regression corpus

All 74 table-driven fixtures from the implementation brief pass. Required groups are:

| Cases | Coverage |
|---|---|
| 1–18 | Global removals, duplicates, empty fields, `+`, exact `%HH` retention, case sensitivity, disabled `utm_`, fragments, invalid encoding, semicolons, nested encoded values, no-op, and removal-only queries |
| 19–33 | Exact X/Twitter, YouTube, Instagram, TikTok, Reddit, Amazon, email-content, and protected-email behavior |
| 34–38 | Maps, search, product variants, calendar/invitation, and `.ics` functional preservation |
| 39–46 | AWS, Google Cloud, CloudFront, Azure SAS, reset, OAuth callback/authorization, and token fragments |
| 47–55 | Facebook/Google wrappers, shorteners, userinfo, non-HTTP schemes, scheme-relative forms, localhost, private IP, and IPv6 |
| 56–65 | Literal Unicode, Punycode, exact whitespace envelope, leading/multiple newlines, prose/code/commands/multiple URLs, and 64 KiB boundary |
| 66–74 | Plain text, URL, matching/conflicting dual representations, rich/custom/multiple/remote values, lazy ownership loss, and foreign marker |

Critical byte fixtures include:

- `https://e.test/p?ut%6D_source=x&a=%2f&b=%41` becoming `https://e.test/p?a=%2f&b=%41`.
- `https://e.test/p?utm_source=x&&q=` becoming `https://e.test/p?&q=`.
- `https://e.test/p?UTM_source=x` remaining unchanged.
- `https://x.com.evil/user/status/123?s=20&t=abc` remaining unchanged.
- Signed/authentication/invitation values with otherwise removable fields remaining unchanged.
- `" \thttps://e.test/p?utm_source=x \r\n"` retaining its exact envelope around the cleaned core.
- Encoded wrapper paths with dot segments, residual `%`, C0/DEL bytes, or decoded slash/backslash separators remaining protected as ambiguous.

## Coordinator and failure injection

Passing sequences include:

- Own-generation suppression and later identical external content.
- Generation change during allowed-representation materialization.
- Rule revision change before commit.
- Disable, pause, sleep/session loss, or conflict immediately before commit.
- Clear failure, object-write failure, readback mismatch, successful owned rollback, and ownership loss before rollback.
- No-op, protected, unsupported, race, and disabled events while Skip Next remains armed.
- Manual clean bypassing pause/disable/Skip without consuming Skip.
- Valid undo, marker/output mismatch, newer-copy race, restore ownership, and single-use invalidation.
- Competing cleaner oscillation, threshold entry, explicit recovery, and distinct-generation recovery.
- Timed pause across relaunch and wall-clock changes.
- Wake/session activation baseline without retroactive cleaning.
- A 110 ms synchronous provider return rejected after the call; nil and ownership-loss providers also preserve.
- Permission-prompt preparation that baselines a newly observed generation, remains no-write, and refreshes the permission state.
- Built-in bootstrap failure that disables persisted user removals for automatic, manual, and App Intent callers.
- Conflict pause that survives sleep/wake and session inactive/active round-trips, remains count-only, and clears only after explicit resume.
- A persisted user-rule ID colliding with a newer built-in ID that fails closed to built-ins and surfaces a load warning.
- A confirmed built-in-preserve override that persists across same-revision relaunch, then disables only overlapping enabled user removals when `reviewedBuiltInRuleSetRevision` no longer matches the bundled revision.

## Performance acceptance

Automated Release acceptance on the current Mac requires:

- 250 ms active polling with 25–50 ms tolerance and approximately four idle count checks per second.
- Average idle CPU at or below 0.5% over ten minutes.
- Activity Monitor Energy Impact remains Low.
- Less than 5 MiB memory growth after baseline across 10,000 synthetic coordinator events.
- A 64 KiB pure transform completes within 10 ms.

`VERIFIED`: The final Release acceptance suite passed 4 of 4 tests. Each transform input was exactly 65,536 bytes and each median used 21 samples:

| Case | Median |
|---|---:|
| Large query value | 9.089834 ms |
| Many query fields | 1.985042 ms |
| Many fragment fields | 0.551584 ms |
| Many path components | 0.607709 ms |
| Long parameter name against 512 rules | 5.48 ms |

Retained resident growth after 10,000 synthetic coordinator events was 49,152 bytes.

`OPEN`: The installed app still needs the ten-minute idle CPU and Activity Monitor Energy Impact observation. The Release microbenchmarks validate the pure transform and coordinator-retention targets, not installed idle energy.

`RECOMMENDATION`: If measured polling misses the energy target, move to 500 ms and document evidence rather than weakening safety.

## Manual QA matrix

Use only synthetic, non-secret values in:

- Safari, Firefox, Chrome, X/Twitter, Mail, Messages, Notes, and Terminal.
- At least one already-installed clipboard manager; do not install one without approval.
- Address-bar copy, Copy Link Address, rich hyperlink, plain text, URL type, matching/mismatched dual representations, rich/custom/multiple values, and rapid repeated copies.
- Immediate paste, enabled/disabled, every pause, Skip Next, manual clean, valid/stale undo, conflict, relaunch, and safe sleep/wake.
- Permission `.default`, `.ask`, `.alwaysAllow`, and `.alwaysDeny`.
- Universal Clipboard and Clipboard History enabled/disabled without exposing existing values.
- Launch at Login status, Settings focus, App Intent through Shortcuts, no Dock icon, menu-extra removal, and installed ad-hoc behavior.

Do not automate logout, privacy-setting changes, or disruptive sleep without explicit user approval. Fast-user/session changes are performed only when safely testable.

## Release verification commands

The project and scheme are both `TrackerFree`. Use the following reproducible automated commands:

```sh
xcodebuild -project TrackerFree.xcodeproj -scheme TrackerFree -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:TrackerFreeTests
xcodebuild -project TrackerFree.xcodeproj -scheme TrackerFree -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:TrackerFreeUITests/TrackerFreeUITests/testSettingsSceneCanOpenForDocklessApp
xcodebuild -project TrackerFree.xcodeproj -scheme TrackerFree -configuration Release -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES test -only-testing:TrackerFreeTests/AcceptanceTests
xcodebuild -project TrackerFree.xcodeproj -scheme TrackerFree -configuration Release build
codesign --verify --deep --strict '/Applications/Tracker Free.app'
xcrun swift Scripts/DocsParity.swift --check
xcrun swift Scripts/DocsParityIntegrationTests.swift
```

`VERIFIED`: `ENABLE_TESTABILITY=YES` is passed only to the Release acceptance test invocation so the test bundle can load the application module. The generated shipping Release configuration remains `ENABLE_TESTABILITY=NO`.

The handoff records exact commands, statuses, macOS/Xcode versions, installed path, signature/entitlements, permission/login results, static/runtime network checks, performance, Git SHA/parity/worktrees, limitations, and non-actions.

`VERIFIED`: The installed Release passes strict signature verification, is byte-identical to the settled artifact, has Hardened Runtime plus the expected sandbox/file entitlements only, includes App Intent metadata, launches, and had no sockets in a bounded post-launch `lsof` snapshot.

`OPEN`: Longer runtime-network and energy observation, real permission states, login-item behavior, Shortcut execution, installed visual interaction, and cross-application manual QA remain unclaimed until directly observed.
