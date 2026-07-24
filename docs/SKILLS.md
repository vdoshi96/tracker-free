# Skills and Workflows

## Documentation workflow

`RECOMMENDATION`: Edit canonical Markdown, then regenerate and check every HTML companion.

```sh
swift Scripts/DocsParity.swift --generate
swift Scripts/DocsParity.swift --check
xcrun swift Scripts/DocsParityIntegrationTests.swift
```

`VERIFIED`: The integration test runs only in temporary Git repositories. It covers deterministic output, missing/stale detection, local-link rewrites, stable duplicate heading IDs, unmanaged collisions, marker-owned orphan cleanup, unsupported RST rejection, and source/output symlink rejection.

## Implementation workflow

`RECOMMENDATION`: Implement in dependency order:

1. Strict URL recognizer and raw query tokenizer.
2. Whole-link protection classifier.
3. Typed rule model, compiler, persistence, import/export, and initial rules.
4. Pure byte-preserving cleaner.
5. Fake and named pasteboard clients.
6. Serialized coordinator, write verification/rollback, pause, skip, undo, conflicts, and lifecycle.
7. Permission UX, menu, Settings, App Intent, and login item.
8. Automated tests, installed Release QA, privacy/network observation, performance, and documentation closeout.

## Evidence workflow

`RECOMMENDATION`: Use synthetic URLs and isolated pasteboards. Ordinary tests must not read `NSPasteboard.general`. Never capture personal clipboard values in logs, screenshots, attachments, reports, filenames, assertions, or signposts.

`RECOMMENDATION`: Keep only the newest completed QA evidence run unless preservation is explicitly requested.

`RECOMMENDATION`: Before closeout, update [Current status](STATUS.md), [Testing](TESTING.md), and [Project log](LOG.md) from exact observed commands and outcomes; then regenerate HTML.

## Repository workflow

`RECOMMENDATION`: Inspect the active repository authority and preserve unrelated modified, untracked, ignored, generated, or private work. Where a GitHub remote exists, complete the required branch push, main merge, local-main update, and completed-worktree cleanup. Never invent an external repository when none is configured.

The durable in-repository instruction and authority map is [AGENTS.md](../AGENTS.md). Treat [Current status](STATUS.md) as current truth and append completed evidence to [Project log](LOG.md) without rewriting intentional history.
