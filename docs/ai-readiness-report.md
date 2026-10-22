# AI-first readiness audit — 2026-10-14

## 1. Current State

Audit baseline: `09ff78e9cfa93d299a82180fcf3d8a1f57a86044` (`v0.7.1`,
Flutter `0.7.1+76`). Inspected the tracked repository inventory, runtime modules,
native bridges, manifests/locks, tests, build/release scripts, documentation and
Git history. This is an engineering readiness audit, not an exhaustive security
review or proof that every execution path is correct.

The primary working folder remains on older `0465b68` with extensive pre-existing
changes and sync-conflict copies. Validation used a separate detached worktree
at the baseline plus only this task's new files. The existing
`chore/ai-first-infra` branch/worktree was discovered and left alone. No fetch,
push, merge, release or remote settings changes were performed in this task.

Architecture: Flutter/Dart UI and storage orchestration, native SQLite FFI,
SPB-compatible encrypted fields/attachments, Kotlin Android and C++ desktop
bridges. No active Rust workspace or sync engine at this baseline. Historical
plans describe a different proposed design. Details: [architecture](architecture.md).

Git history shows frequent UI/release changes and earlier data-loss fixes.
`main.dart` is the largest hotspot (about 21k lines; 81 commits touching its path
in the locally available history), followed by the database implementation.
Existing master workflows build and publish automatically, but none previously
provided a general pull-request verification gate.

The primary folder's older release workflow still runs removed Rust-core checks
and differs from the validated v0.7.1 workflow. New files must be reviewed on the
current agreed base; do not publish the mixed primary tree wholesale.

## 2. Changes Made

Added only these 13 infrastructure/documentation/test files:

- `AGENTS.md`, `CLAUDE.md`.
- `docs/architecture.md`, `docs/development.md`, `docs/testing.md`,
  `docs/ai-workflow.md`, this report.
- `.github/workflows/ci.yml`, `.github/pull_request_template.md`,
  `.github/ISSUE_TEMPLATE/task.md`.
- `app/test/ai_characterization_test.dart`.
- `tools/check_changed_format.dart`, `tools/check_dependencies.dart`.

Production sources, assets, native manifests, dependency versions/locks,
packaging/version scripts and existing tests/workflows were not edited.
The clean validation worktree has no tracked content diff against its baseline;
Flutter regenerated registrant line endings, but Git-normalized content matches.
All deliverable changes are the new allowlisted files. No commit was created.

During final hash comparison, five documentation files had been concurrently
edited outside this run: AGENTS.md, CLAUDE.md, architecture.md, development.md and
ai-workflow.md. Their current contents were reviewed and preserved; they describe
the mixed working tree explicitly. The verified tests/scripts/workflow were not
affected. Do not overwrite those documents with an earlier temporary copy.

## 3. Test Coverage

Fresh Windows execution: **193 passing tests, 16 skipped**, including **11 new
tests**. New tests characterize cycle/orphan category paths, duplicate IDs,
field visibility/order, deterministic layout and fallback, legacy conversions,
binary attachment boundaries/corruption, rekey success/rollback and legacy repair
with value preservation and idempotence. They use synthetic temporary SQLite
databases and do not require personal wallet fixtures.

LCOV reports **7,214 / 10,977 executable Dart lines (65.72%)** across reported
runtime files. This is line coverage, not branch/native coverage or a security
score. Selected measured results:

| Module | Covered lines |
| --- | --- |
| main.dart | 6083 / 9553 |
| spb_wallet_database.dart | 691 / 892 |
| wallet_integrity_service.dart | 104 / 135 |
| wallet_rekey_service.dart | 53 / 54 |
| spb_wallet_crypto.dart | 123 / 127 |
| legacy_swl_codec.dart | 28 / 65 |
| secure_clipboard_service.dart | 9 / 16 |

Sixteen pre-existing skips depend on absent private legacy/demo fixtures. They
were not removed or weakened. Existing entry/editor widget tests serve as smoke
checks; actual native/device integration remains missing. Clipboard expiry is
explicitly bypassed in widget-test bindings by production code, so those tests
cannot establish timer behavior. Future tests need a separately approved seam
or real-device integration rather than changing production code in this task.

## 4. CI/CD

New CI triggers on PRs targeting master, master pushes and manual dispatch.
It retains existing packaging/analyzer/test checks and adds locked dependency
resolution, changed-file format checking, LCOV/JSON results, OSV Pub auditing,
workflow validation, and Windows/Linux/Android compilation/artifacts.
Flutter 3.44.7, Node 22.16.0, Go 1.24.4 and actionlint 1.7.7 are specified.
PR jobs use read-only permissions, no persisted checkout credential and no
publication step. Logs survive failures using `always()`; failures are not masked.

