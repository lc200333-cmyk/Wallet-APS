# Editor selection images and new-vault controls

Based on `d366c52` (0.7.5+80), in the previously agreed isolated worktree.
The mixed main working tree was left intact.

## Scope

- Card template and category choices display the selected object's original
  image in a 24px frame. Template embedded images are supported, with fallback
  for malformed optional previews. IDs and short template labels are unchanged.
- Card/template icon context menus display the same catalog-folder images as
  the navigator, including custom folder images. Command menus retain their
  monochrome pictograms.
- Navigator and right-panel section strips share `WorkspaceSectionBar`, including
  height, typography, background and border. Right headings are `Действие`,
  `Найдено`, `Последние`, with the corresponding navigator images. Collapse,
  search count and recent-card behavior are retained.
- New-vault path placeholder is `Назначить путь`.
- A black, highlighted password-generator button sits at the bottom left.
  `Random.secure()` generates a 20-character password containing upper/lowercase
  Latin letters, digits and symbols, then fills both password controllers and
  updates strength. Generation alone never copies a password.
- Both new-vault password fields offer `Copy` while masked or visible, through
  the existing secure clipboard service. Other password fields retain their
  normal toolbar. No passwords are logged or stored by the generator.
- A regression exposed by copying/focusing and then cancelling on narrow Android
  was fixed: controllers are disposed after `DialogRoute.completed`, when its
  overlay is removed, rather than during the closing animation.

No database schema, encryption, version, dependency or release-workflow changes.

## Verification

Local SDK: Flutter 3.44.8 / Dart 3.12.2; repository CI pins Flutter 3.44.7.
Commands below exited 0 on the final sources:

- `flutter pub get --enforce-lockfile` (no manifest/lockfile changes).
- `flutter analyze --no-pub` (no issues).
- `flutter test --no-pub --coverage --reporter expanded`: 256 passed, 16 skipped.
  Skips remain the existing tests requiring unavailable private fixtures.
- Targeted editor/context-menu tests: 21 passed, including both Windows-wide
  and Android-narrow widget layouts. Tests assert actual image bytes, chosen IDs,
  independent field generation, both Copy actions, repeated generation, masking,
  header collapse/expand and cancellation without controller errors.
- `flutter test --no-pub test/workspace_geometry_test.dart --plain-name
  'windows V1 geometry at 100.0%' --dart-define=GEOMETRY_SCREENSHOTS=true`:
  passed. Test-font capture is suitable for geometry, not native typography.
- `node tests/packaging_scaffold.test.js`.
- `dart tools/check_changed_format.dart d366c52`: 8 changed/new Dart files.
- `dart analyze tools/check_changed_format.dart tools/check_dependencies.dart`.
- `dart tools/check_dependencies.dart`: 89 hosted packages, 0 OSV findings;
  4 SDK packages outside its scope.
- `flutter build windows --release --no-pub`.
- `git diff --check`.

One intermediate analyzer invocation printed an SDK network handshake error
after its analysis result. A standalone final invocation exited 0 cleanly.
Flutter-generated native plugin files had only line-ending differences;
`git diff --quiet` confirmed no content changes before their CRLF normalization.

The built Windows executable was opened for native visual checking. The new-vault
dialog showed the black generator, matching masked values, updated strength and
the Copy menu. The dialog was cancelled without creating a vault. Existing
personal vaults were not opened or modified during this check. Android behavior
was checked with widget tests, not on an Android device.

Build output is under `app/.build-local/windows/x64/runner/Release/`.
No commit, push, installation or release was performed.

## Follow-up: change-password generator

The `Действие → Изменить пароль` dialog now has the same black, highlighted
generator at the bottom left. It reuses `generateVaultPassword()`, fills only
the new/repeat controllers and refreshes strength; old password and hint remain
unchanged. Generation is disabled while saving. Both new-password fields offer
the same explicit `Copy` action through the secure clipboard service. The old
password remains required, and cancellation never submits a password change.

Four new widget regressions cover wide Windows and narrow Android: generation,
regeneration, strength, masked Copy, old-password validation, preservation of
old password/hint, submission through a synthetic callback, disabled generation
during pending save, and cancellation without submission. No personal vault is
opened or rekeyed by these tests.

Follow-up verification: `flutter analyze --no-pub` (no issues), targeted
`flutter test --no-pub test/editor_selection_and_vault_controls_test.dart
test/widget_test.dart --reporter expanded` (121 passed), packaging scaffolding,
changed-file formatting and `git diff --check` all exited 0.
The final full `flutter test --no-pub --coverage --reporter expanded` run exited
0: 260 passed, the same 16 private-fixture skips. Windows release build also
exited 0. The previous test app was already closed; no window needed closing.
The newly rebuilt executable has not been launched for this follow-up. This
dialog's wide/narrow verification is widget-based, not a native rekey test.

## Follow-up: section-strip heights and records label

`Мои карточки` is now `Мои записи` in the navigator, central root heading and
move-to-folder root choice. Model names, category paths and stored data do not
change. Both side panels already use `WorkspaceSectionBar`; its existing shared
height was retained rather than introducing a separate right-side value.

The expanded Windows/Android regression compares actual rendered heights for
`Действие`/`Мои записи`, `Найдено`/`Шаблоны`, and `Последние`/`Иконки`. It also
checks collapsed/expanded right strips and all three active navigator modes.
Icon-library loading is stubbed for this geometry-only test, to avoid unrelated
asset loading and inactivity timers. An initial unstubbed run failed after
switching modes; the isolated regression passes on both layouts (2 tests).

