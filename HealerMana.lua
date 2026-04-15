-- HealerMana.lua
-- Monitors healer mana for all healers in raids and dungeons.
-- Replacement for the WeakAura "Raid Mana Healer Castbar".
--
-- Slash commands:
--   /hm          - show help
--   /hm lock     - toggle click-through lock (lock during raids, unlock to move)
--   /hm alpha    - toggle alphabetical sort
--   /hm class    - toggle sort-by-class
--   /hm mana     - toggle sort-by-mana (ascending)
--   /hm reset    - reset frame to default position

local ADDON_NAME = "HealerMana"

-- ============================================================
-- Defaults
-- ============================================================
local DEFAULTS = {
    sortAlpha        = true,
    sortClass        = false,
    sortMana         = false,
    locked           = false,
    borderClassColor = true,   -- tint icon border with healer class colour
    cellSize         = 52,   -- square icon width/height
    cellSpacing      = 4,    -- gap between cells
    layoutHorizontal = false,  -- false = vertical stack, true = horizontal row
    showPctSymbol    = true,   -- append % after the mana number
    showName         = true,   -- show player name label below icon
    dimOutOfRange    = true,   -- dim icon when healer is out of spell range
    nameFontSize     = 10,     -- player name label font size
    pctFontSize      = 14,     -- mana percent font size
    point            = "CENTER",
    relPoint         = "CENTER",
    x                = 150,
    y                = 0,
}

-- ============================================================
-- Constants
-- ============================================================
local NAME_HEIGHT = 14   -- height of the name label below each icon
local BAR_HEIGHT  = 5    -- thin mana bar below the icon

-- Mana bar colours (RGBA 0-1)
local COL_LOW  = {0.765, 0.118, 0.231}   -- red    < 35 %
local COL_MID  = {1.000, 0.957, 0.408}   -- yellow  35-69 %
local COL_HIGH = {0.671, 0.831, 0.447}   -- green  >= 70 %

-- Name-text colours per healer class
local CLASS_COLOR = {
    DRUID   = {1.000, 0.490, 0.039},
    PALADIN = {0.961, 0.549, 0.729},
    PRIEST  = {1.000, 1.000, 1.000},
    SHAMAN  = {0.000, 0.439, 0.871},
    MONK    = {0.000, 1.000, 0.600},
    EVOKER  = {0.200, 0.580, 0.500},
}


-- ============================================================
-- State
-- ============================================================
local cfg          = {}          -- live config (merged from DEFAULTS + saved)
local healerData   = {}          -- [unitToken] = data table
local mainFrame                  -- root UI frame
local configFrame                -- settings panel
local eventFrame                 -- event listener frame (pre-declared for rebuildRoster)
local barPool      = {}          -- reusable bar frames
local refreshQueued = false

-- ============================================================
-- Helpers
-- ============================================================
local MANA = 0  -- Mana is always power type 0

-- issecretvalue is a WoW 12.0 C-level global; nil on older builds.
-- In WoW 12.0, UnitPower/UnitPowerMax for party/raid members returns a
-- "secret value". Secret values block ALL Lua operations (arithmetic, comparison,
-- string.format) with non-catchable errors. pcall does NOT protect against them.
--
-- THE FIX: UnitPowerPercent(unit, powerType, returnPercent, curveConstant) is the
-- dedicated 12.0 API that returns a PLAIN Lua number (not a secret) for any unit.
-- This is the same approach oUF/ElvUI uses for their [perpp] percent-power tag
-- (ElvUI_Libraries/Game/Shared/oUF/elements/tags.lua:374-388).
local _isSecret  = issecretvalue
local _wrapStr   = C_StringUtil and C_StringUtil.WrapString
local _scaleTo100 = CurveConstants and CurveConstants.ScaleTo100

-- Spells that target alive friendly players at ~40y range.
-- Used with C_Spell.IsSpellInRange (AllowedWhenTainted).
-- Classes with no such spells (DK, Warrior, Rogue, DH) fall through to
-- UnitInRange + issecretvalue/SetAlphaFromBoolean (same as ElvUI).
local RANGE_SPELLS_BY_CLASS = {
    DRUID       = {8936,   774,    5185  },  -- Regrowth, Rejuvenation, Healing Touch
    PALADIN     = {19750,  635,    85673 },  -- Flash of Light, Holy Light, Word of Glory
    PRIEST      = {17,     2061,   21562 },  -- Power Word: Shield, Flash Heal, Prayer of Fortitude
    SHAMAN      = {8004,   331,    1064  },  -- Healing Surge, Healing Wave, Chain Heal
    MONK        = {116670, 124682, 115451},  -- Vivify, Enveloping Mist, Renewing Mist
    EVOKER      = {361469, 355913, 382614},  -- Verdant Embrace, Emerald Blossom, Reversion
    MAGE        = {1459,   475            },  -- Arcane Intellect, Remove Curse
    WARLOCK     = {20707,  5697           },  -- Soulstone, Unending Breath
    HUNTER      = {34477                  },  -- Misdirection
    -- DEATHKNIGHT: Raise Ally (61999) only targets dead players → nil on alive targets.
    -- No usable friendly-target spell. Falls through to UnitInRange + SetAlphaFromBoolean.
    -- WARRIOR, ROGUE, DEMONHUNTER: no friendly-target range spells.
}
local rangeCheckSpell   -- set by detectRangeSpell()

-- Racial spells that target alive friendly players — work for any class of that race.
local RACIAL_RANGE_SPELLS = {
    28880,  -- Gift of the Naaru (Draenei)
    59543,  -- Gift of the Naaru (Draenei, alternate ID)
    69041,  -- Gift of the Naaru (Draenei, higher rank)
}

-- Use IsPlayerSpell to reliably detect if the player knows a spell.
-- Check class spells first, then cross-class racial spells as fallback.
local function detectRangeSpell()
    rangeCheckSpell = nil
    local _, class = UnitClass("player")
    local list = RANGE_SPELLS_BY_CLASS[class]
    if list then
        for _, id in ipairs(list) do
            if IsPlayerSpell(id) then
                rangeCheckSpell = id
                return
            end
        end
    end
    -- Racial fallback: e.g. Draenei DK has Gift of the Naaru (~40y, alive friendly target)
    for _, id in ipairs(RACIAL_RANGE_SPELLS) do
        if IsPlayerSpell(id) then
            rangeCheckSpell = id
            return
        end
    end
end

-- ── Range detection ───────────────────────────────────────────────────────────
-- WoW 12.0 introduced "secret values" — opaque booleans returned by UnitInRange()
-- in instanced/rated content. They cannot be compared in tainted addon code, but
-- WoW 12.0 added two APIs to handle them safely:
--   issecretvalue(v)                         — true if v is a secret value
--   Frame:SetAlphaFromBoolean(v, hi, lo)     — set alpha from a secret bool
-- This is the same approach ElvUI uses (via oUF:IsSecretValue / SetAlphaFromBoolean).

