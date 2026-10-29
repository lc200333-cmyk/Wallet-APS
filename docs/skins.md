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
- The password window is designed at 562 × 642 (702 with a message or
  hint) in every skin. Owner decision (0.7.14+): Windows, Linux and macOS
  draw that design at 75 % (`passwordWindowScale`, a `FittedBox`), so keys,
  labels and icons shrink together; the Windows runner window is
  421.5 × 481.5 (526.5). Phones and tablets keep full size for touch.
- The choice is stored in `wallet_aps_ui_settings.json` (`{"skin": ...}`) in
  the existing application state directory (Design profile), never in a vault.
  A missing, unreadable or unknown value yields Dark (owner decision, 0.7.14+;
  it was Retro before). Writes are serialised,
  replace the file atomically and retry briefly when Windows holds the file;
  a failure is logged and the skin still applies until restart.
- First start without a stored choice: Dark; a stored choice is kept. The
  file carries `"version": 2`; a choice stored by an older version (no
  version, from the Retro-default era) is ignored once, so the first start
  of 0.7.14 opens Dark (owner decision). The
  previous experiment's `wallet_aps_appearance.json` is not read.
- "Сменить тему" (before "Выйти" in every mode of "Действие", all skins and
  layouts) opens a dialog (`skinDialog`) with the same three buttons
  (`skinDialogRetro`, `skinDialogLight`, `skinDialogDark`). The skin applies
  after the dialog has closed, because buttons cannot animate between the
  Retro and modern text styles.

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

## Follow-up (0.7.12+)

- Wide splitters turn primary (2 px) under the mouse pointer; on an Android
  tablet they show a 7×36 handle with a 24 dp grab zone. Retro keeps 9 px
  and no highlight. Widths, limits and keys are unchanged.
- Narrow bottom-sheet menus of cards, folders and templates start with the
  object header (tile, name, template/path); entries are unchanged.
- The Light FAB has the primary-tinted shadow of section 6.3; Dark has none.

## Owner requests (0.7.14+)

- Wide Light/Dark centre: the narrow create button (`modernCreateFab`,
  `modernCreateTemplateFab`, `modernUploadIconFab`) in the bottom right
  corner, above the icon workspace's own button row. Retro (wide centre and
  narrow pane 1) has a blue Retro-style "+" (`retroCreateButton`): cards and
  templates open their existing creation menus at the button, icons open the
  upload.
- Templates: in wide layouts a mouse or pen drags templates (grid or left
  tree, several when selected) onto a template folder of the left panel. The
  folder is stored in the category path, and a "Папка: название" name follows
  the new folder (`templateNameInFolder`). One undo entry per move.
- Wallet icons are at most 128×128: a new ICO icon larger than that is
  reduced on save (other formats were already stored as 64×64), and
  "Проверить и восстановить" (load error report only, no longer a "Действие"
  task) reduces stored ones. The largest ICO frame is chosen by its decoded
  size (a 256 px directory entry is stored as 0). Proportions are kept on a
  transparent square; smaller icons are untouched. Owner decision: stored
  icons are not reduced automatically when a base is opened (tried and
  withdrawn in 0.7.14).
- Touch screens: wide card, folder and icon drags use `PointerDraggable`,
  which starts for a mouse or pen only, so a finger scrolls grids and trees.
  Touch users move items through the long-press menu.
- Light/Dark draw icons without tiles (rows, grids, icon picker, menu
  headers, task rows); a selected grid icon has a frame only. Exception
  (owner decision, 29.10.2026): the "Иконки" workspace frames every icon
  as Retro does — Light with the Retro fill, border and selection colours,
  Dark with those colours inverted (`managedCatalogIconFrame`,
  `skinFrames`).
- Narrow Light/Dark: the fourth tab and its screen are called
  "Управление" (was "База"; owner decision, 29.10.2026).
- Dark card preview, card editor, template preview and template editor
  (owner decision, 29.10.2026): background and fields have the main Dark
  colour (`bg`) whatever the card or template colour (`skinCardSurface`);
  field outlines and labels are the grey of the Light outline
  (`skinCardFieldsTheme`). Focus and errors keep their colours; the card
  colour remains on the icon and the colour swatches.
- "Действие" task icons are 20 % larger in every skin.
- Card preview, every skin: a web-site field (type `url`, or a label with
  "сайт"/"website") has a globe left of the copy button that opens the
  address in the default browser (`https://` is added when missing); an
  e-mail field (type `email`, or a label with "почт"/"email") has an
  envelope that opens a new message in the default mail client (`mailto:`).
  A phone field (type `phone`, or a label with "телеф"/"phone"/"мобильн")
  has a phone button that opens a dialog (`phoneLinkDialog`): WhatsApp
  (`https://wa.me/<digits>`), Telegram (`https://t.me/+<digits>`), "Набор
  номера" (`tel:`), SMS (`sms:`) and "Другая программа…" (`tel:` through the
  Android chooser; on Windows and Linux the system association decides).
  Only http(s), mailto, tel and sms addresses are opened (Windows
  `url.dll`, Linux `xdg-open`, Android `ACTION_VIEW`/`ACTION_SENDTO`/
  `ACTION_DIAL`); a value that is not an address or number shows no button.
