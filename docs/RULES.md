# Rules

## Model

Bundled and imported rules use a versioned typed model with:

- `schemaVersion`, `ruleSetRevision`, `reviewedDate`, unique `id`, and `enabled`.
- User-rule documents may include `reviewedBuiltInRuleSetRevision`, the exact built-in revision against which preserve/removal overlaps were acknowledged.
- `origin`: `builtIn` or `user`.
- `action`: `removeParameter`, `preserveParameter`, or `hardProtectURL`.
- `matcher`: `exactASCIIName` or `asciiPrefix`.
- ASCII `name` and explicit case sensitivity.
- `scope`: `global`, `host`, or `hostPath`.
- Exact canonical hosts, `includeSubdomains` defaulting false, and an optional safe path constraint.
- `confidence`: `verified`, `inferred`, or `experimental`.
- Bounded explanation and provenance URL.

Safe path constraints are absent, a literal prefix with segment-boundary semantics, or a small typed predicate such as `xStatusPermalink`, `youtubeShareContent`, or `instagramContent`.

`RECOMMENDATION`: User data cannot contain regex, JavaScript, scripts, wildcard hosts, arbitrary executable predicates, or remote-update instructions.

## Precedence

1. Parse/type/size/generation failure and immutable whole-URL guards preserve the whole URL.
2. Matching user preserve rule.
3. Matching user remove rule.
4. Most-specific matching built-in scope: host+path, host, then global.
5. At equal built-in specificity, preserve wins.
6. At equal action/scope, exact name wins over prefix.
7. An unresolved collision preserves and reports a generic rule conflict.
8. Unknown parameters preserve.

`RECOMMENDATION`: A user remove can override an ordinary built-in preserve only after a clear warning. It can never override a hard guard. Contradictory imports are rejected atomically; runtime uncertainty still preserves.

`VERIFIED`: A confirmed preserve/removal overlap is persisted with the current built-in revision and remains enabled across relaunch while that revision is unchanged. When the bundled revision changes, only enabled user removals that may overlap built-in preserves are disabled for individual re-review; unrelated user rules retain their state.

## Initial global removals

All are enabled, exact, lowercase, and case-sensitive.

Google Analytics campaign fields:

- `utm_id`
- `utm_source`
- `utm_medium`
- `utm_campaign`
- `utm_source_platform`
- `utm_term`
- `utm_content`
- `utm_creative_format`
- `utm_marketing_tactic`

Google advertising identifiers:

- `gclid`
- `dclid`
- `gbraid`
- `wbraid`
- `gad_source`
- `gad_campaignid`

Other attribution identifiers:

- `msclkid`
- `ttclid`
- `mc_cid`
- `mc_eid`
- `fbclid`

`RECOMMENDATION`: Support `utm_` prefix rules in the model but leave the broad prefix disabled by default.

## Built-in functional preserves

Ordinary built-in preserve rules include:

`q`, `query`, `v`, `id`, `s`, `t`, `code`, `token`, `state`, `page`, `sort`, `filter`, `variant`, `sku`, `list`, `index`, `start`, `end`, `time_continue`, `origin`, `destination`, `waypoints`, `tag`, `linkCode`, `th`, and `psc`.

Unknown-preserve remains the final safety net. A verified host/path-specific removal can outrank a less-specific built-in preserve.

## Scoped rules

### X and Twitter

`INFERENCE`: Remove `s` and `t` only on exact `x.com`, `www.x.com`, `twitter.com`, `www.twitter.com`, and `mobile.twitter.com` hosts, and only on anchored `/{valid-handle}/status/{digits}` or `/i/web/status/{digits}` forms with permitted status suffixes.

Hard-exclude redirect, authentication, account, settings, reset, and email paths. Never remove `t` globally.

### YouTube

`INFERENCE`: Remove `si` only on exact `youtu.be` video paths and exact YouTube hosts with valid `/watch?v=...` or `/shorts/{id}` content routes.

Preserve `v`, `list`, `index`, `t`, `start`, `end`, `playlist`, `listType`, `pp`, `feature`, captions, and player-control fields.

### Instagram

`INFERENCE`: Remove `igsh` and `igshid` only from exact Instagram canonical `/p/`, `/reel/`, and `/tv/` content routes. Do not clean login, redirect, challenge, or account paths.

