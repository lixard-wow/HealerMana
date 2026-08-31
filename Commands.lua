local _, HM = ...

local cfg        = HM.cfg
local healerData = HM.healerData

local MANA        = HM.MANA
local _isSecret    = HM.isSecretValue
local _wrapStr     = HM.wrapStr
local _scaleTo100  = HM.scaleTo100

local function forEachGroupUnit(fn)
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local u = "raid" .. i
            if UnitExists(u) then fn(u) end
        end
    elseif IsInGroup() then
        for _, u in ipairs({"player", "party1", "party2", "party3", "party4"}) do
            if UnitExists(u) then fn(u) end
        end
    end
end

local function printHelp()
    print("|cff00ccffHealerMana|r - type |cffffff00/hm|r to open the settings panel, or:")
    print("  |cffffff00/hm lock|r    - toggle frame lock/unlock")
    print("  |cffffff00/hm alpha|r   - sort alphabetically")
    print("  |cffffff00/hm class|r   - sort by healer class")
    print("  |cffffff00/hm layout|r  - toggle horizontal/vertical layout")
    print("  |cffffff00/hm reset|r   - reset frame to default position")
    print("  |cffffff00/hm debug|r   - dump healer roster and mana readings")
    print("  |cffffff00/hm range|r   - diagnose out-of-range detection")
    print("  |cffffff00/hm raid <n>|r - populate n fake healers to test layout (off to restore)")
    print("  |cffffff00/hm regendebug|r - TEMP: dump Food&Drink detection for tracked units")
    print("  |cffffff00/hm specmonitor|r - TEMP: watch live spec/icon detection for other healers every 2s (again to stop)")
    print("  |cffffff00/hm raidregen|r  - TEMP: preview the Food&Drink icon swap on fake healers")
    print("  |cffffff00/hm auralog|r    - TEMP: watch player's HELPFUL auras every 2s, saves new ones to HealerManaDB.auraLog (again to stop)")
end

local function printDebug()
    print("|cff00ccffHealerMana DEBUG|r ----")
    print("  issecretvalue global: " .. tostring(issecretvalue ~= nil))
    print("  IsInGroup=" .. tostring(IsInGroup()) ..
          "  IsInRaid=" .. tostring(IsInRaid()))
    print("  GetNumGroupMembers=" .. tostring(GetNumGroupMembers()))

    local count = 0
    for _ in pairs(healerData) do count = count + 1 end
    print("  Tracked healers in healerData: " .. count)

    if count == 0 then
        print("  (scanning group units for roles...)")
        forEachGroupUnit(function(u)
            print(string.format("    %s  name=%-12s  role=%s",
                u, tostring(UnitName(u)),
                tostring(UnitGroupRolesAssigned(u))))
        end)
    else
        print("  _isSecret=" .. tostring(_isSecret ~= nil) ..
              "  _wrapStr=" .. tostring(_wrapStr ~= nil) ..
              "  CurveConstants=" .. tostring(CurveConstants ~= nil) ..
              "  ScaleTo100=" .. tostring(_scaleTo100))

        local function safeTest(fn, ...)
            local ok, v = pcall(fn, ...)
            if not ok then return "err", nil end
            if type(v) ~= "number" then return "non-number(" .. type(v) .. ")", nil end
            if _isSecret and _isSecret(v) then return "secret", nil end
            return "plain", v
        end

        for unit, data in pairs(healerData) do
            print("  -- [" .. unit .. "] " .. tostring(data.name or "?"))

            local s, n = safeTest(UnitPowerMax, unit, MANA)
            print("    UnitPowerMax(MANA): " .. s ..
                  (n and ("  value=" .. n) or ""))

            s, n = safeTest(UnitPower, unit, MANA)
            print("    UnitPower(MANA):    " .. s ..
                  (n and ("  value=" .. n) or ""))

            s, n = safeTest(UnitPowerPercent, unit, MANA)
            print("    UnitPowerPercent(u,MANA): " .. s ..
                  (n and ("  value=" .. n) or ""))

            s, n = safeTest(UnitPowerPercent, unit, MANA, true, _scaleTo100)
            print("    UnitPowerPercent(u,MANA,true,ScaleTo100): " .. s ..
                  (n and ("  value=" .. n) or ""))

            s, n = safeTest(UnitPowerPercent, unit, nil, true, _scaleTo100)
            print("    UnitPowerPercent(u,nil,true,ScaleTo100):  " .. s ..
                  (n and ("  value=" .. n) or ""))
        end
    end
    print("|cff00ccffHealerMana DEBUG|r ---- end")
end

