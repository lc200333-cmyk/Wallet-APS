# Appearance-only Design experiment

Implementation against `3abb0f9` / `0.7.9+84`, branch `feat/appearance-only`.
Specification: the 13-page task in `Wallet-APS-Design_Theme_Only_Codex_Task.pdf`,
with the original 47-page concept as its reference appendix. Only visual styling
was taken from that concept; its new navigation and functional proposals were
not implemented. The previously canceled implementation was not restored.

## Boundaries and decisions

- Three explicit modes: Retro (first-install default), Light and Dark. There is
  no System mode. The existing Retro ThemeData values, gradients, fonts and
  enlarged typography remain the baseline.
- `lib/appearance/appearance.dart` holds ThemeData/ColorScheme and explicit
  semantic roles. Call sites identify their purpose, not their RGB hue. No
  global colour inversion, regular-expression colour rewrite or dependency was
  introduced. Dark/light colours follow concept page 7; interactive outlines
  are stronger than passive dividers, and success/warning text shades are
  stronger where needed for normal-text contrast.
- `AppearanceController` lives above MaterialApp in production. Startup awaits
  its preference before runApp. Switching does not replace Navigator, the shell
  or editor state, and does not invoke wallet operations. Theme animation is
  disabled to make switching immediate.
- The three additional password-window buttons have fixed dark-yellow,
  light-grey and dark-grey backgrounds, labels, checkmark, selected semantics
  and a focus border. TextFieldTapRegion preserves pointer-input focus and
  selection. Native keyboard activation still uses standard Flutter buttons.
- Only the additional selector needs extra password-window space. Both existing
  scroll views remain available. The version label fits its available header
  width at large text scales. New theme keys are flat and the backspace command
  uses a font-independent Material pictogram; Retro retains its original glyph.
- Existing object colour IDs, RGB/spbColor values and the seven colour swatches
  remain data. A pure display-only function produces readable object surfaces
  in the new themes, including a deterministic arbitrary-colour fallback.
  Returned display colours are never assigned to models or save arguments.
- Original icon/image libraries, photos, PDF content and background image bytes
  are not recoloured or inverted. White plates behind some original/brand icon
  assets are intentional content-contrast plates, not unthemed windows.
- No changes to schema, SQL, serialization, crypto, password policy, attachments,
  wallet save/load/rekey/repair, IDs or the existing command callbacks. No new
  timers, autosave, navigation, generator settings, filters or trash semantics.
- No change to Design identity, Android signing, dependencies, version, Actions
  or release settings. Nothing was pushed, merged or published.

## Preference

Changed production files: `app/lib/main.dart`,
`app/lib/widgets/workspace_section_bar.dart`, and the three new modules
`app/lib/appearance/appearance.dart`, `appearance_controller.dart` and
`appearance_selector.dart`. Four new tests are `appearance_test.dart`,
`appearance_matrix_test.dart`, `appearance_operations_test.dart` and
`appearance_visual_test.dart` under `app/test/`. This document is the only
additional tracked-intended documentation. Build output and evidence stay ignored.

The only new persistent data is `wallet_aps_appearance.json`, containing schema
version 1 and `retro`, `light` or `dark`. It is stored in the existing isolated
Design support directory, never in a wallet or the stable application's profile.
Desktop: the path_provider support directory followed by `Wallet APS Design`.
Android: the app-private files directory of the existing Design package.

Missing, malformed and unknown preferences fall back to Retro. Writes are
asynchronous, flushed to a temporary file, then renamed into place and serialized
so the last selection wins. Failure leaves the selected theme usable in the
current session and displays a preference-specific warning. No passwords or
paths are written to this preference. The filename differs from the canceled
experiment's preference, so canceled settings are not silently revived.

## UI role and verification map

