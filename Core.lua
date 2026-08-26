local _, HM = ...

local cfg        = HM.cfg
local healerData = HM.healerData
local eventFrame = HM.eventFrame
local DEFAULTS   = HM.DEFAULTS

HM.MANA          = 0
HM.isSecretValue = issecretvalue
HM.wrapStr       = C_StringUtil and C_StringUtil.WrapString
HM.scaleTo100    = CurveConstants and CurveConstants.ScaleTo100

local MANA        = HM.MANA
local _isSecret    = HM.isSecretValue
local _scaleTo100  = HM.scaleTo100

HM.INNERVATE_SPELL_ID = 29166
HM.FOOD_DRINK_NAMES   = {"Refreshment", "Drink", "Mana Lily Tea", "Argentleaf Tea"}

HM.innervateIcon = C_Spell.GetSpellTexture(HM.INNERVATE_SPELL_ID)
HM.foodDrinkIcon = nil

local function auraDataBySpellID(unit, spellID)
    local ok, aura = pcall(C_UnitAuras.GetUnitAuraBySpellID, unit, spellID)
    if ok and type(aura) == "table" then return aura end
    return nil
end

local function auraDataByName(unit, name)
    local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, name, "HELPFUL")
    if ok and type(aura) == "table" then return aura end
    return nil
end

function HM.getRegenState(unit)
    if not UnitExists(unit) then return nil end
    if auraDataBySpellID(unit, HM.INNERVATE_SPELL_ID) then return "innervate" end
    for _, name in ipairs(HM.FOOD_DRINK_NAMES) do
        local aura = auraDataByName(unit, name)
        if aura then
            if not HM.foodDrinkIcon and type(aura.icon) == "number" then
                HM.foodDrinkIcon = aura.icon
            end
            return "drinking"
        end
    end
    return nil
end

local RANGE_SPELLS_BY_CLASS = {
    DRUID       = {8936,   774,    5185  },
    PALADIN     = {19750,  635,    85673 },
    PRIEST      = {17,     2061,   21562 },
    SHAMAN      = {8004,   331,    1064  },
    MONK        = {116670, 124682, 115451},
    EVOKER      = {361469, 355913, 382614},
    MAGE        = {1459,   475            },
    WARLOCK     = {20707,  5697           },
    HUNTER      = {34477                  },
}

local RACIAL_RANGE_SPELLS = {
    28880,
    59543,
    69041,
}

function HM.detectRangeSpell()
    HM.rangeCheckSpell = nil
    local _, class = UnitClass("player")
    local list = RANGE_SPELLS_BY_CLASS[class]
    if list then
        for _, id in ipairs(list) do
            if IsPlayerSpell(id) then
                HM.rangeCheckSpell = id
                return
            end
        end
    end
    for _, id in ipairs(RACIAL_RANGE_SPELLS) do
        if IsPlayerSpell(id) then
            HM.rangeCheckSpell = id
            return
        end
    end
end

function HM.isUnitInRange(unit)
    if HM.rangeCheckSpell then
        local r = C_Spell.IsSpellInRange(HM.rangeCheckSpell, unit)
        if r == true  then return true  end
        if r == false then return false end
    end
    local inRange, checked = UnitInRange(unit)
    if issecretvalue and issecretvalue(checked) then
        return inRange
    elseif checked then
        return inRange and true or false
    end
    return nil
end

local resolvedRoleByName = {}

local function resolveUnitRole(unit)
    local role = UnitGroupRolesAssigned(unit)
    if role == "HEALER" or role == "TANK" or role == "DAMAGER" then
        return role
    end
    if UnitIsUnit(unit, "player") then
        local specIdx = GetSpecialization()
        if not specIdx then return nil end
        local ok, _, _, _, _, specRole = pcall(GetSpecializationInfo, specIdx)
        return ok and specRole or nil
    end
    local name = UnitName(unit)
    if name and resolvedRoleByName[name] then
        return resolvedRoleByName[name]
    end
    local ok, specID = pcall(GetInspectSpecialization, unit)
    if ok and type(specID) == "number" and specID > 0 then
        local ok2, _, _, _, _, specRole = pcall(GetSpecializationInfoByID, specID)
        if ok2 and specRole then
            if name then resolvedRoleByName[name] = specRole end
            return specRole
        end
    end
    return nil
