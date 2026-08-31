# Archive: Innervate detection (removed PROMPT 70)

## Status
Removed from the live addon. Food & Drink / Quiet Contemplation regen detection (the sibling
feature added the same session) is confirmed working and was NOT touched — this archive is
Innervate-specific.

## Why it was removed
Innervate detection (spellID 29166) was confirmed working out of combat, including on another
party member (not just the local player) — first verified this session via live `/hm regendebug`.
But the user confirmed live that it does NOT work once actual combat starts, which is exactly
when a healer's Innervate usually matters most.

User pointed out ElvUI and EllesmereUI both show Innervate correctly on their frames, which would
suggest it should be readable in combat too. Investigated both addons' real installed source
(not guessed) before concluding anything:

- **ElvUI**: its only Innervate reference is a config entry in
  `G.unitframe.aurafilters.Whitelist` (`ElvUI/Game/Mainline/Filters/Filters.lua`) — a static
  "always display this spell if seen" override for its *normal* aura-scanning pipeline. The
  actual data-fetching underneath (`ElvUI_Libraries/Game/Shared/oUF/auraskip.lua`) uses the same
  `C_UnitAuras.GetAuraSlots`/`GetAuraDataBySlot` APIs we use, and explicitly guards against secret
  values AND secret tables (`oUF:IsSecretValue`, `oUF:IsSecretTable`). No special bypass found —
  ElvUI is subject to the same restriction, not exempt from it.
- **EllesmereUI**: its Innervate reference (`EllesmereUIUnitFrames_PlayerAuraBars.lua`) is the
  **player's own** aura bar — watching buffs on yourself, not reading another unit's aura. Your
  own auras are documented as exempt from secrecy, so this is a fundamentally easier case that
  doesn't prove other-unit reads work in combat.

Neither addon was ever confirmed by the user to show Innervate on ANOTHER player specifically
DURING combat — that's the one fact that would have settled whether this is a genuine Blizzard
wall or a fixable bug on our side, and it was never gathered before the decision to remove and
archive rather than keep debugging.

## The likely cause (documented, not fully confirmed for this specific spellID)
Per Warcraft Wiki's Patch 12.1.0 API changes page (sourced from Blizzard's own generated API
doc data): aura data becomes secret "during combat, encounters, M+, and PvP matches" for any
addon, for any spell NOT on Blizzard's "never secret" exception list. Whether spellID 29166
(Innervate) is on that list was never directly confirmed — the improved `/hm regendebug` (added
this session, still in the live addon) prints `secret=` and `inCombat=` specifically so this can
be tested live in the future: a `secret=true` result during real combat would confirm the wall;
a normal `nil`/`secret=false` result would mean something else is actually broken.

## How to resume this later
1. Re-add the pieces below.
2. Have the user run `/hm regendebug` (already has the `secret=`/`inCombat=` reporting) while
   Innervate is actually up on someone AND the user is in real combat — that's the missing data
   point.
3. If confirmed secret/blocked in combat, this is very likely a hard Blizzard-side restriction
   with no addon-side fix — treat as a permanent limitation rather than keep iterating.

## Removed code (as of removal, PROMPT 70)

### Core.lua
```lua
HM.INNERVATE_SPELL_ID  = 29166
...
HM.innervateIcon = C_Spell.GetSpellTexture(HM.INNERVATE_SPELL_ID)

function HM.getRegenState(unit)
    if not UnitExists(unit) then return nil end
    if auraDataBySpellID(unit, HM.INNERVATE_SPELL_ID) then return "innervate" end
    -- ...food/drink checks unchanged, kept...
end
```

### UI.lua (bar-style name-text swap, inside `renderBar`)
```lua
local displayName = data.name
if data.regenState == "innervate" then
    displayName = "Innervate"
elseif data.regenState == "drinking" then
    displayName = "Drinking"
end
```
(kept the `drinking` branch, removed only the `innervate` one — see current code)

### UI.lua (icon-style icon swap, inside `renderBar`)
```lua
local iconID = data.specIcon
local showingRegenIcon = false
if data.regenState == "innervate" and HM.innervateIcon then
    iconID = HM.innervateIcon
    showingRegenIcon = true
elseif data.regenState == "drinking" and data.regenIcon then
    iconID = data.regenIcon
    showingRegenIcon = true
end
```
(kept the `drinking` branch, removed only the `innervate` one — see current code)

### Commands.lua (`/hm regendebug`, inside `reportUnit`)
```lua
local ok1, innervate = pcall(C_UnitAuras.GetUnitAuraBySpellID, unit, HM.INNERVATE_SPELL_ID)
...
local innervateSecret = ok1 and type(innervate) == "table" and HM.isSecretTable and HM.isSecretTable(innervate)
print(string.format("  [%s] %s  innervateOk=%s type=%s secret=%s  inCombat=%s",
    unit, tostring(UnitName(unit)), tostring(ok1), tostring(type(innervate)), tostring(innervateSecret), tostring(InCombatLockdown())))
```

### Commands.lua (`/hm raidregen`)
```lua
if healerData["test1"] then healerData["test1"].regenState = "innervate" end
```
(test1's innervate preview removed; test2's drinking preview kept)

### Commands.lua (printHelp)
```
/hm regendebug - TEMP: dump Innervate/Food&Drink detection for tracked units
/hm raidregen  - TEMP: preview the Innervate/Food&Drink icon swap on fake healers
```
(reworded to drop "Innervate" from both lines)

### Config.lua (Help tab)
```lua
{kind = "header", text = "Innervate / Eating & Drinking (Work in Progress)"},
{kind = "body", text = "In Icon style, a healer's icon is meant to swap to the Innervate or Food & Drink icon while they're regenerating mana that way. This feature is still a work in progress and doesn't work correctly yet."},
```
(reworded to describe only Food & Drink, since that part now works)