### TikTok, Reddit, Amazon, and email

- TikTok: global `ttclid` remains; preserve `_r`, `_t`, `is_from_webapp`, `sender_device`, and opaque short links.
- Reddit: preserve `context`, `depth`, `sort`, `t`, `before`, `after`, `count`, `share_id`, `ref_campaign`, and `ref_source`.
- Amazon: no Amazon-specific removal; preserve `tag`, `linkCode`, `th`, `psc`, `qid`, `sr`, `smid`, functional product/search fields, and `/ref=` path components.
- Email: remove only `mc_cid` and `mc_eid` from ordinary content links; preserve unverified identifiers such as `mkt_tok`, `_hsenc`, `_hsmi`, and `elqTrackId`.

`RECOMMENDATION`: Affiliate attribution is not treated as inert tracking and remains unless a future explicit opt-in category is reviewed.

## Immutable whole-link guards

Protect the entire URL case-insensitively when applicable:

- Any `x-amz-` or `x-goog-` query name.
- `sig`, `signature`, AWS legacy, CloudFront, Google Cloud, Azure SAS, or recognizable signature/HMAC tuples.
- OAuth/OIDC authorization tuples, PKCE markers, `code` with `state`, access/id/refresh tokens, SAML/RelayState, or token-response fragments.
- Sensitive names including `token`, `reset_token`, `verify_token`, `invite`, `invitation`, `ticket`, `hmac`, `jwt`, `auth`, `session`, `api_key`, `key`, `signature`, and `sig`.
- A nonempty query or token-like fragment on oauth/authorize/callback/login/signin/magic/reset/password/verify/verification/invite/invitation/accept/activate/unsubscribe path components.
- `.ics` and recognized invitation/acceptance links.
- Known Facebook/Google redirect wrappers.
- Opaque shorteners including `t.co`, `bit.ly`, `tinyurl.com`, `ow.ly`, `buff.ly`, `amzn.to`, `vm.tiktok.com`, and `vt.tiktok.com`.
- IP, loopback, private/local, `.local`, and single-label hosts.

`RECOMMENDATION`: False protection is preferable to invalidating a signed, authentication, invitation, or functional URL.

## Import, export, and reset

- Import/export contains rules only, never URLs, clipboard samples, history, or result status.
- Maximum import size is 256 KiB, maximum user-rule count is 512, and maximum combined rule count is 2,048.
- Rule IDs and parameter names are at most 128 UTF-8 bytes; explanations are at most 1,024 bytes; provenance URLs are at most 2,048 bytes.
- A scope contains at most 64 exact hosts, and a literal path constraint is at most 512 bytes including its leading slash.
- Reviewed dates must be valid Gregorian `YYYY-MM-DD` dates, not merely date-shaped strings.
- Validate schema, unique IDs, ASCII names, hosts, safe paths, field bounds, dates, and conflicts in a temporary value.
- Show a conflict/summary preview and replace live rules only after explicit confirmation.
- Persist atomically in the sandbox container.
- Export through a user-selected save panel.
- Reset built-in enablement and user rules as distinct actions.
- Hard guards cannot be disabled.

`VERIFIED`: Boundary tests cover the byte, count, field, host, path, and Gregorian-date limits. Imported user `hardProtectURL` rules are additive: they may protect more URLs but cannot relax or replace immutable or built-in guards.

`VERIFIED`: Enabling an imported user removal that overlaps an enabled built-in preserve requires explicit acknowledgement. A built-in bootstrap or persisted-rule validation failure fails closed for automatic, menu-manual, and App Intent cleaning.

`VERIFIED`: If persisted user rules become incompatible with a newer built-in bundle, including an ID collision, the entire incompatible user set is excluded from the live snapshot, built-ins remain active, and Settings displays a load-validation warning. The stored file is not silently rewritten.

`RECOMMENDATION`: `TrackerFree/Resources/BuiltInRules.json` is the reviewed built-in authority. Its `ruleSetRevision` must increase whenever reviewed built-in rule content changes, including action, matcher, name, scope, host/path constraints, enablement, confidence, explanation, or provenance. This revision bump is the invalidation signal that forces affected user-removal overrides through re-review.