Final checks all exited 0: `flutter analyze --no-pub` (no issues), full
`flutter test --no-pub --coverage --reporter expanded` (260 passed, unchanged
16 private-fixture skips), `dart tools/check_changed_format.dart d366c52`,
`node tests/packaging_scaffold.test.js`, `git diff --check`, and
`flutter build windows --release --no-pub`. The user closed the running app
before rebuilding. No vault was modified; Android verification remains
widget-based. The rebuilt executable was not launched in this follow-up.

## Follow-up: bottom separators on right section strips

The three right headers now opt into an explicit 1-logical-pixel bottom border,
using the same `#b7b7b7` gray as the navigator strip separators. Left headers are
unchanged (no doubled borders between adjacent strips). The shared component's
height, backgrounds and typography remain unchanged. The line is present both
when expanded and collapsed, on wide Windows and narrow Android.

The geometry regression now checks actual `BoxDecoration` bottom border sides
against the corresponding navigator's separator color, width and style. An
initial helper incorrectly inspected an outer container; it was corrected to
inspect the actual `WorkspaceSectionBar`. Targeted checks passed on both layouts.
`flutter analyze --no-pub`, changed-file formatting, packaging scaffolding and
`git diff --check` exited 0. No data-storage or dependency changes.
The final full test run exited 0 (260 passed, unchanged 16 private-fixture
skips). `flutter build windows --release --no-pub` exited 0. The app process
was absent before building; no forced shutdown was used. The new executable
was not launched. Android verification was widget-based, not device-based.

## Follow-up: remove empty space between right sections

Removed the four explicit `blockGap` spacers (15 logical pixels each) before
`Найдено` and `Последние` in desktop and mobile action panels. Section content,
collapse controls, heights and gray borders remain intact. The existing spacing
constant is not changed, so unrelated layouts retain their geometry.

The Windows-wide and Android-narrow regression now measures the found heading
against the last action's bottom, the recent heading against an empty found
section's bottom, and all heading edges when collapsed. It reproduced a 15px
gap on both platforms before the fix and passed on both after the fix.

Final checks: analyzer (no issues), full tests (260 passed, unchanged 16 skipped
private-fixture tests), changed-file formatting, packaging scaffolding,
`git diff --check`, and Windows release build passed. The app process was absent
before the build; no forced close was used. The rebuilt executable has not been
launched for this change. No dependencies, stored vault data or version changed.

## Follow-up: full-width management panel and navigator highlighting

- Added fixed `Управление` above the right panel's scrollable content, using
  `spbSectionHeader` (the same 25px gradient title strip as the central root
  heading and navigator vault heading). It is present in desktop and mobile
  action views and stays visible while scrolling.
- Removed the 19px right content gutter. Section backgrounds now reach the
  window's right edge; the panel's default width and resize behavior are retained.
  An explicit interactive 4px overlay thumb remains. Automatic scrollbars are
  disabled only within this panel to prevent a second, wider scrollbar from
  intercepting the collapse controls. Other workspace scrollbars are unchanged.
- Navigator mode strips now retain the matching blue highlight and top/bottom
  gray borders, including inactive modes. Navigation/selected state is retained.
- Renamed `Найдено` to `Найденные`, including its collapse/expand keys and icon
  mapping. Search logic and results/count are unchanged.

New wide-Windows/narrow-Android tests assert gradient/height, matching desktop
central decoration, right-edge geometry, overlay width, non-overlapping arrow
placement, scrollability, fixed heading and a working collapse click after
scrolling. Existing tests also assert navigator backgrounds/borders in each
mode. Test setup was adjusted to keep desktop height above the app's 500px
responsive cutoff. The test exposed duplicate automatic-scrollbar interception;
disabling that duplicate resolved it without disabling interactive scrolling.

Final verification (all exit 0): analyzer without issues; full tests, 262 passed
and the same 16 private-fixture skips; changed-file formatting (9 Dart files);
packaging scaffolding; `git diff --check`; Windows release build. A geometry
screenshot test also passed with Segoe UI loaded from the local OS. Its synthetic
wide screenshot was visually inspected: title alignment, edge-to-edge backgrounds,
blue navigator strips, gray borders and renamed found heading are correct. It is
a widget rendering, not a screenshot of a personal vault or proof of all native
assets. Narrow behavior was verified with Android widget tests, not a device.
The app was already closed before building. The rebuilt executable has not been
launched, and there was no vault modification, installation, commit or push.

## Publication preparation

The user subsequently authorized publication to the existing repository and
its normal automatic version/build workflow. `origin/master` was fetched and
fast-forward reconciliation reported already up to date at `d366c52` (0.7.5+80),
including the previous release bot commit. A separate local backup of the ten
scoped source/test/documentation files and the tracked binary diff was retained.
The mixed original working tree, conflict copies and local outputs are excluded.

Fresh pre-push checks exited 0: locked Pub resolution (no manifest/lock changes),
analyzer (no issues), full tests (262 passed, 16 unavailable-private-fixture
skips), changed-file format (9 Dart files), packaging scaffold, script analysis
and OSV audit (89 hosted packages, 0 findings, 4 SDK packages outside scope).
The already-built Windows release contains the same production sources; no
native Android/Linux build was run locally. Generated plugin files changed only
line endings during Pub resolution; content equality was verified before CRLF
normalization. Version bumping and branding were not run locally. The normal
feature commit intentionally has no release-skip marker; existing automation
performs the patch/build-number increment, builds and publication.
