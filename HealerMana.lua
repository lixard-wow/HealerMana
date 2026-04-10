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

-- Spell IDs whose buff icon replaces the class icon (regen state)
local REGEN_IDS = {
    29166,  -- Innervate
    22734,  -- Drink
}

-- ============================================================
-- State
-- ============================================================
local cfg          = {}          -- live config (merged from DEFAULTS + saved)
local healerData   = {}          -- [unitToken] = data table
local regenNames   = {}          -- [spellName] = iconID  (populated on load)
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

local function isHealer(unit)
    return UnitExists(unit) and UnitGroupRolesAssigned(unit) == "HEALER"
end

-- Healer spec IDs — one per class (Priest defaults to Holy; both heal the same)
local HEALER_SPEC_ID = {
    DRUID   = 105,   -- Restoration
    PALADIN = 65,    -- Holy
    PRIEST  = 257,   -- Holy  (Disc = 256; can't distinguish without full inspect)
    SHAMAN  = 264,   -- Restoration
    MONK    = 270,   -- Mistweaver
    EVOKER  = 1468,  -- Preservation
}

-- classSpecIcon[classToken] = FileDataID, built at load time from WoW's own data
local classSpecIcon = {}
local function buildSpecIcons()
    wipe(classSpecIcon)
    for class, specID in pairs(HEALER_SPEC_ID) do
        local ok, _, _, _, icon = pcall(GetSpecializationInfoByID, specID)
        if ok and icon then classSpecIcon[class] = icon end
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

-- Build the regen-spell-name lookup from spell IDs
local function buildRegenNames()
    buildSpecIcons()
    wipe(regenNames)
    for _, id in ipairs(REGEN_IDS) do
        local info = C_Spell.GetSpellInfo(id)
        if info and info.name then
            regenNames[info.name] = info.iconID
        end
    end
end

-- Return regen buff iconID if the unit has one, or nil.
-- In WoW 12.0 restricted contexts aura.name is a secret value and cannot be used
-- as a table key. We pcall the lookup so the addon doesn't crash; regen detection
-- simply won't fire while values are restricted.
local function getRegenBuffIcon(unit)
    local i = 1
    while true do
        local aura = C_UnitAuras.GetBuffDataByIndex(unit, i)
        if not aura then break end
        local name = aura.name
        -- Guard: if name is a secret value, using it as a table key crashes even inside pcall
        if name and not (_isSecret and _isSecret(name)) then
            local iconID = regenNames[name]
            if iconID then return iconID end
        end
        i = i + 1
    end
    return nil
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
        regenIcon = getRegenBuffIcon(unit),
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

    -- Re-register UNIT_POWER_FREQUENT for exactly the current healer set.
    -- RegisterEvent only delivers player events; party/raid units need RegisterUnitEvent.
    eventFrame:UnregisterEvent("UNIT_POWER_FREQUENT")
    for unit in pairs(healerData) do
        eventFrame:RegisterUnitEvent("UNIT_POWER_FREQUENT", unit)
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
    local d     = healerData[unit]
    d.specIcon  = getSpecIcon(unit, d.class)
    d.connected = UnitIsConnected(unit)
    d.dead      = UnitIsDeadOrGhost(unit)
    d.regenIcon = getRegenBuffIcon(unit)
    -- Note: we no longer cache pct as a number (can't, it's a secret value).
    -- renderBar reads it fresh and feeds it to SetFormattedText.
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
    local cs  = cfg.cellSize
    local bar = CreateFrame("Frame", nil, mainFrame)
    bar:SetSize(cs, cs + NAME_HEIGHT + 2)

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
    local fontSize = math.max(math.floor(cs * 0.28), 12)
    bar.pctTxt = bar:CreateFontString(nil, "OVERLAY")
    bar.pctTxt:SetFont(STANDARD_TEXT_FONT, fontSize, "THICKOUTLINE")
    bar.pctTxt:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, -(cs / 2 - fontSize / 2))
    bar.pctTxt:SetWidth(cs)
    bar.pctTxt:SetJustifyH("CENTER")

    -- Name label directly below the icon
    bar.nameTxt = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.nameTxt:SetPoint("TOPLEFT", bar.icon, "BOTTOMLEFT", 0, -2)
    bar.nameTxt:SetWidth(cs)
    bar.nameTxt:SetJustifyH("CENTER")
    bar.nameTxt:SetWordWrap(false)

    barPool[idx] = bar
    return bar
