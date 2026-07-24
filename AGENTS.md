# Tracker Free Repository Instructions

## Repository hygiene

After every completed feature or iteration, push the working branch, merge it into GitHub `main`, update local `main` to the same commit, and remove completed worktrees.

Keep only active or explicitly unresolved worktrees, and record why each remains. After QA, retain only the newest completed run's evidence unless the user asks to preserve more. If no GitHub remote is configured, record that external push/merge blocker, finish applicable local-main/worktree hygiene, and never invent an external repository.

## Git commit identity

Use the GitHub-provided private noreply address `116222349+vdoshi96@users.noreply.github.com` for the author and committer email of every commit created locally in this repository. Set it in repository-local Git configuration before committing:

```sh
git config --local user.email 116222349+vdoshi96@users.noreply.github.com
```

Verify both `git var GIT_AUTHOR_IDENT` and `git var GIT_COMMITTER_IDENT` before each local commit. GitHub-created merge commits may use GitHub's service noreply metadata. Do not use a Gmail or other personal email address in commit metadata.

## Documentation stewardship

Before finishing, correct stale, inaccurate, or contradictory authoritative documentation with verified information, using its canonical generator when applicable. Preserve intentional history. If blocked or uncertain, record the stale content, proposed correction or open question, and blocker durably in scope, then report it.

## HTML documentation parity

Every project-owned Markdown or other documentation-text artifact must have a same-content HTML counterpart. Markdown is canonical in this repository. Edit Markdown only, then run:

```sh
xcrun swift Scripts/DocsParity.swift --generate
xcrun swift Scripts/DocsParity.swift --check
xcrun swift Scripts/DocsParityIntegrationTests.swift
```

Do not hand-edit generated HTML.

## Project memory map

- [Current status](docs/STATUS.md): current verified state, release gates, and blockers.
- [Project log](docs/LOG.md): dated, append-only implementation and QA history.
- [Project](docs/PROJECT.md): product scope, exclusions, and definition of done.
- [Architecture](docs/ARCHITECTURE.md): runtime design and safety invariants.
- [Rules](docs/RULES.md): rule model, precedence, guards, and import bounds.
- [Privacy](docs/PRIVACY.md): data lifecycle and platform limitations.
- [Testing](docs/TESTING.md): automated evidence, performance, and manual QA.
- [Failure matrix](docs/FAILURE_MATRIX.md): release-blocking risks and mitigations.
- [Decisions](docs/DECISIONS.md): stable implementation decisions.
- [Sources](docs/SOURCES.md): reviewed platform and rule provenance.
- [Skills and workflows](docs/SKILLS.md): maintenance commands and evidence workflow.
- [Wiki index](docs/wiki.md): complete documentation navigation.

Treat `docs/STATUS.md` as current authority and `docs/LOG.md` as intentional history.
