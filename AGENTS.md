# Wallet APS: agent instructions

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
