# TESTING

## Standard Smoke Test
- Load the addon without Lua errors
- Open the main UI/config if applicable
- Reload UI and confirm settings persist
- Check core feature path works
- Check disabled features stop doing work
- Check combat-sensitive features do not cause protected action issues
- Check layout at different UI scales if UI was touched
- Check localization keys for any new text

## Task-Specific Tests
- Add per-task testing notes here

## Results
- 2026-08-14 (static/code-review smoke test, no live client access): full luacheck pass (0 new warnings, only 2 pre-existing unrelated items), .toc-vs-disk file check (clean), cross-checked every `cfg.X` reference across all 6 files against DEFAULTS (no missing defaults), and manually traced every config control's callback across all 7 tabs and both display styles for nil-safety, forward-reference bugs, and API-signature mismatches. Found and fixed one real issue: UI.lua's icon-style renderBar still called `getFillColor(data, pct)` with a stale 2nd argument left over from the Mana Threshold removal (PROMPT 45) — harmless in Lua (extra args are silently dropped) but misleading; fixed to `getFillColor(data)`. No other bugs found. This is NOT a substitute for an in-game pass — could not click through the actual UI, trigger real events, or verify visual rendering.
