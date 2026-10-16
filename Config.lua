local _, HM = ...

local cfg     = HM.cfg
local barPool = HM.barPool
local Theme   = HM.Theme

local HEADER_H = 42

local function label(parent, text, size, colorKey)
    local fs = Theme.Text(parent, "body", size or 12, colorKey or "muted")
    fs:SetText(text or "")
    return fs
end

local function maskCircle(owner, texture)
    local mask = owner:CreateMaskTexture()
    mask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
    mask:SetAllPoints(texture)
    texture:AddMaskTexture(mask)
end

local function makeToggle(parent, labelText, getVal, onToggle)
    local BOX = 16
    local tog = CreateFrame("Button", nil, parent)
    tog:SetHeight(BOX)
    tog:RegisterForClicks("LeftButtonUp")

    local cb = Theme.Check(tog, BOX, function(self) onToggle(self:GetChecked()) end)
    cb:SetPoint("LEFT", tog, "LEFT", 0, 0)
    cb:SetChecked(getVal() == true)

    local lbl = label(tog, labelText)
    lbl:SetPoint("LEFT", cb, "RIGHT", 8, 0)

    local function hover(on) Theme.SetColor(lbl, on and "text" or "muted") end
    tog:SetScript("OnClick", function() cb:Click() end)
    tog:SetScript("OnEnter", function() hover(true) end)
    tog:SetScript("OnLeave", function() hover(false) end)
    cb:HookScript("OnEnter", function() hover(true) end)
    cb:HookScript("OnLeave", function() hover(false) end)
    Theme.Skin(function() tog:SetWidth(BOX + 8 + lbl:GetStringWidth() + 8) end)

    function tog:SetChecked(v) cb:SetChecked(v == true) end
    function tog:GetChecked() return cb:GetChecked() end
    return tog
end

local function makeSlider(parent, labelText, minVal, maxVal, stepVal, onChange)
    local TRACK_H = 4
    local THUMB_SIZE = 14
    local THUMB_RADIUS = THUMB_SIZE / 2
    local s = CreateFrame("Frame", nil, parent)
    s:SetHeight(40)

    s.lbl = label(s, labelText)
    s.lbl:SetPoint("TOPLEFT", s, "TOPLEFT", 0, 0)

    s.valTxt = Theme.Text(s, "strong", 12, "accent")
    s.valTxt:SetPoint("TOPRIGHT", s, "TOPRIGHT", 0, 0)
    s.valTxt:SetJustifyH("RIGHT")

    local track = CreateFrame("Frame", nil, s)
    track:SetPoint("TOPLEFT",  s, "TOPLEFT",  THUMB_RADIUS, -22)
    track:SetPoint("TOPRIGHT", s, "TOPRIGHT", -THUMB_RADIUS, -22)
    track:SetHeight(TRACK_H)
    Theme.Box(track, "well", "border", "none")

    local fill = track:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("LEFT", track, "LEFT", 0, 0)
    fill:SetHeight(TRACK_H)

    local thumb = CreateFrame("Frame", nil, track)
    thumb:SetSize(THUMB_SIZE, THUMB_SIZE)
    thumb:SetFrameLevel(track:GetFrameLevel() + 1)

    local thumbRing = thumb:CreateTexture(nil, "BACKGROUND")
    thumbRing:SetAllPoints()
    maskCircle(thumb, thumbRing)

    local thumbDot = thumb:CreateTexture(nil, "ARTWORK")
    thumbDot:SetPoint("TOPLEFT", 2, -2)
    thumbDot:SetPoint("BOTTOMRIGHT", -2, 2)
    maskCircle(thumb, thumbDot)

    Theme.Skin(function(_, C)
        fill:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.8)
        thumbRing:SetColorTexture(C.window[1], C.window[2], C.window[3], 1)
        thumbDot:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    end)

    local hit = CreateFrame("Button", nil, track)
    hit:SetPoint("TOPLEFT",     track, "TOPLEFT",     -4,  8)
    hit:SetPoint("BOTTOMRIGHT", track, "BOTTOMRIGHT",  4, -8)
    hit:RegisterForClicks("LeftButtonDown", "LeftButtonUp")

    s._value = minVal

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
        s._value = v
        redraw()
    end
    function s:GetValue() return s._value end

    local function fromCursor()
        local x = GetCursorPosition() / hit:GetEffectiveScale()
        local l, r = hit:GetLeft() or 0, hit:GetRight() or 1
        if r <= l then return minVal end
        return minVal + math.max(0, math.min(1, (x - l) / (r - l))) * (maxVal - minVal)
    end
    hit:SetScript("OnMouseDown", function()
        s:SetValue(fromCursor())
        onChange(s._value)
        s:SetScript("OnUpdate", function()
            local v = snap(fromCursor())
            if v ~= s._value then
                s:SetValue(v)
                onChange(s._value)
            end
        end)
    end)
    hit:SetScript("OnMouseUp", function() s:SetScript("OnUpdate", nil) end)
    track:HookScript("OnSizeChanged", redraw)
    s:SetValue(minVal)
    return s
end

local function makeStepper(parent, getVal, onChange, minVal, maxVal)
    local s = CreateFrame("Frame", nil, parent)
    s:SetSize(96, 24)

    local minusBtn = Theme.TextButton(s, "-", 24, 24)
    minusBtn:SetPoint("LEFT", s, "LEFT", 0, 0)

    local plusBtn = Theme.TextButton(s, "+", 24, 24)
    plusBtn:SetPoint("RIGHT", s, "RIGHT", 0, 0)

    local valTxt = Theme.Text(s, "strong", 12, "text")
    valTxt:SetPoint("TOPLEFT",     minusBtn, "TOPRIGHT",   0, 0)
    valTxt:SetPoint("BOTTOMRIGHT", plusBtn,  "BOTTOMLEFT", 0, 0)
    valTxt:SetJustifyH("CENTER")

    function s:Refresh()
        valTxt:SetText(tostring(getVal()))
    end

    minusBtn:SetScript("OnClick", function()
        onChange(math.max(minVal, getVal() - 1))
        s:Refresh()
    end)
    plusBtn:SetScript("OnClick", function()
        onChange(math.min(maxVal, getVal() + 1))
        s:Refresh()
    end)

    s:Refresh()
    return s
