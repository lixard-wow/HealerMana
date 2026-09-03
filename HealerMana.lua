local ADDON_NAME, HM = ...

HM.DEFAULTS = {
    sortMode         = "alpha",
    locked           = false,
    borderClassColor = true,
    nameClassColor   = true,
    cellSize         = 52,
    cellSpacing      = 4,
    layoutHorizontal = false,
    gridEnabled      = false,
    gridColumns      = 4,
    displayStyle     = "icon",
    barWidth         = 160,
    barHeight        = 20,
    barTexture       = "Blizzard",
    showPctSymbol    = true,
    showName         = true,
    nameOverflow     = "shrink",
    dimOutOfRange    = true,
    hideSelf             = false,
    showWhenSolo          = false,
    showInOpenWorld       = true,
    showInDungeons        = true,
    showInRaids           = true,
    showInScenarios       = true,
    showInBattlegrounds   = true,
    showInArenas          = true,
    nameFontSize     = 10,
    pctFontSize      = 14,
    point            = "CENTER",
    relPoint         = "CENTER",
    x                = 150,
    y                = 0,
    barColorMode       = "class",
    barColorCustom     = {r = 0.30, g = 0.60, b = 0.90},
    bgColor            = {r = 0.05, g = 0.05, b = 0.05, a = 0.85},
    borderCustomColor  = {r = 0.85, g = 0.85, b = 0.85},
    nameCustomColor    = {r = 1.00, g = 1.00, b = 1.00},
    pctClassColor      = false,
    pctCustomColor     = {r = 1.00, g = 1.00, b = 1.00},
    fontFace           = false,
    fontSizeOverride   = false,
    nameFontSizeManual = 10,
    pctFontSizeManual  = 14,
    barFillOpacity     = 1.00,
    iconTintOpacity    = 0.22,
    outOfRangeOpacity  = 0.35,
    testPreviewCount   = 5,
}

HM.cfg             = {}
HM.healerData      = {}
HM.barPool         = {}
HM.testModeActive  = false
HM.rangeCheckSpell = nil

HM.eventFrame = CreateFrame("Frame")

local rosterUpdateQueued = false

local function queueRosterRebuild()
    if rosterUpdateQueued then return end
    rosterUpdateQueued = true
    C_Timer.After(0.5, function()
        rosterUpdateQueued = false
        HM.rebuildRoster()
        HM.refreshDisplay()
    end)
end

HM.eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName ~= ADDON_NAME then return end

        HealerManaDB = HealerManaDB or {}
        local db = HealerManaDB
        for k, v in pairs(HM.DEFAULTS) do
            if db[k] ~= nil then HM.cfg[k] = db[k] else HM.cfg[k] = v end
        end
        HM.cfg.nameFontSize, HM.cfg.pctFontSize = HM.autoFontSizes(HM.cfg.cellSize)
        HealerManaDB.nameFontSize, HealerManaDB.pctFontSize = HM.cfg.nameFontSize, HM.cfg.pctFontSize

        HM.buildSpecIcons() HM.detectRangeSpell()
        HM.createMainFrame()
        HM.setupSlash()
        HM.initMinimapIcon()
        C_Timer.NewTicker(0.5, function()
            if not next(HM.healerData) then return end
            if not HM.testModeActive then
                for unit in pairs(HM.healerData) do
                    HM.updateUnit(unit)
                end
            end
            HM.refreshDisplay()
        end)
        C_Timer.NewTicker(1, function()
            if next(HM.healerData) and not HM.testModeActive then
                HM.retryUnresolvedIcons()
            end
        end)
        print("|cff00ccffHealerMana|r loaded.  Type |cffffff00/hm|r for options.")

    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(1.5, function()
            HM.buildSpecIcons() HM.detectRangeSpell()
            HM.rebuildRoster()
            HM.refreshDisplay()
        end)

    elseif event == "GROUP_ROSTER_UPDATE" or event == "ROLE_CHANGED_INFORM" then
        queueRosterRebuild()

    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        HM.forgetResolvedRole(...)
        queueRosterRebuild()

    elseif event == "INSPECT_READY" then
        HM.handleInspectReady(...)
        queueRosterRebuild()

    elseif event == "UNIT_POWER_FREQUENT" then
        local unit, powerType = ...
        if powerType == "MANA" and HM.healerData[unit] then
            HM.refreshDisplay()
        end

    elseif event == "UNIT_FLAGS" or event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH"
        or event == "UNIT_AURA" or event == "UNIT_CONNECTION" then
        local unit = ...
        if HM.healerData[unit] then
            HM.updateUnit(unit)
            HM.refreshDisplay()
        end

    elseif event == "UNIT_IN_RANGE_UPDATE" then
        local unit = ...
        if HM.healerData[unit] and not UnitIsUnit(unit, "player") then
            HM.refreshDisplay()
        end

    elseif event == "PLAYER_REGEN_ENABLED" then
        HM.refreshDisplay()
    end
end)

HM.eventFrame:RegisterEvent("ADDON_LOADED")
HM.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
HM.eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
HM.eventFrame:RegisterEvent("ROLE_CHANGED_INFORM")
HM.eventFrame:RegisterEvent("INSPECT_READY")
HM.eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
HM.eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