end

local function getBar(idx)
    return barPool[idx] or createBar(idx)
end

local function positionBar(bar, idx)
    bar:ClearAllPoints()
    local cs  = cfg.cellSize
    local gap = cfg.cellSpacing
    bar:SetPoint("TOPLEFT", mainFrame, "TOPLEFT",
        0, -(idx - 1) * (cs + NAME_HEIGHT + 2 + gap))
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
    -- Icon: regen buff icon > spec icon (e.g. Chain Heal for Resto Shaman)
    local iconID = data.regenIcon or data.specIcon
    if iconID then
        bar.icon:SetTexture(iconID)
        bar.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- trim default icon border
    end

    -- Name text + border
    bar.nameTxt:SetText(data.name)
    local cc = CLASS_COLOR[data.class]
    if cc then
        bar.nameTxt:SetTextColor(cc[1], cc[2], cc[3])
        if cfg.borderClassColor then
            bar.border:SetBackdropBorderColor(cc[1], cc[2], cc[3], 1)
        else
            bar.border:SetBackdropBorderColor(0.85, 0.85, 0.85, 1)
        end
    else
        bar.nameTxt:SetTextColor(0.85, 0.85, 0.85)
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
            bar.pctTxt:SetText(p .. "%")
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
            local formatted = format("%.0f%%", pct)
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
        local cellH  = cs + NAME_HEIGHT + 2
        local totalW = cs
        local totalH = count > 0 and (count * (cellH + gap) - gap) or 1

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

local function makeSlider(parent, labelText, minVal, maxVal, step, yOff, onChange)
    -- Container holds label + slider + min/max annotations
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(240, 48)
    holder:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, yOff)

    local lbl = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
    lbl:SetText(labelText)
    holder.lbl = lbl

    local sl = CreateFrame("Slider", nil, holder, "BackdropTemplate")
    sl:SetSize(220, 16)
    sl:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -18)
    sl:SetOrientation("HORIZONTAL")
    sl:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    sl:SetBackdrop({
        bgFile   = "Interface\\Buttons\\UI-SliderBar-Background",
        edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 3, right = 3, top = 6, bottom = 6 },
    })
    sl:SetMinMaxValues(minVal, maxVal)
    sl:SetValueStep(step)
    sl:SetObeyStepOnDrag(true)

    local minLbl = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    minLbl:SetPoint("TOPLEFT", sl, "BOTTOMLEFT", 0, -2)
    minLbl:SetText(tostring(minVal))

    local maxLbl = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    maxLbl:SetPoint("TOPRIGHT", sl, "BOTTOMRIGHT", 0, -2)
    maxLbl:SetText(tostring(maxVal))

    sl:SetScript("OnValueChanged", function(self, val)
        val = math.floor(val / step + 0.5) * step
        lbl:SetText(labelText .. ": " .. val)
        onChange(val)
    end)

    holder.slider = sl
    return holder
end

