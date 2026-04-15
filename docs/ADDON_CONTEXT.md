# ADDON_CONTEXT

## Addon Identity
- Addon Name: HealerMana
- Primary Purpose: Monitors healer mana for all healers in raids and dungeons. Icon-grid display with mana %, regen state (eating/drinking/innervate), range dimming, and class-colored borders. Replacement for the WeakAura "Raid Mana Healer Castbar".
- Expansion Target: Midnight (Interface 120001)

## Core Features
- Icon grid (vertical or horizontal layout) — one cell per healer
- Mana % display via UnitPowerPercent with full WoW 12.0 secret-value handling
- Regen state detection: eating, drinking, Innervate (icon + label replaces mana %)
- Out-of-range dimming via C_Spell.IsSpellInRange / UnitInRange / SetAlphaFromBoolean
- Class-colored borders and name labels per healer
- Spec icon from GetInspectSpecialization / GetSpecializationInfo with class fallback
- Configurable: cell size, spacing, layout, font sizes, sort order, lock, name/% symbol visibility

## Architecture Overview
- Modules:
  - Core: roster management (rebuildRoster, snapshotUnit, updateUnit), mana reading (readUnitPctRaw), range detection (isUnitInRange, detectRangeSpell), regen detection (getRegenInfo, buildRegenNames)
  - UI: bar pool (createBar, getBar, positionBar, renderBar), display refresh (refreshDisplay), main frame (createMainFrame), config panel (createConfigFrame)
  - Systems: event handler (eventFrame), slash commands (setupSlash)
- Notes:
  - All code lives in HealerMana.lua (single file)
  - Keep responsibilities clearly separated
  - Avoid cross-module leakage

## Slash Commands
- /hm (or /healermana) — open config panel
- /hm lock    — toggle frame lock/unlock
- /hm alpha   — toggle alphabetical sort
- /hm class   — toggle sort by healer class
- /hm layout  — toggle horizontal/vertical layout
- /hm reset   — reset frame to default position
- /hm debug   — dump healer roster and mana readings
- /hm range   — diagnose out-of-range detection
- /hm buffs   — dump all player buffs with spell IDs

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

## Known Constraints
- No Blizzard templates
- Event-driven preferred (0.5s ticker for mana refresh, unit events per healer)
- Combat lockdown safe — no protected frame writes in tainted paths
- No secret value misuse — UnitPower/UnitPowerPercent values are never compared or concatenated; routed through WrapString + SetFormattedText or SetAlphaFromBoolean
- No external libraries

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
