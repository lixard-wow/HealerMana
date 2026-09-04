# Changelog

## Unreleased
- Added a Druid shapeshift-form indicator: while a healer Druid is in Cat, Bear, or Moonkin Form, their icon shows the actual Feral/Guardian/Balance icon (Icon style) or a colored [Cat]/[Bear]/[Moonkin] tag next to their name (Bar style), making it clear at a glance they're not actively healing. Cat and Bear Form now update correctly even during combat; Moonkin Form only updates outside of combat
- Mana % is now hidden while a Druid is in Cat or Bear Form, since neither uses mana as their active resource
- Fixed: a healer who is both dead and disconnected now shows "Offline" instead of "Dead", since being offline is the more important thing to notice
- Priest healers' icons now show up faster, show a generic class icon instead of a blank space while their exact spec is still resolving, and no longer flicker back and forth once resolved
- Confirmed: Food & Drink detection cannot work at all inside an active Mythic+ run (the whole run, not just active pulls) — this is a Blizzard restriction with no workaround, not a bug

## 1.0.3
- Fixed sliders in the settings panel getting their handle cut off when dragged all the way to the left or right edge
- Fixed Holy Priests sometimes showing the Discipline Priest icon instead of their own
- Fixed other players briefly flashing into the tracker before the addon could tell they weren't actually a healer — it now waits until it's sure before showing anyone
- Fixed a healer's icon sometimes showing an unrelated class's icon (like a Druid's Bear Form) instead of their own
- A healer's icon now correctly swaps to show Food & Drink while they're regenerating mana that way

## 1.0.2
- Fixed a bug where a dead healer wouldn't show as "Dead" right away, and could get stuck showing "Dead" after being revived
- Sort options simplified into a single Sort By choice (Alphabetical or Healer Class) instead of two separate toggles

## 1.0.1
- Added a Bars display style as an alternative to icons, with its own width, height, and texture options
- Settings panel reorganized into tabs (General, Layout, Fill Color, Background & Border, Text, Sort & Visibility, Help)
- Added a minimap icon — left-click opens settings, right-click toggles a fake-healer preview
- Added per-instance visibility toggles (open world, dungeons, raids, scenarios, battlegrounds, arenas) and a show-while-solo option
- Dead and offline healers are now clearly labeled instead of showing a stale mana reading
- Added a Help tab in settings explaining each option
- Bar color is now customizable: class color, a custom color, or color-by-mana (low/mid/high thresholds you can pick yourself)
- Background and border colors can now be customized
- Name and mana % text colors can now be customized
- Font can now be changed (uses any font your other addons make available) and font size can be manually overridden

## 1.0.0
- Release