local function createConfigFrame()
    local f = CreateFrame("Frame", "HealerManaConfig", UIParent, "BackdropTemplate")
    f:SetSize(280, 395)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    f:SetBackdropColor(0, 0, 0, 0.85)

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOP", f, "TOP", 0, -14)
    title:SetText("|cff00ccffHealerMana|r Settings")

    local closeX = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeX:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    closeX:SetScript("OnClick", function() f:Hide() end)

    -- Helper: section header
    local function sectionLabel(text, yOff)
        local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("TOPLEFT", f, "TOPLEFT", 16, yOff)
        lbl:SetText(text)
        lbl:SetTextColor(1, 0.82, 0)
    end

    -- Helper: checkbox row
    local function makeCheckbox(yOff, label, getVal, onToggle)
        local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", f, "TOPLEFT", 14, yOff)
        cb.text:SetText(label)
        cb:SetChecked(getVal())
        cb:SetScript("OnClick", function(self) onToggle(self:GetChecked()) end)
        return cb
    end

    -- ── Sort ──────────────────────────────────────────────────
    sectionLabel("Sort Order", -46)

    local cbAlpha = makeCheckbox(-64, "Alphabetical", function() return cfg.sortAlpha end,
        function(v) saveKey("sortAlpha", v) refreshDisplay() end)

    local cbClass = makeCheckbox(-88, "By healer class", function() return cfg.sortClass end,
        function(v) saveKey("sortClass", v) refreshDisplay() end)

    -- ── Display ───────────────────────────────────────────────
    sectionLabel("Display", -118)

    local cbLock = makeCheckbox(-136, "Lock frame (click-through)",
        function() return cfg.locked end,
        function(v)
            saveKey("locked", v)
            mainFrame:EnableMouse(not cfg.locked)
        end)

    local cbBorderColor = makeCheckbox(-160, "Class color border",
        function() return cfg.borderClassColor end,
        function(v)
            saveKey("borderClassColor", v)
            refreshDisplay()
        end)

    -- Icon size
    local sizeHolder = makeSlider(f, "Icon Size: " .. cfg.cellSize,
        24, 96, 4, -196,
        function(val)
            if val == cfg.cellSize then return end
            saveKey("cellSize", val)
            for _, b in ipairs(barPool) do b:Hide() end
            wipe(barPool)
            refreshDisplay()
        end)
    sizeHolder.slider:SetValue(cfg.cellSize)

    -- Icon spacing
    local gapHolder = makeSlider(f, "Icon Spacing: " .. cfg.cellSpacing,
        0, 16, 1, -256,
        function(val)
            if val == cfg.cellSpacing then return end
            saveKey("cellSpacing", val)
            refreshDisplay()
        end)
    gapHolder.slider:SetValue(cfg.cellSpacing)

    -- ── Buttons ───────────────────────────────────────────────
    local resetBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    resetBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 14)
    resetBtn:SetSize(120, 24)
    resetBtn:SetText("Reset Position")
    resetBtn:SetScript("OnClick", function()
        mainFrame:ClearAllPoints()
        mainFrame:SetPoint(DEFAULTS.point, UIParent, DEFAULTS.relPoint,
                           DEFAULTS.x, DEFAULTS.y)
        cfg.point    = DEFAULTS.point;    HealerManaDB.point    = nil
        cfg.relPoint = DEFAULTS.relPoint; HealerManaDB.relPoint = nil
        cfg.x        = DEFAULTS.x;       HealerManaDB.x        = nil
        cfg.y        = DEFAULTS.y;       HealerManaDB.y        = nil
        print("|cff00ccffHealerMana|r: position reset.")
    end)

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    closeBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 14)
    closeBtn:SetSize(80, 24)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Sync controls to current cfg whenever the panel opens
    f:SetScript("OnShow", function()
        cbAlpha:SetChecked(cfg.sortAlpha)
        cbClass:SetChecked(cfg.sortClass)
        cbLock:SetChecked(cfg.locked)
        cbBorderColor:SetChecked(cfg.borderClassColor)
        sizeHolder.lbl:SetText("Icon Size: " .. cfg.cellSize)
        sizeHolder.slider:SetValue(cfg.cellSize)
        gapHolder.lbl:SetText("Icon Spacing: " .. cfg.cellSpacing)
        gapHolder.slider:SetValue(cfg.cellSpacing)
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
    print("  |cffffff00/hm lock|r   - toggle frame lock/unlock")
    print("  |cffffff00/hm alpha|r  - toggle alphabetical sort")
    print("  |cffffff00/hm class|r  - toggle sort by class")
    print("  |cffffff00/hm reset|r  - reset frame to default position")
    print("  |cffffff00/hm debug|r  - dump healer roster and mana readings")
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

        elseif cmd == "debug" then
            printDebug()

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
        if (...) ~= ADDON_NAME then return end

        -- Merge saved values over defaults
        HealerManaDB = HealerManaDB or {}
        local db = HealerManaDB
        for k, v in pairs(DEFAULTS) do
            cfg[k] = (db[k] ~= nil) and db[k] or v
        end

        buildRegenNames() buildSpecIcons()
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
            buildRegenNames() buildSpecIcons()
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
            -- Triggers a re-render; renderBar reads UnitPowerPercent fresh
            -- and feeds the secret value through SetFormattedText + WrapString.
            updateUnit(unit)
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
    elseif event == "UNIT_AURA" then
        -- Catches Innervate / Drink buff gaining or fading
        local unit = ...
        if healerData[unit] then
            updateUnit(unit)
            refreshDisplay()
        end

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
-- UNIT_POWER_FREQUENT is registered dynamically per-healer in rebuildRoster()
-- using RegisterUnitEvent so it fires for party/raid members, not just the player.
eventFrame:RegisterEvent("UNIT_FLAGS")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("INSPECT_READY")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
