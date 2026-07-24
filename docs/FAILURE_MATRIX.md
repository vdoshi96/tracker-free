# Failure-Mode Matrix

`RECOMMENDATION`: Any row marked as a version-1 blocker must have preventive design, runtime handling, and a passing deterministic test before release.

| Failure mode | Severity | Preventive design and runtime mitigation | Required evidence | Blocks v1 |
|---|---|---|---|---|
| Clipboard erased or corrupted | Critical | Build replacement first; tiny verified commit; rollback only while owned | Inject clear/write/readback failures | Yes, except minimized disclosed process-death window |
| Rich text, image, or file replaced by text | Critical | Strict one-item/two-type allowlist | HTML, RTF/RTFD, image, file, custom fixtures | Yes |
| Lazy/promised representation fails or stalls | High | Materialize only allowed data; reject nil, ownership loss, oversize, or a return later than 100 ms | Nil, ownership-loss, and 110 ms late-return tests | Yes, subject to disclosed synchronous limit |
| Self-triggered loop | High | Exact-generation suppression, marker support, no-op avoidance | Own-write loop test | Yes |
| Competing cleaners oscillate | High | Idempotence and one write per generation; conflict pause | Fake competing transformer | Yes |
| Functional parameter removed | High | Unknown-preserve, exact/scoped rules, undo and user preserve | Major-site fixture matrix | Yes |
| Signed URL broken | Critical | Immutable signed-link guard | AWS, CloudFront, GCS, Azure fixtures | Yes |
| OAuth, login, reset, or invite broken | Critical | Immutable auth/token/path guard | OAuth, PKCE, reset, invite corpus | Yes |
| Prose, code, Markdown, or command changed | High | Exact-one-URL recognizer | Prose, code, HTML, terminal fixtures | Yes |
| Immediate paste receives original | Medium | Truthful polling model; manual clean/Intent | Rapid copy/paste timing QA | No if disclosed |
| Wrong generation cleaned | High | Recheck after reads and immediately before write | Generation change during transform | Yes |
| Stale undo overwrites newer copy | Critical | Generation, output, and marker-bound undo | Concurrent undo race | Yes |
| URL spelling changes | High | Raw whole-field deletion only; postconditions | `+`, `%HH`, order, duplicate, empty-field corpus | Yes |
| Rule collision | High | Deterministic precedence; atomic import rejection | Permutation/conflict tests | Yes |
| Lookalike domain matches | High | Exact/dot-boundary canonical host matching | `notx.com`, `x.com.evil`, Punycode fixtures | Yes |
| Oversized or malformed input consumes resources | High | 64 KiB input, 8 KiB path/fragment, 256 query-field, and 128 path/fragment-component caps | Fuzz, exact boundaries, and 8 MiB early-rejection tests | Yes |
| Polling wastes CPU or memory | Medium | Tolerant count-only fast path; 500 ms fallback | Idle energy and stress measurements | No if target met |
| Clipboard content enters diagnostics | Critical | Metadata-only logger and redacted assertions | Sentinel source/log/persistence scan | Yes |
| Compromised remote rules | Critical | No remote mechanism | Static and runtime no-network checks | Yes |
| Redirect resolution leaks URL | Critical | No resolver, URL session, DNS, or preview | Zero-network integration observation | Yes |
| Pasteboard access denied or prompt loops | High | Contextual onboarding and operational permission state | Four-state permission matrix | Yes unless truthful/safe |
| Launch at Login fails | Medium | Installed stable identity and actual service status | Register/unregister/status QA | No for core cleaning |
| Signing identity changes behavior | Medium | Stable ID/path and documented re-onboarding | Rebuild/reinstall comparison | No if documented |
| macOS update changes pasteboard behavior | Medium | Isolated adapter and fail-open handling | Supported-version smoke matrix | No |
| App killed during mutation or lifecycle change | High | Tiny no-await window and lifecycle wipe/baseline | Forced termination and lifecycle tests | Yes for avoidable corruption |
| Menu state disagrees with processing | Medium | Coordinator as single source of truth | State/UI assertions | Yes |
| Skip Next consumed by irrelevant event | Medium | Consume only at stable would-change decision | Non-URL/no-op/own-write sequences | Yes |
| Undo occurs after another write | Critical | Immediate generation/readback recheck | Newer-copy race | Yes |
| Universal Clipboard conflict | Medium-high | Remote-marker skip and `.currentHostOnly` writes | Synthetic cross-device QA | No if safe/disclosed |
| Clipboard-manager conflict | Medium-high | Generation checks, idempotence, conflict pause | Existing-manager QA | No if no corruption |
| Tests touch personal clipboard | Critical | Fake/named default; isolated opt-in guard | Static `.general` allowlist | Yes |
| macOS Clipboard History retains values | High privacy | Accurate disclosure; no app persistence | System-setting review without content exposure | No, platform limitation |
| Host-only rewrite changes cross-device expectations | Medium | Explicit local-only generation policy | Synthetic Universal Clipboard QA | No if disclosed |
| Malicious or huge custom-rule import | High | Typed non-executable schema, size/count/conflict caps | Adversarial import tests | Yes |

## Irreducible and empirical limits

`OPEN`: Public AppKit has no atomic compare-and-swap or process-death-safe pasteboard transaction. The final-check/write and post-clear process-death windows may ship only when minimized, tested around all avoidable failures, and disclosed.

`OPEN`: A synchronous lazy pasteboard provider has no public cancellation API. Measure and fail open after the call, but do not claim a timeout can prevent the provider from blocking unless local API evidence supports it.

`VERIFIED`: Conflict recovery is explicit-only. Tests prove that generation increments remain count-only while conflict-paused, that sleep/wake and session round-trips preserve the pause, and that explicit resume clears the short pair ring and baselines the current generation without reading it.
