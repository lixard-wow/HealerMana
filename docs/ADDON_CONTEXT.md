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
- Spec icon from GetInspectSpecialization / GetSpecializationInfo with class fallback; Priest (the only class with two Healer-role specs) shows a generic class-icon placeholder while resolving instead of blank or a guess
- Druid shapeshift-form indicator — while a healer Druid is in Cat, Bear, or Moonkin Form, Icon style replaces their spec icon outright with the Feral/Guardian/Balance spell icon; Bar style prefixes their name with a colored `[Cat]`/`[Bear]`/`[Moonkin]` tag. Cat/Bear detected via UnitPowerType (confirmed reliable in AND out of combat with live data); Moonkin still detected via aura (works out of combat only, same limitation Innervate has — see docs/ARCHIVE_INNERVATE_DETECTION.md). Mana % is hidden (blank) while in Cat or Bear Form, since neither uses Mana as their active resource; Moonkin still uses Mana so its % keeps showing
- Configurable: cell size, spacing, layout, font sizes, sort order, lock, name/% symbol visibility
- Minimap icon (LibDBIcon-1.0 + LibDataBroker-1.1) — left-click opens settings, right-click toggles a 5-healer test preview, tooltip explains the addon

## Architecture Overview
- Files (load order per .toc), sharing state via the standard `local ADDON_NAME, HM = ...` addon table:
  - HealerMana.lua: bootstrap — DEFAULTS, shared HM state (cfg, healerData, barPool, eventFrame), ADDON_LOADED/event dispatch
  - Core.lua: roster management (rebuildRoster, snapshotUnit, updateUnit), mana reading (readUnitPctRaw), range detection (isUnitInRange, detectRangeSpell), spec icons (buildSpecIcons, getSpecIcon), saveKey/resetPosition
  - UI.lua: bar pool (createBar, getBar, positionBar, renderBar), display refresh (refreshDisplay), main frame (createMainFrame)
  - Config.lua: widget helpers (makeToggle, makeSlider, makeDropdown, makeColorSwatch, makeTabButton, flatBtn), left-tab/right-content settings panel (createConfigFrame, openConfig) with 7 tabs (General, Layout, Fill Color, Background & Border, Text, Sort & Visibility, Help — the last is static reference text, no controls)
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
  - sortMode ("alpha" or "class")
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
- Food & Drink icon-swap detection (and any other aura-based detection: Druid Moonkin Form) does not work anywhere inside an active Mythic+ run, even out of combat between pulls — confirmed via Blizzard's own documented aura-secrecy rule: aura/cooldown data is secret whenever "a mythic keystone run has started and not yet completed" is true, independent of actual combat state. A raid only trips this during an actual encounter/combat, so it works fine between raid pulls; a key trips it for the entire run. Live-confirmed twice: once via a Druid demonstrably in Bear Form returning a clean "not found" on the aura check during combat, once via the user's own Food & Drink test during an active key. `/hm regendebug` now also prints `mythicPlusActive=` (via C_ChallengeMode.IsChallengeModeActive) alongside `inCombat=` to make this visible on demand.
  - **FINAL PROOF (PROMPT 82, `/hm auradump` live data):** 6 real dumps captured across an M+ session — all 2 checks with `mythicPlusActive=false` succeeded fully (GetUnitAuras and GetAuraSlots agreed exactly, real aura lists including "Well Fed" once actually eating); all 4 checks with `mythicPlusActive=true` (one of them mid-combat) failed completely, this time with an explicit engine error instead of silent emptiness: `GetAuraSlots(): Auras cannot be accessed when secret while tainted by 'HealerMana' / Lua Taint: HealerMana`. Critically, this failed even when checking the player's OWN character's own auras (self-data, normally exempt from secrecy) — once anything in that render tick touches a secret value, the whole execution is marked tainted, and Blizzard's engine refuses ALL aura access for the rest of that tick while an M+ run is active, no exceptions. This is no longer an inference from absence of data — it's Blizzard's own thrown error naming the exact cause. Nothing further to test here.
  - **CONFIRMED NO WORKAROUND EXISTS — do not re-research this.** Checked every angle: (1) "is mana increasing" — can't be computed at all, since comparing two secret mana readings requires arithmetic/comparison, both of which throw on secret values (see the Offline/Dead text-fit crash this session for a real example of exactly that failure). (2) Combat log (COMBAT_LOG_EVENT_UNFILTERED / CombatLogGetCurrentEventInfo) — removed from addon access entirely in this Midnight client, not merely secret; this is why DBM/BigWigs had to migrate to UNIT_* events instead. (3) UNIT_SPELLCAST_START/SUCCEEDED — gated by the identical restriction as auras, confirmed by the existence of Blizzard's own C_Secrets.ShouldUnitSpellCastBeSecret() API. (4) UnitStandState (sit/kneel detection) — does not exist as a real addon-callable Lua function; a search result claiming otherwise was a hallucination (conflating a real server-protocol concept with a nonexistent Lua wrapper) — verified absent from both Gethe/wow-ui-source and Ketho's official API annotations, despite a sanity-check confirming the same search method correctly finds real functions like UnitPowerType. (5) Blizzard's own CompactUnitFrame.lua (their real raid/party frame code) has zero references to Refreshment/Drink/Food/regen for other units — their own default UI doesn't attempt this either. (6) Blizzard's own generated API docs confirm `GetUnitAuraBySpellID` is flagged `SecretWhenUnitAuraRestricted = true, RequiresNonSecretAura = true` directly in their documentation metadata. The reason Cat/Bear Form had a workaround (UnitPowerType) and Food & Drink doesn't: UnitPowerType is metadata about which resource bar to display, categorically exempt from the secrecy system; there is no equivalent non-secret categorical signal for "is this unit eating."

## Current Focus
- Session initialization; no active task

## Notes for AI
- Do not guess APIs
- Do not expand scope
- Keep solutions minimal
- Follow CLAUDE.md and DEV_RULES.md strictly
- Secret value rules: NEVER do arithmetic, comparison, tostring, or string.format on values that may be secret (UnitPower, UnitPowerMax, UnitPowerPercent for grouped units in 12.0). Use issecretvalue() to detect, WrapString+SetFormattedText to display, SetAlphaFromBoolean for alpha.
