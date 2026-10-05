local _, HM = ...

local cfg = HM.cfg

local function printHelp()
    print("|cff00ccffHealerMana|r - type |cffffff00/hm|r to open the settings panel, or:")
    print("  |cffffff00/hm lock|r    - toggle frame lock/unlock")
    print("  |cffffff00/hm alpha|r   - sort alphabetically")
    print("  |cffffff00/hm class|r   - sort by healer class")
    print("  |cffffff00/hm layout|r  - toggle horizontal/vertical layout")
    print("  |cffffff00/hm reset|r   - reset frame to default position")
    print("  |cffffff00/hm raid <n>|r - populate n fake healers to test layout (off to restore)")
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

        elseif cmd == "help" then
            printHelp()

        elseif cmd == "reset" then
            HM.resetPosition()

        else
            printHelp()
        end
    end
end
