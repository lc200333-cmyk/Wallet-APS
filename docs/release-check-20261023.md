# Release preparation - 2026-10-23

Prepared from fetched master `b1efd67` (0.7.3+78) in a new isolated worktree.
The user authorized inclusion of the remaining CI/contributor files and release
0.7.4. The original mixed checkout and all its local files remain untouched.
Master's newer interface fixes, icon archives and versions are preserved.

Scope: publish the existing read-only CI workflow, issue/PR templates and Docker
context exclusions. Add `.dockerignore` to Release's path filter, because it
changes Docker build inputs; packaging assertions cover this requirement and
the exclusion of local backups, build caches and sync-conflict files.
No application sources, native runners, assets, manifests or lockfiles changed.

Checks on Windows with Flutter 3.44.7 / Dart 3.12.2 (all exit 0):

- `flutter pub get --enforce-lockfile`.
- `node tests/packaging_scaffold.test.js`, including new packaging assertions.
- `actionlint` 1.7.7 with shellcheck disabled, matching CI: all workflows valid.
- `flutter analyze --no-pub`: no issues.
- `dart analyze tools/check_changed_format.dart tools/check_dependencies.dart`:
  no issues.
- `flutter test --no-pub --coverage --reporter expanded`: 206 passed, 16 skipped.
  Skips require unavailable private/manual fixtures; none were uploaded.
- `dart tools/check_changed_format.dart b1efd67`: no changed/new Dart files.
- `dart tools/check_dependencies.dart`: 89 hosted packages, 0 OSV findings;
  4 SDK packages outside scope.
- `git diff --check`.

Commit marker `[release 0.7.4]` requests the existing Release workflow to bump
all version sources, commit/tag and build the release. Versions are deliberately
not bumped locally. Existing publication and two-release retention are unchanged.
CI remains separate from Release and does not gate its publication.

Native installer/device smoke tests and Linux/Android builds were not executed
locally for this infrastructure-only change. Hosted builds and publication must
be checked in GitHub Actions after push; local checks do not prove their success.