- Template folders for new bases: "Папки шаблонов для новых баз"
  (templates mode, "Действие") saves the open base's layout — every
  template's stored name and category path, and the template folder
  settings — to `wallet_aps_template_layout.json` in the application state
  directory (`TemplateLayout`). A new base, copied from
  `assets/base_wallet/MyWallet.swl`, takes that layout before it is opened,
  otherwise the shipped `assets/base_wallet/template_layout.json` when
  present. Templates are matched by ID, otherwise by a name without folder
  that is unique on both sides; unmatched templates stay put. The folder is
  written as a "Папка: название" name (as in the standard set), never as a
  category path, so a new base gets no empty card folders. The shipped
  layout is the owner's (29.10.2026): all 59 standard templates in 11
  folders.
- New-base contents (owner decision, 29.10.2026): `MyWallet.swl` is the
  owner's demo base "тест", re-keyed to `0000` — 12 folders, 16 cards (SPB
  demo cards, "О программе Wallet" notes and "С чего начать" with the
  getting-started PDF attached), 60 templates (the standard set and
  "Заметка") and its icons. Only invented demo data belongs there: every
  installation ships it.
- Narrow Light/Dark "Мои записи": the path row and the search field stay
  above the scrolling list (folders, cards, "Найденные").
- Icon folder names in the left panel use 85 % of the folder font.
- Icon browsers ("Иконки" workspace, the folder icon picker and the card
  editor's icon pickers) show icons 25 % smaller in every skin
  (`WorkspaceGeometry.iconBrowserScale`). Owner decision (29.10.2026): the
  "Иконки" workspace is 25 % larger again (`iconWorkspaceScale`); its
  frames are grey (`managedIconFrameGrey`, inverted in Dark), 0.75 px wide
  and rounded by 6 instead of 1 px and 8. The pickers keep 75 %.
- Light/Dark card mode grid (cards and folders): the selection frame is
  grey (`managedIconFrameGrey`, inverted in Dark), 1.5 px and rounded by 6
  instead of primary, 2 px and 12 (owner decision, 30.10.2026). The
  templates grid keeps its frame.
- Light/Dark search field (wide and narrow): always a grey frame
  (`managedIconFrameGrey`, inverted in Dark), 1.5 px instead of the former
  2 px focus frame, corner radius 30 % of the former pill (owner decision,
  30.10.2026).
- Light/Dark password field: grey frame (inverted in Dark), 0.75 px and
  1.5 px focused instead of 1 px and 2 px primary, radius 3.6 instead of
  12 (`modernFieldBorder`; owner decision, 30.10.2026).
- Password keypad, every skin and keyboard mode: the backspace key draws
  "⌫" itself (`BackspaceGlyph`), sized like the Segoe UI Symbol glyph, with
  a cross half as large (owner decision, 30.10.2026).
- Left "Мои записи" tree, every skin and layout (owner decision,
  29.10.2026): folder and card rows are 2 px taller
  (`treeRowExtraSpacing`), card icons 4 % smaller (`treeCardIconScale`).
  The template and icon folder trees are unchanged.
- Retro "Последние" rows repeat the "Действие" rows: icon size, font and
  row spacing (owner decision, 29.10.2026). Light and Dark are unchanged.
- Retro "Иконки" bottom row: the yellow button (`pasteManagedIconButton`,
  paste glyph) pastes from the clipboard and sits right of the icon folder
  button; the blue "+" and the upload button are gone there (upload is the
  central "+" and the "Действие" task). Light/Dark keep their row.
- Icon folders renamed: "Логотипы компаний" → "Логотипы", "Дополнительные" →
  "Разные" (labels only; storage keys unchanged).
- Linux looks like Windows (owner decision, 29.10.2026), Windows is the
  reference. Every size that was Windows-only (search field and buttons,
  mode rows, left tree folder font and icons, larger "Действие" text,
  full-screen icon pickers in the card editor) now applies to both
  (`isDesktopTargetPlatform`). Text uses Wallet Sans on Linux
  (`platformFontFamily`, `assets/fonts/README.md`): Roboto with the width
  and line height of Segoe UI per weight, because Segoe UI may not be
  shipped and the usual Linux default (DejaVu Sans) is 16 % wider. Window
  handling (login window size, title bar) is unchanged.
- Retro references were regenerated for these intentional changes; only the
  right "Действие" panel and the Retro "+" button differ.

## Open items

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
