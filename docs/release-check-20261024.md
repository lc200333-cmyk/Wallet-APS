# Release preparation - 2026-10-24

Fetched master `c315022` (0.7.4+79), including the automatic version commits and
the newer CI workflow. Fast-forwarded the agreed interface worktree from
`7c32910` without conflicts, retaining all its local application/test changes.
The original mixed checkout, sync-conflict copies and local artifacts remain
untouched; outdated versions and icon expectations there were not copied over
the newer master. No force push, reset or cleanup is used.

Scope: hide confirmation for unnamed new cards/templates; alphabetical template
folders with short visible names and a shared folder editor; substring search on
Enter versus explicit exact search; the "Recent" panel label; uniform monochrome
menu pictograms. The template-folder persistence decision and compatibility
boundaries are documented in `template-folder-editing.md`.

Checks after combining with master, all exit 0:

- `flutter pub get --enforce-lockfile` (no dependency changes).
- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub --coverage --reporter expanded`: 245 passed, 16 skipped.
  Skips require unavailable private/manual fixtures. New tests use synthetic data
  and cover wide Windows and narrow Android widget layouts.
- `node tests/packaging_scaffold.test.js`.
- `dart tools/check_changed_format.dart c315022`: 15 Dart files checked.
- `dart tools/check_dependencies.dart`: 89 hosted packages, 0 OSV findings;
  4 SDK packages are outside scope.
- `dart analyze tools/check_changed_format.dart tools/check_dependencies.dart`.
- `flutter build windows --release --no-pub`.
- `git diff --check` and scoped diff review.

Local SDK: Flutter 3.44.8 / Dart 3.12.2; the hosted CI pin remains 3.44.7.
Linux/Android native builds and installer/device smoke tests were not run locally;
widget tests do not replace them. Build output, personal wallets, backups and
machine-specific files are excluded from the commit.

The feature commit deliberately has no skip marker. Application paths match the
existing master push filters, so CI, Windows setup and Release are eligible.
Versions are not bumped manually: after verification, Release should patch-bump
0.7.4 to 0.7.5 and create its version commit/tag and platform builds. Existing
publication and two-release retention are unchanged. Hosted Actions status must
be checked after push; local success does not prove hosted build success.
