# TODO

## Active
- [ ] Remove the TEMP `/hm regendebug` and `/hm raidregen` slash commands (Commands.lua) once Innervate/Food & Drink icon-swap detection is confirmed working in real play (added PROMPT 56) — also remove their printHelp() lines
- [ ] Identify the remaining ~3 current-season Cooking "Tea" buff names (Core.lua's HM.FOOD_DRINK_NAMES has Mana Lily Tea + Argentleaf Tea confirmed so far, PROMPT 61) — run /hm regendebug while drinking an unconfirmed tea and add its name to the list once it prints a match
- [ ] Icon Tint Opacity slider past ~90 in `/hm raid <n>` test mode makes the fake healers fully vanish and they don't recover just by sliding back down (only a UI reload or `/hm raid off` then back on restores them). No visible Lua error, but user doesn't have Show Lua Errors / BugSack enabled, and errors inside C_Timer.After callbacks (where HM.refreshDisplay lives) are silent without one of those. Need `/console scriptErrors 1` (or BugSack) + a repro with the error text before this can be root-caused — no fix attempted yet, added during PROMPT 66 cleanup pass

## Backlog
- [ ] Click-to-battle-rez: clicking a dead healer's bar/icon casts the clicking player's own battle rez on them, regardless of the clicker's class (PROMPT 65, deferred at user's request — "save it for maybe later use"). Research already done, don't re-research:
  - Current battle-rez classes/spells (verified, not guessed): Druid Rebirth (20484), Death Knight Raise Ally (61999), Paladin Intercession (391054). Warlock Soulstone excluded (pre-death only, can't target a corpse). Hunters have no current brez.
  - Simple approach: convert bars to SecureActionButtonTemplate buttons with a static macro `/cast [@unit] Rebirth` + `/cast [@unit] Raise Ally` + `/cast [@unit] Intercession` as 3 lines — unknown spells silently no-op, so whichever the clicking player actually has just fires. No Lua class-detection needed.
  - Confirmed safe under WoW's secret-value restrictions: combat-res spells are explicitly whitelisted from that system (12.0.1+).
  - Real constraint (not fixable, not an addon bug): which real unit a secure button targets can only be set/changed OUTSIDE combat (protected attribute). So target assignment should refresh on each roster rebuild (already happens); a healer who joins brand-new mid-fight might not be click-ready until the next out-of-combat rebuild. Every click-cast raid addon (Clique, VuhDo, Cell) shares this limitation.
  - Open design question not yet decided: plain click vs. Shift+Click (or other modifier) to avoid accidental casts — recommended Shift+Click, not yet confirmed with user.
  - Known unconfirmed detail from research: whether there's a shared raid-wide brez charge pool currently limiting availability beyond the individual spell's own cooldown/charges — flagged as uncertain in the original research, would need in-game or BattleRezTracker-addon cross-check if pursued.

## Completed
- [ ] Move finished items here and mark with prompt number/date if desired
