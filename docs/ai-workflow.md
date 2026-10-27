# AI development and release workflow

## Design repository override (2026-10-27)

This private standalone clone preserves upstream history through `f438ef2`.
The owner authorized independent CI/CD and separate installation identities.
The historical preparation notes below do not describe this later setup.
All workflow jobs are restricted to `lc200333-cmyk/Wallet-APS-Design`; release
and retention use the current repository and its built-in `GITHUB_TOKEN`.
There is no cross-repository publication token. Existing version increments,
three-platform builds and retention of two releases remain enabled here only.

Windows uses a new installer GUID, Design install directory and Open With
ProgID without replacing the stable `.swl` default. Android uses a distinct
application ID; Linux uses a distinct application/package ID and install paths.
Settings, icons, default vault and recovery folders are separated. No stable
profile or personal vault is migrated. Explicitly opening a shared vault can
still modify that file: use disposable copies for experiments.

Private release downloads require authentication. Instead of embedding a
credential or silently falling back to public upstream releases, Design opens
its Releases page in the user's authenticated browser. This deliberately trades
automatic in-app downloads for credential safety and repository isolation.
Generic updater characterization remains testable through injected loaders.

Keep design commits separate from this repository/identity setup. Later transfer
only selected UI and regression-test changes into a fresh upstream branch,
excluding workflows, versions, identities and experimental instructions. Review
the complete resulting diff before any separately authorized upstream PR/push.
See the README for the owner's project-switching and download instructions.

The first proof release compiled its APK but failed copying it with only 21 MB
free on the hosted runner. The Docker Android job now removes only the runner's
unused native SDK at the exact resolved path `/usr/local/lib/android/sdk` before
building. Its container has an independent SDK at `/opt/android-sdk`. The native
CI APK job retains its host SDK. Application dependencies and verification stay
unchanged; a paid larger runner is not required for this fix.

## Task to pull request

1. Define acceptance criteria and permitted scope in an issue. Read AGENTS.md,
   affected source and tests; record baseline failures and uncertain assumptions.
2. Start from an agreed base in a clean branch/worktree. Names:
   `feat/<topic>`, `fix/<topic>`, `test/<topic>`, `docs/<topic>`, `chore/<topic>`.
   Preserve the user's dirty tree. Fetch/push only within granted authorization.
3. Implement the smallest change. Add regression tests that fail for the defect,
   or characterization tests before touching legacy behavior. Use synthetic data.
4. Run [checks](testing.md), inspect the scoped diff and perform self-review.
5. With authorization to publish the branch, open a PR using the template.
   Record commands/results, baseline failures, skipped tests and UI evidence.
6. CI validates the PR. A human reviews and approves merge. Agents do not merge
   their own work or change repository protection/secrets/permissions.

Definition of Done: acceptance criteria demonstrated; compatibility retained;
meaningful tests; required checks executed successfully (or explicitly blocked
and not merge-ready); no unrelated changes/secrets; self-review complete;
architecture docs updated when needed; human review requested.

Review focus: vault corruption/data loss, rollback and backup, secret exposure,
legacy round trips, narrow/wide UI, native differences, dependencies and CI
privileges. Never weaken assertions or suppress analyzer failures for green CI.

## Existing CD and safe future release

The existing `release.yml` automatically verifies, bumps versions, commits/tags,
builds Windows setup/Android APK/Linux deb, publishes GitHub Releases and deletes
all but two releases/tags. `release_cleanup.yml` can also delete releases manually.
`windows_setup.yml` builds an installer on selected master pushes/manual runs.
These workflows were not modified or dispatched by this preparation task.

Local release.yml still references removed Rust core; cached origin/master has
newer release logic. Reconcile the intended base before release. Do not cherry-pick
an old release workflow over the newer one. New CI is separate and does not gate
the old release workflow automatically.

Versions currently span package.json/package-lock.json, pubspec version/build
number, app_version.dart, Inno Setup and the deb script. `tools/bump_version.js`
changes these files. A `[release X.Y.Z]` message can select a release version;
`[skip release]` affects the existing version job, not all workflows.

Before an authorized release: select the exact reviewed commit; require all CI
checks and device smoke tests; inspect version changes; build and review artifacts;
verify signing and checksums; obtain human publication approval. Retain previous
installers and a vault backup for recovery. Binary rollback must not assume a
future storage migration is reversible.

Proposed next CD change (not enabled): manual workflow on an immutable commit/tag,
separate build and publish jobs, a draft release and protected `release` environment
with required reviewers for publication. Build jobs use read-only permissions;
only publication gets contents:write. Set up environment reviewers, signing keys
and repository rules only after separate approval. A manual dispatch alone is
not a reviewer gate. Remove destructive release retention only in an approved
release-policy change.

Keep signing passwords/keystores/tokens in approved GitHub environment secrets,
never YAML or fixtures. Use the scoped GitHub token where sufficient; expose no
secrets to PR code. Android debug signing must be replaced through an approved
key-management and installed-app upgrade plan before production distribution.
