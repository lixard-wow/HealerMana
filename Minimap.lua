local ADDON_NAME, HM = ...

local ICON_PATH = "Interface\\AddOns\\HealerMana\\HealerMana_32x32.tga"

function HM.setMinimapIconShown(shown)
    local LibStub = _G.LibStub
    local ldbIcon = LibStub and LibStub("LibDBIcon-1.0", true)
    if not ldbIcon then return end
    HealerManaDB.minimap = HealerManaDB.minimap or {}
    HealerManaDB.minimap.hide = not shown
    if shown then
        ldbIcon:Show(ADDON_NAME)
    else
        ldbIcon:Hide(ADDON_NAME)
    end
end

function HM.initMinimapIcon()
    local LibStub = _G.LibStub
    local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
    if not ldb then return end

    local dataObject = ldb:NewDataObject(ADDON_NAME, {
        type = "launcher",
        text = "HealerMana",
        icon = ICON_PATH,
        OnClick = function()
            HM.openConfig()
        end,
        OnTooltipShow = function(tt)
            tt:AddLine("HealerMana")
            tt:AddLine(" ")
            tt:AddLine("Tracks the mana of every healer in your group or raid.", 1, 1, 1, true)
            tt:AddLine(" ")
            tt:AddLine("|cff1eff00Left-Click|r Open settings")
        end,
    })

    local ldbIcon = LibStub("LibDBIcon-1.0", true)
    if ldbIcon then
        HealerManaDB.minimap = HealerManaDB.minimap or { hide = false }
        ldbIcon:Register(ADDON_NAME, dataObject, HealerManaDB.minimap)
        local button = ldbIcon.objects and ldbIcon.objects[ADDON_NAME]
        if button then
            button:SetHitRectInsets(0, 0, 0, 0)
            button:SetFrameLevel(button:GetFrameLevel() + 1)
        end
    end
end
