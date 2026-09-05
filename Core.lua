local _, HM = ...

local cfg        = HM.cfg
local healerData = HM.healerData
local eventFrame = HM.eventFrame
local DEFAULTS   = HM.DEFAULTS

HM.MANA          = 0
HM.isSecretValue = issecretvalue
HM.isSecretTable = issecrettable
HM.wrapStr       = C_StringUtil and C_StringUtil.WrapString
HM.scaleTo100    = CurveConstants and CurveConstants.ScaleTo100

local MANA        = HM.MANA
local _isSecret    = HM.isSecretValue
local _isSecretTable = HM.isSecretTable
local _scaleTo100  = HM.scaleTo100

HM.FOOD_SPELL_ID       = 45618
HM.DRINK_SPELL_ID      = 43183
HM.FOOD_DRINK_SPELL_ID = 192002
HM.QUIET_CONTEMPLATION_SPELL_ID = 461063

HM.FOOD_DRINK_SPELL_IDS = {HM.FOOD_SPELL_ID, HM.DRINK_SPELL_ID, HM.FOOD_DRINK_SPELL_ID, HM.QUIET_CONTEMPLATION_SPELL_ID}

HM.FOOD_DRINK_NAMES = {"Refreshment", "Drink", "Mana Lily Tea", "Argentleaf Tea", "Tranq Bloom Tea"}

local function isUsableAuraTable(aura)
    if type(aura) ~= "table" then return false end
    if _isSecretTable and _isSecretTable(aura) then return false end
    return true
end

local function auraDataBySpellID(unit, spellID)
    local ok, aura = pcall(C_UnitAuras.GetUnitAuraBySpellID, unit, spellID)
    if ok and isUsableAuraTable(aura) then return aura end
    return nil
end

local function auraDataByName(unit, name)
    local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, name, "HELPFUL")
    if ok and isUsableAuraTable(aura) then return aura end
    return nil
end

function HM.getRegenState(unit)
    if not UnitExists(unit) then return nil end
    for _, spellID in ipairs(HM.FOOD_DRINK_SPELL_IDS) do
        local aura = auraDataBySpellID(unit, spellID)
        if aura then
            return "drinking", type(aura.icon) == "number" and aura.icon or nil
        end
    end
    for _, name in ipairs(HM.FOOD_DRINK_NAMES) do
        local aura = auraDataByName(unit, name)
        if aura then
            return "drinking", type(aura.icon) == "number" and aura.icon or nil
        end
    end
    return nil
end

HM.CAT_FORM_SPELL_ID     = 768
HM.BEAR_FORM_SPELL_ID    = 5487
HM.MOONKIN_FORM_SPELL_ID = 24858
HM.CAT_FORM_ICON      = C_Spell.GetSpellTexture(HM.CAT_FORM_SPELL_ID)
HM.BEAR_FORM_ICON     = C_Spell.GetSpellTexture(HM.BEAR_FORM_SPELL_ID)
HM.MOONKIN_FORM_ICON  = C_Spell.GetSpellTexture(HM.MOONKIN_FORM_SPELL_ID)

HM.FORM_ICON = {
    CAT     = HM.CAT_FORM_ICON,
    BEAR    = HM.BEAR_FORM_ICON,
    MOONKIN = HM.MOONKIN_FORM_ICON,
}

function HM.getDruidForm(unit, classToken)
    if classToken ~= "DRUID" or not UnitExists(unit) then return nil end
    local _, powerToken = UnitPowerType(unit)
    if powerToken == "ENERGY" then return "CAT" end
    if powerToken == "RAGE" then return "BEAR" end
    if auraDataBySpellID(unit, HM.MOONKIN_FORM_SPELL_ID) then return "MOONKIN" end
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

function HM.forgetResolvedRole(unit)
    local name = UnitName(unit)
    if name then resolvedRoleByName[name] = nil end
end

local function resolveUnitRole(unit)
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
        local roleOk, specRole = pcall(GetSpecializationRoleByID, specID)
        if roleOk and specRole then
            if name then resolvedRoleByName[name] = specRole end
            return specRole
        end
    end

    local assignedRole = UnitGroupRolesAssigned(unit)
    if assignedRole == "HEALER" or assignedRole == "TANK" or assignedRole == "DAMAGER" then
        return assignedRole
    end
    return nil
end

local function findUnitByGUID(guid)
    if not guid then return nil end
    if UnitGUID("player") == guid then return "player" end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local u = "raid" .. i
            if UnitExists(u) and UnitGUID(u) == guid then return u end
        end
    elseif IsInGroup() then
        for i = 1, GetNumGroupMembers() - 1 do
            local u = "party" .. i
            if UnitExists(u) and UnitGUID(u) == guid then return u end
        end
    end
    return nil
end

function HM.handleInspectReady(guid)
    local unit = findUnitByGUID(guid)
    if not unit or UnitIsUnit(unit, "player") then return end

    local ok, specID = pcall(GetInspectSpecialization, unit)
    if not (ok and type(specID) == "number" and specID > 0) then return end

    local roleOk, specRole = pcall(GetSpecializationRoleByID, specID)
    if roleOk and specRole then
        local name = UnitName(unit)
        if name then resolvedRoleByName[name] = specRole end
    end

    if healerData[unit] then
        local iconOk, _, _, _, icon = pcall(GetSpecializationInfoByID, specID)
        if iconOk and icon then healerData[unit].specIcon = icon end
    end
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
HM.GENERIC_CLASS_ICON_TEXTURE = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"

