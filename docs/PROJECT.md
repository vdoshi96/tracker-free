# Project

## Goal

Build a production-quality native macOS application named Tracker Free.

`RECOMMENDATION`: Tracker Free removes known tracking query parameters from qualifying copied links using conservative, user-auditable rules.

`RECOMMENDATION`: Unknown parameters remain unchanged. Any ambiguity, parser failure, unsupported pasteboard type, race, sensitive marker, or rule conflict leaves the original clipboard unchanged.

## Product boundary

Version 1 is a local-only `MenuBarExtra(.menu)` utility with an ordinary Settings scene, `LSUIElement`, App Sandbox, Hardened Runtime, no network entitlement, and no runtime third-party dependency.

Version 1 includes:

- Generation-based General-pasteboard monitoring.
- Manual cleaning and a `Clean Current Clipboard` App Intent.
- Requested enabled state distinct from operational state.
- Skip Next, timed/indefinite pause, and one memory-only undo token.
- Local structured rule preferences, validation, import, export, and reset.
- Launch at Login through `SMAppService.mainApp`.
- A macOS 13 deployment floor with Swift 6 strict concurrency.
- A locally ad-hoc-signed Release installation.

Version 1 excludes:

- Embedded, prose, Markdown, HTML, source-code, command, or multiple-URL rewriting.
- Redirect resolution, shortener expansion, DNS, link previews, or any web request.
- Recursive nested-URL cleaning.
- Rich-text cloning, clipboard history, or disk-backed undo.
- Arbitrary regular expressions, scripts, JavaScript, or remote rules.
- Global key monitoring, event taps, synthetic paste, Accessibility, Automation, or Input Monitoring.
- Analytics, telemetry, remote crash reporting, updater, or server.
- Literal Unicode URL transformation.
- Affiliate-identifier removal by default.
- Developer ID, notarization, Mac App Store, or paid-membership distribution work.

## Truthful language

Do not claim that Tracker Free:

- Identifies or removes every tracker.
- Makes a URL anonymous.
- Guarantees every paste receives the cleaned value.
- Cleans every URL from every application.
- Removes path tracking, cookies, fingerprinting, referrers, redirects, or server-side tracking.
- Prevents macOS from storing clipboard content.

## Definition of done

`VERIFIED`: The production implementation, deterministic engine, coordinator, rules, isolated pasteboard integration, Swift Testing/XCTest suites, XCUITest Settings/status inventory, bounded-input acceptance, and Release transform/stress checks are implemented and passing on the current build host.

`OPEN`: The release is complete only after the remaining installed-application, signing/entitlement, real permission, login-item, Shortcut, energy, runtime-network, cross-application, documentation-parity, and repository-hygiene gates in [Testing](TESTING.md) and [Current status](STATUS.md) are evidenced.

## Research baseline

`VERIFIED`: The implementation brief uses a research baseline of 2026-07-23 and records macOS 26.6 build 25G70, Xcode 26.6 build 17F113, the macOS 26.5 SDK, and Swift 6.3.3.

`VERIFIED`: The current build host is macOS 26.6 build 25G70 with Xcode 26.6 build 17F113.

`OPEN`: Compilation targets macOS 13, but runtime compatibility on macOS 13 through 15 must not be claimed without coverage.
