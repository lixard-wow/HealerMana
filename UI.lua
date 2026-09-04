local _, HM = ...

local cfg     = HM.cfg
local barPool = HM.barPool

function HM.autoFontSizes(cellSize)
    local nameFs = math.max(8, math.min(20, math.floor(cellSize * 0.19 + 0.5)))
    local pctFs  = math.max(8, math.min(20, math.floor(cellSize * 0.27 + 0.5)))
    return nameFs, pctFs
end

local NAME_HEIGHT = 14
local MIN_NAME_FONT = 6
local PCT_RESERVE = 44

local function shrinkTextToFit(fs, baseSize, maxW)
    local size = baseSize
    local fontPath = HM.getFontPath()
    fs:SetFont(fontPath, size, "OUTLINE")
    while size > MIN_NAME_FONT and fs:GetStringWidth() > maxW do
        size = size - 1
        fs:SetFont(fontPath, size, "OUTLINE")
    end
    return size
end

local function autoBarFontSize(barHeight)
    return math.max(8, math.min(20, math.floor(barHeight * 0.55 + 0.5)))
end

local function effectiveNameFontSize(autoSize)
    if cfg.fontSizeOverride then return cfg.nameFontSizeManual end
    return autoSize
end

local function effectivePctFontSize(autoSize)
    if cfg.fontSizeOverride then return cfg.pctFontSizeManual end
    return autoSize
end

local function stripLastUTF8Char(s)
    local i = #s
    if i == 0 then return s end
    while i > 1 and s:byte(i) >= 0x80 and s:byte(i) < 0xC0 do
        i = i - 1
    end
    return s:sub(1, i - 1)
end

local function truncateTextToFit(fs, text, maxW)
    fs:SetText(text)
    if fs:GetStringWidth() <= maxW then return end
    local truncated = text
    while #truncated > 0 do
        truncated = stripLastUTF8Char(truncated)
        fs:SetText(truncated .. "…")
        if #truncated == 0 or fs:GetStringWidth() <= maxW then break end
    end
    if #truncated == 0 then fs:SetText("…") end
end

local FORM_LABEL = {CAT = "Cat", BEAR = "Bear", MOONKIN = "Moonkin"}
local FORM_COLOR = {CAT = {1.00, 0.65, 0.00}, BEAR = {0.70, 0.40, 0.15}, MOONKIN = {0.60, 0.40, 0.90}}
local NO_MANA_FORMS = {CAT = true, BEAR = true}

local CLASS_COLOR = {
    DRUID   = {1.000, 0.490, 0.039},
    PALADIN = {0.961, 0.549, 0.729},
    PRIEST  = {1.000, 1.000, 1.000},
    SHAMAN  = {0.000, 0.439, 0.871},
    MONK    = {0.000, 1.000, 0.600},
    EVOKER  = {0.200, 0.580, 0.500},
}

local _wrapStr = HM.wrapStr

local mainFrame
local BORDER_OVERHANG = 8