-- Returns the range status for a unit:
--   true        — confirmed in range (plain bool)
--   false       — confirmed out of range (plain bool)
--   secret bool — instanced content: pass to Frame:SetAlphaFromBoolean
--   nil         — unknown (treat as in-range to avoid false dimming)
local function isUnitInRange(unit)
    -- Priority 1: C_Spell.IsSpellInRange — AllowedWhenTainted, works for classes
    -- that have a learnable friendly-target spell (healers, mage, warlock, etc.).
    if rangeCheckSpell then
        local r = C_Spell.IsSpellInRange(rangeCheckSpell, unit)
        if r == true  then return true  end
        if r == false then return false end
    end
    -- Priority 2: UnitInRange — the same call ElvUI uses for all classes.
    -- Outside instances returns plain booleans. Inside instanced/rated content
    -- the second return (wasChecked) is a secret value; issecretvalue() detects
    -- this safely without comparing the value. We return the raw secret inRange
    -- boolean so renderBar can pass it to Frame:SetAlphaFromBoolean, which reads
    -- secret booleans internally without causing taint errors.
    local inRange, checked = UnitInRange(unit)
    if issecretvalue and issecretvalue(checked) then
        return inRange  -- secret bool — let SetAlphaFromBoolean handle it
    elseif checked then
        return inRange and true or false
    end
    -- Cannot determine range — return nil so caller doesn't falsely dim.
    return nil
end

local function isHealer(unit)
    return UnitExists(unit) and UnitGroupRolesAssigned(unit) == "HEALER"
end

-- Healer spec IDs — one per class (Priest defaults to Holy; both heal the same)
local HEALER_SPEC_ID = {
    DRUID   = {105},        -- Restoration
    PALADIN = {65},         -- Holy
    PRIEST  = {256, 257},   -- Discipline, Holy (both are healer specs)
    SHAMAN  = {264},        -- Restoration
    MONK    = {270},        -- Mistweaver
    EVOKER  = {1468},       -- Preservation
}

-- classSpecIcon[classToken] = FileDataID, built at load time from WoW's own data
-- For classes with multiple healer specs (e.g. Priest), uses the first valid icon
-- as a fallback; GetInspectSpecialization gives the real spec once inspected.
local classSpecIcon = {}
local function buildSpecIcons()
    wipe(classSpecIcon)
    for class, specIDs in pairs(HEALER_SPEC_ID) do
        for _, specID in ipairs(specIDs) do
            local ok, _, _, _, icon = pcall(GetSpecializationInfoByID, specID)
            if ok and icon then
                classSpecIcon[class] = icon
                break  -- use first valid spec as class fallback
            end
        end
    end
end

-- Returns the best spec icon FileDataID for a healer unit
local function getSpecIcon(unit, classToken)
    if UnitIsUnit(unit, "player") then
        local specIdx = GetSpecialization()
        if specIdx then
            local ok, _, _, _, icon = pcall(GetSpecializationInfo, specIdx)
            if ok and icon then return icon end
        end
    else
        -- GetInspectSpecialization works passively for nearby group members
        local ok, specID = pcall(GetInspectSpecialization, unit)
        if ok and type(specID) == "number" and specID > 0 then
            local ok2, _, _, _, icon = pcall(GetSpecializationInfoByID, specID)
            if ok2 and icon then return icon end
        end
    end
    return classSpecIcon[classToken]  -- fallback: class healer spec icon
end

-- Snapshot one unit's current state.
local function snapshotUnit(unit)
    if not UnitExists(unit) then return nil end
    local name          = UnitName(unit)
    local _, classToken = UnitClass(unit)
    return {
        unit      = unit,
        name      = name or "?",
        class     = classToken or "",
        specIcon  = getSpecIcon(unit, classToken),
        connected = UnitIsConnected(unit),
        dead      = UnitIsDeadOrGhost(unit),
    }
end

-- ============================================================
-- Roster management
-- ============================================================
local function rebuildRoster()
    wipe(healerData)
    if IsInRaid() then
        local n = GetNumGroupMembers()
        for i = 1, n do
            local unit = "raid" .. i
            if isHealer(unit) then
                healerData[unit] = snapshotUnit(unit)
            end
        end
    elseif IsInGroup() then
        -- Party: "player" + party1..party(n-1)
        if isHealer("player") then
            healerData["player"] = snapshotUnit("player")
        end
        local n = GetNumGroupMembers() - 1   -- excludes self
        for i = 1, n do
            local unit = "party" .. i
            if isHealer(unit) then
                healerData[unit] = snapshotUnit(unit)
            end
        end
    end

    -- Re-register unit events for exactly the current healer set.
    -- RegisterEvent only delivers player events; party/raid units need RegisterUnitEvent.
    eventFrame:UnregisterEvent("UNIT_POWER_FREQUENT")
    eventFrame:UnregisterEvent("UNIT_IN_RANGE_UPDATE")
    for unit in pairs(healerData) do
        eventFrame:RegisterUnitEvent("UNIT_POWER_FREQUENT", unit)
        eventFrame:RegisterUnitEvent("UNIT_IN_RANGE_UPDATE", unit)
    end
    -- Request spec data for each non-player healer so INSPECT_READY fires and
    -- getSpecIcon can return the real spec icon instead of the class fallback.
    -- Stagger 0.5 s apart to avoid throttling on large rosters.
    local delay = 0.2
    for unit in pairs(healerData) do
        if not UnitIsUnit(unit, "player") then
            local u = unit  -- capture for closure
            C_Timer.After(delay, function()
                if UnitExists(u) and healerData[u] then
                    NotifyInspect(u)
                end
            end)
            delay = delay + 0.5
        end
    end
end

-- ============================================================
-- Mana % reader (WoW 12.0 secret-value handling)
-- ============================================================
-- WoW 12.0 makes UnitPower / UnitPowerPercent return "secret values" for any
-- grouped unit (including the player when grouped). You CANNOT do arithmetic,
-- comparison, concatenation, or string.format("%d", ...) on them.
--
-- ElvUI/oUF's solution (which actually works in 12.0):
--   1. Get the value with pcall, accept that it might be a secret value.
--   2. NEVER touch it in Lua. Don't math it, don't concat it, don't format it.
--   3. Pass it straight to FontString:SetFormattedText("%s%%", WrapString(v))
--      — the C rendering layer accepts wrapped secret values and unwraps them
--      for display.
-- Reference: ElvUI_Libraries/Game/Shared/oUF/elements/tags.lua:693-751
--   CreateTagFunc detects secret returns from tag functions and wraps them
--   with C_StringUtil.WrapString; the tag Update function then writes the
--   buffer to the FontString via SetFormattedText, which renders it correctly.
--
-- Side effect: because we never get a plain number, we cannot apply the
-- low/mid/high colour gradient on the icon tint for grouped units.

-- Returns the raw value from UnitPowerPercent. May be a plain number (player
-- when ungrouped, older builds) or a "secret value" object (grouped units in
-- 12.0). Either way, it's safe to feed to WrapString + SetFormattedText.
local function readUnitPctRaw(unit)
    local ok, pct = pcall(UnitPowerPercent, unit, MANA, true, _scaleTo100)
    if ok then return pct end
    -- Older builds: try the 2-arg form
    local ok2, pct2 = pcall(UnitPowerPercent, unit, MANA)
    if ok2 then return pct2 end
    return nil
end

-- Detect a plain Lua number (not a secret) so we can apply the colour gradient.
local function isPlainNumber(v)
    if type(v) ~= "number" then return false end
    if _isSecret and _isSecret(v) then return false end
    return true
end

local function updateUnit(unit)
    if not healerData[unit] then return end
    local d          = healerData[unit]
    d.specIcon  = getSpecIcon(unit, d.class)
    d.connected = UnitIsConnected(unit)
    d.dead      = UnitIsDeadOrGhost(unit)
end