end

local function isHealer(unit)
    if not UnitExists(unit) then return false end
    local role = resolveUnitRole(unit)
    if role == "HEALER" then return true end
    if role == nil and not UnitIsUnit(unit, "player") then
        return true
    end
    return false
end

function HM.pruneNonHealers()
    local changed = false
    for unit in pairs(healerData) do
        if not UnitIsUnit(unit, "player") then
            local role = resolveUnitRole(unit)
            if role and role ~= "HEALER" then
                healerData[unit] = nil
                changed = true
            end
        end
    end
    return changed
end

function HM.shouldShowForCurrentInstance()
    local inInstance, instanceType = IsInInstance()
    if not inInstance then return cfg.showInOpenWorld end
    if instanceType == "party" then return cfg.showInDungeons end
    if instanceType == "raid" then return cfg.showInRaids end
    if instanceType == "scenario" then return cfg.showInScenarios end
    if instanceType == "pvp" then return cfg.showInBattlegrounds end
    if instanceType == "arena" then return cfg.showInArenas end
    return true
end

function HM.getLSM()
    local LibStub = _G.LibStub
    return LibStub and LibStub:GetLibrary("LibSharedMedia-3.0", true)
end

function HM.getFontPath()
    if cfg.fontFace then
        local LSM = HM.getLSM()
        if LSM then
            local path = LSM:Fetch(LSM.MediaType and LSM.MediaType.FONT or "font", cfg.fontFace, true)
            if path then return path end
        end
    end
    return STANDARD_TEXT_FONT
end

local HEALER_SPEC_ID = {
    DRUID   = {105},
    PALADIN = {65},
    PRIEST  = {256, 257},
    SHAMAN  = {264},
    MONK    = {270},
    EVOKER  = {1468},
}

local classSpecIcon = {}
function HM.buildSpecIcons()
    wipe(classSpecIcon)
    for class, specIDs in pairs(HEALER_SPEC_ID) do
        for _, specID in ipairs(specIDs) do
            local ok, _, _, _, icon = pcall(GetSpecializationInfoByID, specID)
            if ok and icon then
                classSpecIcon[class] = icon
                break
            end
        end
    end
end

function HM.getSpecIcon(unit, classToken)
    if UnitIsUnit(unit, "player") then
        local specIdx = GetSpecialization()
        if specIdx then
            local ok, _, _, _, icon = pcall(GetSpecializationInfo, specIdx)
            if ok and icon then return icon end
        end
    else
        local ok, specID = pcall(GetInspectSpecialization, unit)
        if ok and type(specID) == "number" and specID > 0 then
            local ok2, _, _, _, icon = pcall(GetSpecializationInfoByID, specID)
            if ok2 and icon then return icon end
        end
    end
    return classSpecIcon[classToken]
end

local function snapshotUnit(unit)
    if not UnitExists(unit) then return nil end
    local name          = UnitName(unit)
    local _, classToken = UnitClass(unit)
    return {
        unit       = unit,
        name       = name or "?",
        class      = classToken or "",
        specIcon   = HM.getSpecIcon(unit, classToken),
        connected  = UnitIsConnected(unit),
        dead       = UnitIsDeadOrGhost(unit),
        regenState = HM.getRegenState(unit),
    }
end