local specMonitorTicker = nil
local function toggleSpecMonitor()
    if specMonitorTicker then
        specMonitorTicker:Cancel()
        specMonitorTicker = nil
        print("|cff00ccffHealerMana|r: spec monitor OFF")
        return
    end
    print("|cff00ccffHealerMana|r: spec monitor ON (TEMP) - sampling every 2s, /hm specmonitor to stop")
    specMonitorTicker = C_Timer.NewTicker(2, function()
        for unit, data in pairs(healerData) do
            if not UnitIsUnit(unit, "player") then
                local ok, specID = pcall(GetInspectSpecialization, unit)
                local roleOk, role = false, nil
                if ok and type(specID) == "number" and specID > 0 then
                    roleOk, role = pcall(GetSpecializationRoleByID, specID)
                end
                print(string.format("  [%s] %s  storedIcon=%s  liveSpecID=%s(ok=%s)  liveRole=%s(ok=%s)",
                    unit, tostring(UnitName(unit)),
                    tostring(data.specIcon ~= nil),
                    tostring(specID), tostring(ok),
                    tostring(role), tostring(roleOk)))
            end
        end
    end)
end

local auraLogTicker = nil
local function toggleAuraLog()
    if auraLogTicker then
        auraLogTicker:Cancel()
        auraLogTicker = nil
        print("|cff00ccffHealerMana|r: aura log OFF - entries saved in HealerManaDB.auraLog (survives /reload, read after logout/reload from the SavedVariables file)")
        return
    end
    HealerManaDB.auraLog = HealerManaDB.auraLog or {}
    print("|cff00ccffHealerMana|r: aura log ON (TEMP) - go eat/drink now, new auras are saved to HealerManaDB.auraLog. /hm auralog to stop")
    auraLogTicker = C_Timer.NewTicker(2, function()
        local ok, auras = pcall(C_UnitAuras.GetUnitAuras, "player", "HELPFUL")
        if not ok or type(auras) ~= "table" then
            print("  aura log: GetUnitAuras failed - " .. tostring(auras))
            return
        end
        local now = date("%H:%M:%S")
        for _, aura in ipairs(auras) do
            local key = tostring(aura.spellId)
            local entry = HealerManaDB.auraLog[key]
            if not entry then
                entry = {name = aura.name, spellId = aura.spellId, duration = aura.duration, firstSeen = now}
                HealerManaDB.auraLog[key] = entry
                print(string.format("|cff00ccffHealerMana|r aura log: NEW  %s  spellId=%s  duration=%s",
                    tostring(aura.name), tostring(aura.spellId), tostring(aura.duration)))
            end
            entry.lastSeen = now
        end
    end)
end

