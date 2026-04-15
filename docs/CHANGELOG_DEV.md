# CHANGELOG_DEV

## Unreleased

### Format
- PROMPT X
  - Intent:
  - Files changed:
  - Result:
  - Notes:

### Entries
- PROMPT 1
  - Intent: Session initialization — read all context docs, populate ADDON_CONTEXT.md with real addon details
  - Files changed: docs/ADDON_CONTEXT.md
  - Result: ADDON_CONTEXT.md updated from placeholder template to reflect actual HealerMana addon (identity, features, architecture, slash commands, SavedVariables, constraints)
  - Notes: TOC Interface 120001 vs CLAUDE.md target 120000 — noted, not changed per rules
- PROMPT 3
  - Intent: Fix eating/drinking/Innervate detection for non-player healers
  - Files changed: HealerMana.lua
  - Result: Replaced non-existent C_UnitAuras.GetAuraDataBySpellID with C_UnitAuras.GetUnitAuraBySpellID(unit, spellID) (added 11.2.5). The old call was dead code — the guard condition was always false, so non-player units always fell through to the unsafe GetBuffDataByIndex fallback. Now correctly detects eating/drinking/Innervate on party and raid members.
  - Notes: GetPlayerAuraBySpellID (player path) was already correct. Fallback retained for pre-11.2.5 builds. Midnight drink IDs confirmed correct (1269919 = Drink, 6% mana/sec).
- PROMPT 4
  - Intent: Fix icon size slider — step 1 per tick, range 30–60
  - Files changed: HealerMana.lua
  - Result: Changed makeSlider call from (24, 96, step=4) to (30, 60, step=1). Default cellSize (52) is within new range.
  - Notes: Saved values outside 30–60 are clamped by existing slider snap logic.
- PROMPT 5
  - Intent: Fix regen detection dropping after first hit; align font size slider ranges
  - Files changed: HealerMana.lua
  - Result: Removed updateUnit() call from UNIT_POWER_FREQUENT handler — mana ticks were racing to clear d.regenLabel by re-running getRegenInfo() on every tick, wiping Drinking/Innervate state set by UNIT_AURA. renderBar reads mana % fresh via readUnitPctRaw, so only refreshDisplay() is needed there. Also changed Mana % Size slider max from 24 to 20 to match Name Size range (8–20).
  - Notes: Regen state (regenLabel/regenIcon) is now exclusively managed by UNIT_AURA and rebuildRoster, not mana ticks.
- PROMPT 6
  - Intent: Remove eating/drinking/Innervate detection — aura queries return nil in M+ and boss encounters (SecretWhenUnitAuraRestricted); no addon workaround possible
  - Files changed: HealerMana.lua
  - Result: Removed REGEN_SPELLS table, regenNames/regenIconById state, buildRegenNames(), getRegenInfo(), regenIcon/regenLabel fields from snapshotUnit/updateUnit, regenLabel render branch in renderBar, UNIT_AURA event handler and registration, /hm buffs slash command. buildSpecIcons() now called directly instead of via buildRegenNames().
  - Notes: Re-add when Blizzard whitelists eating/drinking/Innervate spell IDs as non-secret.
- PROMPT 2
  - Intent: Update Interface version to 120001 across all doc files
  - Files changed: CLAUDE.md, docs/DEV_RULES.md, docs/ADDON_CONTEXT.md
  - Result: All three files now consistently reference 120001; stale TOC mismatch note removed from ADDON_CONTEXT.md
  - Notes: TOC was already 120001; this aligns the docs