local TEST_CLASSES = {"DRUID", "PALADIN", "PRIEST", "SHAMAN", "MONK", "EVOKER"}
function HM.generateTestRoster(n)
    wipe(healerData)
    for i = 1, n do
        local class = TEST_CLASSES[((i - 1) % #TEST_CLASSES) + 1]
        healerData["test" .. i] = {
            unit      = "player",
            name      = "TestHealer" .. i,
            class     = class,
            specIcon  = classSpecIcon[class],
            connected = true,
            dead      = false,
            testPct   = (n > 1) and (5 + (i - 1) * 90 / (n - 1)) or 50,
        }
    end
end

function HM.rebuildRoster()
    if HM.testModeActive then return end
    wipe(healerData)
    if IsInRaid() then
        local n = GetNumGroupMembers()
        for i = 1, n do
            local unit = "raid" .. i
            if isHealer(unit) and not (cfg.hideSelf and UnitIsUnit(unit, "player")) then
                healerData[unit] = snapshotUnit(unit)
            end
        end
    elseif IsInGroup() then
        if isHealer("player") and not cfg.hideSelf then
            healerData["player"] = snapshotUnit("player")
        end
        local n = GetNumGroupMembers() - 1
        for i = 1, n do
            local unit = "party" .. i
            if isHealer(unit) then
                healerData[unit] = snapshotUnit(unit)
            end
        end
    elseif cfg.showWhenSolo then
        if isHealer("player") and not cfg.hideSelf then
            healerData["player"] = snapshotUnit("player")
        end
    end

    eventFrame:UnregisterEvent("UNIT_POWER_FREQUENT")
    eventFrame:UnregisterEvent("UNIT_IN_RANGE_UPDATE")
    eventFrame:UnregisterEvent("UNIT_FLAGS")
    eventFrame:UnregisterEvent("UNIT_HEALTH")
    eventFrame:UnregisterEvent("UNIT_MAXHEALTH")
    eventFrame:UnregisterEvent("UNIT_AURA")
    eventFrame:UnregisterEvent("UNIT_CONNECTION")
    for unit in pairs(healerData) do
        eventFrame:RegisterUnitEvent("UNIT_POWER_FREQUENT", unit)
        eventFrame:RegisterUnitEvent("UNIT_IN_RANGE_UPDATE", unit)
        eventFrame:RegisterUnitEvent("UNIT_FLAGS", unit)
        eventFrame:RegisterUnitEvent("UNIT_HEALTH", unit)
        eventFrame:RegisterUnitEvent("UNIT_MAXHEALTH", unit)
        eventFrame:RegisterUnitEvent("UNIT_AURA", unit)
        eventFrame:RegisterUnitEvent("UNIT_CONNECTION", unit)
    end
    local delay = 0.2
    for unit in pairs(healerData) do
        if not UnitIsUnit(unit, "player") then
            local u = unit
            C_Timer.After(delay, function()
                if UnitExists(u) and healerData[u] then
                    NotifyInspect(u)
                end
            end)
            delay = delay + 0.5
        end
    end
end

function HM.readUnitPctRaw(unit)
    local ok, pct = pcall(UnitPowerPercent, unit, MANA, true, _scaleTo100)
    if ok then return pct end
    local ok2, pct2 = pcall(UnitPowerPercent, unit, MANA)
    if ok2 then return pct2 end
    return nil
end

function HM.isPlainNumber(v)
    if type(v) ~= "number" then return false end
    if _isSecret and _isSecret(v) then return false end
    return true
end

function HM.updateUnit(unit)
    if not healerData[unit] then return end
    local d     = healerData[unit]
    d.specIcon  = HM.getSpecIcon(unit, d.class)
    d.connected = UnitIsConnected(unit)
    d.dead      = UnitIsDeadOrGhost(unit)
    d.regenState = HM.getRegenState(unit)
end

local sortBuf = {}
function HM.getSorted()
    wipe(sortBuf)
    for unit, data in pairs(healerData) do
        sortBuf[#sortBuf + 1] = {unit = unit, data = data}
    end
    table.sort(sortBuf, function(a, b)
        local ad, bd = a.data, b.data
        if cfg.sortMode == "class" and ad.class ~= bd.class then
            return ad.class < bd.class
        end
        return (ad.name or "") <= (bd.name or "")
    end)
    return sortBuf
end

function HM.saveKey(key, value)
    cfg[key] = value
    HealerManaDB[key] = value
end

function HM.resetPosition()
    HM.mainFrame:ClearAllPoints()
    HM.mainFrame:SetPoint(DEFAULTS.point, UIParent, DEFAULTS.relPoint, DEFAULTS.x, DEFAULTS.y)
    cfg.point    = DEFAULTS.point
    cfg.relPoint = DEFAULTS.relPoint
    cfg.x        = DEFAULTS.x
    cfg.y        = DEFAULTS.y
    HealerManaDB.point    = nil
    HealerManaDB.relPoint = nil
    HealerManaDB.x        = nil
    HealerManaDB.y        = nil
    print("|cff00ccffHealerMana|r: position reset.")
end