local function createBar(idx)
    if cfg.displayStyle == "bar" then
        local w, h = cfg.barWidth, cfg.barHeight
        local bar = CreateFrame("Frame", nil, mainFrame)
        bar:SetSize(w, h)

        bar.bg = bar:CreateTexture(nil, "BACKGROUND")
        bar.bg:SetAllPoints()
        bar.bg:SetColorTexture(cfg.bgColor.r, cfg.bgColor.g, cfg.bgColor.b, cfg.bgColor.a)

        bar.fill = CreateFrame("StatusBar", nil, bar)
        bar.fill:SetPoint("TOPLEFT", bar, "TOPLEFT", 1, -1)
        bar.fill:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -1, 1)
        local texPath = "Interface\\TargetingFrame\\UI-StatusBar"
        local LSM = HM.getLSM()
        if LSM then
            texPath = LSM:Fetch("statusbar", cfg.barTexture) or texPath
        end
        bar.fill:SetStatusBarTexture(texPath)
        bar.fill:SetMinMaxValues(0, 100)
        bar.fill:SetValue(100)

        if cfg.showName then
            bar.nameTxt = bar.fill:CreateFontString(nil, "OVERLAY")
            bar.nameTxt:SetFont(HM.getFontPath(), effectiveNameFontSize(autoBarFontSize(h)), "OUTLINE")
            bar.nameTxt:SetPoint("LEFT", bar, "LEFT", 4, 0)
            bar.nameTxt:SetJustifyH("LEFT")
            bar.nameTxt:SetWordWrap(false)
        end

        bar.pctTxt = bar.fill:CreateFontString(nil, "OVERLAY")
        bar.pctTxt:SetFont(HM.getFontPath(), effectivePctFontSize(autoBarFontSize(h)), "OUTLINE")
        bar.pctTxt:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
        bar.pctTxt:SetJustifyH("RIGHT")

        barPool[idx] = bar
        return bar
    end

    local cs      = cfg.cellSize
    local nameH   = cfg.showName and (NAME_HEIGHT + 2) or 0
    local bar = CreateFrame("Frame", nil, mainFrame)
    bar:SetSize(cs, cs + nameH)

    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    bar.bg:SetSize(cs, cs)
    bar.bg:SetColorTexture(cfg.bgColor.r, cfg.bgColor.g, cfg.bgColor.b, cfg.bgColor.a)

    bar.icon = bar:CreateTexture(nil, "ARTWORK")
    bar.icon:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    bar.icon:SetSize(cs, cs)

    bar.tint = bar:CreateTexture(nil, "OVERLAY")
    bar.tint:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    bar.tint:SetSize(cs, cs)
    bar.tint:SetTexture("Interface\\BUTTONS\\WHITE8X8")
    bar.tint:SetBlendMode("BLEND")
    bar.tint:SetAlpha(cfg.iconTintOpacity)

    bar.border = CreateFrame("Frame", nil, bar, "BackdropTemplate")
    bar.border:SetPoint("TOPLEFT", bar.icon, "TOPLEFT", -4, 4)
    bar.border:SetPoint("BOTTOMRIGHT", bar.icon, "BOTTOMRIGHT", 4, -4)
    bar.border:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    bar.border:SetBackdropBorderColor(0.85, 0.85, 0.85, 1)

    local pctFs = effectivePctFontSize(cfg.pctFontSize)
    bar.pctTxt = bar:CreateFontString(nil, "OVERLAY")
    bar.pctTxt:SetFont(HM.getFontPath(), pctFs, "OUTLINE")
    bar.pctTxt:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, -(cs / 2 - pctFs / 2))
    bar.pctTxt:SetWidth(cs)
    bar.pctTxt:SetJustifyH("CENTER")

    if cfg.showName then
        local nameFs = effectiveNameFontSize(cfg.nameFontSize)
        bar.nameTxt = bar:CreateFontString(nil, "OVERLAY")
        bar.nameTxt:SetFont(HM.getFontPath(), nameFs, "OUTLINE")
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

function HM.rebuildBarPool()
    for _, b in ipairs(barPool) do b:Hide() end
    wipe(barPool)
end

local function positionBar(bar, idx)
    bar:ClearAllPoints()
    local gap = cfg.cellSpacing
    if cfg.displayStyle == "bar" then
        local w, h = cfg.barWidth, cfg.barHeight
        if cfg.gridEnabled then
            local cols = cfg.gridColumns
            local col  = (idx - 1) % cols
            local row  = math.floor((idx - 1) / cols)
            bar:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", col * (w + gap), -row * (h + gap))
        elseif cfg.layoutHorizontal then
            bar:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", (idx - 1) * (w + gap), 0)
        else
            bar:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 0, -(idx - 1) * (h + gap))
        end
        return
    end

    local cs    = cfg.cellSize
    local nameH = cfg.showName and (NAME_HEIGHT + 2) or 0
    if cfg.gridEnabled then
        local cols  = cfg.gridColumns
        local xStep = cs + BORDER_OVERHANG + gap
        local yStep = cs + nameH + gap
        local col   = (idx - 1) % cols
        local row   = math.floor((idx - 1) / cols)
        bar:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", col * xStep, -row * yStep)
    elseif cfg.layoutHorizontal then
        local step = cs + BORDER_OVERHANG + gap
        bar:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", (idx - 1) * step, 0)
    else
        bar:SetPoint("TOPLEFT", mainFrame, "TOPLEFT",
            0, -(idx - 1) * (cs + nameH + gap))
    end
end

local function getFillColor(data)
    if cfg.barColorMode == "custom" then
        local c = cfg.barColorCustom
        return c.r, c.g, c.b
    else
        local cc = CLASS_COLOR[data.class]
        if cc then return cc[1], cc[2], cc[3] end
        local c = cfg.barColorCustom
        return c.r, c.g, c.b
    end
end

local function setPctText(fs, pct)
    if HM.isPlainNumber(pct) then
        local p = math.floor(pct + 0.5)
        fs:SetText(cfg.showPctSymbol and (p .. "%") or tostring(p))
    elseif pct ~= nil and _wrapStr then
        local formatted = cfg.showPctSymbol and format("%.0f%%", pct) or format("%.0f", pct)
        fs:SetFormattedText("%s", _wrapStr(formatted, "", ""))
    else
        fs:SetText("")
    end
end