-- ============================================================
-- Sort
-- ============================================================
local sortBuf = {}
local function getSorted()
    wipe(sortBuf)
    for unit, data in pairs(healerData) do
        sortBuf[#sortBuf + 1] = {unit = unit, data = data}
    end
    table.sort(sortBuf, function(a, b)
        local ad, bd = a.data, b.data
        if cfg.sortClass and ad.class ~= bd.class then
            return ad.class < bd.class
        end
        -- NOTE: mana-sort is disabled in 12.0 because the percent is a
        -- "secret value" that can't be compared. Falls through to alpha.
        return (ad.name or "") <= (bd.name or "")
    end)
    return sortBuf
end

-- ============================================================
-- UI – cell creation
-- Each healer = square class icon  +  % text centered on it  +  name below
-- ============================================================
local function createBar(idx)
    local cs      = cfg.cellSize
    local nameH   = cfg.showName and (NAME_HEIGHT + 2) or 0
    local bar = CreateFrame("Frame", nil, mainFrame)
    bar:SetSize(cs, cs + nameH)

    -- Dark background behind the icon
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    bar.bg:SetSize(cs, cs)
    bar.bg:SetColorTexture(0, 0, 0, 0.6)

    -- Class / regen icon — fills the square
    bar.icon = bar:CreateTexture(nil, "ARTWORK")
    bar.icon:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    bar.icon:SetSize(cs, cs)

    -- Subtle colour tint over the icon based on mana level
    bar.tint = bar:CreateTexture(nil, "OVERLAY")
    bar.tint:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    bar.tint:SetSize(cs, cs)
    bar.tint:SetTexture("Interface\\BUTTONS\\WHITE8X8")
    bar.tint:SetBlendMode("BLEND")
    bar.tint:SetAlpha(0.22)

    -- Tooltip-style border around the icon square
    bar.border = CreateFrame("Frame", nil, bar, "BackdropTemplate")
    bar.border:SetPoint("TOPLEFT", bar.icon, "TOPLEFT", -4, 4)
    bar.border:SetPoint("BOTTOMRIGHT", bar.icon, "BOTTOMRIGHT", 4, -4)
    bar.border:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    bar.border:SetBackdropBorderColor(0.85, 0.85, 0.85, 1)  -- overwritten per-render with class colour

    -- % text: anchored by TOPLEFT so there's no ambiguity, positioned at icon centre
    local pctFs = cfg.pctFontSize
    bar.pctTxt = bar:CreateFontString(nil, "OVERLAY")
    bar.pctTxt:SetFont(STANDARD_TEXT_FONT, pctFs, "THICKOUTLINE")
    bar.pctTxt:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, -(cs / 2 - pctFs / 2))
    bar.pctTxt:SetWidth(cs)
    bar.pctTxt:SetJustifyH("CENTER")

    -- Name label directly below the icon (only when showName is enabled)
    if cfg.showName then
        local nameFs = cfg.nameFontSize
        bar.nameTxt = bar:CreateFontString(nil, "OVERLAY")
        bar.nameTxt:SetFont(STANDARD_TEXT_FONT, nameFs, "OUTLINE")
        bar.nameTxt:SetPoint("TOPLEFT", bar.icon, "BOTTOMLEFT", 0, -2)
        bar.nameTxt:SetWidth(cs)
        bar.nameTxt:SetJustifyH("CENTER")
        bar.nameTxt:SetWordWrap(false)
    end

    barPool[idx] = bar
    return bar
end

local function getBar(idx)
    return barPool[idx] or createBar(idx)
end

-- BORDER_OVERHANG: the icon border frame extends 4px outside the icon on each
-- side (SetPoint TOPLEFT -4,4 / BOTTOMRIGHT 4,-4).  In horizontal layout the
-- step must include this 8px total overhang so adjacent borders don't overlap.
-- Vertical layout naturally absorbs it via nameH (≥16px when name is visible).
local BORDER_OVERHANG = 8  -- 4px left + 4px right (or top + bottom)

local function positionBar(bar, idx)
    bar:ClearAllPoints()
    local cs    = cfg.cellSize
    local gap   = cfg.cellSpacing
    local nameH = cfg.showName and (NAME_HEIGHT + 2) or 0
    if cfg.layoutHorizontal then
        -- step = icon width + border overhang + gap: gap=0 means borders touching
        local step = cs + BORDER_OVERHANG + gap
        bar:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", (idx - 1) * step, 0)
    else
        bar:SetPoint("TOPLEFT", mainFrame, "TOPLEFT",
            0, -(idx - 1) * (cs + nameH + gap))
    end
end

local function getManaColor(pct)
    if pct < 35 then
        return COL_LOW[1],  COL_LOW[2],  COL_LOW[3]
    elseif pct < 70 then
        return COL_MID[1],  COL_MID[2],  COL_MID[3]
    else
        return COL_HIGH[1], COL_HIGH[2], COL_HIGH[3]
    end
end

local function renderBar(bar, data)
    -- Out-of-range: dim the entire bar frame.
    -- Uses C_Spell.IsSpellInRange (AllowedWhenTainted) so this works even when
    -- the addon's code path is tainted during combat.
    if cfg.dimOutOfRange and not UnitIsUnit(data.unit, "player") then
        local inRange = isUnitInRange(data.unit)
        if issecretvalue and issecretvalue(inRange) then
            -- Secret bool from UnitInRange (instanced content) — use the Blizzard
            -- API that can read secret values without causing taint errors.
            -- Same approach as ElvUI / oUF SetAlphaFromBoolean.
            bar:SetAlphaFromBoolean(inRange, 1, 0.35)
        elseif inRange == false then
            bar:SetAlpha(0.35)
        else
            bar:SetAlpha(1)  -- true or nil (unknown) → full alpha
        end
    else
        bar:SetAlpha(1)
    end

    local iconID = data.specIcon
    if iconID then
        bar.icon:SetTexture(iconID)
        bar.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- trim default icon border
    end

    -- Name text + border
    local cc = CLASS_COLOR[data.class]
    if bar.nameTxt then
        bar.nameTxt:SetText(data.name)
        if cc then
            bar.nameTxt:SetTextColor(cc[1], cc[2], cc[3])
        else
            bar.nameTxt:SetTextColor(0.85, 0.85, 0.85)
        end
    end
    if cc then
        if cfg.borderClassColor then
            bar.border:SetBackdropBorderColor(cc[1], cc[2], cc[3], 1)
        else
            bar.border:SetBackdropBorderColor(0.85, 0.85, 0.85, 1)
        end
    else
        bar.border:SetBackdropBorderColor(0.85, 0.85, 0.85, 1)
    end

    -- % text centered on the icon
    if data.dead then
        bar.pctTxt:SetText("Dead")
        bar.pctTxt:SetTextColor(0.9, 0.3, 0.3)
        bar.icon:SetAlpha(0.4)
        bar.tint:SetColorTexture(0.4, 0.4, 0.4)
        bar.tint:SetAlpha(0.22)
    elseif not data.connected then
        bar.pctTxt:SetText("DC")
        bar.pctTxt:SetTextColor(0.6, 0.6, 0.6)
        bar.icon:SetAlpha(0.4)
        bar.tint:SetColorTexture(0.4, 0.4, 0.4)
        bar.tint:SetAlpha(0.22)
    else
        bar.icon:SetAlpha(1)
        bar.pctTxt:SetTextColor(1, 1, 1)

        -- Read fresh each render. The result is either:
        --   - a plain Lua number 0-100 (player when ungrouped, older builds), or
        --   - a "secret value" (any grouped unit on 12.0).
        -- For plain numbers we display normally and apply the colour gradient.
        -- For secret values we route through SetFormattedText + WrapString;
        -- the C rendering layer unwraps and displays the actual percent. We
        -- can't compare a secret to thresholds, so the gradient is skipped.
        local pct = readUnitPctRaw(data.unit)

        if isPlainNumber(pct) then
            local p = math.floor(pct + 0.5)
            bar.pctTxt:SetText(cfg.showPctSymbol and (p .. "%") or tostring(p))
            local r, g, b = getManaColor(p)
            bar.tint:SetColorTexture(r, g, b)
            bar.tint:SetAlpha(0.22)
        elseif pct ~= nil and _wrapStr then
            -- Secret value path — mirrors ElvUI's E:GetFormattedText at
            -- ElvUI/Game/Shared/General/Math.lua:319-338. format() works on
            -- secret numbers in 12.0 (they propagate, not error), returning
            -- a secret-marked string with the precision baked in. We then
            -- route through WrapString + SetFormattedText for display.
            -- %.0f = whole percent — keeps the text short enough to fit in
            -- the 52px icon cell (otherwise "100.0%" overflows).
            local formatted = cfg.showPctSymbol and format("%.0f%%", pct) or format("%.0f", pct)
            bar.pctTxt:SetFormattedText("%s", _wrapStr(formatted, "", ""))
            bar.tint:SetColorTexture(0.45, 0.45, 0.55)  -- neutral tint
            bar.tint:SetAlpha(0.22)
        else
            bar.pctTxt:SetText("")
            bar.tint:SetColorTexture(0.4, 0.4, 0.4)
            bar.tint:SetAlpha(0.22)
        end
    end

    bar:Show()
