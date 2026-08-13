# ADDON_CONTEXT

## Addon Identity
- Addon Name: HealerMana
- Primary Purpose: Monitors healer mana for all healers in raids and dungeons. Icon-grid or bar display with mana %, range dimming, and class-colored borders.
- Expansion Target: Midnight (Interface 120100)

## Core Features
- Icon grid or bar display (vertical, horizontal, or grid layout) — one cell per healer
- Mana % display via UnitPowerPercent with full WoW 12.0 secret-value handling
- Out-of-range dimming via C_Spell.IsSpellInRange / UnitInRange / SetAlphaFromBoolean
- Class-colored borders and name labels per healer
- Spec icon from GetInspectSpecialization / GetSpecializationInfo with class fallback
- Configurable: cell size, spacing, layout, font sizes, sort order, lock, name/% symbol visibility
- Minimap icon (LibDBIcon-1.0 + LibDataBroker-1.1) — left-click opens settings, right-click toggles a 5-healer test preview, tooltip explains the addon

## Architecture Overview
- Files (load order per .toc), sharing state via the standard `local ADDON_NAME, HM = ...` addon table:
  - HealerMana.lua: bootstrap — DEFAULTS, shared HM state (cfg, healerData, barPool, eventFrame), ADDON_LOADED/event dispatch
  - Core.lua: roster management (rebuildRoster, snapshotUnit, updateUnit), mana reading (readUnitPctRaw), range detection (isUnitInRange, detectRangeSpell), spec icons (buildSpecIcons, getSpecIcon), saveKey/resetPosition
  - UI.lua: bar pool (createBar, getBar, positionBar, renderBar), display refresh (refreshDisplay), main frame (createMainFrame)
  - Config.lua: widget helpers (makeToggle, makeSlider, makeDropdown, makeColorSwatch, makeTabButton, flatBtn), left-tab/right-content settings panel (createConfigFrame, openConfig)
  - Commands.lua: slash commands (setupSlash), debug dumps (printDebug, printHelp)
  - Minimap.lua: LibDataBroker launcher object + LibDBIcon registration (initMinimapIcon, setMinimapIconShown); left-click opens settings, right-click toggles the test-roster preview directly (no menu)
  - Libs/: embedded LibStub, LibDataBroker-1.1, LibDBIcon-1.0 (third-party, not linted/edited)
- Notes:
  - Keep responsibilities clearly separated
  - Avoid cross-module leakage
  - Cross-file mutable state (cfg, healerData, barPool, mainFrame, eventFrame, rangeCheckSpell, testModeActive, DEFAULTS) lives on the shared HM table; functions exposed to other files are assigned as `function HM.name(...)`
  - Config.lua additionally exposes HM.addBorder, HM.flatBtn, HM.uiColors so Minimap.lua's quick menu matches the settings panel's visual style without duplicating widget code

## Slash Commands
- /hm (or /healermana) — open config panel
- /hm lock    — toggle frame lock/unlock
- /hm alpha   — toggle alphabetical sort
- /hm class   — toggle sort by healer class
- /hm layout  — toggle horizontal/vertical layout
- /hm reset   — reset frame to default position
- /hm raid <n> — populate n fake healers to test layout (off to restore)
- /hm debug   — dump healer roster and mana readings
- /hm range   — diagnose out-of-range detection

Also reachable without typing: minimap icon left-click (settings) / right-click (quick layout menu — style, arrange, sort, lock, raid preview, reset, open settings).

## SavedVariables
- Name: HealerManaDB
- Structure:
  - sortAlpha, sortClass, sortMana (sort toggles)
  - locked (frame click-through)
  - borderClassColor, showPctSymbol, showName, dimOutOfRange (display toggles)
  - cellSize, cellSpacing (sizing)
  - layoutHorizontal (layout)
  - nameFontSize, pctFontSize (font sizes)
  - point, relPoint, x, y (frame position)
  - minimap = { hide, minimapPos, lock } — owned/written by LibDBIcon-1.0, not by saveKey

## Known Constraints
- No Blizzard templates
- Event-driven preferred (0.5s ticker for mana refresh, unit events per healer)
- Combat lockdown safe — no protected frame writes in tainted paths
- No secret value misuse — UnitPower/UnitPowerPercent values are never compared or concatenated; routed through WrapString + SetFormattedText or SetAlphaFromBoolean
- External libraries: LibStub, LibDataBroker-1.1, LibDBIcon-1.0 only (embedded in Libs/, explicitly approved for the minimap icon) — no others without explicit approval

## Known Issues
- None logged

## Current Focus
- Session initialization; no active task

## Notes for AI
- Do not guess APIs
- Do not expand scope
- Keep solutions minimal
- Follow CLAUDE.md and DEV_RULES.md strictly
- Secret value rules: NEVER do arithmetic, comparison, tostring, or string.format on values that may be secret (UnitPower, UnitPowerMax, UnitPowerPercent for grouped units in 12.0). Use issecretvalue() to detect, WrapString+SetFormattedText to display, SetAlphaFromBoolean for alpha.
