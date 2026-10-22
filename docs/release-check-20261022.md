# Release preparation — 2026-10-22

Based on remote master `ae39268` (0.7.2+77), preserving its replacement icon
archives and release version. Local interface changes were combined using a
three-way patch in an isolated worktree. Original working files, sync conflict
copies, local backups, build output and temporary artifacts were retained locally.

Changes include editor alignment, the seven-colour palette, white defaults for
new folders and templates, navigator accordion ordering, password keypad feedback,
database terminology and renamed icon catalogs. The requested search rollback is
preserved: submitting a query still selects exact-match search.

Release preparation also updates packaging and template-layout assertions to the
requested labels/layout and fixes template header overflow using actual layout
constraints. No release workflow, cryptography or storage schema was changed.

Checks on the combined tree:

- `flutter pub get --enforce-lockfile`: exit 0.
- `flutter analyze --no-pub`: exit 0, no issues.
- `flutter test --no-pub --reporter expanded`: exit 0, 206 passed, 16 skipped.
  Skips are fixture-dependent legacy/manual tests; private wallets were not copied.
- `node tests/packaging_scaffold.test.js`: exit 0.
- `dart tools/check_changed_format.dart ae39268`: exit 0, 12 Dart files checked.
- `dart tools/check_dependencies.dart`: exit 0, 89 hosted packages, no OSV findings;
  four SDK packages are outside the check's scope.

Native release artifacts and Linux/Android runtime smoke tests are not produced by
these local checks. Existing GitHub Actions perform platform builds after push;
the workflow's existing publication and retention policy remains unchanged.