end

-- ============================================================
-- Display refresh (deferred to coalesce rapid-fire events)
-- ============================================================
local function refreshDisplay()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0, function()
        refreshQueued = false

        local sorted = getSorted()
        local count  = #sorted
        local cs     = cfg.cellSize
        local gap    = cfg.cellSpacing
        local nameH  = cfg.showName and (NAME_HEIGHT + 2) or 0
        local cellH  = cs + nameH
        local totalW, totalH
        if cfg.layoutHorizontal then
            -- (count-1) full steps + last icon width (no trailing gap/overhang)
            local step = cs + BORDER_OVERHANG + gap
            totalW = count > 0 and ((count - 1) * step + cs) or 1
            totalH = cellH
        else
            totalW = cs
            totalH = count > 0 and (count * (cellH + gap) - gap) or 1
        end

        mainFrame:SetSize(totalW, totalH)

        for i, entry in ipairs(sorted) do
            local bar = getBar(i)
            positionBar(bar, i)
            renderBar(bar, entry.data)
        end

        -- Hide surplus bars
        for i = count + 1, #barPool do
            barPool[i]:Hide()
        end

        if count > 0 then mainFrame:Show() else mainFrame:Hide() end
    end)
end

-- ============================================================
-- Main frame creation
-- ============================================================
local function createMainFrame()
    mainFrame = CreateFrame("Frame", "HealerManaFrame", UIParent)
    mainFrame:SetFrameStrata("MEDIUM")
    mainFrame:SetMovable(true)
    mainFrame:SetClampedToScreen(true)
    mainFrame:EnableMouse(not cfg.locked)

    mainFrame:SetPoint(cfg.point, UIParent, cfg.relPoint, cfg.x, cfg.y)

    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", function(self)
        if not cfg.locked then self:StartMoving() end
    end)
    mainFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        cfg.point    = p
        cfg.relPoint = rp
        cfg.x        = x
        cfg.y        = y
        -- Persist immediately
        HealerManaDB.point    = p
        HealerManaDB.relPoint = rp
        HealerManaDB.x        = x
        HealerManaDB.y        = y
    end)

    mainFrame:Hide()
end

-- ============================================================
-- Config UI
-- ============================================================
local function saveKey(key, value)
    cfg[key] = value
    HealerManaDB[key] = value
end

