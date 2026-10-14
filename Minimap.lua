local ADDON_NAME, HM = ...

local ICON_PATH = "Interface\\AddOns\\HealerMana\\HealerMana_32x32.tga"

function HM.setMinimapIconShown(shown)
    local ldbIcon = LibStub("LibDBIcon-1.0")
    HealerManaDB.minimap = HealerManaDB.minimap or {}
    HealerManaDB.minimap.hide = not shown
    if shown then
        ldbIcon:Show(ADDON_NAME)
    else
        ldbIcon:Hide(ADDON_NAME)
    end
end

function HM.initMinimapIcon()
    local dataObject = LibStub("LibDataBroker-1.1"):NewDataObject(ADDON_NAME, {
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

    local ldbIcon = LibStub("LibDBIcon-1.0")
    HealerManaDB.minimap = HealerManaDB.minimap or { hide = false }
    ldbIcon:Register(ADDON_NAME, dataObject, HealerManaDB.minimap)
    local button = ldbIcon:GetMinimapButton(ADDON_NAME)
    if button then
        button:SetHitRectInsets(0, 0, 0, 0)
        button:SetFrameLevel(button:GetFrameLevel() + 1)
    end
end
