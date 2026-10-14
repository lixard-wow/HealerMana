local addonName, HM = ...

local Theme = {}
HM.Theme = Theme

local function Hex(value)
    return { tonumber(value:sub(2, 3), 16) / 255, tonumber(value:sub(4, 5), 16) / 255, tonumber(value:sub(6, 7), 16) / 255, 1 }
end

local FONTS = "Interface\\AddOns\\" .. addonName .. "\\Media\\Fonts\\"
local ART = "Interface\\AddOns\\" .. addonName .. "\\Media\\Art\\"
local BARLOW = FONTS .. "Barlow-Regular.ttf"
local BARLOW_COND = FONTS .. "BarlowCondensed-Bold.ttf"
local BARLOW_SEMI = FONTS .. "Barlow-SemiBold.ttf"
local CINZEL = FONTS .. "Cinzel-Bold.ttf"
local SOURCE = FONTS .. "SourceSans3-Regular.ttf"
local SOURCE_BOLD = FONTS .. "SourceSans3-Bold.ttf"

Theme.ORDER = { "workbench", "ledger", "classic" }

Theme.THEMES = {
    workbench = {
        name = "Workbench",
        fonts = { body = BARLOW, strong = BARLOW_SEMI, heading = BARLOW_COND, title = BARLOW_COND, button = BARLOW_SEMI },
        titleSize = 17, headingSize = 13, windowRadius = 10, buttonRadius = 4,
        uppercaseTitle = true, headerFill = true, stripe = true,
        colors = {
            window = Hex("#171a1f"), header = Hex("#1d2127"), field = Hex("#1d2127"), well = Hex("#121519"),
            hover = Hex("#262b32"), border = Hex("#2c323a"), line = Hex("#2c323a"),
            accent = Hex("#4fbf8f"), text = Hex("#e8ebee"), muted = Hex("#9aa3ad"), title = Hex("#e8ebee"), heading = Hex("#e8ebee"),
            button = Hex("#262b32"), buttonBorder = Hex("#262b32"), buttonHover = Hex("#30363f"), buttonText = Hex("#e8ebee"),
            icon = Hex("#c3cad2"), iconHover = Hex("#ffffff"),
        },
    },
    ledger = {
        name = "Artisan Ledger",
        fonts = { body = SOURCE, strong = SOURCE_BOLD, heading = CINZEL, title = CINZEL, button = SOURCE_BOLD },
        titleSize = 14, headingSize = 12, windowRadius = 4, buttonRadius = 4,
        innerFrame = true,
        colors = {
            window = Hex("#1c1611"), header = Hex("#1c1611"), field = Hex("#120e0b"), well = Hex("#120e0b"),
            hover = Hex("#2e241b"), border = Hex("#5a4630"), line = Hex("#3a2e22"),
            accent = Hex("#c9a35a"), text = Hex("#efe6d6"), muted = Hex("#bfb19e"), title = Hex("#e9d9b4"), heading = Hex("#f3e6c8"),
            button = Hex("#241c15"), buttonBorder = Hex("#5a4630"), buttonHover = Hex("#2e241b"), buttonText = Hex("#e9d9b4"),
            icon = Hex("#a8998a"), iconHover = Hex("#e9d9b4"),
        },
    },
    classic = {
        name = "Lixard Classic",
        fonts = { body = SOURCE, strong = SOURCE_BOLD, heading = SOURCE_BOLD, title = SOURCE_BOLD, button = SOURCE },
        titleSize = 15, headingSize = 13, windowRadius = 0, buttonRadius = 0,
        classAccent = true,
        colors = {
            window = { 0.06, 0.06, 0.06, 1 }, header = { 0.06, 0.06, 0.06, 1 }, field = Hex("#101010"), well = Hex("#0b0b0b"),
            hover = Hex("#1f1f1f"), border = { 0.22, 0.22, 0.22, 1 }, line = { 0.29, 0.29, 0.29, 1 },
            accent = { 0.78, 0.66, 0.22, 1 }, text = { 0.92, 0.91, 0.86, 1 }, muted = { 0.70, 0.70, 0.70, 1 },
            title = { 0.92, 0.91, 0.86, 1 }, heading = { 0.92, 0.91, 0.86, 1 },
            button = Hex("#161616"), buttonBorder = { 0.22, 0.22, 0.22, 1 }, buttonHover = Hex("#202020"), buttonText = { 0.92, 0.91, 0.86, 1 },
            icon = { 0.70, 0.70, 0.70, 1 }, iconHover = { 0.92, 0.91, 0.86, 1 },
        },
    },
}

local skins = {}

