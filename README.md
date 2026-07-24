# Tracker Free

Tracker Free is a native macOS menu-bar utility that removes known tracking query parameters from qualifying copied links using conservative, user-auditable rules.

`RECOMMENDATION`: Treat every ambiguity as a reason to leave the clipboard unchanged. Tracker Free does not claim to identify every tracker, anonymize a URL, clean every paste, or remove path, cookie, fingerprinting, referrer, redirect, or server-side tracking.

## Version 1 scope

- Automatic monitoring of new General-pasteboard generations.
- Manual cleaning through the menu and a `Clean Current Clipboard` App Intent.
- Enabled, timed pause, indefinite pause, Skip Next, and memory-only Restore Original controls.
- Structured built-in and user removal/preservation rules with local import and export.
- Launch at Login through `SMAppService.mainApp`.
- App Sandbox, Hardened Runtime, and no network client or server entitlement.
- Swift 6, a macOS 13 deployment target, and local ad-hoc signing.

`RECOMMENDATION`: Version 1 handles exactly one unambiguous plain-text and/or URL pasteboard item. It skips rich, custom, multiple-item, remote, sensitive, malformed, literal-Unicode, local-network, redirect-wrapper, and shortener values.

## Privacy summary

Tracker Free does not persist clipboard contents in its own files, database, analytics, or logs.

`VERIFIED`: The General pasteboard participates in Universal Clipboard, and current macOS can retain clipboard generations in system Clipboard History. Tracker Free cannot retract an original value that already synchronized or erase selected system-history entries. Cleaned and restored generations use `.currentHostOnly`.

See [Privacy](docs/PRIVACY.md) for the complete data-lifecycle and platform limitations.

## Project documentation

- [Repository instructions](AGENTS.md)
- [Project](docs/PROJECT.md)
- [Current status](docs/STATUS.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Rules](docs/RULES.md)
- [Decisions](docs/DECISIONS.md)
- [Privacy](docs/PRIVACY.md)
- [Testing](docs/TESTING.md)
- [Failure matrix](docs/FAILURE_MATRIX.md)
- [Sources](docs/SOURCES.md)
- [Skills and workflows](docs/SKILLS.md)
- [Project log](docs/LOG.md)
- [Wiki index](docs/wiki.md)

## Documentation parity

Markdown is canonical. Never edit generated HTML directly.

```sh
swift Scripts/DocsParity.swift --generate
swift Scripts/DocsParity.swift --check
xcrun swift Scripts/DocsParityIntegrationTests.swift
```

`VERIFIED`: The generator discovers only Git-visible tracked or non-ignored files through NUL-delimited Git output. It refuses symlink sources/outputs, unmanaged same-basename HTML, unsupported structured formats, and malformed ownership markers. Writes are atomic per companion, and only marker-owned orphans are removed.

## Development status

See [Current status](docs/STATUS.md). The implementation and isolated automated suites are complete and passing on the recorded build host. Installed-Release, real General-pasteboard permission, login-item, Shortcut, energy, and cross-application workflow claims remain `OPEN` until observed from the final installed application.
