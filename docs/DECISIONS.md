# Decisions

## Decision labels

- `VERIFIED`: Supported directly by a reviewed source or local test.
- `INFERENCE`: Drawn from reviewed behavior or API surfaces.
- `RECOMMENDATION`: Chosen implementation policy.
- `OPEN`: Requires local verification or future work.

## Platform and lifecycle

`VERIFIED`: `MenuBarExtra` and `SMAppService` support the macOS 13 deployment floor.

`RECOMMENDATION`: Use SwiftUI lifecycle, `MenuBarExtra(.menu)`, an ordinary Settings scene, and `LSUIElement`. Retain `NSStatusItem` only as a fallback if local QA proves required menu behavior impossible.

`RECOMMENDATION`: Put every mutable pasteboard, permission, generation, pause, skip, undo, conflict, lifecycle, and menu-status transition in one `@MainActor` coordinator.

`RECOMMENDATION`: Use a synchronous immutable `Sendable` cleaning engine. Never pass `NSPasteboard` or `NSPasteboardItem` across actors/tasks and never add `@unchecked Sendable`.

## Pasteboard monitoring

`VERIFIED`: `changeCount` is the public generation/ownership token, and one-item eligibility cannot be established with `string(forType:)`.

`INFERENCE`: AppKit has no dependable public General-pasteboard change notification, so serialized polling is the dependable public design.

`RECOMMENDATION`: Poll at 250 ms with tolerance only while operational, and count-only at one second while disabled, paused, permission-blocked, sleeping, session-inactive, or conflict-paused.

`RECOMMENDATION`: Baseline at startup, re-enable, resume, expiry, wake, and session activation. Never retroactively inspect or clean an older generation.

## Safe writes

`VERIFIED`: There is no public transactional compare-and-swap pasteboard API.

`RECOMMENDATION`: Build a complete bounded replacement first, make a final generation check, then perform a tiny synchronous `.currentHostOnly` clear/write/readback sequence with a private marker.

`RECOMMENDATION`: Roll back only when the current generation proves the app still owns the failed clear/write. Never overwrite a newer owner.

`OPEN`: A micro-race remains between final check and ownership mutation, and process death after clear can leave an empty generation. Minimize and disclose both windows.

## URL handling

`VERIFIED`: `URLComponents` reconstruction can normalize percent spellings and literal Unicode.

`RECOMMENDATION`: Use Foundation only for strict validation and inspection. Emit output only by deleting approved raw query fields from the original ASCII URL.

`RECOMMENDATION`: Never recursively clean nested values, resolve redirects, alter fragments, or transform literal Unicode URLs in version 1.

## Rule policy

`RECOMMENDATION`: Unknown parameters remain preserved. Exact documented names are safer than broad prefixes.

`RECOMMENDATION`: User preserve rules outrank user remove rules. User remove rules outrank ordinary built-ins only after a warning. Immutable URL guards outrank everything.

`RECOMMENDATION`: Rules are bundled or user-authored local typed data. No regex, script, wildcard host, remote fetch, or executable predicate is accepted.

## Privacy and distribution

`RECOMMENDATION`: No analytics, updater, remote rules, resolver, URL session, WebKit, network client/server entitlement, or copied-link navigation.

`RECOMMENDATION`: Same-Mac use is a sandboxed Hardened Runtime Release build signed ad hoc to run locally. Do not claim Developer ID signing or notarization.

`RECOMMENDATION`: Cleaned and restored generations are `.currentHostOnly`, because the original generation's Universal Clipboard origin cannot be determined.

## Documentation

`RECOMMENDATION`: Markdown is canonical. Generated same-directory HTML contains an ownership marker and source SHA and must never be edited by hand.

`VERIFIED`: `Scripts/DocsParity.swift` uses Git-visible NUL-delimited discovery, stable heading IDs, local Markdown-link rewriting, per-file atomic writes, collision/symlink protection, marker-owned orphan cleanup, and fail-closed unsupported-format handling.