local function createConfigFrame()
    -- ── Palette ───────────────────────────────────────────────
    local BG      = {0.06, 0.06, 0.06, 0.98}
    local TITLE   = {0.08, 0.08, 0.08, 1.00}
    local GROUP   = {0.09, 0.09, 0.09, 0.85}
    local BTN     = {0.12, 0.12, 0.12, 1.00}
    local BTN_HOV = {0.20, 0.20, 0.20, 1.00}
    local BORDER  = {0.22, 0.22, 0.22}
    local MUTED   = {0.70, 0.70, 0.70}
    local PRIMARY = {0.92, 0.91, 0.86}
    local ACCENT  = {0.78, 0.66, 0.22}

    -- 1-pixel border drawn as four texture lines
    local function addBorder(frame)
        local function edge(a, b, horiz)
            local t = frame:CreateTexture(nil, "BORDER")
            t:SetPoint(a, frame, a)
            t:SetPoint(b, frame, b)
            if horiz then t:SetHeight(1) else t:SetWidth(1) end
            t:SetColorTexture(BORDER[1], BORDER[2], BORDER[3], 1)
        end
        edge("TOPLEFT",    "TOPRIGHT",    true)
        edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
        edge("TOPLEFT",    "BOTTOMLEFT",  false)
        edge("TOPRIGHT",   "BOTTOMRIGHT", false)
    end

    -- Flat dark button (hover brightens, text lightens)
    local function flatBtn(parent, text, w, h)
        local btn = CreateFrame("Button", nil, parent)
        btn:SetSize(w or 100, h or 24)
        btn.bg = btn:CreateTexture(nil, "BACKGROUND")
        btn.bg:SetAllPoints()
        btn.bg:SetColorTexture(BTN[1], BTN[2], BTN[3], BTN[4])
        addBorder(btn)
        btn.lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        btn.lbl:SetPoint("CENTER")
        btn.lbl:SetText(text or "")
        btn.lbl:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
        btn:SetScript("OnEnter", function(self)
            self.bg:SetColorTexture(BTN_HOV[1], BTN_HOV[2], BTN_HOV[3], BTN_HOV[4])
            self.lbl:SetTextColor(PRIMARY[1], PRIMARY[2], PRIMARY[3])
        end)
        btn:SetScript("OnLeave", function(self)
            self.bg:SetColorTexture(BTN[1], BTN[2], BTN[3], BTN[4])
            self.lbl:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
        end)
        return btn
    end

    -- Custom toggle: small box + gold fill check
    local function makeToggle(parent, labelText, getVal, onToggle)
        local BOX = 14
        local tog = CreateFrame("Button", nil, parent)
        tog:SetHeight(BOX)
        tog:EnableMouse(true)
        tog:RegisterForClicks("LeftButtonUp")

        local box = CreateFrame("Frame", nil, tog)
        box:SetSize(BOX, BOX)
        box:SetPoint("LEFT", tog, "LEFT", 0, 0)
        box.bg = box:CreateTexture(nil, "BACKGROUND")
        box.bg:SetAllPoints()
        box.bg:SetColorTexture(0.08, 0.08, 0.08, 1)
        addBorder(box)

        local check = box:CreateTexture(nil, "ARTWORK")
        check:SetPoint("TOPLEFT",     box, "TOPLEFT",     3, -3)
        check:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -3,  3)
        check:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.9)
        check:SetShown(getVal() == true)

        local lbl = tog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", box, "RIGHT", 6, 0)
        lbl:SetText(labelText or "")
        lbl:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
        tog:SetWidth(BOX + 6 + (lbl:GetStringWidth() or 100) + 8)

        tog._checked = (getVal() == true)
        function tog:SetChecked(v)
            self._checked = (v == true)
            check:SetShown(self._checked)
        end
        function tog:GetChecked() return self._checked end

        tog:SetScript("OnClick", function(self)
            self:SetChecked(not self:GetChecked())
            onToggle(self:GetChecked())
        end)
        return tog
    end

    -- Custom slider: label + value text + flat fill track + thumb
    local function makeSlider(parent, labelText, minVal, maxVal, stepVal, onChange)
        local TRACK_H = 4
        local s = CreateFrame("Frame", nil, parent)
        s:SetHeight(36)

        s.lbl = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        s.lbl:SetPoint("TOPLEFT", s, "TOPLEFT", 0, 0)
        s.lbl:SetText(labelText or "")
        s.lbl:SetTextColor(MUTED[1], MUTED[2], MUTED[3])

        s.valTxt = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        s.valTxt:SetPoint("TOPRIGHT", s, "TOPRIGHT", 0, 0)
        s.valTxt:SetJustifyH("RIGHT")
        s.valTxt:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])

        local track = CreateFrame("Frame", nil, s)
        track:SetPoint("BOTTOMLEFT",  s, "BOTTOMLEFT",  0, 4)
        track:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", 0, 4)
        track:SetHeight(TRACK_H)
        track.bg = track:CreateTexture(nil, "BACKGROUND")
        track.bg:SetAllPoints()
        track.bg:SetColorTexture(0.18, 0.18, 0.18, 1)
        addBorder(track)

        local fill = track:CreateTexture(nil, "ARTWORK")
        fill:SetPoint("LEFT", track, "LEFT", 0, 0)
        fill:SetHeight(TRACK_H)
        fill:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.7)

        local thumb = CreateFrame("Frame", nil, track)
        thumb:SetSize(8, 8)
        thumb:SetFrameLevel(track:GetFrameLevel() + 1)
        thumb.bg = thumb:CreateTexture(nil, "ARTWORK")
        thumb.bg:SetAllPoints()
        thumb.bg:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.95)

        local hit = CreateFrame("Button", nil, track)
        hit:SetPoint("TOPLEFT",     track, "TOPLEFT",     -4,  6)
        hit:SetPoint("BOTTOMRIGHT", track, "BOTTOMRIGHT",  4, -6)
        hit:EnableMouse(true)
        hit:RegisterForClicks("LeftButtonDown", "LeftButtonUp")

        s._min = minVal;  s._max = maxVal
        s._step = stepVal;  s._value = minVal

        local function snap(v)
            if stepVal and stepVal > 0 then
                return minVal + math.floor((v - minVal) / stepVal + 0.5) * stepVal
            end
            return v
        end
        local function redraw()
            local w = track:GetWidth()
            if not w or w <= 1 then return end
            local t = (maxVal > minVal) and ((s._value - minVal) / (maxVal - minVal)) or 0
            t = math.max(0, math.min(1, t))
            fill:SetWidth(math.max(w * t, 1))
            thumb:ClearAllPoints()
            thumb:SetPoint("CENTER", track, "LEFT", w * t, 0)
            s.valTxt:SetText(tostring(s._value))
        end
        function s:SetValue(v)
            v = snap(math.max(minVal, math.min(maxVal, tonumber(v) or minVal)))
            s._value = v; redraw()
        end
        function s:GetValue() return s._value end

        local function fromCursor()
            local x = select(1, GetCursorPosition()) / hit:GetEffectiveScale()
            local l, r = hit:GetLeft() or 0, hit:GetRight() or 1
            if r <= l then return minVal end
            return minVal + math.max(0, math.min(1, (x - l) / (r - l))) * (maxVal - minVal)
        end
        local dragging = false
        hit:SetScript("OnMouseDown", function()
            dragging = true
            s:SetValue(snap(fromCursor())); onChange(s._value)
            s:SetScript("OnUpdate", function()
                if dragging then
                    local v = snap(fromCursor())
                    if v ~= s._value then s:SetValue(v); onChange(s._value) end
                end
            end)
        end)
        hit:SetScript("OnMouseUp", function()
            dragging = false; s:SetScript("OnUpdate", nil)
        end)
        track:HookScript("OnSizeChanged", redraw)
        s:SetValue(minVal)
        return s
    end

    -- Group box with gold title label
    local function makeGroup(parent, title)
        local g = CreateFrame("Frame", nil, parent)
        g.bg = g:CreateTexture(nil, "BACKGROUND")
        g.bg:SetAllPoints()
        g.bg:SetColorTexture(GROUP[1], GROUP[2], GROUP[3], GROUP[4])
        addBorder(g)
        if title then
            g.hdr = g:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            g.hdr:SetPoint("TOPLEFT", g, "TOPLEFT", 8, -6)
            g.hdr:SetText(title)
            g.hdr:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
        end
        g.content = CreateFrame("Frame", nil, g)
        g.content:SetPoint("TOPLEFT",     g, "TOPLEFT",     8, title and -22 or -8)
        g.content:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", -8, 8)
        return g
    end

    -- ── Main frame ────────────────────────────────────────────
    local f = CreateFrame("Frame", "HealerManaConfig", UIParent)
    f:SetSize(300, 520)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)

    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(BG[1], BG[2], BG[3], BG[4])
    addBorder(f)

    -- Title bar (drag handle)
    local titleBar = CreateFrame("Frame", nil, f)
    titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    titleBar:SetHeight(32)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
    titleBar:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)
    titleBar.bg = titleBar:CreateTexture(nil, "BACKGROUND")
    titleBar.bg:SetAllPoints()
    titleBar.bg:SetColorTexture(TITLE[1], TITLE[2], TITLE[3], TITLE[4])
    local barDiv = titleBar:CreateTexture(nil, "BORDER")
    barDiv:SetPoint("BOTTOMLEFT",  titleBar, "BOTTOMLEFT",  0, 0)
    barDiv:SetPoint("BOTTOMRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
    barDiv:SetHeight(1)
    barDiv:SetColorTexture(BORDER[1], BORDER[2], BORDER[3], 1)

    local titleLbl = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleLbl:SetPoint("LEFT", titleBar, "LEFT", 12, 0)
    titleLbl:SetText("HealerMana")
    titleLbl:SetTextColor(PRIMARY[1], PRIMARY[2], PRIMARY[3])

    -- × close button (red on hover)
    local xBtn = CreateFrame("Button", nil, titleBar, "BackdropTemplate")
    xBtn:SetSize(24, 24)
    xBtn:SetPoint("RIGHT", titleBar, "RIGHT", -8, 0)
    xBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8",
                       edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    xBtn:SetBackdropColor(0.15, 0.15, 0.15, 1)
    xBtn:SetBackdropBorderColor(BORDER[1], BORDER[2], BORDER[3], 1)
    xBtn.x = xBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    xBtn.x:SetPoint("CENTER", 0, 0)
    xBtn.x:SetFont(STANDARD_TEXT_FONT, 18, "")
    xBtn.x:SetText("×")
    xBtn.x:SetTextColor(0.8, 0.8, 0.8)
    xBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.5, 0.1, 0.1, 1)
        self:SetBackdropBorderColor(0.8, 0.2, 0.2, 1)
        self.x:SetTextColor(1, 1, 1)
    end)
    xBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.15, 0.15, 0.15, 1)
        self:SetBackdropBorderColor(BORDER[1], BORDER[2], BORDER[3], 1)
        self.x:SetTextColor(0.8, 0.8, 0.8)
    end)
    xBtn:SetScript("OnClick", function() f:Hide() end)

    -- Footer
    local footer = CreateFrame("Frame", nil, f)
    footer:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  0, 0)
    footer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    footer:SetHeight(44)
    footer.bg = footer:CreateTexture(nil, "BACKGROUND")
    footer.bg:SetAllPoints()
    footer.bg:SetColorTexture(TITLE[1], TITLE[2], TITLE[3], TITLE[4])
    local footDiv = footer:CreateTexture(nil, "BORDER")
    footDiv:SetPoint("TOPLEFT",  footer, "TOPLEFT",  0, 0)
    footDiv:SetPoint("TOPRIGHT", footer, "TOPRIGHT", 0, 0)
    footDiv:SetHeight(1)
    footDiv:SetColorTexture(BORDER[1], BORDER[2], BORDER[3], 1)

    local resetBtn = flatBtn(footer, "Reset Position", 120, 24)
    resetBtn:SetPoint("LEFT", footer, "LEFT", 12, 0)
    resetBtn:SetScript("OnClick", function()
        mainFrame:ClearAllPoints()
        mainFrame:SetPoint(DEFAULTS.point, UIParent, DEFAULTS.relPoint, DEFAULTS.x, DEFAULTS.y)
        cfg.point    = DEFAULTS.point;    HealerManaDB.point    = nil
        cfg.relPoint = DEFAULTS.relPoint; HealerManaDB.relPoint = nil
        cfg.x        = DEFAULTS.x;        HealerManaDB.x        = nil
        cfg.y        = DEFAULTS.y;        HealerManaDB.y        = nil
        print("|cff00ccffHealerMana|r: position reset.")
    end)

    local closeFootBtn = flatBtn(footer, "Close", 80, 24)
    closeFootBtn:SetPoint("RIGHT", footer, "RIGHT", -12, 0)
    closeFootBtn:SetScript("OnClick", function() f:Hide() end)

    -- Scrollable content area between title bar and footer
    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT",     titleBar, "BOTTOMLEFT",  12, -8)
    scroll:SetPoint("BOTTOMRIGHT", footer,   "TOPRIGHT",   -12,  8)
    scroll:EnableMouseWheel(true)

    local content = CreateFrame("Frame", nil, scroll)
    scroll:SetScrollChild(content)
    content:SetPoint("TOPLEFT")
    content:SetWidth(1)
    scroll:HookScript("OnSizeChanged", function(self)
        content:SetWidth(self:GetWidth())
    end)
    scroll:SetScript("OnMouseWheel", function(self, d)
        local cur = self:GetVerticalScroll()
        local max = math.max(0, (content:GetHeight() or 0) - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(max, cur - d * 40)))
    end)

    -- ── Content layout constants ──────────────────────────────
    -- innerH formula for a group: 12 + 22*nToggles + 44*nSliders
    --   12 = top(6) + bottom(6) inner padding
    --   22 = toggle height(18) + gap(4)
    --   44 = slider height(36) + gap(8)
    -- groupH = innerH + 30  (22 header + 8 bottom offset in makeGroup)
    local GROUP_GAP = 8
    local contentY  = 0  -- tracks cumulative top-of-next-group

    local function placeGroup(title, nT, nS)
        local innerH = 12 + nT * 22 + nS * 44
        local groupH = innerH + 30
        local g = makeGroup(content, title)
        g:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -contentY)
        g:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -contentY)
        g:SetHeight(groupH)
        contentY = contentY + groupH + GROUP_GAP
        return g
    end

    -- ── Sort Order ────────────────────────────────────────────
    local sortG = placeGroup("Sort Order", 2, 0)
    local iy = -6  -- inner y cursor (relative to group.content TOPLEFT)

    local cbAlpha = makeToggle(sortG.content, "Alphabetical",
        function() return cfg.sortAlpha end,
        function(v) saveKey("sortAlpha", v); refreshDisplay() end)
    cbAlpha:SetPoint("TOPLEFT", sortG.content, "TOPLEFT", 0, iy); iy = iy - 22

    local cbClass = makeToggle(sortG.content, "By healer class",
        function() return cfg.sortClass end,
        function(v) saveKey("sortClass", v); refreshDisplay() end)
    cbClass:SetPoint("TOPLEFT", sortG.content, "TOPLEFT", 0, iy)

    -- ── Display ───────────────────────────────────────────────
    local dispG = placeGroup("Display", 5, 0)
    iy = -6

    local cbLock = makeToggle(dispG.content, "Lock frame (click-through)",
        function() return cfg.locked end,
        function(v) saveKey("locked", v); mainFrame:EnableMouse(not cfg.locked) end)
    cbLock:SetPoint("TOPLEFT", dispG.content, "TOPLEFT", 0, iy); iy = iy - 22

    local cbBorderColor = makeToggle(dispG.content, "Class color border",
        function() return cfg.borderClassColor end,
        function(v) saveKey("borderClassColor", v); refreshDisplay() end)
    cbBorderColor:SetPoint("TOPLEFT", dispG.content, "TOPLEFT", 0, iy); iy = iy - 22

    local cbPctSymbol = makeToggle(dispG.content, "Show % symbol",
        function() return cfg.showPctSymbol end,
        function(v) saveKey("showPctSymbol", v); refreshDisplay() end)
    cbPctSymbol:SetPoint("TOPLEFT", dispG.content, "TOPLEFT", 0, iy); iy = iy - 22

    local cbShowName = makeToggle(dispG.content, "Show player name",
        function() return cfg.showName end,
        function(v)
            saveKey("showName", v)
            for _, b in ipairs(barPool) do b:Hide() end
            wipe(barPool); refreshDisplay()
        end)
    cbShowName:SetPoint("TOPLEFT", dispG.content, "TOPLEFT", 0, iy); iy = iy - 22

    local cbDimRange = makeToggle(dispG.content, "Dim when out of range",
        function() return cfg.dimOutOfRange end,
        function(v) saveKey("dimOutOfRange", v); refreshDisplay() end)
    cbDimRange:SetPoint("TOPLEFT", dispG.content, "TOPLEFT", 0, iy)

    -- ── Size ──────────────────────────────────────────────────
    local sizeG = placeGroup("Size", 0, 2)
    iy = -6

    local sizeSlider = makeSlider(sizeG.content, "Icon Size", 30, 60, 1,
        function(val)
            if val == cfg.cellSize then return end
            saveKey("cellSize", val)
            for _, b in ipairs(barPool) do b:Hide() end
            wipe(barPool); refreshDisplay()
        end)
    sizeSlider:SetPoint("TOPLEFT",  sizeG.content, "TOPLEFT",  0, iy)
    sizeSlider:SetPoint("TOPRIGHT", sizeG.content, "TOPRIGHT", 0, iy)
    sizeSlider:SetValue(cfg.cellSize)
    iy = iy - 44

    local function gapLabel() return cfg.layoutHorizontal and "Horizontal Spacing" or "Vertical Spacing" end
    local gapSlider = makeSlider(sizeG.content, gapLabel(), 0, 16, 1,
        function(val)
            if val == cfg.cellSpacing then return end
            saveKey("cellSpacing", val); refreshDisplay()
        end)
    gapSlider:SetPoint("TOPLEFT",  sizeG.content, "TOPLEFT",  0, iy)
    gapSlider:SetPoint("TOPRIGHT", sizeG.content, "TOPRIGHT", 0, iy)
    gapSlider:SetValue(cfg.cellSpacing)

    -- ── Layout ────────────────────────────────────────────────
    local layoutG = placeGroup("Layout", 1, 0)
    iy = -6

    local cbLayout = makeToggle(layoutG.content, "Horizontal (left-to-right)",
        function() return cfg.layoutHorizontal end,
        function(v)
            saveKey("layoutHorizontal", v)
            gapSlider.lbl:SetText(gapLabel())
            for _, b in ipairs(barPool) do b:Hide() end
            wipe(barPool); refreshDisplay()
        end)
    cbLayout:SetPoint("TOPLEFT", layoutG.content, "TOPLEFT", 0, iy)

    -- ── Font Sizes ────────────────────────────────────────────
    local fontG = placeGroup("Font Sizes", 0, 2)
    iy = -6

    local nameFsSlider = makeSlider(fontG.content, "Name Size", 8, 20, 1,
        function(val)
            if val == cfg.nameFontSize then return end
            saveKey("nameFontSize", val)
            for _, b in ipairs(barPool) do b:Hide() end
            wipe(barPool); refreshDisplay()
        end)
    nameFsSlider:SetPoint("TOPLEFT",  fontG.content, "TOPLEFT",  0, iy)
    nameFsSlider:SetPoint("TOPRIGHT", fontG.content, "TOPRIGHT", 0, iy)
    nameFsSlider:SetValue(cfg.nameFontSize)
    iy = iy - 44

    local pctFsSlider = makeSlider(fontG.content, "Mana % Size", 8, 20, 1,
        function(val)
            if val == cfg.pctFontSize then return end
            saveKey("pctFontSize", val)
            for _, b in ipairs(barPool) do b:Hide() end
            wipe(barPool); refreshDisplay()
        end)
    pctFsSlider:SetPoint("TOPLEFT",  fontG.content, "TOPLEFT",  0, iy)
    pctFsSlider:SetPoint("TOPRIGHT", fontG.content, "TOPRIGHT", 0, iy)
    pctFsSlider:SetValue(cfg.pctFontSize)

    -- Set scroll content height based on total laid-out height
    content:SetHeight(contentY - GROUP_GAP + 4)

    -- ── OnShow sync ───────────────────────────────────────────
    f:SetScript("OnShow", function()
        cbAlpha:SetChecked(cfg.sortAlpha)
        cbClass:SetChecked(cfg.sortClass)
        cbLock:SetChecked(cfg.locked)
        cbBorderColor:SetChecked(cfg.borderClassColor)
        cbPctSymbol:SetChecked(cfg.showPctSymbol)
        cbShowName:SetChecked(cfg.showName)
        cbDimRange:SetChecked(cfg.dimOutOfRange)
        sizeSlider:SetValue(cfg.cellSize)
        gapSlider.lbl:SetText(gapLabel())
        gapSlider:SetValue(cfg.cellSpacing)
        cbLayout:SetChecked(cfg.layoutHorizontal)
        nameFsSlider:SetValue(cfg.nameFontSize)
        pctFsSlider:SetValue(cfg.pctFontSize)
    end)

    f:Hide()
    configFrame = f