local function renderBar(bar, data)
    if cfg.dimOutOfRange and not UnitIsUnit(data.unit, "player") then
        local inRange = HM.isUnitInRange(data.unit)
        if issecretvalue and issecretvalue(inRange) then
            bar:SetAlphaFromBoolean(inRange, 1, cfg.outOfRangeOpacity)
        elseif inRange == false then
            bar:SetAlpha(cfg.outOfRangeOpacity)
        else
            bar:SetAlpha(1)
        end
    else
        bar:SetAlpha(1)
    end

    if cfg.displayStyle == "bar" then
        local displayName = data.name
        if data.regenState == "drinking" then
            displayName = "Drinking"
        elseif data.form then
            displayName = "[" .. FORM_LABEL[data.form] .. "] " .. data.name
        end
        if bar.nameTxt then
            if bar.nameTxt._lastName ~= displayName then
                local maxW = math.max(bar:GetWidth() - PCT_RESERVE - 8, 10)
                if cfg.nameOverflow == "truncate" then
                    bar.nameTxt:SetFont(HM.getFontPath(), effectiveNameFontSize(autoBarFontSize(cfg.barHeight)), "OUTLINE")
                    truncateTextToFit(bar.nameTxt, displayName, maxW)
                else
                    bar.nameTxt:SetText(displayName)
                    shrinkTextToFit(bar.nameTxt, effectiveNameFontSize(autoBarFontSize(cfg.barHeight)), maxW)
                end
                bar.nameTxt._lastName = displayName
            end
        end
        local cc = CLASS_COLOR[data.class]
        if not data.connected then
            bar.fill:SetStatusBarColor(0.4, 0.4, 0.4, cfg.barFillOpacity)
            bar.fill:SetValue(100)
            bar.pctTxt:SetText("Offline")
            bar.pctTxt:SetTextColor(0.6, 0.6, 0.6)
            if bar.nameTxt then bar.nameTxt:SetTextColor(0.6, 0.6, 0.6) end
        elseif data.dead then
            bar.fill:SetStatusBarColor(0.4, 0.4, 0.4, cfg.barFillOpacity)
            bar.fill:SetValue(100)
            bar.pctTxt:SetText("Dead")
            bar.pctTxt:SetTextColor(0.9, 0.3, 0.3)
            if bar.nameTxt then bar.nameTxt:SetTextColor(0.6, 0.6, 0.6) end
        else
            local pct = data.testPct or HM.readUnitPctRaw(data.unit)
            local fr, fg, fb = getFillColor(data)
            bar.fill:SetStatusBarColor(fr, fg, fb, cfg.barFillOpacity)
            if bar.nameTxt then
                if data.form then
                    local fc = FORM_COLOR[data.form]
                    bar.nameTxt:SetTextColor(fc[1], fc[2], fc[3])
                elseif cc and cfg.nameClassColor then
                    bar.nameTxt:SetTextColor(cc[1], cc[2], cc[3])
                else
                    local nc = cfg.nameCustomColor
                    bar.nameTxt:SetTextColor(nc.r, nc.g, nc.b)
                end
            end

            bar.fill:SetValue(pct or 0)

            if NO_MANA_FORMS[data.form] then
                bar.pctTxt:SetText("")
            else
                setPctText(bar.pctTxt, pct)
            end
            if cc and cfg.pctClassColor then
                bar.pctTxt:SetTextColor(cc[1], cc[2], cc[3])
            else
                local pc = cfg.pctCustomColor
                bar.pctTxt:SetTextColor(pc.r, pc.g, pc.b)
            end
        end
        bar:Show()
        return
    end

    local iconID = data.specIcon
    local showingOverrideIcon = false
    if data.regenState == "drinking" and data.regenIcon then
        iconID = data.regenIcon
        showingOverrideIcon = true
    elseif data.form and HM.FORM_ICON[data.form] then
        iconID = HM.FORM_ICON[data.form]
        showingOverrideIcon = true
    end
    if type(iconID) == "table" then
        bar.icon:SetTexture(iconID.texture)
        bar.icon:SetTexCoord(unpack(iconID.coords))
    elseif iconID then
        bar.icon:SetTexture(iconID)
        bar.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    else
        bar.icon:SetTexture(nil)
    end

    local cc = CLASS_COLOR[data.class]
    if bar.nameTxt then
        if bar.nameTxt._lastName ~= data.name then
            if cfg.nameOverflow == "truncate" then
                bar.nameTxt:SetFont(HM.getFontPath(), effectiveNameFontSize(cfg.nameFontSize), "OUTLINE")
                truncateTextToFit(bar.nameTxt, data.name, bar.nameTxt:GetWidth())
            else
                bar.nameTxt:SetText(data.name)
                shrinkTextToFit(bar.nameTxt, effectiveNameFontSize(cfg.nameFontSize), bar.nameTxt:GetWidth())
            end
            bar.nameTxt._lastName = data.name
        end
        if cc and cfg.nameClassColor then
            bar.nameTxt:SetTextColor(cc[1], cc[2], cc[3])
        else
            local nc = cfg.nameCustomColor
            bar.nameTxt:SetTextColor(nc.r, nc.g, nc.b)
        end
    end
    if cc and cfg.borderClassColor then
        bar.border:SetBackdropBorderColor(cc[1], cc[2], cc[3], 1)
    else
        local bc = cfg.borderCustomColor
        bar.border:SetBackdropBorderColor(bc.r, bc.g, bc.b, 1)
    end

    if not data.connected then
        bar.pctTxt:SetText("Offline")
        bar.pctTxt:SetTextColor(0.6, 0.6, 0.6)
        bar.icon:SetAlpha(0.4)
        bar.tint:SetColorTexture(0.4, 0.4, 0.4)
        bar.tint:SetAlpha(showingOverrideIcon and 0 or cfg.iconTintOpacity)
    elseif data.dead then
        bar.pctTxt:SetText("Dead")
        bar.pctTxt:SetTextColor(0.9, 0.3, 0.3)
        bar.icon:SetAlpha(0.4)
        bar.tint:SetColorTexture(0.4, 0.4, 0.4)
        bar.tint:SetAlpha(showingOverrideIcon and 0 or cfg.iconTintOpacity)
    else
        bar.icon:SetAlpha(1)
        if cc and cfg.pctClassColor then
            bar.pctTxt:SetTextColor(cc[1], cc[2], cc[3])
        else
            local pc = cfg.pctCustomColor
            bar.pctTxt:SetTextColor(pc.r, pc.g, pc.b)
        end

        local pct = data.testPct or HM.readUnitPctRaw(data.unit)
        local fr, fg, fb = getFillColor(data)

        if NO_MANA_FORMS[data.form] then
            bar.pctTxt:SetText("")
        else
            setPctText(bar.pctTxt, pct)
        end
        bar.tint:SetColorTexture(fr, fg, fb)
        bar.tint:SetAlpha(showingOverrideIcon and 0 or cfg.iconTintOpacity)
    end

    bar:Show()
