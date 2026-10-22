# Testing

Run from a clean working copy with Flutter 3.44.7. Existing baseline on Windows
was 182 passing tests and 16 skipped at v0.7.1; see the audit report for this
task's fresh results. Test counts are not coverage percentages.

```sh
node tests/packaging_scaffold.test.js
cd app
flutter pub get --enforce-lockfile
flutter analyze
flutter test --coverage --reporter expanded
flutter test test/ai_characterization_test.dart
cd ..
dart tools/check_changed_format.dart <base-commit>
dart tools/check_dependencies.dart
```

The formatting check examines changed/new Dart files, including unstaged and
untracked files. Existing formatting debt is not rewritten by this task.
Changing a legacy Dart file may require a separately reviewed formatting-only
change; do not silently bypass the check or reformat the entire application.
For a full non-mutating inventory: `dart format --output=none --set-exit-if-changed app/lib app/test`.

| Test layer | Existing evidence and gaps |
| --- | --- |
| Unit/characterization | Fields, dates, layout, icon references, version comparison and scaling. New standalone tests cover cycles/orphans, field projection, layout fallback, malformed attachment payloads and legacy ID conversions. |
| SQLite integration | `data_integrity_test`, `spb_wallet_icon_fallback_test`, `legacy_swl_compatibility_test`: round trips, backups, recovery, undo, metadata. New synthetic rekey tests cover success and rollback with a corrupt payload. |
| Widget/regression/smoke | `widget_test`, `workspace_geometry_test`, Android resolution/scaling and icon editor tests exercise entry screen, editors, navigation, responsive layout and mock native channels. |
| Source/package checks | Node packaging assertions and Android privacy/branding tests inspect source text. Useful safeguards, not runtime integration evidence. |
| Native end-to-end | No `integration_test` device suite. Build success does not prove SAF permissions, clipboard sharing, PDF rendering or installer behavior. |

Some legacy wallet and manual screenshot tests skip when private files in
`docs/` are absent (MW/VadWall/old-current wallet fixtures and demo screenshots).
Keep those skips visible; never upload personal wallets to make CI green.
Future work: replace gaps with sanitized/synthetic fixtures, then test native
save failures and recovery on real devices. New tests require no private files.

CI saves LCOV and machine-readable Flutter test events, command logs and build
artifacts. Coverage is informational until a measured, reviewed baseline exists.
It excludes native Kotlin/C++ execution and does not imply security correctness.
OSV checks exact hosted Pub package versions; it does not audit SDK binaries,
Gradle/native dependencies, operating-system packages or custom cryptography.
Network failures and vulnerability findings fail the check; investigate them.

Manual smoke before an approved release, using only disposable synthetic data:
create/open/lock a vault; create/edit/reopen a card; change password; backup and
reopen the copy; verify image/PDF attachment and external open; check clipboard
expiry, narrow/wide layout, Android SAF reopen and Windows/Linux launch.