end

local function openConfig()
    if not configFrame then createConfigFrame() end
    configFrame:Show()
    configFrame:Raise()
end

-- ============================================================
-- Slash commands
-- ============================================================
local function printHelp()
    print("|cff00ccffHealerMana|r - type |cffffff00/hm|r to open the settings panel, or:")
    print("  |cffffff00/hm lock|r    - toggle frame lock/unlock")
    print("  |cffffff00/hm alpha|r   - toggle alphabetical sort")
    print("  |cffffff00/hm class|r   - toggle sort by class")
    print("  |cffffff00/hm layout|r  - toggle horizontal/vertical layout")
    print("  |cffffff00/hm reset|r   - reset frame to default position")
    print("  |cffffff00/hm debug|r   - dump healer roster and mana readings")
    print("  |cffffff00/hm range|r   - diagnose out-of-range detection")
end

local function printDebug()
    print("|cff00ccffHealerMana DEBUG|r ----")
    print("  issecretvalue global: " .. tostring(issecretvalue ~= nil))
    print("  IsInGroup=" .. tostring(IsInGroup()) ..
          "  IsInRaid=" .. tostring(IsInRaid()))
    print("  GetNumGroupMembers=" .. tostring(GetNumGroupMembers()))

    -- Count tracked healers
    local count = 0
    for _ in pairs(healerData) do count = count + 1 end
    print("  Tracked healers in healerData: " .. count)

    if count == 0 then
        -- Show all units and their roles so we can see why none qualify
        print("  (scanning group units for roles...)")
        if IsInRaid() then
            for i = 1, GetNumGroupMembers() do
                local u = "raid" .. i
                if UnitExists(u) then
                    print(string.format("    %s  name=%-12s  role=%s",
                        u, tostring(UnitName(u)),
                        tostring(UnitGroupRolesAssigned(u))))
                end
            end
        elseif IsInGroup() then
            for _, u in ipairs({"player","party1","party2","party3","party4"}) do
                if UnitExists(u) then
                    print(string.format("    %s  name=%-12s  role=%s",
                        u, tostring(UnitName(u)),
                        tostring(UnitGroupRolesAssigned(u))))
                end
            end
        end
    else
        print("  _isSecret=" .. tostring(_isSecret ~= nil) ..
              "  _wrapStr=" .. tostring(_wrapStr ~= nil) ..
              "  CurveConstants=" .. tostring(CurveConstants ~= nil) ..
              "  ScaleTo100=" .. tostring(_scaleTo100))

        -- IMPORTANT: NEVER concatenate a secret value (or anything tostring'd
        -- from one) into a print() — WoW's chat system censors the entire line
        -- to "???". Always reduce to a boolean (ok / secret) before printing.
        local function safeTest(fn, ...)
            local ok, v = pcall(fn, ...)
            if not ok then return "err", nil end
            if type(v) ~= "number" then return "non-number(" .. type(v) .. ")", nil end
            if _isSecret and _isSecret(v) then return "secret", nil end
            return "plain", v   -- safe to print v as a normal number
        end

        for unit, data in pairs(healerData) do
            print("  -- [" .. unit .. "] " .. tostring(data.name or "?"))

            -- UnitPowerMax
            local s, n = safeTest(UnitPowerMax, unit, MANA)
            print("    UnitPowerMax(MANA): " .. s ..
                  (n and ("  value=" .. n) or ""))

            -- UnitPower (current)
            s, n = safeTest(UnitPower, unit, MANA)
            print("    UnitPower(MANA):    " .. s ..
                  (n and ("  value=" .. n) or ""))

            -- UnitPowerPercent old-style (2-arg, returns 0-1 fraction)
            s, n = safeTest(UnitPowerPercent, unit, MANA)
            print("    UnitPowerPercent(u,MANA): " .. s ..
                  (n and ("  value=" .. n) or ""))

            -- UnitPowerPercent NEW-STYLE — what readUnitPctRaw() actually uses
            s, n = safeTest(UnitPowerPercent, unit, MANA, true, _scaleTo100)
            print("    UnitPowerPercent(u,MANA,true,ScaleTo100): " .. s ..
                  (n and ("  value=" .. n) or ""))

            -- UnitPowerPercent without powerType (matches oUF [perpp] tag)
            s, n = safeTest(UnitPowerPercent, unit, nil, true, _scaleTo100)
            print("    UnitPowerPercent(u,nil,true,ScaleTo100):  " .. s ..
                  (n and ("  value=" .. n) or ""))
        end
    end
    print("|cff00ccffHealerMana DEBUG|r ---- end")