end

local refreshQueued = false
function HM.refreshDisplay()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0, function()
        refreshQueued = false

        local sorted = HM.getSorted()
        local count  = #sorted
        local gap    = cfg.cellSpacing
        local totalW, totalH
        if cfg.displayStyle == "bar" then
            local w, h = cfg.barWidth, cfg.barHeight
            if cfg.gridEnabled then
                local cols     = cfg.gridColumns
                local usedCols = count > 0 and math.min(count, cols) or 0
                local rows     = count > 0 and math.ceil(count / cols) or 0
                totalW = count > 0 and ((usedCols - 1) * (w + gap) + w) or 1
                totalH = count > 0 and ((rows - 1) * (h + gap) + h) or 1
            elseif cfg.layoutHorizontal then
                totalW = count > 0 and ((count - 1) * (w + gap) + w) or 1
                totalH = h
            else
                totalW = w
                totalH = count > 0 and (count * (h + gap) - gap) or 1
            end
            mainFrame:SetSize(totalW, totalH)

            for i, entry in ipairs(sorted) do
                local bar = getBar(i)
                positionBar(bar, i)
                renderBar(bar, entry.data)
            end
            for i = count + 1, #barPool do
                barPool[i]:Hide()
            end
            if count > 0 and HM.shouldShowForCurrentInstance() then mainFrame:Show() else mainFrame:Hide() end
            return
        end

        local cs     = cfg.cellSize
        local nameH  = cfg.showName and (NAME_HEIGHT + 2) or 0
        local cellH  = cs + nameH
        if cfg.gridEnabled then
            local cols     = cfg.gridColumns
            local xStep    = cs + BORDER_OVERHANG + gap
            local yStep    = cs + nameH + gap
            local usedCols = count > 0 and math.min(count, cols) or 0
            local rows     = count > 0 and math.ceil(count / cols) or 0
            totalW = count > 0 and ((usedCols - 1) * xStep + cs) or 1
            totalH = count > 0 and ((rows - 1) * yStep + cellH) or 1
        elseif cfg.layoutHorizontal then
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

        for i = count + 1, #barPool do
            barPool[i]:Hide()
        end

        if count > 0 and HM.shouldShowForCurrentInstance() then mainFrame:Show() else mainFrame:Hide() end
    end)
end

function HM.createMainFrame()
    mainFrame = CreateFrame("Frame", "HealerManaFrame", UIParent)
    HM.mainFrame = mainFrame
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
        HealerManaDB.point    = p
        HealerManaDB.relPoint = rp
        HealerManaDB.x        = x
        HealerManaDB.y        = y
    end)

    mainFrame:Hide()
end