function Theme.Load()
    local key = HealerManaDB.theme
    if not Theme.THEMES[key] then key = "workbench" end
    Theme.key = key
    Theme.T = Theme.THEMES[key]
    local C = {}
    for k, v in pairs(Theme.T.colors) do C[k] = v end
    if Theme.T.classAccent then
        local _, class = UnitClass("player")
        local cc = C_ClassColor.GetClassColor(class)
        if cc then
            C.accent = { cc.r, cc.g, cc.b, 1 }
        end
    end
    Theme.C = C
end

function Theme.Skin(fn)
    skins[#skins + 1] = fn
    fn(Theme.T, Theme.C)
end

function Theme.Set(key)
    if not Theme.THEMES[key] then return end
    HealerManaDB.theme = key
    Theme.Load()
    for _, fn in ipairs(skins) do fn(Theme.T, Theme.C) end
end

function Theme.Next()
    local order = Theme.ORDER
    for i, key in ipairs(order) do
        if key == Theme.key then
            Theme.Set(order[i % #order + 1])
            return
        end
    end
    Theme.Set(order[1])
end

local pending = {}
local retrying = false

local function Retry()
    retrying = false
    for fs, req in pairs(pending) do
        req.tries = req.tries + 1
        if fs:SetFont(req.file, req.size, req.flags) or req.tries > 10 then
            pending[fs] = nil
        end
    end
    if next(pending) then
        retrying = true
        C_Timer.After(0.3, Retry)
    end
end

function Theme.SetFont(fs, file, size, flags)
    flags = flags or ""
    if fs:SetFont(file, size, flags) then
        pending[fs] = nil
        return
    end
    fs:SetFont(STANDARD_TEXT_FONT, size, flags)
    pending[fs] = { file = file, size = size, flags = flags, tries = 0 }
    if not retrying then
        retrying = true
        C_Timer.After(0.3, Retry)
    end
end

function Theme.Text(parent, role, size, colorKey, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    Theme.Skin(function(T, C)
        local s = size
        if role == "title" then s = T.titleSize elseif role == "heading" then s = size or T.headingSize end
        Theme.SetFont(fs, T.fonts[role] or T.fonts.body, s or 12)
        local c = C[fs.colorKey or colorKey or "text"]
        fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
        if role == "title" and fs.rawText then
            fs:SetText(T.uppercaseTitle and fs.rawText:upper() or fs.rawText)
        end
    end)
    return fs
end

function Theme.SetColor(fs, colorKey)
    fs.colorKey = colorKey
    local c = Theme.C[colorKey]
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
end

function Theme.SetTitle(fs, text)
    fs.rawText = text
    fs:SetText(Theme.T.uppercaseTitle and text:upper() or text)
end

local function Shape(tex, radius)
    if radius and radius > 0 then
        tex:SetTexture(ART .. "round" .. radius)
        tex:SetTextureSliceMargins(radius, radius, radius, radius)
        tex:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
    else
        tex:SetTextureSliceMargins(0, 0, 0, 0)
        tex:SetColorTexture(1, 1, 1, 1)
    end
end
Theme.Shape = Shape

local function Tint(tex, c, alpha)
    tex:SetVertexColor(c[1], c[2], c[3], alpha or c[4] or 1)
end
Theme.Tint = Tint

function Theme.Box(frame, fillKey, borderKey, radiusKey, sublevel)
    local edge = frame:CreateTexture(nil, "BACKGROUND", nil, (sublevel or 0) - 2)
    edge:SetAllPoints()
    local fill = frame:CreateTexture(nil, "BACKGROUND", nil, (sublevel or 0) - 1)
    fill:SetPoint("TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", -1, 1)
    frame.edge, frame.fill = edge, fill
    Theme.Skin(function(T, C)
        local r = T[radiusKey or "buttonRadius"] or 0
        Shape(edge, r)
        Shape(fill, r)
        Tint(edge, C[borderKey or "border"])
        Tint(fill, C[fillKey or "window"])
    end)
    return fill, edge
end

function Theme.Line(parent, layer)
    local line = parent:CreateTexture(nil, layer or "BORDER")
    Theme.Skin(function(_, C) line:SetColorTexture(C.line[1], C.line[2], C.line[3], 1) end)
    return line
end

function Theme.Window(frame, headerHeight)
    Theme.Box(frame, "window", "border", "windowRadius")
    local header = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(headerHeight - 1)
    local line = Theme.Line(frame)
    line:SetPoint("TOPLEFT", 1, -headerHeight)
    line:SetPoint("TOPRIGHT", -1, -headerHeight)
    line:SetHeight(1)
    local stripe = frame:CreateTexture(nil, "BORDER", nil, 1)
    stripe:SetPoint("TOPLEFT", 1, -headerHeight)
    stripe:SetSize(48, 2)
    local ring = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
    ring:SetPoint("TOPLEFT", 4, -4)
    ring:SetPoint("BOTTOMRIGHT", -4, 4)
    local ringFill = frame:CreateTexture(nil, "BACKGROUND", nil, 3)
    ringFill:SetPoint("TOPLEFT", ring, 1, -1)
    ringFill:SetPoint("BOTTOMRIGHT", ring, -1, 1)
    Theme.Skin(function(T, C)
        header:SetShown(T.headerFill and true or false)
        header:SetColorTexture(C.header[1], C.header[2], C.header[3], 1)
        stripe:SetShown(T.stripe and true or false)
        stripe:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
        ring:SetShown(T.innerFrame and true or false)
        ringFill:SetShown(T.innerFrame and true or false)
        ring:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
        ringFill:SetColorTexture(C.window[1], C.window[2], C.window[3], 1)
    end)
end

function Theme.Frame(name, strata, headerH, iconPath, titleText)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetFrameStrata(strata)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:Hide()
    Theme.Window(f, headerH)
    tinsert(UISpecialFrames, name)

    local drag = CreateFrame("Frame", nil, f)
    drag:SetPoint("TOPLEFT")
    drag:SetPoint("TOPRIGHT", -70, 0)
    drag:SetHeight(headerH)
    drag:EnableMouse(true)
    drag:SetScript("OnMouseDown", function() f:StartMoving() end)
    drag:SetScript("OnMouseUp", function() f:StopMovingOrSizing() end)

    local ico = f:CreateTexture(nil, "ARTWORK")
    ico:SetSize(22, 22)
    ico:SetPoint("LEFT", f, "TOPLEFT", 12, -headerH / 2)
    ico:SetTexture(iconPath)

    local title = Theme.Text(f, "title", nil, "title")
    title:SetPoint("LEFT", ico, "RIGHT", 8, 0)
    Theme.SetTitle(title, titleText)

    local size = headerH - 18
    f.closeBtn = Theme.IconButton(f, "icon_close", size, function() f:Hide() end, "Close")
    f.closeBtn:SetPoint("RIGHT", f, "TOPRIGHT", -10, -headerH / 2)
    f.themeBtn = Theme.IconButton(f, "icon_gear", size, function() Theme.Next() end,
        function() return "Theme: " .. Theme.T.name .. "\nClick for the next theme" end)
    f.themeBtn:SetPoint("RIGHT", f.closeBtn, "LEFT", -4, 0)
    return f
end

function Theme.IconButton(parent, icon, size, onClick, tooltip)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    local fill = Theme.Box(b, "button", "buttonBorder", "buttonRadius")
    local tex = b:CreateTexture(nil, "ARTWORK")
    tex:SetTexture(ART .. icon)
    tex:SetSize(math.floor(size * 0.5 + 0.5), math.floor(size * 0.5 + 0.5))
    tex:SetPoint("CENTER")
    Theme.Skin(function(_, C) Tint(tex, C.icon) end)
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self)
        Tint(tex, Theme.C.iconHover)
        Tint(fill, Theme.C.buttonHover)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(type(tooltip) == "function" and tooltip() or tooltip, 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function()
        Tint(tex, Theme.C.icon)
        Tint(fill, Theme.C.button)
        GameTooltip:Hide()
    end)
    return b
end

function Theme.TextButton(parent, text, width, height)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, height)
    local fill, edge = Theme.Box(b, "button", "buttonBorder", "buttonRadius")
    local lbl = Theme.Text(b, "button", 12, "buttonText")
    lbl:SetPoint("CENTER")
    lbl:SetJustifyH("CENTER")
    lbl:SetText(text)
    b.lbl = lbl
    b:SetScript("OnEnter", function()
        Tint(fill, Theme.C.buttonHover)
        Tint(edge, Theme.C.accent)
    end)
    b:SetScript("OnLeave", function()
        Tint(fill, Theme.C.button)
        Tint(edge, Theme.C.buttonBorder)
    end)
    return b
end

function Theme.Check(parent, size, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    local _, edge = Theme.Box(b, "field", "border", "buttonRadius")
    local mark = b:CreateTexture(nil, "ARTWORK")
    mark:SetPoint("TOPLEFT", 4, -4)
    mark:SetPoint("BOTTOMRIGHT", -4, 4)
    local function Paint()
        local C = Theme.C
        Shape(mark, Theme.T.buttonRadius > 0 and 4 or 0)
        Tint(mark, C.accent)
        mark:SetShown(b.checked)
        Tint(edge, (b.checked or b:IsMouseOver()) and C.accent or C.border)
    end
    function b:SetChecked(on)
        self.checked = on and true or false
        Paint()
    end
    function b:GetChecked()
        return self.checked
    end
    b:SetScript("OnClick", function(self)
        self:SetChecked(not self.checked)
        onClick(self)
    end)
    b:SetScript("OnEnter", Paint)
    b:SetScript("OnLeave", Paint)
    Theme.Skin(Paint)
    return b
end
