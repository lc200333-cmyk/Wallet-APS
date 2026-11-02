# Theme switching and Windows focus

The local Windows Application log recorded an access violation (`0xc0000005`,
followed by `0xc000041d`) in `flutter_windows.dll` while running Wallet APS.
This establishes a native crash, but the log alone does not identify the exact
engine function or prove that changing the skin caused it.

The host previously called `SetFocus(child_content_)` on every `WM_ACTIVATE`,
including `WA_INACTIVE`. It now restores child focus only on activation and only
for a valid child HWND. Deactivation must let Windows transfer focus elsewhere
without re-entering Flutter focus handling. `WM_FONTCHANGE` also checks engine
availability before use during startup/teardown.

No engine/SDK upgrade, global exception suppression, or accessibility disabling
is involved. Repeated theme-switch widget tests cover password entry and all
unlocked modes, preserving shell identity, typed password and synthetic cards.
They check intermediate animation frames as well as the final state.

Widget tests cannot reproduce a native engine access violation. Build the Windows
runner and manually repeat theme changes, focus changes and window resizing to
validate this mitigation on the affected machine. The original native failure
has not been reproduced deterministically; these guards are not proof that every
possible engine crash has been eliminated.