Actually verified locally:

- `flutter pub get --enforce-lockfile`: passed; lock unchanged.
- `flutter analyze --no-pub` and analysis of new Dart scripts: passed.
- Full Flutter tests with coverage and JSON events: passed, counts above.
- Node 22.16.0 `tests/packaging_scaffold.test.js`: passed.
- `actionlint 1.7.7 -shellcheck=` on all workflows: passed (ShellCheck not run).
- Changed-file formatting: passed for all three new Dart files.
- Full non-mutating Dart format inventory: fails on one existing test,
  `android_template_icon_picker_test.dart`; left unchanged and documented.
- `flutter build windows --release --no-pub`: passed, `wallet_aps.exe` produced.
- Live OSV query: 89 hosted Pub packages, zero reported findings; four SDK
  packages excluded. This does not audit native, OS, Gradle or SDK dependencies.
- Production/lock/asset diff and whitespace review: no task-owned changes.

Not verified: execution of the new workflow on GitHub, new Linux/Android CI
build paths, physical-device/installer smoke, native behavior, repository branch
protection. Push is not authorized. The successful older release is not evidence
that this new workflow will pass. npm package.json has no external dependencies;
the packaging script was executed directly with a temporary verified Node binary.

Build recipes are reproducible commands, not byte-reproducible builds: runner
images, apt packages, action major-version tags and existing release Docker
Flutter stable clones can change. Existing CD is unchanged. See
[workflow and CD recommendations](ai-workflow.md) for an owner-approved manual
release gate and secret/signing management. OSV API contract:
https://google.github.io/osv.dev/api/ ; Actions syntax:
https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax .

## 5. Risks

- Legacy AES-ECB/SHA-1-based format lacks modern authenticated encryption;
  compatibility must be maintained until a separately designed migration.
- Backup, file replacement, SQLite repair and rekey are data-loss-sensitive.
  Current tests cover selected failures, not power loss or arbitrary corruption.
- Android release is debug-signed in the current Gradle configuration; changing
  identity can break updates/access to existing private data.
- Existing master publication deletes older releases/tags beyond two; a merge of
  tests can itself trigger publication. Use an approved `[skip release]` merge
  message for this infrastructure change if no release is intended.
- Synology conflict files and the old local HEAD make blanket staging unsafe.
- Widget/native-channel mocks cannot establish real SAF, clipboard, PDFium or
  installer correctness. No private test data should be added to fill that gap.
- Advisory absence is not a security guarantee. OSV network failure is an error,
  not a passing audit. New actionlint checks YAML/expressions, not shell semantics.

## 6. Technical Debt

| Priority | Work requiring a separate scoped task |
| --- | --- |
| P0 before unattended releases | Agree signing identity, approval gate, retention/rollback policy; configure remote protections only with owner permission. |
| P1 | Replace private-fixture gaps with sanitized fixtures; cover repair rollback, wrong-password/corrupt rekey, interrupted native saves and permissions. |
| P1 | Pin release SDK/container/action revisions and audit native dependencies. Validate all three new CI build jobs remotely. |
| P1 | Add real-device/native integration tests for Android SAF, clipboard expiry, attachment/PDF and close/save paths. |
| P2 | Incrementally separate UI orchestration from storage behind tested seams; no broad monolith refactor during feature work. |
| P2 | Review historical docs and unify build recipes; retire platform regeneration/cache patching only after equivalence tests. |
| P2 | Fix the existing formatting-only test debt in a separately visible change; consider coverage trends after several stable CI runs. |

## 7. AI Readiness

Ready for small, supervised AI tasks with documented boundaries and local tests.
Not ready for unattended merging/releasing or autonomous cryptographic/storage
redesign. CI files are prepared and locally validated but not yet deployed.
Human review and publication approval remain explicit process requirements.

## 8. Next Steps

1. Review only the 13 listed files; prepare a fresh branch from the current
   remote master when push/PR is authorized, retaining local user changes.
2. Open an authorized PR; observe all new CI jobs, investigate platform failures
   without disabling checks, and confirm artifact/log retention.
3. Owner approves required status checks/review rules and a release environment;
   design manual publication and signing/retention changes in a separate PR.
4. Add synthetic corruption/rollback cases and native device smoke coverage.
5. Trial several small AI tasks under review; measure regressions and CI stability
   before granting broader autonomy.

Local evidence is retained in `dist/ai-readiness-20261014/` in the primary working
folder (ignored, not a deliverable): Flutter logs/events, LCOV, OSV response and
Windows build log. The isolated validation worktree is retained for inspection
under the system temporary directory, `wallet-aps-ai-audit-20261014`.