end

local function setupSlash()
    SLASH_HEALERMANA1 = "/healermana"
    SLASH_HEALERMANA2 = "/hm"
    SlashCmdList["HEALERMANA"] = function(msg)
        local cmd = (msg or ""):lower():match("^%s*(.-)%s*$")

        if cmd == "" or cmd == "config" or cmd == "options" then
            openConfig()

        elseif cmd == "lock" then
            cfg.locked = not cfg.locked
            HealerManaDB.locked = cfg.locked
            mainFrame:EnableMouse(not cfg.locked)
            print("|cff00ccffHealerMana|r: frame " ..
                  (cfg.locked and "|cffff4444locked|r (click-through)" or "|cff00ff00unlocked|r (drag to move)"))

        elseif cmd == "alpha" then
            cfg.sortAlpha = not cfg.sortAlpha
            HealerManaDB.sortAlpha = cfg.sortAlpha
            print("|cff00ccffHealerMana|r: alphabetical sort " ..
                  (cfg.sortAlpha and "|cff00ff00ON|r" or "|cffff4444OFF|r"))
            refreshDisplay()

        elseif cmd == "class" then
            cfg.sortClass = not cfg.sortClass
            HealerManaDB.sortClass = cfg.sortClass
            print("|cff00ccffHealerMana|r: class sort " ..
                  (cfg.sortClass and "|cff00ff00ON|r" or "|cffff4444OFF|r"))
            refreshDisplay()

        elseif cmd == "mana" then
            cfg.sortMana = not cfg.sortMana
            HealerManaDB.sortMana = cfg.sortMana
            print("|cff00ccffHealerMana|r: mana sort " ..
                  (cfg.sortMana and "|cff00ff00ON|r" or "|cffff4444OFF|r"))
            refreshDisplay()

        elseif cmd == "layout" then
            cfg.layoutHorizontal = not cfg.layoutHorizontal
            HealerManaDB.layoutHorizontal = cfg.layoutHorizontal
            print("|cff00ccffHealerMana|r: layout " ..
                  (cfg.layoutHorizontal and "|cff00ff00horizontal|r" or "|cff00ff00vertical|r"))
            for _, b in ipairs(barPool) do b:Hide() end
            wipe(barPool)
            refreshDisplay()

        elseif cmd == "debug" then
            printDebug()

        elseif cmd == "range" then
            -- Diagnose range detection
            local _, class = UnitClass("player")
            print("|cff00ccffHealerMana|r: range debug ---")
            print("  player class: " .. tostring(class))
            print("  rangeCheckSpell: " .. tostring(rangeCheckSpell))
            if rangeCheckSpell then
                local info = C_Spell.GetSpellInfo(rangeCheckSpell)
                print("  spell name: " .. tostring(info and info.name))
            end
            print("  dimOutOfRange cfg: " .. tostring(cfg.dimOutOfRange))
            print("  issecretvalue API: " .. (issecretvalue and "available (WoW 12.0+)" or "NOT available"))
            print("  issecretvalue API: " .. (issecretvalue and "available" or "NOT available"))
            local healerCount = 0
            for _ in pairs(healerData) do healerCount = healerCount + 1 end
            print("  tracked healers: " .. healerCount .. (healerCount == 0 and " (not in a group?)" or ""))
            for unit in pairs(healerData) do
                local spellResult = rangeCheckSpell and C_Spell.IsSpellInRange(rangeCheckSpell, unit)
                local uirInRange, uirChecked = UnitInRange(unit)
                local uirStr
                if issecretvalue and issecretvalue(uirChecked) then
                    uirStr = "secret(" .. tostring(uirInRange) .. ")"
                elseif uirChecked then
                    uirStr = tostring(uirInRange)
                else
                    uirStr = "unchecked"
                end
                print(string.format("  [%s]  spell=%s  UnitInRange=%s  isUnitInRange=%s",
                    unit,
                    tostring(spellResult),
                    uirStr,
                    tostring(isUnitInRange(unit))))
            end
            print("|cff00ccffHealerMana|r: --- end range debug")

        elseif cmd == "help" then
            printHelp()

        elseif cmd == "reset" then
            mainFrame:ClearAllPoints()
            mainFrame:SetPoint(DEFAULTS.point, UIParent, DEFAULTS.relPoint, DEFAULTS.x, DEFAULTS.y)
            cfg.point    = DEFAULTS.point
            cfg.relPoint = DEFAULTS.relPoint
            cfg.x        = DEFAULTS.x
            cfg.y        = DEFAULTS.y
            HealerManaDB.point    = nil
            HealerManaDB.relPoint = nil
            HealerManaDB.x        = nil
            HealerManaDB.y        = nil
            print("|cff00ccffHealerMana|r: position reset.")

        else
            printHelp()  -- unknown command
        end
    end
