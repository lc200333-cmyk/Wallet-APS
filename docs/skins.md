# Interface skins: Retro, Light, Dark

Specification: `Wallet-APS_themes_task.pdf` with the phone and wide-screen
concepts (owner documents, 27.10.2026). Owner decisions taken during the work
are recorded below. Functions, vault format, storage, password semantics and
the core are unchanged; only presentation differs between skins.

## Base and scope

- Implemented in Wallet-APS-Design on `feat/skins-retro-light-dark`, based on
  master `3a0dfca` (0.7.11, the restored 0.7.6 interface). The task text was
  written for main-project `0465b68` (0.5.3); where names differ, the current
  code wins: "Мои записи", "Управление", "Действие", "Найденные",
  "Последние" are kept, because labels and task texts must not change.
- The earlier, reverted theme experiment (`6a01960`) was not reused.

## Selection and storage

- Three buttons in the bottom row of the password window ("Тема:"): Ретро,
  Светлая, Тёмная (`skinRetroButton`, `skinLightButton`, `skinDarkButton`,
  row `skinSelector`). Owner decision: fixed colours in every skin — dark
  yellow, light grey, dark grey; the active skin has a frame and a check mark
  and is announced as selected.
- The password window is 562 × 642 (702 with a message or hint) in every
  skin; the Windows runner sizes were changed accordingly.
- The choice is stored in `wallet_aps_ui_settings.json` (`{"skin": ...}`) in
  the existing application state directory (Design profile), never in a vault.
  A missing, unreadable or unknown value yields Retro. Writes are serialised,
  replace the file atomically and retry briefly when Windows holds the file;
  a failure is logged and the skin still applies until restart.
- First start after the update: Retro. The previous experiment's
  `wallet_aps_appearance.json` is not read.

## Architecture

- `lib/ui/skin/app_skin.dart`: `AppSkin`, `AppSkinStore`, `appSkin`
  notifier, `WalletSkinTokens` (`ThemeExtension`, colour roles of section 6)
  and `buildModernTheme` (explicit `ColorScheme`, component themes, platform
  typography). `WalletSkinTokens.of(context)` falls back to Retro when a tree
  has no extension (tests, isolated dialogs).
- `lib/ui/modern/*.dart` are `part` files of `main.dart`, so new layouts call
  the same `_VaultShellState` methods with the same keys and callbacks.
  - `modern_password.dart`: flat keypad keys and the skin selector.
  - `modern_wide.dart`: toolbar, navigator header, mode rows, path row,
    right-panel groups, "Не сохранено" chip, list rows, colour tiles.
  - `modern_mobile.dart`: narrow shell with `NavigationBar` (Мои записи,
    Шаблоны, Иконки, База), folder screens, FABs, base tab with tasks and
    the session history, Android Back handling, menus as bottom sheets.
  - `modern_dialogs.dart`: shared dialog styling and the autolock dialog.
- Retro: every changed spot keeps its original literal on the `isRetro` path.
  `test/skin_retro_reference_test.dart` compares eleven Retro screens pixel by
  pixel with images rendered from the unchanged code before the work started.
  Alternative considered: moving every literal into tokens with Retro values.
  Rejected: many literals are gradients and 3D shadows with no modern
  counterpart, and the branch keeps Retro provably identical.
- `showSkinMenu` replaces the 16 `showMenu` calls. Retro and wide layouts call
  `showMenu` with the same arguments; narrow Light/Dark render the same
  `PopupMenuItem`s (keys, values, order) in a bottom sheet, whose route
  receives the tapped value. Destructive items are separated and red in
  Light/Dark.
- The only new indicator is the "Не сохранено" chip (`unsavedChip`), shown
  from the existing `spbWritePending` flag.

## Narrow Light/Dark behaviour

- Tabs call `showSpbCardsMode`, `showSpbTemplatesMode`, `showSpbIconsMode`;
  the base tab is a UI-only flag (`modernVaultTabOpen`, never stored).
- Folder rows call `openSpbFolder`, `mobileFolderUp` calls
  `openParentSpbFolder`, card rows call the existing primary-click handler
  (preview), long presses open the existing folder and card menus.
- The base tab lists `spbCardModeTasks()` (extracted unchanged from
  `spbTasksForCurrentMode`) and the session history with "Вернуть"
  (`restoreSessionUndoAt`).
- Android Back: sheets/dialogs/full-screen pages close as routes; then search
  is cleared, then the parent folder opens, then other tabs return to
  "Мои записи"; at the root the previous behaviour (leaving) is kept.
- Multiple selection does not exist in the narrow layout and was not added.
- Large dialogs already fill a narrow screen; their frame loses its corners
  in Light/Dark.

## Not implemented / open items

- Splitter hover highlight (primary 2 px) and the 7×36 tablet handle with a
  24 dp grab zone: splitter geometry and behaviour are unchanged; only the
  line colour follows the skin.
- Header block (tile, title, subtitle) inside the narrow bottom-sheet menus:
  the generic menu helper only knows the menu entries.
- Primary-tinted FAB shadow; default Material elevation is used.
- Window title bars (DWM, GTK) are unchanged by owner decision.
- Device checks: Windows release build only; Linux, Android phone/tablet,
  TalkBack and SAF flows still need manual verification.

## Verification

- `test/skin_test.dart`: storage, window sizes, switching keeps text, focus
  and keyboard mode, persistence, accessibility of the selector, WCAG contrast
  of text roles (≥ 4.5:1) and palette glyphs (≥ 3:1).
- `test/skin_shell_test.dart`: all skins × narrow / wide / Android tablet build
  every mode without exceptions; controls, keys and every task of every mode
  are reachable; tabs and FABs call existing methods; Back sequence; card menu
  sheet; chip; Retro has no modern controls; status-bar brightness.
- `test/skin_retro_reference_test.dart`: Retro pixel identity.
- `test/skin_preview_test.dart`: manual screenshots with real fonts
  (skipped unless `SKIN_PREVIEW=true`), written to `.codex/skin-preview`.