local function printRegenDebug()
    print("|cff00ccffHealerMana|r: regen debug (TEMP command, remove after verifying) ---")
    local checked = 0
    local function reportUnit(unit)
        checked = checked + 1
        local idResults = {}
        for _, spellID in ipairs(HM.FOOD_DRINK_SPELL_IDS) do
            local ok, aura = pcall(C_UnitAuras.GetUnitAuraBySpellID, unit, spellID)
            local secret = ok and type(aura) == "table" and HM.isSecretTable and HM.isSecretTable(aura)
            idResults[#idResults + 1] = string.format("%s(ok=%s,type=%s,secret=%s)", spellID, tostring(ok), tostring(type(aura)), tostring(secret))
        end
        local nameResults = {}
        for _, name in ipairs(HM.FOOD_DRINK_NAMES) do
            local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, name, "HELPFUL")
            local secret = ok and type(aura) == "table" and HM.isSecretTable and HM.isSecretTable(aura)
            nameResults[#nameResults + 1] = string.format("%s(ok=%s,type=%s,secret=%s)", name, tostring(ok), tostring(type(aura)), tostring(secret))
        end
        local storedRegen = healerData[unit] and healerData[unit].regenState
        local storedDead  = healerData[unit] and healerData[unit].dead
        print(string.format("  [%s] %s  inCombat=%s",
            unit, tostring(UnitName(unit)), tostring(InCombatLockdown())))
        print("    food/drink spellIDs: " .. table.concat(idResults, " "))
        print("    food/drink names: " .. table.concat(nameResults, " "))
        print(string.format("    liveRegenState=%s  storedRegenState=%s  liveDead=%s  storedDead=%s",
            tostring(HM.getRegenState(unit)), tostring(storedRegen),
            tostring(UnitIsDeadOrGhost(unit)), tostring(storedDead)))
    end
    for unit in pairs(healerData) do reportUnit(unit) end
    if checked == 0 then
        print("  (no tracked healers - scanning group units instead)")
        forEachGroupUnit(reportUnit)
        if not IsInRaid() and not IsInGroup() and UnitExists("player") then
            reportUnit("player")
        end
    end
    print("|cff00ccffHealerMana|r: --- end regen debug")
end

function HM.setupSlash()
    SLASH_HEALERMANA1 = "/healermana"
    SLASH_HEALERMANA2 = "/hm"
    SlashCmdList["HEALERMANA"] = function(msg)
        local cmd = (msg or ""):lower():match("^%s*(.-)%s*$")

        if cmd == "" or cmd == "config" or cmd == "options" then
            HM.openConfig()

        elseif cmd == "lock" then
            HM.saveKey("locked", not cfg.locked)
            HM.mainFrame:EnableMouse(not cfg.locked)
            print("|cff00ccffHealerMana|r: frame " ..
                  (cfg.locked and "|cffff4444locked|r (click-through)" or "|cff00ff00unlocked|r (drag to move)"))

        elseif cmd == "alpha" then
            HM.saveKey("sortMode", "alpha")
            print("|cff00ccffHealerMana|r: sort set to |cff00ff00alphabetical|r")
            HM.refreshDisplay()

        elseif cmd == "class" then
            HM.saveKey("sortMode", "class")
            print("|cff00ccffHealerMana|r: sort set to |cff00ff00healer class|r")
            HM.refreshDisplay()

        elseif cmd == "layout" then
            HM.saveKey("layoutHorizontal", not cfg.layoutHorizontal)
            print("|cff00ccffHealerMana|r: layout " ..
                  (cfg.layoutHorizontal and "|cff00ff00horizontal|r" or "|cff00ff00vertical|r"))
            HM.rebuildBarPool()
            HM.refreshDisplay()

        elseif cmd == "raid" or cmd:match("^raid%s") then
            local arg = cmd:match("^raid%s+(%S+)$")
            if not arg or arg == "off" or arg == "0" then
                HM.testModeActive = false
                print("|cff00ccffHealerMana|r: test mode OFF, restoring real roster.")
                HM.rebuildRoster()
                HM.refreshDisplay()
            else
                local n = tonumber(arg)
                if not n or n < 1 then
                    print("|cff00ccffHealerMana|r: usage - /hm raid <count> (1-20), or /hm raid off")
                else
                    n = math.min(math.floor(n), 20)
                    HM.testModeActive = true
                    HM.saveKey("testPreviewCount", n)
                    HM.generateTestRoster(n)
                    print("|cff00ccffHealerMana|r: test mode ON - " .. n ..
                          " fake healers. /hm raid off to restore.")
                    HM.refreshDisplay()
                end
            end

        elseif cmd == "debug" then
            printDebug()

        elseif cmd == "regendebug" then
            printRegenDebug()

        elseif cmd == "specmonitor" then
            toggleSpecMonitor()

        elseif cmd == "auralog" then
            toggleAuraLog()

        elseif cmd == "raidregen" then
            HM.testModeActive = true
            HM.generateTestRoster(3)
            if healerData["test2"] then
                healerData["test2"].regenState = "drinking"
                healerData["test2"].regenIcon = C_Spell.GetSpellTexture(HM.DRINK_SPELL_ID)
            end
            print("|cff00ccffHealerMana|r: regen preview ON (TEMP command) - " ..
                  "test2=Food & Drink icon, test1/test3=normal. /hm raid off to restore.")
            HM.refreshDisplay()

        elseif cmd == "range" then
            local _, class = UnitClass("player")
            print("|cff00ccffHealerMana|r: range debug ---")
            print("  player class: " .. tostring(class))
            print("  rangeCheckSpell: " .. tostring(HM.rangeCheckSpell))
            if HM.rangeCheckSpell then
                local info = C_Spell.GetSpellInfo(HM.rangeCheckSpell)
                print("  spell name: " .. tostring(info and info.name))
            end
            print("  dimOutOfRange cfg: " .. tostring(cfg.dimOutOfRange))
            print("  issecretvalue API: " .. (issecretvalue and "available (WoW 12.0+)" or "NOT available"))
            local healerCount = 0
            for _ in pairs(healerData) do healerCount = healerCount + 1 end
            print("  tracked healers: " .. healerCount .. (healerCount == 0 and " (not in a group?)" or ""))
            for unit in pairs(healerData) do
                local spellResult = HM.rangeCheckSpell and C_Spell.IsSpellInRange(HM.rangeCheckSpell, unit)
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
                    tostring(HM.isUnitInRange(unit))))
            end
            print("|cff00ccffHealerMana|r: --- end range debug")

        elseif cmd == "help" then
            printHelp()

        elseif cmd == "reset" then
            HM.resetPosition()

        else
            printHelp()
        end
    end
end
