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

## 2026-07-24 — commit-email privacy rewrite

`VERIFIED`: With explicit user authorization, rewrote the author and committer metadata of the three locally created commits that used a personal Gmail address. The replacement commits use GitHub's private noreply address while preserving the original file trees, timestamps, messages, and commit topology.

`VERIFIED`: A force-push alone could not remove the prior repository's read-only pull-request reference. The prior public repository and its single pull request were therefore deleted, then [vdoshi96/tracker-free](https://github.com/vdoshi96/tracker-free) was recreated at the same public URL and populated only with the sanitized history.

`VERIFIED`: The pre-rewrite public tip and its rewritten counterpart have the same Git tree identity. Git object integrity and 14-source documentation parity pass, every commit reachable from public `main` uses private or GitHub service noreply metadata, and repository-local Git configuration plus project rules prevent future local commits from using a personal email address.

`CONSEQUENCE`: Every rewritten commit and descendant has a new commit ID. The removed repository's pull request and its discussion are intentionally unavailable.

## 2026-09-22 — public README, screenshots, and draft release

`VERIFIED`: Rewrote the root README for public readers and removed evidence tags from that file only. Internal documents keep their `VERIFIED`, `RECOMMENDATION`, and `OPEN` labels. Items that `STATUS.md` marks `OPEN` are described in the README as unverified.

`VERIFIED`: Added light-mode @2x screenshots under `docs/screenshots/`. The Rules and Privacy images are XCUITest window screenshots of the Release build, launched with `--ui-testing-open-settings` so it used a fake pasteboard. The menu image is the app's menu items and default post-clean state rendered by AppKit `NSMenu` in a separate harness process. Screen Recording was unavailable to the build host, and synthesized clicks did not open the status item. The throwaway capture test and harness were not committed.

`VERIFIED`: Built Release with Xcode 27.0 (27A5228h) on macOS 27.2 (26B5091g). The output is arm64 only; an `ARCHS="arm64 x86_64"` request still produced arm64. It is ad-hoc signed with Hardened Runtime, has only the App Sandbox and user-selected read/write entitlements, and passes strict `codesign` verification both before zipping and after extraction. `ditto -c -k --keepParent` produced `TrackerFree-1.0.0-macOS.zip` (363,955 bytes; SHA-256 `109b218b81c191bcf2c86e6724cdb974357f10d89b194dadcd51ab0919f3085a`). That zip is attached to an unpublished draft GitHub release `v1.0.0` targeting `main`.

`OPEN`: The draft release is not notarized. Publishing it, and every installed-build item in [Current status](STATUS.md), remains a separate decision.

## 2026-09-23 — display-only rule explanation formatting

`VERIFIED`: The Settings rule list no longer shows leading evidence tags (`VERIFIED:`, `RECOMMENDATION:`, `INFERENCE:`, `OPEN:`, `CONSEQUENCE:`) in each rule's subtitle, and it capitalizes the confidence and the first letter of the explanation. Only exact, known tags are removed. The bundled JSON, persisted user rules, and the export format are unchanged. New `RuleDisplayFormattingTests` cover tag removal, untagged and edge-case text, an unchanged stored explanation, and the absence of tags from every bundled rule's subtitle.

`VERIFIED`: The Debug `-only-testing:TrackerFreeTests` run ran 83 top-level tests (79 XCTest and 4 Swift Testing): 82 passed, 1 Release-only performance case was skipped, and none failed.

`VERIFIED`: The refreshed `docs/screenshots/rules.png` and the new `general.png` are XCUITest window captures of the Release build, taken in the isolated `--ui-testing-open-settings` mode with a fake pasteboard and in-memory state. The General capture turned on automatic cleaning in that isolated state only. Its Launch at Login row reports the build host's live `SMAppService` status and does not close the Launch at Login gate in [Current status](STATUS.md).

`OPEN`: The build host locked during capture. A Rules view scrolled to the host-scoped rules could not be captured, and the existing `testSettingsSceneCanOpenForDocklessApp` could not be rerun afterwards, so it has no fresh result from this session.

## 2026-11-04 — X Copy link from Firefox left uncleaned

`VERIFIED`: Symptom: a link copied with X's web "Copy link" in Firefox stayed on the clipboard unchanged. The live clipboard item advertised `public.html` and `public.utf8-plain-text`. The HTML was Firefox's document wrapper around a single span holding the same URL, which a page's copy command produces. The snapshot reader allowed only plain text and URL types, so it rejected the item as `unsupportedType` before cleaning. Debug-level diagnostics are not persisted, so the unified log held no record of the skip.