end

local function makeDropdown(parent, labelText, options, getVal, onSelect)
    local d = CreateFrame("Frame", nil, parent)
    d:SetHeight(40)

    d.lbl = label(d, labelText)
    d.lbl:SetPoint("TOPLEFT", d, "TOPLEFT", 0, 0)

    local btn = CreateFrame("Button", nil, d)
    btn:SetPoint("BOTTOMLEFT",  d, "BOTTOMLEFT",  0, 0)
    btn:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", 0, 0)
    btn:SetHeight(24)
    local _, btnEdge = Theme.Box(btn, "field", "border", "buttonRadius")
    local valTxt = Theme.Text(btn, "body", 12, "text")
    valTxt:SetPoint("LEFT", btn, "LEFT", 8, 0)
    local arrow = Theme.Text(btn, "strong", 12, "muted")
    arrow:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
    arrow:SetText("v")

    local ROW_H = 22
    local menu = CreateFrame("Frame", nil, UIParent)
    menu:SetFrameStrata("TOOLTIP")
    menu:Hide()
    Theme.Box(menu, "field", "border", "buttonRadius")
    menu:SetPoint("TOPLEFT",  btn, "BOTTOMLEFT",  0, -2)
    menu:SetPoint("TOPRIGHT", btn, "BOTTOMRIGHT", 0, -2)
    menu:SetHeight(#options * ROW_H + 8)

    local overlay = CreateFrame("Button", nil, UIParent)
    overlay:SetAllPoints(UIParent)
    overlay:SetFrameStrata("TOOLTIP")
    overlay:Hide()

    local function close()
        menu:Hide()
        overlay:Hide()
        Theme.Tint(btnEdge, Theme.C.border)
    end
    overlay:SetScript("OnClick", close)

    for i, opt in ipairs(options) do
        local row = CreateFrame("Button", nil, menu)
        row:SetFrameStrata("TOOLTIP")
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT",  menu, "TOPLEFT",  4, -4 - (i - 1) * ROW_H)
        row:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -4, -4 - (i - 1) * ROW_H)
        local rowFill = Theme.Box(row, "hover", "hover", "buttonRadius")
        row.edge:Hide()
        rowFill:Hide()
        local rowLbl = label(row, opt.label)
        rowLbl:SetPoint("LEFT", row, "LEFT", 6, 0)
        row:SetScript("OnEnter", function()
            rowFill:Show()
            Theme.SetColor(rowLbl, "text")
        end)
        row:SetScript("OnLeave", function()
            rowFill:Hide()
            Theme.SetColor(rowLbl, "muted")
        end)
        row:SetScript("OnClick", function()
            close()
            d:SetValue(opt.value)
            onSelect(opt.value)
        end)
    end

    btn:SetScript("OnClick", function()
        if menu:IsShown() then
            close()
        else
            menu:Show()
            overlay:Show()
            Theme.Tint(btnEdge, Theme.C.accent)
        end
    end)
    btn:SetScript("OnEnter", function() Theme.SetColor(arrow, "text") end)
    btn:SetScript("OnLeave", function() Theme.SetColor(arrow, "muted") end)

    function d:SetValue(v)
        for _, opt in ipairs(options) do
            if opt.value == v then
                valTxt:SetText(opt.label)
                break
            end
        end
    end
    d:SetValue(getVal())
    return d
end

local function makeColorSwatch(parent, labelText, getColor, onChange, hasAlpha)
    local SWATCH = 20
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(SWATCH)

    row.lbl = label(row, labelText)
    row.lbl:SetPoint("LEFT", row, "LEFT", 0, 0)

    local swatch = CreateFrame("Button", nil, row)
    swatch:SetSize(SWATCH, SWATCH)
    swatch:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    local _, swatchEdge = Theme.Box(swatch, "field", "border", "buttonRadius")
    swatch.tex = swatch:CreateTexture(nil, "ARTWORK")
    swatch.tex:SetPoint("TOPLEFT", 3, -3)
    swatch.tex:SetPoint("BOTTOMRIGHT", -3, 3)
    swatch:SetScript("OnEnter", function() Theme.Tint(swatchEdge, Theme.C.accent) end)
    swatch:SetScript("OnLeave", function() Theme.Tint(swatchEdge, Theme.C.border) end)

    local function refresh()
        local c = getColor()
        swatch.tex:SetColorTexture(c.r, c.g, c.b, hasAlpha and c.a or 1)
    end
    refresh()
    row.refresh = refresh

    swatch:SetScript("OnClick", function()
        local c = getColor()
        ColorPickerFrame:SetupColorPickerAndShow({
            r = c.r, g = c.g, b = c.b,
            opacity = hasAlpha and c.a or 1,
            hasOpacity = hasAlpha and true or false,
            swatchFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                local a = hasAlpha and ColorPickerFrame:GetColorAlpha() or nil
                onChange(r, g, b, a)
                refresh()
            end,
            opacityFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                local a = ColorPickerFrame:GetColorAlpha()
                onChange(r, g, b, a)
                refresh()
            end,
            cancelFunc = function(prev)
                onChange(prev.r, prev.g, prev.b, hasAlpha and prev.a or nil)
                refresh()
            end,
        })
    end)

    return row
end

