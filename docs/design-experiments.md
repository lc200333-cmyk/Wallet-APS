# Design experiment history

## 2026-10-28: Retro, Light and Dark skins (new specification)

Started from the restored interface (`3a0dfca`) per the owner's new
specification `Wallet-APS_themes_task.pdf`; the reverted experiment was not
restored. Retro is the original interface; Light and Dark are selected in the
password window and stored outside vaults. Details, decisions, verification
and open items: [skins.md](skins.md). Pushed to master at the owner's
request; the existing release workflow selects the next patch version.

## 2026-10-28: return to the original interface

The owner requested a fresh starting point for new designs and authorized a
rollback release numbered 0.7.11. Revert only the theme experiment `6a01960`,
not its ancestors or the subsequent version commit `2073d30`.

The application UI returns exactly to `3abb0f9`: no Light/Dark themes or theme
selector. The appearance layer and its feature-specific tests are removed as
one experiment; all pre-existing regression tests remain unchanged. Storage,
password semantics, original commands, Design identity, Android signing and
CI/CD are unchanged. No wallet or personal profile is modified.

Use a normal revert commit, never reset or force-push published history. The
canceled code remains recoverable in `6a01960`, branch `feat/appearance-only`
and the v0.7.10 source history. Do not automatically restore it for the next
design request; start from the restored UI and the owner's new specification.

The old isolated `wallet_aps_appearance.json` preference is left untouched and
is no longer read by the restored application. Do not delete personal profile
files or migrate vaults merely to remove the themes.

Release automation, not a local manual bump, selects 0.7.11 and increments the
Android build number. Existing release retention still keeps two releases.

Local verification before the automated version bump (Flutter 3.44.8 / Dart
3.12.2 on Windows): original UI source comparison, packaging, analyzer,
changed-file formatting and Windows release build all passed (exit 0).
The full suite passed 265 tests with 16 unchanged private-fixture skips.
OSV checked 89 hosted packages with no findings; 4 SDK packages are outside
that audit. Local Android/Linux native builds were not executed in this rollback
step; the authorized GitHub release workflow builds those packages separately.