| Existing UI | Roles and concept pages | Verification |
| --- | --- | --- |
| Password, four keyboard layouts, hint/error, new database, change password | canvas/surface/text/focus, neutral keys, selected mode, primary command; 9-12, 35 | Both platform layouts, all themes, error/hint and scrolling; menu/dialog captures |
| Main panes, database header, trees, search, Management/Action/Found/Recent strips | canvas/surface/header/selected/divider/text; 13-18, 45 | Wide/narrow widget renders; unchanged search Enter/exact-button tests |
| Context menus for cards, templates, folders, creation and session undo | surface, primary selection, onSurface, outline; 8, 18, 29-33 | Existing menus opened and dismissed in all three themes and both layouts |
| Card, template and folder editors; previews and all existing fields | display-only object surface, themed field, header, outline, primary/neutral command; 19-32 | Pre-change Retro comparison; draft, validation, undo, save and route-retention tests |
| Original icon selectors and colour chooser | theme surrounding UI; preserve image bytes, swatch values and references; 22-25, 28, 33 | Existing icon/palette/dropdown tests retained; contrast tests cover stored palette and arbitrary RGB |
| Delete confirmations, move dialogs, imports/exports, archive/history, errors, inactivity and updates | common ThemeData plus explicit custom surfaces, actions and status roles; 34-44 | Maintenance/menu matrix; operations and compatibility suite; inactivity and deletion renders |
| Tooltip, Snackbar, text menus, dropdown, calendar, cursor, scrollbars | standard components inherit ColorScheme; custom bars/fields use explicit roles; 8 | Full widget suite and source review of local Theme overrides |

This map distinguishes shared styling coverage from native end-to-end coverage.
It does not claim every possible state of every native integration was exercised.

## Evidence and commands

Local SDK: Flutter 3.44.8 / Dart 3.12.2 (CI pins Flutter 3.44.7); Windows host.
Logs and screenshots are ignored local evidence under `.codex/appearance-*`.
All fixtures created by these tests are synthetic temporary wallets.

| Command | Exit / result |
| --- | --- |
| `node tests/packaging_scaffold.test.js` | 0; packaging, repository isolation and signing contracts passed |
| `flutter pub get --enforce-lockfile` | 0; no dependency/version changes |
| `flutter analyze --no-pub` | 0; no issues |
| `flutter test --no-pub --coverage --reporter expanded` | 0; 309 passed, 16 existing skips |
| `flutter test --no-pub test/ai_characterization_test.dart` | 0; 11 tests, including rekey and unknown metadata |
| `flutter test --no-pub test/appearance_test.dart` | 0; 17 tests |
| `flutter test --no-pub test/appearance_operations_test.dart` | 0; synthetic CRUD/copy/move/trash/undo/attachment/export/reopen in each theme |
| `flutter test --no-pub test/appearance_visual_test.dart test/appearance_matrix_test.dart --dart-define=APPEARANCE_CAPTURE=all` | 0; 24 tests and 126 renders |
| `dart tools/check_changed_format.dart 3abb0f9` | 0; changed/new Dart files formatted |
| `dart tools/check_dependencies.dart` | 0; 89 hosted packages, 0 OSV findings; 4 SDK packages outside scope |
| `flutter build windows --release --no-pub` | 0; `.build-local/windows/x64/runner/Release/wallet_aps.exe` |
| `flutter build apk --debug --no-pub` | 1; Android SDK is absent, not a successful APK build |

The baseline was captured before UI modifications: workspace, new card,
new template, new folder and both previews at 1280x900 and 360x800. All 12
post-change Retro renders compare with zero differing pixels outside the actual
current-time Text rectangle. There were no pre-change password/menu baselines;
their new renders are inspection evidence, not pixel-regression proof.

The input matrix additionally covers 320x480 (keyboard inset), 360x800,
412x900, 1280x900 and 1600x1000, at text scales 1.0/1.3/2.0, all themes and
four keyboard layouts. The selected theme does not clear input/caret/selection,
focus, keyboard mode, password visibility, error or chosen database. Tests cover
Enter/Space, selected semantics, draft/route retention and unchanged search modes.
The synthetic SWL test compares unchanged bytes, IDs, dirty/pending flags, undo
and session trash across repeated theme switches; separate operation tests save
and reopen data and attachments in each theme.

## Remaining limitations before release

- The 16 pre-existing skips require unavailable private legacy/demo fixtures;
  no private wallet was added and no existing assertion was relaxed.
- No native Android APK/device verification is possible without its SDK/device.
  Narrow Android evidence here is Flutter widget rendering on Windows.
- Linux native build/runtime requires a Linux host; it was not executed here.
- No claim of a complete native Windows interaction/installer audit. The Windows
  release build is verified; screenshots are explicitly Flutter test renders.
- System file pickers, OS keyboard, external programs and PDF page contents are
  outside the application theme's control.
- Existing clipping of the Retro new-database title on a narrow screen is not
  redesigned. New themes fit that existing title into its unchanged height.
- The new tests do not constitute a security audit or 100% code coverage.
  Before an authorized release, perform the native disposable-wallet smoke
  sequence in `testing.md`, especially SAF, clipboard, PDF and installer behavior.