`VERIFIED`: A second gap was present behind the first: the URL also carried an X `a=` value beside `s=20`, and only `s` and `t` had X rules, so the item would have been cleaned only partly even if it had been admitted.

`VERIFIED`: Fix: `public.html` is admitted only as a plain-text companion whose markup is limited to `html`, `head`, `meta`, `body`, and `span` elements, comments, and a doctype, and whose decoded, edge-trimmed text equals the plain-text URL core. It is kept in the snapshot for byte-exact rollback and Restore Original. Cleaned writes never carry HTML. Added `builtin.remove.x.status.a`, scoped like the `s` and `t` rules, and bumped the rule-set revision to `2026110301`.

`VERIFIED`: New tests failed before the fix (`unsupportedType` for the redundant HTML item, `?a=xa3_synthetic` retained, and an HTML-bearing transform committed) and pass after it. The Debug `-only-testing:TrackerFreeTests` run reported 87 top-level tests (83 XCTest and 4 Swift Testing): 86 passed, 1 Release-only performance case skipped, 0 failed. Release acceptance passed 4 of 4. The static safety scans found no violations; the script's `rg` scans were rerun with `grep` because `rg` was not installed (see [Current status](STATUS.md)).

`VERIFIED`: Installed the new Release at `/Applications/Tracker Free.app` (executable SHA-256 `874236fcaafefc46170468617832df2bbcd32349112ca06800d0bf5b6e54259c`, ad-hoc, Hardened Runtime, strict verification passed) after copying the prior build to a temporary backup. A General-pasteboard item reproducing the Firefox inventory was cleaned automatically to plain text plus the Tracker Free marker within one polling interval.

`OPEN`: Safari page-initiated copies also add web archive and RTF types and therefore remain hard skips. Chrome's live inventory for X Copy link was not observed in this session; its documented `<meta charset>` plus span shape is covered by an isolated test.

## 2026-11-04 — Chrome and Safari Copy link companions; static safety scan

`VERIFIED`: The earlier fix admitted only HTML, so the same X Copy link from Chrome or Safari would still be skipped. Copying a synthetic URL from a page that mirrors X's span copy showed why. Chrome 156, driven through DevTools with a trusted click and a temporary profile, added `org.chromium.source-url` and a 24-byte `org.chromium.internal.source-rfh-token` beside its HTML. The system WebKit that Safari 27.3 uses, run in a WebKit view, added a web archive, RTF, UTF-16 text, and WebKit custom data. Decoding each one showed it was redundant: every rich form renders only the URL, the alternate text matches it, and the custom data holds an origin with empty data and type lists.

`VERIFIED`: Generalized `PasteboardContent.html` to `companions` (type identifier to original bytes) under `PasteboardCompanionPolicy`. Each type has its own check, documented in [Architecture](ARCHITECTURE.md). Companions are read with the same generation, duration, and 64 KiB combined bounds as primary text. They are kept for byte-exact rollback and Restore Original and are never carried on a cleaned write.

`VERIFIED`: `Scripts/VerifyStaticSafety.sh` now scans with the base-system `grep` and fails closed when `grep` reports an error. The new `Scripts/VerifyStaticSafetyTests.sh` failed against the old script on a PATH without `rg`: three planted violations passed. It passes against the new script, which also rejects an unreadable source subdirectory.

`VERIFIED`: The new tests failed before the change (Chrome and WebKit inventories skipped) and pass after it. The Debug `-only-testing:TrackerFreeTests` run reported 88 top-level tests (84 XCTest and 4 Swift Testing): 87 passed, 1 Release-only performance case skipped, 0 failed. Release acceptance passed 4 of 4, and static safety and its tests pass.

`VERIFIED`: Installed the Release (executable SHA-256 `0ca3dd668eebc86e772732a7b316402049cda17ce3cc15c54808e3334da9ef62`, ad-hoc, Hardened Runtime, strict verification passed). With it running, a live Chrome copy and a live WebKit copy were each cleaned automatically to plain text plus the Tracker Free marker. Tracker Free was stopped while the raw inventories were captured. The user's prior clipboard link was saved first and restored afterwards.

`OPEN`: The Safari app itself was not driven, because doing so would have needed Safari automation settings changed. The evidence comes from the same system WebKit inside a WebKit view.