function HM.buildSpecIcons()
    wipe(classSpecIcon)
    for class, specIDs in pairs(HEALER_SPEC_ID) do
        if #specIDs == 1 then
            local ok, _, _, _, icon = pcall(GetSpecializationInfoByID, specIDs[1])
            if ok and icon then
                classSpecIcon[class] = icon
            end
        elseif CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class] then
            classSpecIcon[class] = {texture = HM.GENERIC_CLASS_ICON_TEXTURE, coords = CLASS_ICON_TCOORDS[class]}
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
    local regenState, regenIcon = HM.getRegenState(unit)
    return {
        unit       = unit,
        name       = name or "?",
        class      = classToken or "",
        specIcon   = HM.getSpecIcon(unit, classToken),
        connected  = UnitIsConnected(unit),
        dead       = UnitIsDeadOrGhost(unit),
        regenState = regenState,
        regenIcon  = regenIcon,
        form       = HM.getDruidForm(unit, classToken),
    }
end

local TEST_CLASSES = {"DRUID", "PALADIN", "PRIEST", "SHAMAN", "MONK", "EVOKER"}
local TEST_DRUID_FORMS = {"CAT", "BEAR", "MOONKIN", nil}
local testClassIcon = {}
local testDruidIndex = 0
function HM.generateTestRoster(n)
    wipe(healerData)
    testDruidIndex = 0
    for i = 1, n do
        local class = TEST_CLASSES[((i - 1) % #TEST_CLASSES) + 1]
        if testClassIcon[class] == nil then
            local ok, _, _, _, icon = pcall(GetSpecializationInfoByID, HEALER_SPEC_ID[class][1])
            testClassIcon[class] = (ok and icon) or false
        end
        local form
        if class == "DRUID" then
            testDruidIndex = testDruidIndex + 1
            form = TEST_DRUID_FORMS[((testDruidIndex - 1) % #TEST_DRUID_FORMS) + 1]
        end
        healerData["test" .. i] = {
            unit      = "player",
            name      = "TestHealer" .. i,
            class     = class,
            specIcon  = testClassIcon[class] or nil,
            connected = true,
            dead      = false,
            form      = form,
            testPct   = (n > 1) and (5 + (i - 1) * 90 / (n - 1)) or 50,
        }
    end
end

local inspectQueue = {}
local inspectQueued = {}
local inspectTicker = nil

function HM.enqueueInspect(unit, priority)
    if inspectQueued[unit] then
        if priority then
            for i, u in ipairs(inspectQueue) do
                if u == unit then
                    table.remove(inspectQueue, i)
                    table.insert(inspectQueue, 1, unit)
                    break
                end
            end
        end
        return
    end
    inspectQueued[unit] = true
    if priority then
        table.insert(inspectQueue, 1, unit)
    else
        inspectQueue[#inspectQueue + 1] = unit
    end
    if inspectTicker then return end
    inspectTicker = C_Timer.NewTicker(1.7, function()
        if #inspectQueue == 0 then
            inspectTicker:Cancel()
            inspectTicker = nil
            return
        end
        if InspectFrame and InspectFrame:IsShown() then return end
        local u = table.remove(inspectQueue, 1)
        if not u then return end
        inspectQueued[u] = nil
        if UnitExists(u) then NotifyInspect(u) end
    end)
end

function HM.rebuildRoster()
    if HM.testModeActive then return end
    local previousIconsByName = {}
    for _, d in pairs(healerData) do
        if d.name and type(d.specIcon) == "number" then previousIconsByName[d.name] = d.specIcon end
    end
    wipe(healerData)

    local allUnits = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            allUnits[#allUnits + 1] = "raid" .. i
        end
    elseif IsInGroup() then
        allUnits[#allUnits + 1] = "player"
        for i = 1, GetNumGroupMembers() - 1 do
            allUnits[#allUnits + 1] = "party" .. i
        end
    elseif cfg.showWhenSolo then
        allUnits[#allUnits + 1] = "player"
    end

    for _, unit in ipairs(allUnits) do
        if UnitExists(unit) then
            local role = resolveUnitRole(unit)
            local snap
            if role == "HEALER" and not (cfg.hideSelf and UnitIsUnit(unit, "player")) then
                snap = snapshotUnit(unit)
                if type(snap.specIcon) ~= "number" and previousIconsByName[snap.name] then
                    snap.specIcon = previousIconsByName[snap.name]
                end
                healerData[unit] = snap
            end
            if role ~= "TANK" and role ~= "DAMAGER" and not UnitIsUnit(unit, "player") then
                HM.enqueueInspect(unit, role == "HEALER" and snap and type(snap.specIcon) ~= "number")
            end
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
end

function HM.toggleTestPreview()
    if HM.testModeActive then
        HM.testModeActive = false
        HM.rebuildRoster()
    else
        HM.testModeActive = true
        HM.generateTestRoster(cfg.testPreviewCount)
    end
    HM.refreshDisplay()
end

function HM.retryUnresolvedIcons()
    for unit, data in pairs(healerData) do
        if not data.specIcon and not UnitIsUnit(unit, "player") and UnitExists(unit) then
            HM.enqueueInspect(unit, true)
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
    local d = healerData[unit]
    local newIcon = HM.getSpecIcon(unit, d.class)
    if type(newIcon) == "number" or type(d.specIcon) ~= "number" then
        if newIcon then d.specIcon = newIcon end
    end
    d.connected = UnitIsConnected(unit)
    d.dead      = UnitIsDeadOrGhost(unit)
    d.regenState, d.regenIcon = HM.getRegenState(unit)
    d.form      = HM.getDruidForm(unit, d.class)
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
        return (ad.name or "") < (bd.name or "")
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
