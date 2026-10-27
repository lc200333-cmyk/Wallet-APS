# Wallet APS Design: isolated experiment

This is the temporary PRIVATE repository `lc200333-cmyk/Wallet-APS-Design`,
created from main-project commit `f438ef2` (0.7.6+81), with Git history retained.

## Non-negotiable repository boundary

- Work only in this independent clone. Never edit, commit, push, publish, delete
  releases or change settings in `lc200333-cmyk/Wallet-APS` without a separate,
  explicit user request to that effect. Its local dirty working trees are out
  of scope. The `source` remote is for reading only; its push URL is blocked.
- Before any push, verify `origin` targets exactly
  `https://github.com/lc200333-cmyk/Wallet-APS-Design.git`. Never replace this
  with the source URL, use force push, or mirror-push an established repository.
- Keep this repository private. CI/CD, version bumps, tags, release assets and
  release cleanup must target ONLY Wallet-APS-Design and use its GITHUB_TOKEN.
  Never introduce a personal token with access to the main repository.
- The user authorized initial setup and a proof release in this copy. Later
  pushes/releases/settings changes still need task-specific authorization.
- Keep design changes in small, focused commits. Separate infrastructure,
  distribution identity and version commits from portable UI changes.
- To return selected work, start a fresh branch from the main project's CURRENT
  master, apply only user-selected UI changes and relevant tests, review the diff
  and use a pull request. Do NOT merge the entire experimental master or copy
  .github workflows, AGENTS.md, app identity, version/bump files or update-channel
  changes into the main project by default. Never rewrite its history.
- Test only disposable vaults. Until isolated installers/settings are verified,
  do not install this copy over Wallet APS or open personal vaults. Private
  release downloads use the user's browser session, never a token in the app.

The rules below remain applicable. Historical audit docs describe the original
project; they do not grant permission to modify it.

# Wallet APS: engineering instructions

Read [architecture](docs/architecture.md), [development](docs/development.md),
[testing](docs/testing.md), and [workflow](docs/ai-workflow.md) before changing code.
`plans/` contains historical proposals, not the implemented architecture.

## Before work

- Read the affected implementation, callers, tests and local instructions.
- Inspect `git status`, branch, base commit and existing changes. Preserve user
  changes, untracked files and sync conflict copies. Never reset or clean them.
- State scope, acceptance criteria, assumptions and a short verification plan.
- For infrastructure-only tasks, do not edit production sources, assets, native
  runners, dependency manifests or lockfiles. Record pre-existing modifications.
- Use a separate agreed worktree when the current tree is mixed. Do not borrow
  or overwrite an existing worktree without checking its ownership and status.

## Implementation and safety

- Keep changes small and backward compatible; test new behavior and regressions.
- Do not redesign architecture, remove unclear legacy code, perform broad
  refactors, change public interfaces unnecessarily or add unjustified dependencies.
- Preserve `.swl` compatibility, unknown metadata, IDs, attachments and password
  semantics. Use synthetic temporary wallets; never mutate personal vaults.
- Check both narrow Android and wide desktop behavior for UI changes.
- Never weaken tests, suppress failures or present unexecuted checks as passing.
- Never commit secrets, personal vaults, machine paths, SDK caches or build output.
- Record significant architecture decisions with rationale and alternatives in
  `docs/`; identify unverified assumptions explicitly.

## Delivery

- Run applicable checks in `docs/testing.md`; self-review the complete scoped diff.
- Report commands, exit status, skips, limitations and remaining risks.
- Human approval is required for merge, push, release/publication, repository
  settings, permissions, branch protection and secrets unless expressly authorized.
- Existing release automation publishes on eligible `master` pushes and deletes
  old releases. Read `docs/ai-workflow.md` before any release-related operation.
- Do not run version bump or branding generation merely to validate a change:
  those commands modify production/version files.