local function makeTabButton(parent, labelText)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(28)

    local fill = Theme.Box(btn, "hover", "hover", "buttonRadius")
    btn.edge:Hide()

    local accent = btn:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, -4)
    accent:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 4)
    accent:SetWidth(3)

    btn.lbl = Theme.Text(btn, "strong", 12, "muted")
    btn.lbl:SetPoint("LEFT",  btn, "LEFT",  12, 0)
    btn.lbl:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
    btn.lbl:SetText(labelText or "")

    local function paint()
        local lit = btn._active or btn:IsMouseOver()
        fill:SetShown(btn._active)
        accent:SetShown(btn._active)
        accent:SetColorTexture(Theme.C.accent[1], Theme.C.accent[2], Theme.C.accent[3], 1)
        Theme.SetColor(btn.lbl, lit and "text" or "muted")
    end
    function btn:SetActive(active)
        self._active = active and true or false
        paint()
    end
    btn:SetScript("OnEnter", paint)
    btn:SetScript("OnLeave", paint)
    Theme.Skin(paint)
    return btn
end

local configFrame

local function createConfigFrame()
    local f = Theme.Frame("HealerManaConfig", "HIGH", HEADER_H, "Interface\\AddOns\\HealerMana\\HealerMana_32x32.tga", "HealerMana")
    f:SetSize(480, 560)
    f:SetPoint("CENTER")

    local FOOTER_H = 44
    local footer = CreateFrame("Frame", nil, f)
    footer:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  0, 0)
    footer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    footer:SetHeight(FOOTER_H)
    local footDiv = Theme.Line(footer)
    footDiv:SetPoint("TOPLEFT",  footer, "TOPLEFT",  1, 0)
    footDiv:SetPoint("TOPRIGHT", footer, "TOPRIGHT", -1, 0)
    footDiv:SetHeight(1)

    local resetBtn = Theme.TextButton(footer, "Reset Position", 120, 24)
    resetBtn:SetPoint("LEFT", footer, "LEFT", 12, 0)
    resetBtn:SetScript("OnClick", HM.resetPosition)

    local closeFootBtn = Theme.TextButton(footer, "Close", 80, 24)
    closeFootBtn:SetPoint("RIGHT", footer, "RIGHT", -12, 0)
    closeFootBtn:SetScript("OnClick", function() f:Hide() end)

    local previewGroup = CreateFrame("Frame", nil, footer)
    previewGroup:SetSize(234, 24)
    previewGroup:SetPoint("LEFT", resetBtn, "RIGHT", 10, 0)

    local previewBtn = Theme.TextButton(previewGroup, "Start Preview", 130, 24)
    previewBtn:SetPoint("LEFT", previewGroup, "LEFT", 0, 0)

    local previewStepper = makeStepper(previewGroup,
        function() return cfg.testPreviewCount end,
        function(v)
            HM.saveKey("testPreviewCount", v)
            if HM.testModeActive then
                HM.generateTestRoster(v)
                HM.refreshDisplay()
            end
        end,
        1, 20)
    previewStepper:SetPoint("RIGHT", previewGroup, "RIGHT", 0, 0)

    local function refreshPreviewBtn()
        previewBtn.lbl:SetText(HM.testModeActive and "Stop Preview" or "Start Preview")
    end
    refreshPreviewBtn()

    previewBtn:SetScript("OnClick", function()
        HM.toggleTestPreview()
        refreshPreviewBtn()
    end)

    local body = CreateFrame("Frame", nil, f)
    body:SetPoint("TOPLEFT",     f,        "TOPLEFT",    0, -HEADER_H)
    body:SetPoint("BOTTOMRIGHT", footer,   "TOPRIGHT",   0, 0)

    local TAB_RAIL_W = 150

    local tabRail = CreateFrame("Frame", nil, body)
    tabRail:SetPoint("TOPLEFT",    body, "TOPLEFT",    12, -12)
    tabRail:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 12,  12)
    tabRail:SetWidth(TAB_RAIL_W)

    local railDiv = Theme.Line(tabRail)
    railDiv:SetPoint("TOP",    tabRail, "TOPRIGHT",    6, 0)
    railDiv:SetPoint("BOTTOM", tabRail, "BOTTOMRIGHT", 6, 0)
    railDiv:SetWidth(1)

    local scroll = CreateFrame("ScrollFrame", nil, body)
    scroll:SetPoint("TOPLEFT",     tabRail, "TOPRIGHT",    12,  0)
    scroll:SetPoint("BOTTOMRIGHT", body,    "BOTTOMRIGHT", -12, 12)
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

    local TOGGLE_H, DROPDOWN_H, SLIDER_H, SWATCH_H = 26, 48, 48, 28
    local SECTION_GAP = 14

    local panes, paneRefresh, tabButtons = {}, {}, {}
    local activeTab
    local updateBgBorderTabLabel

    local function newPane(key)
        local pane = CreateFrame("Frame", nil, content)
        pane:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, 0)
        pane:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
        pane:Hide()
        pane._key = key
        panes[key] = pane
        return pane
    end

    local function layoutRows(pane, rows)
        local y = -10
        local totalH = 20
        local prevGroup
        for _, row in ipairs(rows) do
            if prevGroup and row.group and row.group ~= prevGroup then
                y = y - SECTION_GAP
                totalH = totalH + SECTION_GAP
            end
            row.w:ClearAllPoints()
            row.w:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, y)
            if row.stretch ~= false then
                row.w:SetPoint("TOPRIGHT", pane, "TOPRIGHT", 0, y)
            end
            row.w:Show()
            y = y - row.h
            totalH = totalH + row.h
            prevGroup = row.group or prevGroup
        end
        pane:SetHeight(totalH)
        if activeTab == pane._key then content:SetHeight(totalH) end
    end

    local function switchTab(key)
        activeTab = key
        for k, btn in pairs(tabButtons) do btn:SetActive(k == key) end
        for k, pane in pairs(panes) do
            if k == key then pane:Show() else pane:Hide() end
        end
        paneRefresh[key]()
        content:SetHeight(panes[key]:GetHeight())
        scroll:SetVerticalScroll(0)
    end

    local function colorSetter(key, hasAlpha)
        return function(r, g, b, a)
            local c = {r = r, g = g, b = b}
            if hasAlpha then c.a = a end
            HM.saveKey(key, c)
            HM.refreshDisplay()
        end
    end

    local generalPane = newPane("general")

    local displayStyleDropdown = makeDropdown(generalPane, "Display Style", {
            {value = "icon", label = "Icons"},
            {value = "bar",  label = "Bars"},
        }, function() return cfg.displayStyle end,
        function(value)
            HM.saveKey("displayStyle", value)
            HM.rebuildBarPool(); HM.refreshDisplay()
            paneRefresh.layout()
            paneRefresh.barColor()
            paneRefresh.bgBorder()
            updateBgBorderTabLabel()
        end)

    local themeOptions = {}
    for _, key in ipairs(Theme.ORDER) do
        themeOptions[#themeOptions + 1] = {value = key, label = Theme.THEMES[key].name}
    end
    local themeDropdown = makeDropdown(generalPane, "Theme", themeOptions,
        function() return Theme.key end, Theme.Set)
    Theme.Skin(function() themeDropdown:SetValue(Theme.key) end)

    local cbDimRange = makeToggle(generalPane, "Dim when out of range",
        function() return cfg.dimOutOfRange end,
        function(v)
            HM.saveKey("dimOutOfRange", v); HM.refreshDisplay()
            paneRefresh.general()
        end)

    local outOfRangeSlider = makeSlider(generalPane, "Out of Range Opacity", 0, 100, 1,
        function(val)
            local v = val / 100
            if v == cfg.outOfRangeOpacity then return end
            HM.saveKey("outOfRangeOpacity", v); HM.refreshDisplay()
        end)
    outOfRangeSlider:SetValue(math.floor(cfg.outOfRangeOpacity * 100 + 0.5))

    local cbHideSelf = makeToggle(generalPane, "Hide own bar",
        function() return cfg.hideSelf end,
        function(v) HM.saveKey("hideSelf", v); HM.rebuildRoster(); HM.refreshDisplay() end)

    local cbLock = makeToggle(generalPane, "Lock frame (click-through)",
        function() return cfg.locked end,
        function(v) HM.saveKey("locked", v); HM.mainFrame:EnableMouse(not cfg.locked) end)

    local cbMinimapIcon = makeToggle(generalPane, "Show minimap icon",
        function() return not (HealerManaDB.minimap and HealerManaDB.minimap.hide) end,
        function(v) HM.setMinimapIconShown(v) end)

    paneRefresh.general = function()
        local rows = {
            {w = themeDropdown,        h = DROPDOWN_H, group = "dropdown"},
            {w = displayStyleDropdown, h = DROPDOWN_H, group = "dropdown"},
            {w = cbDimRange,           h = TOGGLE_H, stretch = false, group = "toggle"},
            {w = cbHideSelf,           h = TOGGLE_H, stretch = false, group = "toggle"},
            {w = cbLock,               h = TOGGLE_H, stretch = false, group = "toggle"},
            {w = cbMinimapIcon,        h = TOGGLE_H, stretch = false, group = "toggle"},
        }
        if cfg.dimOutOfRange then
            rows[#rows + 1] = {w = outOfRangeSlider, h = SLIDER_H, group = "slider"}
        end

        outOfRangeSlider:Hide()
        layoutRows(generalPane, rows)
    end

    local layoutPane = newPane("layout")

    local function currentLayoutMode()
        if cfg.gridEnabled then return "grid"
        elseif cfg.layoutHorizontal then return "horizontal"
        else return "vertical" end
    end

    local gapLabel = function() return cfg.layoutHorizontal and "Horizontal Spacing" or "Vertical Spacing" end
    local gapSlider

    local layoutModeDropdown = makeDropdown(layoutPane, "Layout Mode", {
            {value = "horizontal", label = "Horizontal"},
            {value = "vertical",   label = "Vertical"},
            {value = "grid",       label = "Grid"},
        }, currentLayoutMode,
        function(value)
            if value == "grid" then
                HM.saveKey("gridEnabled", true)
            else
                HM.saveKey("gridEnabled", false)
                HM.saveKey("layoutHorizontal", value == "horizontal")
            end
            gapSlider.lbl:SetText(gapLabel())
            HM.rebuildBarPool(); HM.refreshDisplay()
            paneRefresh.layout()
        end)

    local sizeSlider = makeSlider(layoutPane, "Icon Size", 30, 60, 1,
        function(val)
            if val == cfg.cellSize then return end
            HM.saveKey("cellSize", val)
            local nameFs, pctFs = HM.autoFontSizes(val)
            HM.saveKey("nameFontSize", nameFs)
            HM.saveKey("pctFontSize", pctFs)
            HM.rebuildBarPool(); HM.refreshDisplay()
        end)
    sizeSlider:SetValue(cfg.cellSize)

    gapSlider = makeSlider(layoutPane, gapLabel(), 0, 16, 1,
        function(val)
            if val == cfg.cellSpacing then return end
            HM.saveKey("cellSpacing", val); HM.refreshDisplay()
        end)
    gapSlider:SetValue(cfg.cellSpacing)

    local gridColsSlider = makeSlider(layoutPane, "Grid Columns", 1, 8, 1,
        function(val)
            if val == cfg.gridColumns then return end
            HM.saveKey("gridColumns", val); HM.refreshDisplay()
        end)
    gridColsSlider:SetValue(cfg.gridColumns)

    local barWidthSlider = makeSlider(layoutPane, "Bar Width", 80, 260, 5,
        function(val)
            if val == cfg.barWidth then return end
            HM.saveKey("barWidth", val)
            HM.rebuildBarPool(); HM.refreshDisplay()
        end)
    barWidthSlider:SetValue(cfg.barWidth)

    local barHeightSlider = makeSlider(layoutPane, "Bar Height", 12, 32, 1,
        function(val)
            if val == cfg.barHeight then return end
            HM.saveKey("barHeight", val)
            HM.rebuildBarPool(); HM.refreshDisplay()
        end)
    barHeightSlider:SetValue(cfg.barHeight)

    local barTextureDropdown
    local layoutLSM = HM.getLSM()
    if layoutLSM then
        local options = {}
        for _, name in ipairs(layoutLSM:List("statusbar")) do
            options[#options + 1] = {value = name, label = name}
        end
        barTextureDropdown = makeDropdown(layoutPane, "Bar Texture", options,
            function() return cfg.barTexture end,
            function(value)
                HM.saveKey("barTexture", value)
                HM.rebuildBarPool(); HM.refreshDisplay()
            end)
        barTextureDropdown:SetValue(cfg.barTexture)
    end

    paneRefresh.layout = function()
        local isBar = cfg.displayStyle == "bar"
        local rows = {{w = layoutModeDropdown, h = DROPDOWN_H, group = "dropdown"}}
        if isBar and barTextureDropdown then
            rows[#rows + 1] = {w = barTextureDropdown, h = DROPDOWN_H, group = "dropdown"}
        end

        if isBar then
            rows[#rows + 1] = {w = barWidthSlider,  h = SLIDER_H, group = "slider"}
            rows[#rows + 1] = {w = barHeightSlider, h = SLIDER_H, group = "slider"}
            rows[#rows + 1] = {w = gapSlider,       h = SLIDER_H, group = "slider"}
        else
            rows[#rows + 1] = {w = sizeSlider, h = SLIDER_H, group = "slider"}
            rows[#rows + 1] = {w = gapSlider,  h = SLIDER_H, group = "slider"}
            if cfg.gridEnabled then rows[#rows + 1] = {w = gridColsSlider, h = SLIDER_H, group = "slider"} end
        end

        local allWidgets = {sizeSlider, gapSlider, gridColsSlider, barWidthSlider, barHeightSlider}
        if barTextureDropdown then allWidgets[#allWidgets + 1] = barTextureDropdown end
        for _, w in ipairs(allWidgets) do w:Hide() end

        layoutRows(layoutPane, rows)
    end

    local barColorPane = newPane("barColor")

    local barColorModeDropdown = makeDropdown(barColorPane, "Fill Color Mode", {
            {value = "class",  label = "Class Color"},
            {value = "custom", label = "Custom Color"},
        }, function() return cfg.barColorMode end,
        function(value)
            HM.saveKey("barColorMode", value)
            HM.refreshDisplay()
            paneRefresh.barColor()
        end)

    local barColorCustomSwatch = makeColorSwatch(barColorPane, "Custom Color",
        function() return cfg.barColorCustom end, colorSetter("barColorCustom"))

    local barOpacitySlider = makeSlider(barColorPane, "Bar Opacity", 0, 100, 1,
        function(val)
            local v = val / 100
            if v == cfg.barFillOpacity then return end
            HM.saveKey("barFillOpacity", v); HM.refreshDisplay()
        end)
    barOpacitySlider:SetValue(math.floor(cfg.barFillOpacity * 100 + 0.5))

    local iconTintOpacitySlider = makeSlider(barColorPane, "Icon Tint Opacity", 0, 100, 1,
        function(val)
            local v = val / 100
            if v == cfg.iconTintOpacity then return end
            HM.saveKey("iconTintOpacity", v); HM.refreshDisplay()
        end)
    iconTintOpacitySlider:SetValue(math.floor(cfg.iconTintOpacity * 100 + 0.5))

    paneRefresh.barColor = function()
        local rows = {{w = barColorModeDropdown, h = DROPDOWN_H, group = "dropdown"}}

        if cfg.displayStyle == "bar" then
            rows[#rows + 1] = {w = barOpacitySlider, h = SLIDER_H, group = "slider"}
        else
            rows[#rows + 1] = {w = iconTintOpacitySlider, h = SLIDER_H, group = "slider"}
        end

        if cfg.barColorMode == "custom" then
            rows[#rows + 1] = {w = barColorCustomSwatch, h = SWATCH_H, group = "swatch"}
        end

        for _, w in ipairs({barColorModeDropdown, barColorCustomSwatch, barOpacitySlider, iconTintOpacitySlider}) do
            w:Hide()
        end

        layoutRows(barColorPane, rows)
    end

    local bgBorderPane = newPane("bgBorder")

    local bgSwatch = makeColorSwatch(bgBorderPane, "Background Color",
        function() return cfg.bgColor end,
        function(r, g, b, a)
            HM.saveKey("bgColor", {r = r, g = g, b = b, a = a})
            HM.rebuildBarPool(); HM.refreshDisplay()
        end, true)

    local cbBorderColor = makeToggle(bgBorderPane, "Class color border",
        function() return cfg.borderClassColor end,
        function(v)
            HM.saveKey("borderClassColor", v); HM.refreshDisplay()
            paneRefresh.bgBorder()
        end)

    local borderSwatch = makeColorSwatch(bgBorderPane, "Border Color",
        function() return cfg.borderCustomColor end, colorSetter("borderCustomColor"))

    paneRefresh.bgBorder = function()
        local rows = {}
        if cfg.displayStyle == "icon" then
            rows[#rows + 1] = {w = cbBorderColor, h = TOGGLE_H, stretch = false, group = "toggle"}
        end
        if cfg.displayStyle == "bar" then
            rows[#rows + 1] = {w = bgSwatch, h = SWATCH_H, group = "swatch"}
        end
        if cfg.displayStyle == "icon" and not cfg.borderClassColor then
            rows[#rows + 1] = {w = borderSwatch, h = SWATCH_H, group = "swatch"}
        end

        bgSwatch:Hide(); cbBorderColor:Hide(); borderSwatch:Hide()
        layoutRows(bgBorderPane, rows)
    end

    local textPane = newPane("text")

    local cbShowName = makeToggle(textPane, "Show player name",
        function() return cfg.showName end,
        function(v)
            HM.saveKey("showName", v)
            HM.rebuildBarPool(); HM.refreshDisplay()
            paneRefresh.text()
        end)

    local nameOverflowDropdown = makeDropdown(textPane, "Long Name Handling", {
            {value = "shrink",   label = "Shrink to Fit"},
            {value = "truncate", label = "Truncate"},
        }, function() return cfg.nameOverflow end,
        function(value)
            HM.saveKey("nameOverflow", value)
            for _, b in ipairs(barPool) do
                if b.nameTxt then b.nameTxt._lastName = nil end
            end
            HM.refreshDisplay()
        end)

    local cbNameColor = makeToggle(textPane, "Class color name",
        function() return cfg.nameClassColor end,
        function(v)
            HM.saveKey("nameClassColor", v); HM.refreshDisplay()
            paneRefresh.text()
        end)

    local nameColorSwatch = makeColorSwatch(textPane, "Name Text Color",
        function() return cfg.nameCustomColor end, colorSetter("nameCustomColor"))

    local cbPctSymbol = makeToggle(textPane, "Show % symbol",
        function() return cfg.showPctSymbol end,
        function(v) HM.saveKey("showPctSymbol", v); HM.refreshDisplay() end)

    local cbPctColor = makeToggle(textPane, "Class color percent",
        function() return cfg.pctClassColor end,
        function(v)
            HM.saveKey("pctClassColor", v); HM.refreshDisplay()
            paneRefresh.text()
        end)

    local pctColorSwatch = makeColorSwatch(textPane, "Percent Text Color",
        function() return cfg.pctCustomColor end, colorSetter("pctCustomColor"))

    local fontDropdown
    local textLSM = HM.getLSM()
    if textLSM then
        local fontType = textLSM.MediaType and textLSM.MediaType.FONT or "font"
        local options = {{value = false, label = "Default"}}
        for _, name in ipairs(textLSM:List(fontType) or {}) do
            options[#options + 1] = {value = name, label = name}
        end
        fontDropdown = makeDropdown(textPane, "Font", options,
            function() return cfg.fontFace end,
            function(value)
                HM.saveKey("fontFace", value)
                HM.rebuildBarPool(); HM.refreshDisplay()
            end)
    end

    local cbFontOverride = makeToggle(textPane, "Override font size",
        function() return cfg.fontSizeOverride end,
        function(v)
            HM.saveKey("fontSizeOverride", v)
            HM.rebuildBarPool(); HM.refreshDisplay()
            paneRefresh.text()
        end)

    local nameFontSlider = makeSlider(textPane, "Name Font Size", 6, 24, 1,
        function(val)
            if val == cfg.nameFontSizeManual then return end
            HM.saveKey("nameFontSizeManual", val)
            HM.rebuildBarPool(); HM.refreshDisplay()
        end)
    nameFontSlider:SetValue(cfg.nameFontSizeManual)

    local pctFontSlider = makeSlider(textPane, "Percent Font Size", 6, 24, 1,
        function(val)
            if val == cfg.pctFontSizeManual then return end
            HM.saveKey("pctFontSizeManual", val)
            HM.rebuildBarPool(); HM.refreshDisplay()
        end)
    pctFontSlider:SetValue(cfg.pctFontSizeManual)

    paneRefresh.text = function()
        local rows = {}

        if cfg.showName then
            rows[#rows + 1] = {w = nameOverflowDropdown, h = DROPDOWN_H, group = "dropdown"}
        end
        if fontDropdown then
            rows[#rows + 1] = {w = fontDropdown, h = DROPDOWN_H, group = "dropdown"}
        end

        rows[#rows + 1] = {w = cbShowName, h = TOGGLE_H, stretch = false, group = "toggle"}
        if cfg.showName then
            rows[#rows + 1] = {w = cbNameColor, h = TOGGLE_H, stretch = false, group = "toggle"}
        end
        rows[#rows + 1] = {w = cbPctSymbol,    h = TOGGLE_H, stretch = false, group = "toggle"}
        rows[#rows + 1] = {w = cbPctColor,     h = TOGGLE_H, stretch = false, group = "toggle"}
        rows[#rows + 1] = {w = cbFontOverride, h = TOGGLE_H, stretch = false, group = "toggle"}

        if cfg.fontSizeOverride then
            rows[#rows + 1] = {w = nameFontSlider, h = SLIDER_H, group = "slider"}
            rows[#rows + 1] = {w = pctFontSlider,  h = SLIDER_H, group = "slider"}
        end

        if cfg.showName and not cfg.nameClassColor then
            rows[#rows + 1] = {w = nameColorSwatch, h = SWATCH_H, group = "swatch"}
        end
        if not cfg.pctClassColor then
            rows[#rows + 1] = {w = pctColorSwatch, h = SWATCH_H, group = "swatch"}
        end

        local allWidgets = {nameOverflowDropdown, cbNameColor, nameColorSwatch, cbPctSymbol, cbPctColor, pctColorSwatch,
            cbFontOverride, nameFontSlider, pctFontSlider}
        if fontDropdown then allWidgets[#allWidgets + 1] = fontDropdown end
        for _, w in ipairs(allWidgets) do w:Hide() end

        layoutRows(textPane, rows)
    end

    local sortVisPane = newPane("sortVis")

    local sortModeDropdown = makeDropdown(sortVisPane, "Sort By", {
            {value = "alpha", label = "Alphabetical"},
            {value = "class", label = "Healer Class"},
        }, function() return cfg.sortMode end,
        function(value)
            HM.saveKey("sortMode", value)
            HM.refreshDisplay()
        end)

    local cbShowWhenSolo = makeToggle(sortVisPane, "Show when Solo",
        function() return cfg.showWhenSolo end,
        function(v) HM.saveKey("showWhenSolo", v); HM.rebuildRoster(); HM.refreshDisplay() end)

    local cbShowOpenWorld = makeToggle(sortVisPane, "Show in Open World",
        function() return cfg.showInOpenWorld end,
        function(v) HM.saveKey("showInOpenWorld", v); HM.refreshDisplay() end)

    local cbShowDungeons = makeToggle(sortVisPane, "Show in Dungeons",
        function() return cfg.showInDungeons end,
        function(v) HM.saveKey("showInDungeons", v); HM.refreshDisplay() end)

    local cbShowRaids = makeToggle(sortVisPane, "Show in Raids",
        function() return cfg.showInRaids end,
        function(v) HM.saveKey("showInRaids", v); HM.refreshDisplay() end)

    local cbShowScenarios = makeToggle(sortVisPane, "Show in Scenarios",
        function() return cfg.showInScenarios end,
        function(v) HM.saveKey("showInScenarios", v); HM.refreshDisplay() end)

    local cbShowBattlegrounds = makeToggle(sortVisPane, "Show in Battlegrounds",
        function() return cfg.showInBattlegrounds end,
        function(v) HM.saveKey("showInBattlegrounds", v); HM.refreshDisplay() end)

    local cbShowArenas = makeToggle(sortVisPane, "Show in Arenas",
        function() return cfg.showInArenas end,
        function(v) HM.saveKey("showInArenas", v); HM.refreshDisplay() end)

    paneRefresh.sortVis = function()
        layoutRows(sortVisPane, {
            {w = sortModeDropdown,    h = DROPDOWN_H, group = "dropdown"},
            {w = cbShowWhenSolo,      h = TOGGLE_H, stretch = false, group = "visibility"},
            {w = cbShowOpenWorld,     h = TOGGLE_H, stretch = false, group = "visibility"},
            {w = cbShowDungeons,      h = TOGGLE_H, stretch = false, group = "visibility"},
            {w = cbShowRaids,         h = TOGGLE_H, stretch = false, group = "visibility"},
            {w = cbShowScenarios,     h = TOGGLE_H, stretch = false, group = "visibility"},
            {w = cbShowBattlegrounds, h = TOGGLE_H, stretch = false, group = "visibility"},
            {w = cbShowArenas,        h = TOGGLE_H, stretch = false, group = "visibility"},
        })
    end

    local helpPane = newPane("help")

    local HELP_SECTIONS = {
        {kind = "title", text = "HealerMana"},
        {kind = "body", text = "Tracks the mana of every healer in your group or raid, shown as a row of bars or a strip of icons, positioned and styled however you like."},
        {kind = "header", text = "Eating & Drinking"},
        {kind = "body", text = "In Icon style, a healer's icon swaps to their Food & Drink icon while they're regenerating mana that way. This does not update anywhere inside an active Mythic+ run (a Blizzard restriction on that content, not a bug) - it still works normally in raids, dungeons outside of keys, and the open world."},
        {kind = "header", text = "Druid Forms"},
        {kind = "body", text = "A healer Druid's icon shows their Feral/Guardian/Balance icon while in Cat, Bear, or Moonkin Form (Bar style shows a colored [Cat]/[Bear]/[Moonkin] tag instead), and mana % is hidden while in Cat or Bear Form since neither uses mana. Cat and Bear Form update correctly even in combat; Moonkin Form only updates outside of combat (a Blizzard restriction)."},
        {kind = "header", text = "Theme"},
        {kind = "body", text = "Click the gear in the title bar to switch between Workbench, Artisan Ledger, Horde, Alliance and Slate, or pick one under General."},
        {kind = "header", text = "Minimap Icon"},
        {kind = "body", text = "Click the minimap icon to open this settings panel."},
        {kind = "header", text = "Test Preview"},
        {kind = "body", text = "Use the Start Preview button and the count next to it in this panel's footer to fill the tracker with fake healers, so you can check your setup without a real group. Stop Preview restores your real roster."},
        {kind = "header", text = "Slash Commands"},
        {kind = "body", text = "/hm - open settings\n/hm raid <1-20> - preview that many fake healers\n/hm raid off - restore the real roster\n/hm help - list commands in chat"},
        {kind = "header", text = "General"},
        {kind = "body", text = "Display Style (Icons or Bars), out-of-range dimming and its opacity, hiding your own bar, locking the frame in place, and the minimap icon's visibility."},
        {kind = "header", text = "Layout"},
        {kind = "body", text = "Arrangement (Horizontal, Vertical, or Grid), icon size or bar width/height, spacing between entries, grid column count, and bar texture."},
        {kind = "header", text = "Fill Color"},
        {kind = "body", text = "Class Color or a Custom Color for the bar fill / icon tint, plus separate opacity sliders for bars and for the icon tint overlay."},
        {kind = "header", text = "Background & Border"},
        {kind = "body", text = "Background color (Bar style only - hidden behind icon art otherwise) and border color, including a class-color option (Icon style only - Bars have no border)."},
        {kind = "header", text = "Text"},
        {kind = "body", text = "Show or hide the name label, long-name handling, name color, the % symbol, percent-text color, font choice, and a manual font size override."},
        {kind = "header", text = "Sort & Visibility"},
        {kind = "body", text = "Sort order (alphabetical or by class), whether to show while solo, and which instance types (open world, dungeons, raids, scenarios, battlegrounds, arenas) the tracker appears in."},
        {kind = "header", text = "Moving the Frame"},
        {kind = "body", text = "Drag the tracker to reposition it (unless locked in General). Use Reset Position in this panel's footer to snap it back to the default spot."},
    }

    local helpWidgets = {}
    for _, section in ipairs(HELP_SECTIONS) do
        local fs
        if section.kind == "title" then
            fs = Theme.Text(helpPane, "heading", 16, "title")
        elseif section.kind == "header" then
            fs = Theme.Text(helpPane, "heading", nil, "accent")
        else
            fs = Theme.Text(helpPane, "body", 12, "text")
        end
        fs:SetJustifyV("TOP")
        fs:SetWordWrap(true)
        fs:SetText(section.text)
        helpWidgets[#helpWidgets + 1] = {fs = fs, kind = section.kind}
    end

    paneRefresh.help = function()
        local paneWidth = helpPane:GetWidth()
        if not paneWidth or paneWidth < 10 then paneWidth = 260 end
        local y = -10
        local totalH = 20
        for i, w in ipairs(helpWidgets) do
            if i > 1 and w.kind == "header" then
                y = y - SECTION_GAP
                totalH = totalH + SECTION_GAP
            end
            w.fs:ClearAllPoints()
            w.fs:SetPoint("TOPLEFT", helpPane, "TOPLEFT", 0, y)
            w.fs:SetWidth(paneWidth)
            local h = w.fs:GetStringHeight()
            y = y - h - 4
            totalH = totalH + h + 4
        end
        helpPane:SetHeight(totalH)
        if activeTab == helpPane._key then content:SetHeight(totalH) end
    end

    local TAB_DEFS = {
        {key = "general",  label = "General"},
        {key = "layout",   label = "Layout"},
        {key = "barColor", label = "Fill Color"},
        {key = "bgBorder", label = "Background & Border"},
        {key = "text",     label = "Text"},
        {key = "sortVis",  label = "Sort & Visibility"},
        {key = "help",     label = "Help"},
    }

    local y = 0
    for _, def in ipairs(TAB_DEFS) do
        local btn = makeTabButton(tabRail, def.label)
        btn:SetPoint("TOPLEFT",  tabRail, "TOPLEFT",  0, -y)
        btn:SetPoint("TOPRIGHT", tabRail, "TOPRIGHT", 0, -y)
        btn:SetScript("OnClick", function() switchTab(def.key) end)
        tabButtons[def.key] = btn
        y = y + 30
    end

    updateBgBorderTabLabel = function()
        tabButtons.bgBorder.lbl:SetText(cfg.displayStyle == "bar" and "Background" or "Border")
    end
    updateBgBorderTabLabel()

    Theme.Skin(function()
        if activeTab then paneRefresh[activeTab]() end
    end)

    f:SetScript("OnShow", function()
        displayStyleDropdown:SetValue(cfg.displayStyle)
        updateBgBorderTabLabel()
        cbDimRange:SetChecked(cfg.dimOutOfRange)
        outOfRangeSlider:SetValue(math.floor(cfg.outOfRangeOpacity * 100 + 0.5))
        cbHideSelf:SetChecked(cfg.hideSelf)
        cbLock:SetChecked(cfg.locked)
        cbMinimapIcon:SetChecked(not (HealerManaDB.minimap and HealerManaDB.minimap.hide))

        layoutModeDropdown:SetValue(currentLayoutMode())
        sizeSlider:SetValue(cfg.cellSize)
        gapSlider.lbl:SetText(gapLabel())
        gapSlider:SetValue(cfg.cellSpacing)
        gridColsSlider:SetValue(cfg.gridColumns)
        barWidthSlider:SetValue(cfg.barWidth)
        barHeightSlider:SetValue(cfg.barHeight)
        if barTextureDropdown then barTextureDropdown:SetValue(cfg.barTexture) end

        barColorModeDropdown:SetValue(cfg.barColorMode)
        barColorCustomSwatch.refresh()
        barOpacitySlider:SetValue(math.floor(cfg.barFillOpacity * 100 + 0.5))
        iconTintOpacitySlider:SetValue(math.floor(cfg.iconTintOpacity * 100 + 0.5))

        bgSwatch.refresh()
        cbBorderColor:SetChecked(cfg.borderClassColor)
        borderSwatch.refresh()

        cbShowName:SetChecked(cfg.showName)
        nameOverflowDropdown:SetValue(cfg.nameOverflow)
        cbNameColor:SetChecked(cfg.nameClassColor)
        nameColorSwatch.refresh()
        cbPctSymbol:SetChecked(cfg.showPctSymbol)
        cbPctColor:SetChecked(cfg.pctClassColor)
        pctColorSwatch.refresh()
        if fontDropdown then fontDropdown:SetValue(cfg.fontFace) end
        cbFontOverride:SetChecked(cfg.fontSizeOverride)
        nameFontSlider:SetValue(cfg.nameFontSizeManual)
        pctFontSlider:SetValue(cfg.pctFontSizeManual)

        sortModeDropdown:SetValue(cfg.sortMode)
        cbShowWhenSolo:SetChecked(cfg.showWhenSolo)
        cbShowOpenWorld:SetChecked(cfg.showInOpenWorld)
        cbShowDungeons:SetChecked(cfg.showInDungeons)
        cbShowRaids:SetChecked(cfg.showInRaids)
        cbShowScenarios:SetChecked(cfg.showInScenarios)
        cbShowBattlegrounds:SetChecked(cfg.showInBattlegrounds)
        cbShowArenas:SetChecked(cfg.showInArenas)

        refreshPreviewBtn()
        previewStepper:Refresh()

        switchTab(activeTab or "general")
    end)

    f:Hide()
    configFrame = f
end

function HM.openConfig()
    if not configFrame then createConfigFrame() end
    configFrame:Show()
    configFrame:Raise()
end
