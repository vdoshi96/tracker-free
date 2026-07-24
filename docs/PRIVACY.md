# Privacy and Security

## Core statement

Tracker Free does not persist clipboard contents in its own files, database, analytics, or logs.

`RECOMMENDATION`: Clipboard originals, outputs, undo state, and conflict pairs remain in bounded RAM only. They are released on invalidation and wiped on sleep/session loss, logout, termination, or process exit.

## Data handling

Tracker Free does not place clipboard values, originals, parameter values, or content-derived hashes in:

- `UserDefaults` or the custom-rule file.
- Logs, assertions, errors, signposts, crash annotations, or notifications.
- Menu tooltips, filenames, screenshots, test attachments, or generated QA reports.
- Analytics, telemetry, remote crash reporting, update checks, or a server.

`RECOMMENDATION`: `os.Logger` may record only bounded result enums, timings, counts, rule revision, parameter names approved for display, and generic error categories. Custom rules display a configured safe name, not an untrusted copied value.

## Network boundary

`RECOMMENDATION`: The app contains no `URLSession`, WebKit, Network-framework client, DNS lookup, redirect resolver, shortener expansion, link preview, or copied-link navigation.

`RECOMMENDATION`: App Sandbox and Hardened Runtime are enabled. Network client/server entitlements are absent. User-selected file access is included only when required for rule import/export.

`RECOMMENDATION`: Rules are bundled and locally edited typed data. They are never downloaded and never executable.

## Pasteboard access

`VERIFIED`: Current AppKit exposes `NSPasteboard.accessBehavior` and General-pasteboard programmatic access can require user approval. Pattern detection can avoid an access alert for supported detection but does not authorize matched-value reads.

`RECOMMENDATION`: On current macOS, automatic cleaning is operational only with `.alwaysAllow`. `.default`, `.ask`, and `.alwaysDeny` are permission-required or blocked states; they must not silently appear active or repeatedly trigger prompts.

`RECOMMENDATION`: First enablement explains why background cleaning needs access before any programmatic content read that may prompt. Manual user-initiated behavior is tested rather than assumed.

`OPEN`: The exact macOS 26.6 alert wording, Settings label/navigation, count/type-inspection behavior, and App Intent treatment require local observation. Do not hardcode an undocumented Settings deep link.

`VERIFIED`: The permission adapter and fake-pasteboard tests keep blocked states count-only, baseline a newly observed generation before a contextual prompt attempt, and never clean that prompting generation. The `.alwaysDeny` recovery UI opens System Settings without relying on an undocumented deep link; the real four-state matrix remains `OPEN`.

No Accessibility, Automation, Input Monitoring, Screen Recording, Full Disk Access, global key event, event tap, or synthetic paste is requested.

## Clipboard History

`VERIFIED`: Current macOS can retain text, images, links, and files in Spotlight Clipboard History when Clipboard Search is enabled.

Tracker Free has no documented API to erase selected system-history generations. macOS may retain both the original and cleaned value. The user controls the system Clipboard Search setting.

`RECOMMENDATION`: Never state that clipboard values are never persisted anywhere; the accurate claim is limited to Tracker Free's own storage, analytics, and logs.

## Universal Clipboard

`VERIFIED`: The General pasteboard automatically participates in Universal Clipboard, no public API identifies a generation's origin, and `.currentHostOnly` makes a newly written generation local to the current Mac.

The original may synchronize before Tracker Free rewrites it, and Tracker Free cannot retract it. Version 1 intentionally writes cleaned and restored generations with `.currentHostOnly`, so the rewritten value does not intentionally propagate to another device.

## Retention and recovery

- Undo stores one original/output pair in RAM only after a verified successful write.
- Any intervening external generation invalidates undo.
- Relaunch, crash, sleep, or session resignation loses undo.
- A two-second bounded RAM pair ring supports conflict detection; no persistent hash is substituted.
- Sleep or session loss wipes that ring but preserves an already-entered generic conflict-pause state until explicit resume.
- A crash can leave original or cleaned content.
- A crash during the irreducible clear/write interval can leave an empty generation.
- A synchronous lazy provider can block or allocate before returning; Tracker Free rejects a return later than 100 ms but cannot preempt the AppKit call.

`RECOMMENDATION`: Minimize the synchronous mutation window, verify readback, and roll back only while ownership is certain.

## Verification

Release evidence must include:

- A static source and entitlement scan.
- Runtime observation showing no app-originated network requests.
- A sentinel check proving clipboard content is absent from logs and persistence.
- Inspection of the sandbox, Hardened Runtime, file access, and absent network entitlements.
- Synthetic-only Clipboard History and Universal Clipboard checks without displaying existing history.

`OPEN`: These are release claims only after evidence is recorded in [Current status](STATUS.md).