end

-- ============================================================
-- Event handling
-- ============================================================
eventFrame = CreateFrame("Frame")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    -- -------------------------------------------------------
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName ~= ADDON_NAME then return end

        -- Merge saved values over defaults
        HealerManaDB = HealerManaDB or {}
        local db = HealerManaDB
        for k, v in pairs(DEFAULTS) do
            -- Must use if/else here: `cond and false or default` evaluates to
            -- `default` when the saved value is false, discarding the saved off state.
            if db[k] ~= nil then cfg[k] = db[k] else cfg[k] = v end
        end

        buildSpecIcons() detectRangeSpell()
        createMainFrame()
        setupSlash()
        -- Periodic refresh so mana % stays current. renderBar reads pct fresh
        -- each tick via UnitPowerPercent and feeds the (possibly secret) value
        -- straight to SetFormattedText, so we just need to retick the display.
        C_Timer.NewTicker(0.5, function()
            if next(healerData) then refreshDisplay() end
        end)
        print("|cff00ccffHealerMana|r loaded.  Type |cffffff00/hm|r for options.")

    -- -------------------------------------------------------
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Give the roster a moment to settle after a zone change
        C_Timer.After(1.5, function()
            buildSpecIcons() detectRangeSpell()
            rebuildRoster()
            refreshDisplay()
        end)

    -- -------------------------------------------------------
    elseif event == "GROUP_ROSTER_UPDATE" or event == "ROLE_CHANGED_INFORM" then
        -- Roles may not be assigned yet; short delay is safe
        C_Timer.After(0.5, function()
            rebuildRoster()
            refreshDisplay()
        end)

    -- -------------------------------------------------------
    elseif event == "UNIT_POWER_FREQUENT" then
        local unit, powerType = ...
        if powerType == "MANA" and healerData[unit] then
            refreshDisplay()
        end

    -- -------------------------------------------------------
    elseif event == "UNIT_FLAGS" then
        -- Catches dead / ghost / connected state changes
        local unit = ...
        if healerData[unit] then
            updateUnit(unit)
            refreshDisplay()
        end

    -- -------------------------------------------------------
    elseif event == "UNIT_IN_RANGE_UPDATE" then
        -- Engine fires this when a unit crosses the 40-yard threshold.
        -- isUnitInRange() reads range fresh each call, so just redraw.
        local unit = ...
        if healerData[unit] and not UnitIsUnit(unit, "player") then
            refreshDisplay()
        end

    -- -------------------------------------------------------
    elseif event == "PLAYER_REGEN_ENABLED" then
        refreshDisplay()

    elseif event == "INSPECT_READY" then
        -- Spec data is now available for an inspected unit; refresh all icons
        for unit in pairs(healerData) do
            healerData[unit].specIcon = getSpecIcon(unit, healerData[unit].class)
        end
        refreshDisplay()

    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        -- Player swapped specs mid-session
        if healerData["player"] then
            healerData["player"].specIcon = getSpecIcon("player", healerData["player"].class)
            refreshDisplay()
        end
    end
end)

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("ROLE_CHANGED_INFORM")
-- UNIT_POWER_FREQUENT and UNIT_IN_RANGE_UPDATE are registered dynamically per-healer in
-- rebuildRoster() using RegisterUnitEvent so they fire for party/raid members.
eventFrame:RegisterEvent("UNIT_FLAGS")
eventFrame:RegisterEvent("INSPECT_READY")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
