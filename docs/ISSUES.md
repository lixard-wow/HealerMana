# ISSUES

## Open
- None logged yet

## Fixed
- [FIXED] Bar still shows "Dead" after a healer is resurrected
  - Fixed in: PROMPT 7
  - Notes: UNIT_FLAGS was registered globally (RegisterEvent) instead of per-unit (RegisterUnitEvent), so it only fired for the player's own unit. Party/raid healers, including follower-dungeon NPC healers, never had d.dead re-checked after a revive. Reported repro was a follower dungeon; root cause is unrelated to follower dungeons specifically — same bug would hit any non-player healer in a normal group.

## Format
- [OPEN] Short title
  - Repro:
  - Notes:
  - Created by:

- [FIXED] Short title
  - Fixed in:
  - Notes:
