--[[ LibFreeUI-1.0
     The look of the Free addons' option windows (graphite + ember), as one small kit:
     window with header, optional cards, tabs and footer; two responsive columns; switches, segmented
     choices, sliders with a free value box, dropdowns, text boxes, buttons. Opens inside Free Hub when
     it is installed.

     local kit = LibStub("LibFreeUI-1.0"):New({ name = "FreeGuildOptions", title = "Free Guild", sub = "Guild ranks",
                                                 icon = path, w = 860, h = 640, addon = "FreeGuild" })
]]
local MAJOR, MINOR = "LibFreeUI-1.0", 2
local lib = LibStub and LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

local WHITE = "Interface\\Buttons\\WHITE8x8"
local FONT = "Fonts\\ARIALN.TTF"

lib.C = {
    bg       = { 0.070, 0.074, 0.085, 0.97 },
    panel    = { 0.098, 0.104, 0.118, 1 },
    control  = { 0.145, 0.151, 0.170, 1 },
    hover    = { 0.190, 0.197, 0.222, 1 },
    text     = { 0.930, 0.937, 0.955, 1 },
    dim      = { 0.700, 0.712, 0.750, 1 },
    muted    = { 0.500, 0.515, 0.560, 1 },
    accent   = { 1.000, 0.540, 0.240, 1 },
    accentHi = { 1.000, 0.640, 0.380, 1 },
    onAccent = { 0.100, 0.050, 0.020, 1 },
    good     = { 0.450, 0.850, 0.500, 1 },
    bad      = { 1.000, 0.420, 0.380, 1 },
}
local C = lib.C

local Kit = {}
Kit.__index = Kit

function lib:New(o)
    local k = setmetatable({}, Kit)
    k.o = o
    k.W, k.H = o.w or 760, o.h or 600
    k.PAD, k.GAP = 18, 40
    k.COLW = (k.W - 2 * k.PAD - k.GAP) / 2
    k.LX, k.RX = k.PAD, k.PAD + k.COLW + k.GAP
    k.ROW = o.row or 36
    k.media = o.media or ("Interface\\AddOns\\" .. (o.addon or "") .. "\\Media\\")
    k.refreshers, k.flow, k.onResize = {}, {}, {}
    k.C = C
    return k
end

function Kit:OnRefresh(fn) self.refreshers[#self.refreshers + 1] = fn end
function Kit:Refresh()
    if self.frame and self.frame:IsShown() then for _, fn in ipairs(self.refreshers) do fn() end end
end
function Kit:Y(i) return -22 - (i - 1) * self.ROW end

-- point: anchor of the element at (x, y) from the parent's top-left. right: x is a right edge. width: stretched.
function Kit:Flow(obj, point, x, y, width, right)
    self.flow[#self.flow + 1] = { o = obj, p = point, x = x, y = y, w = width, right = right }
end
function Kit:Reflow(width)
    width = math.max(self.W, width or self.W)
    local colW = (width - 2 * self.PAD - self.GAP) / 2
    local dC = colW - self.COLW
    local rx = self.PAD + colW + self.GAP
    for _, e in ipairs(self.flow) do
        if e.p then
            local x = e.x
            if x >= self.RX - 1 then x = x - self.RX + rx end
            if e.right then x = x + dC end
            e.o:SetPoint(e.p, e.o:GetParent(), "TOPLEFT", x, e.y)
        end
        if e.w and e.w >= 100 then e.o:SetWidth(e.w + dC) end
    end
    for _, fn in ipairs(self.onResize) do fn(width) end
end

-- ------------------------------------------------------------ primitives
function lib.SetFont(obj, size, flags)
    obj:SetFont(FONT, size, flags or "")
    if not obj:GetFont() then obj:SetFont(STANDARD_TEXT_FONT, size, flags or "") end
end
-- Font path of a dropdown item (item.font = path, or item.fontKey through LibFreeMedia); nil when none
local function ItemFont(it)
    if not it then return nil end
    if it.font then return it.font end
    if it.fontKey then
        local LFM = LibStub and LibStub("LibFreeMedia-1.0", true)
        if LFM then
            local ok, p = pcall(LFM.FontPath, LFM, it.fontKey)
            if ok then return p end
        end
    end
end
-- sets the preview font on a font string, or restores the default one
local function PaintFont(fs, it, size)
    local p = ItemFont(it)
    if p then
        local ok, res = pcall(fs.SetFont, fs, p, size, "")
        if ok and res ~= false then return end
    end
    lib.SetFont(fs, size)
end
function Kit:Text(parent, size, color, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    lib.SetFont(fs, size)
    fs:SetTextColor(unpack(color or C.text))
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    return fs
end
function Kit:Fill(parent, color, layer, sub)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
    t:SetTexture(WHITE)
    t:SetVertexColor(unpack(color))
    return t
end
function Kit:Border(f, alpha, layer)
    f.edges = {}
    for i, p in ipairs({ { "TOPLEFT", "TOPRIGHT", "h" }, { "BOTTOMLEFT", "BOTTOMRIGHT", "h" },
                         { "TOPLEFT", "BOTTOMLEFT", "v" }, { "TOPRIGHT", "BOTTOMRIGHT", "v" } }) do
        local e = f:CreateTexture(nil, layer or "BORDER")
        e:SetTexture(WHITE)
        e:SetVertexColor(1, 1, 1, alpha or 0.07)
        e:SetPoint(p[1]); e:SetPoint(p[2])
        if p[3] == "h" then e:SetHeight(1) else e:SetWidth(1) end
        f.edges[i] = e
    end
end
function Kit:BorderColor(f, r, g, b, a) for _, e in ipairs(f.edges or {}) do e:SetVertexColor(r, g, b, a) end end

function Kit:Label(parent, text, x, y)
    local fs = self:Text(parent, 13, C.text)
    fs:SetPoint("TOPLEFT", x, y)
    self:Flow(fs, "TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end
function Kit:Hint(parent, text, x, y, width)
    local fs = self:Text(parent, 11, C.muted)
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetWidth(width)
    self:Flow(fs, "TOPLEFT", x, y, width)
    fs:SetText(text or "")
    return fs
end
function Kit:Caption(parent, text, x, y)
    local fs = self:Text(parent, 11, C.accent)
    fs:SetPoint("TOPLEFT", x, y)
    self:Flow(fs, "TOPLEFT", x, y)
    fs:SetText(text:upper())
    return fs
end

function Kit:Button(parent, label, width, primary, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 28)
    b.bg = self:Fill(b, primary and C.accent or C.control)
    b.bg:SetAllPoints()
    if not primary then self:Border(b, 0.08) end
    b.label = self:Text(b, 13, primary and C.onAccent or C.text)
    b.label:SetPoint("CENTER")
    b.label:SetText(label)
    b.primary = primary
    b:SetScript("OnEnter", function(s) if s:IsEnabled() then s.bg:SetVertexColor(unpack(primary and C.accentHi or C.hover)) end
        if s.tip then GameTooltip:SetOwner(s, "ANCHOR_TOP"); GameTooltip:AddLine(s.tip, 1, 1, 1, true); GameTooltip:Show() end end)
    b:SetScript("OnLeave", function(s) s.bg:SetVertexColor(unpack(primary and C.accent or C.control)); if s.tip then GameTooltip:Hide() end end)
    b:SetScript("OnClick", onClick)
    hooksecurefunc(b, "SetEnabled", function(s, on) s:SetAlpha(on and 1 or 0.4) end)
    return b
end

function Kit:Switch(parent, get, set)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(34, 18)
    local CIRCLE = self.o.circle
    local function cap(left)
        local t = b:CreateTexture(nil, "ARTWORK")
        if CIRCLE then t:SetTexture(CIRCLE); t:SetTexCoord(left and 0 or 0.5, left and 0.5 or 1, 0, 1) else t:SetTexture(WHITE) end
        t:SetSize(9, 18)
        t:SetPoint(left and "LEFT" or "RIGHT")
        return t
    end
    local l, r = cap(true), cap(false)
    local m = b:CreateTexture(nil, "ARTWORK"); m:SetTexture(WHITE)
    m:SetPoint("TOPLEFT", l, "TOPRIGHT"); m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")
    local knob = b:CreateTexture(nil, "OVERLAY"); knob:SetTexture(CIRCLE or WHITE); knob:SetSize(14, 14)
    local function paint(on)
        local col = on and C.accent or C.control
        l:SetVertexColor(unpack(col)); r:SetVertexColor(unpack(col)); m:SetVertexColor(unpack(col))
        knob:ClearAllPoints()
        if on then knob:SetPoint("RIGHT", -2, 0); knob:SetVertexColor(unpack(C.onAccent))
        else knob:SetPoint("LEFT", 2, 0); knob:SetVertexColor(unpack(C.dim)) end
    end
    b:SetScript("OnClick", function() set(not get()); paint(get() and true or false) end)
    self:OnRefresh(function() paint(get() and true or false) end)
    return b
end
function Kit:SwitchRow(parent, text, x, y, width, get, set)
    local lbl = self:Label(parent, text, x, y - 2)
    local s = self:Switch(parent, get, set)
    s:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + width, y)
    self:Flow(s, "TOPRIGHT", x + width, y, nil, true)
    s.labelFS = lbl
    return s
end

function Kit:Segmented(parent, items, x, y, width, get, set, height)
    height = height or 26
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width, height)
    f:SetPoint("TOPLEFT", x, y)
    self:Flow(f, "TOPLEFT", x, y, width)
    local bg = self:Fill(f, C.control); bg:SetAllPoints()
    local buttons = {}
    local function layout()
        local w = (f:GetWidth() or width) / #items
        if not w or w <= 0 then w = width / #items end
        for i, b in ipairs(buttons) do
            b:SetSize(w - 2, height - 4)
            b:SetPoint("LEFT", 1 + (i - 1) * w, 0)
        end
    end
    f:SetScript("OnSizeChanged", layout)
    for i, it in ipairs(items) do
        local b = CreateFrame("Button", nil, f)
        b.sel = self:Fill(b, C.accent, "ARTWORK"); b.sel:SetAllPoints()
        b.hl = self:Fill(b, { 1, 1, 1, 0.05 }, "ARTWORK", 1); b.hl:SetAllPoints(); b.hl:Hide()
        b.label = self:Text(b, 12, C.dim); b.label:SetPoint("CENTER"); b.label:SetText(it[2])
        b:SetScript("OnEnter", function(s) s.hl:Show() end)
        b:SetScript("OnLeave", function(s) s.hl:Hide() end)
        b:SetScript("OnClick", function() set(it[1]) end)
        b.value = it[1]
        buttons[i] = b
    end
    layout()
    self:OnRefresh(function()
        local v = get()
        for _, b in ipairs(buttons) do
            local on = (b.value == v)
            b.sel:SetShown(on)
            b.label:SetTextColor(unpack(on and C.onAccent or C.dim))
        end
    end)
    return f
end

function Kit:InputBox(parent, width, height)
    local eb = CreateFrame("EditBox", nil, parent)
    eb:SetSize(width, height or 24)
    eb:SetAutoFocus(false)
    eb:SetTextInsets(6, 6, 0, 0)
    lib.SetFont(eb, 13)
    eb:SetTextColor(unpack(C.text))
    local bg = self:Fill(eb, C.control); bg:SetAllPoints()
    self:Border(eb, 0.08)
    local kit = self
    eb:SetScript("OnEditFocusGained", function(s) kit:BorderColor(s, C.accent[1], C.accent[2], C.accent[3], 0.9); s:HighlightText() end)
    eb:SetScript("OnEditFocusLost", function(s) kit:BorderColor(s, 1, 1, 1, 0.08); s:HighlightText(0, 0) end)
    eb:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    return eb
end

function lib.num(text)
    local t = tostring(text or ""):gsub(",", ".")
    t = t:gsub("[^%d%.%-]", "")
    return tonumber(t)
end
function lib.fmtNum(v)
    v = tonumber(v) or 0
    if math.floor(v) == v then return tostring(v) end
    local s = string.format("%.2f", v):gsub("0+$", "")
    s = s:gsub("%.$", "")
    return s
end

-- o = { lo, hi, step, min, max (hard limits for typed values, optional) }
function Kit:SliderRow(parent, text, x, y, width, get, set, o)
    self:Label(parent, text, x, y - 5)
    local box = self:InputBox(parent, 64)
    box:SetJustifyH("CENTER")
    box:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + width, y)
    self:Flow(box, "TOPRIGHT", x + width, y, nil, true)
    local s = CreateFrame("Slider", nil, parent)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(width - 110 - 64 - 12, 18)
    self:Flow(s, nil, 0, 0, width - 110 - 64 - 12)
    s:SetPoint("RIGHT", box, "LEFT", -12, 0)
    s:SetMinMaxValues(o.lo, o.hi)
    s:SetValueStep(o.step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    s:EnableMouseWheel(true)
    local track = self:Fill(s, { 1, 1, 1, 0.10 }); track:SetHeight(4); track:SetPoint("LEFT"); track:SetPoint("RIGHT")
    local fill = self:Fill(s, C.accent, "ARTWORK"); fill:SetHeight(4); fill:SetPoint("LEFT")
    s:SetThumbTexture(WHITE)
    local thumb = s:GetThumbTexture()
    thumb:SetSize(6, 16)
    thumb:SetVertexColor(unpack(C.text))
    local function clamp(v)
        if o.min and v < o.min then v = o.min end
        if o.max and v > o.max then v = o.max end
        return v
    end
    local updating = false
    local function paint(v)
        local frac = (math.max(o.lo, math.min(o.hi, v)) - o.lo) / (o.hi - o.lo)
        fill:SetWidth(math.max(0.01, frac * (s:GetWidth() or 1)))
    end
    s:SetScript("OnSizeChanged", function() paint(tonumber(get()) or o.lo) end)
    s:SetScript("OnValueChanged", function(_, v)
        paint(v)
        if updating then return end
        v = math.floor(v / o.step + 0.5) * o.step
        set(clamp(v))
    end)
    s:SetScript("OnMouseWheel", function(_, d)
        local v = (tonumber(get()) or 0) + d * o.step * (IsShiftKeyDown() and 10 or 1)
        set(clamp(v))
    end)
    s:SetScript("OnEnter", function() thumb:SetVertexColor(unpack(C.accent)) end)
    s:SetScript("OnLeave", function() thumb:SetVertexColor(unpack(C.text)) end)
    local kit = self
    box:SetScript("OnEnterPressed", function(b)
        local v = lib.num(b:GetText())
        b:ClearFocus()
        if v ~= nil then set(clamp(v)) else kit:Refresh() end
    end)
    box:SetScript("OnEscapePressed", function(b) b:ClearFocus(); kit:Refresh() end)
    self:OnRefresh(function()
        local v = tonumber(get()) or o.lo
        updating = true
        s:SetValue(math.max(o.lo, math.min(o.hi, v)))
        updating = false
        paint(v)
        if not box:HasFocus() then box:SetText(lib.fmtNum(v)) end
    end)
    return s, box
end

-- items: { { key=, label= }, ... } or a function returning that. labelW: width of the label (0 = no label)
function Kit:Dropdown(parent, text, x, y, width, getItems, get, set, labelW)
    if type(getItems) ~= "function" then local items = getItems; getItems = function() return items end end
    labelW = labelW or (text and 120 or 0)
    if text then self:Label(parent, text, x, y - 5) end
    local kit = self
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width - labelW, 26)
    b:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + width, y)
    self:Flow(b, "TOPRIGHT", x + width, y, width - labelW, true)
    local bg = self:Fill(b, C.control); bg:SetAllPoints()
    self:Border(b, 0.08)
    local val = self:Text(b, 13, C.text); val:SetPoint("LEFT", 8, 0); val:SetPoint("RIGHT", -24, 0); val:SetWordWrap(false)
    local arrow = self:Text(b, 12, C.dim); arrow:SetPoint("RIGHT", -8, 0); arrow:SetText("v")
    b:SetScript("OnEnter", function() bg:SetVertexColor(unpack(C.hover)) end)
    b:SetScript("OnLeave", function() bg:SetVertexColor(unpack(C.control)) end)
    local list = CreateFrame("Frame", nil, self.frame or parent)
    list:SetFrameStrata("FULLSCREEN_DIALOG")
    list:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -2)
    list:EnableMouse(true)
    list:EnableMouseWheel(true)
    list:Hide()
    local lbg = self:Fill(list, { 0.11, 0.115, 0.13, 1 }); lbg:SetAllPoints()
    self:Border(list, 0.12)
    local ROWS, RH = 12, 22
    local rows, offset = {}, 0
    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, list)
        r:SetHeight(RH)
        r:SetPoint("TOPLEFT", 1, -1 - (i - 1) * RH); r:SetPoint("TOPRIGHT", -1, -1 - (i - 1) * RH)
        r.hl = self:Fill(r, { 1, 1, 1, 0.08 }, "ARTWORK", 2); r.hl:SetAllPoints(); r.hl:Hide()
        r.text = self:Text(r, 12, C.text); r.text:SetPoint("LEFT", 8, 0); r.text:SetPoint("RIGHT", -8, 0); r.text:SetWordWrap(false)
        r:SetScript("OnEnter", function(s) s.hl:Show() end)
        r:SetScript("OnLeave", function(s) s.hl:Hide() end)
        r:SetScript("OnClick", function(s) list:Hide(); lib.openList = nil; if s.key ~= nil then set(s.key) end end)
        rows[i] = r
    end
    local function render()
        local items = getItems()
        offset = math.max(0, math.min(offset, #items - ROWS))
        list:SetHeight(math.min(ROWS, #items) * RH + 2)
        for i = 1, ROWS do
            local it = items[i + offset]
            local r = rows[i]
            if it then
                r.key = it.key
                PaintFont(r.text, it, 12)
                r.text:SetText(it.label)
                r.text:SetTextColor(unpack(it.key == get() and C.accent or (it.color or C.text)))
                r:Show()
            else
                r.key = nil
                r:Hide()
            end
        end
    end
    list:SetScript("OnMouseWheel", function(_, d) offset = offset - d * 3; render() end)
    b:SetScript("OnClick", function()
        if list:IsShown() then list:Hide(); lib.openList = nil; return end
        if lib.openList then lib.openList:Hide() end
        local items = getItems()
        offset = 0
        for i, it in ipairs(items) do if it.key == get() then offset = math.max(0, i - 6) end end
        list:SetWidth(b:GetWidth() or (width - labelW))
        list:SetFrameStrata("FULLSCREEN_DIALOG")
        list:SetFrameLevel(((kit.frame and kit.frame:GetFrameLevel()) or 1) + 100)
        render(); list:Show(); lib.openList = list
    end)
    b.placeholder = ""
    self:OnRefresh(function()
        local cur = get()
        local label, sel
        for _, it in ipairs(getItems()) do if it.key == cur then label = it.label; sel = it end end
        PaintFont(val, sel, 13)
        val:SetText(label or (cur ~= nil and tostring(cur)) or b.placeholder)
    end)
    return b
end

-- Font picker: every row (and the closed box) shows its name in its own font. Needs LibFreeMedia-1.0 (falls back to game fonts).
function Kit:FontDropdown(parent, text, x, y, width, get, set, labelW)
    local function items()
        local LFM = LibStub and LibStub("LibFreeMedia-1.0", true)
        local out = {}
        local list = LFM and LFM:ListFonts()
        if list then
            for i, f in ipairs(list) do out[i] = { key = f.key, label = f.label, font = f.path } end
        else
            out = { { key = "ARIALN", label = "Arial Narrow", font = "Fonts\\ARIALN.TTF" }, { key = "FRIZQT", label = "Friz Quadrata", font = "Fonts\\FRIZQT__.TTF" },
                    { key = "MORPHEUS", label = "Morpheus", font = "Fonts\\MORPHEUS.TTF" }, { key = "SKURRI", label = "Skurri", font = "Fonts\\SKURRI.TTF" } }
        end
        return out
    end
    return self:Dropdown(parent, text, x, y, width, items, get, set, labelW)
end

-- Outline style picker (Shadow / None / Outline / Thick outline / Pixel outline)
function Kit:OutlineDropdown(parent, text, x, y, width, get, set, labelW)
    local function items()
        local LFM = LibStub and LibStub("LibFreeMedia-1.0", true)
        local src = (LFM and LFM.OUTLINES) or {
            { key = "NONE", label = "Shadow" }, { key = "CLEAN", label = "None" }, { key = "OUTLINE", label = "Outline" },
            { key = "THICKOUTLINE", label = "Thick outline" }, { key = "MONOCHROMEOUTLINE", label = "Pixel outline" } }
        return src
    end
    return self:Dropdown(parent, text, x, y, width, items, get, set, labelW)
end

-- ------------------------------------------------------------ window
-- o.cards  = { { title=, state=function, on=function, onClick=function, selected=function } ... } (optional)
-- o.tabs   = { { "key", "Label" }, ... }
-- returns pages[key], footer
function Kit:Build()
    local o = self.o
    local kit = self
    local W, H, PAD = self.W, self.H, self.PAD
    local frame = CreateFrame("Frame", o.name, UIParent)
    self.frame = frame
    frame:SetSize(W, H)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    if frame.SetDontSavePosition then frame:SetDontSavePosition(true) end
    if o.name then tinsert(UISpecialFrames, o.name) end
    local shadow = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    frame.fhShadow = shadow
    if o.shadow then shadow:SetTexture(o.shadow) else shadow:SetTexture(WHITE) end
    shadow:SetVertexColor(0, 0, 0, o.shadow and 0.8 or 0.35)
    shadow:SetPoint("TOPLEFT", -36, 36); shadow:SetPoint("BOTTOMRIGHT", 36, -36)
    if not o.shadow then shadow:SetPoint("TOPLEFT", -4, 4); shadow:SetPoint("BOTTOMRIGHT", 4, -4) end
    local bg = self:Fill(frame, C.bg, "BACKGROUND", -6); bg:SetAllPoints()
    self:Border(frame, 0.09)
    local topLine = self:Fill(frame, C.accent, "BORDER", 2); topLine:SetHeight(2); topLine:SetPoint("TOPLEFT"); topLine:SetPoint("TOPRIGHT")

    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT"); header:SetPoint("TOPRIGHT"); header:SetHeight(54)
    header:EnableMouse(true); header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() (frame.fhMover or frame):StartMoving() end)
    header:SetScript("OnDragStop", function() (frame.fhMover or frame):StopMovingOrSizing() end)
    local icon = header:CreateTexture(nil, "ARTWORK"); icon:SetTexture(o.icon); icon:SetSize(32, 32); icon:SetPoint("LEFT", PAD, -1)
    local title = self:Text(header, 17, C.text); title:SetPoint("LEFT", icon, "RIGHT", 10, 7); title:SetText(o.title or "")
    local ver = (C_AddOns and C_AddOns.GetAddOnMetadata and o.addon and C_AddOns.GetAddOnMetadata(o.addon, "Version")) or ""
    local sub = self:Text(header, 11, C.muted); sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    self.subtitle = sub
    sub:SetText((o.sub or "") .. (ver ~= "" and ("  ·  v" .. ver) or ""))
    if o.subFn then self:OnRefresh(function() sub:SetText((o.sub or "") .. (ver ~= "" and ("  ·  v" .. ver) or "") .. o.subFn()) end) end
    local close = CreateFrame("Button", nil, header); close:SetSize(26, 26); close:SetPoint("RIGHT", -12, 0)
    local x1 = self:Fill(close, C.dim, "ARTWORK"); x1:SetSize(14, 2); x1:SetPoint("CENTER"); x1:SetRotation(math.rad(45))
    local x2 = self:Fill(close, C.dim, "ARTWORK"); x2:SetSize(14, 2); x2:SetPoint("CENTER"); x2:SetRotation(math.rad(-45))
    close:SetScript("OnEnter", function() x1:SetVertexColor(unpack(C.accent)); x2:SetVertexColor(unpack(C.accent)) end)
    close:SetScript("OnLeave", function() x1:SetVertexColor(unpack(C.dim)); x2:SetVertexColor(unpack(C.dim)) end)
    close:SetScript("OnClick", function() frame:Hide() end)
    frame.fhClose = close

    local top = -62
    if o.cards then
        local NB = #o.cards
        local gap = 6
        local cards = {}
        local function place(width)
            local cw = (width - 2 * PAD - (NB - 1) * gap) / NB
            for i, card in ipairs(cards) do
                card:SetWidth(cw)
                card:SetPoint("TOPLEFT", PAD + (i - 1) * (cw + gap), -62)
            end
        end
        self.onResize[#self.onResize + 1] = place
        for i, info in ipairs(o.cards) do
            local card = CreateFrame("Button", nil, frame)
            card:SetHeight(46)
            cards[i] = card
            card.bg = self:Fill(card, C.panel); card.bg:SetAllPoints()
            self:Border(card, 0.06)
            card.mark = self:Fill(card, C.accent, "ARTWORK"); card.mark:SetHeight(2); card.mark:SetPoint("BOTTOMLEFT"); card.mark:SetPoint("BOTTOMRIGHT"); card.mark:Hide()
            card.dot = card:CreateTexture(nil, "ARTWORK"); card.dot:SetTexture(o.circle or WHITE); card.dot:SetSize(8, 8); card.dot:SetPoint("TOPLEFT", 10, -12)
            card.name = self:Text(card, 13, C.text); card.name:SetPoint("LEFT", card.dot, "RIGHT", 6, 0); card.name:SetPoint("RIGHT", -4, 0); card.name:SetWordWrap(false)
            card.name:SetText(info.title)
            card.state = self:Text(card, 11, C.muted); card.state:SetPoint("TOPLEFT", 24, -27); card.state:SetPoint("RIGHT", -4, 0); card.state:SetWordWrap(false)
            local function selected() return info.selected and info.selected() end
            card:SetScript("OnEnter", function(s) if not selected() then s.bg:SetVertexColor(unpack(C.control)) end end)
            card:SetScript("OnLeave", function(s) if not selected() then s.bg:SetVertexColor(unpack(C.panel)) end end)
            card:SetScript("OnClick", function() if info.onClick then if lib.openList then lib.openList:Hide(); lib.openList = nil end; info.onClick(); kit:Refresh() end end)
            self:OnRefresh(function()
                local sel = selected()
                local on = not info.on or info.on()
                card.bg:SetVertexColor(unpack(sel and C.control or C.panel))
                card.mark:SetShown(sel and true or false)
                card.dot:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], on and 1 or 0.25)
                card.name:SetTextColor(unpack(on and C.text or C.muted))
                card.state:SetText(info.state and info.state() or "")
            end)
        end
        place(W)
        top = -120
    end

    local pages, tabButtons = {}, {}
    self.pages = pages
    self.activeTab = o.tabs and o.tabs[1][1]
    local tabY = top
    local line = self:Fill(frame, { 1, 1, 1, 0.07 }, "BORDER"); line:SetHeight(1)
    line:SetPoint("TOPLEFT", PAD, tabY - 30); line:SetPoint("TOPRIGHT", -PAD, tabY - 30)
    local tx = PAD
    for _, t in ipairs(o.tabs or {}) do
        local b = CreateFrame("Button", nil, frame)
        b.label = self:Text(b, 14, C.dim); b.label:SetPoint("LEFT"); b.label:SetText(t[2])
        b:SetSize((b.label:GetStringWidth() or 60) + 4, 30)
        b:SetPoint("TOPLEFT", tx, tabY)
        b.under = self:Fill(b, C.accent, "ARTWORK"); b.under:SetHeight(2); b.under:SetPoint("BOTTOMLEFT", 0, -1); b.under:SetPoint("BOTTOMRIGHT", 0, -1)
        b:SetScript("OnClick", function() kit.activeTab = t[1]; if lib.openList then lib.openList:Hide(); lib.openList = nil end; kit:Refresh() end)
        b:SetScript("OnEnter", function(s) if kit.activeTab ~= t[1] then s.label:SetTextColor(unpack(C.text)) end end)
        b:SetScript("OnLeave", function(s) if kit.activeTab ~= t[1] then s.label:SetTextColor(unpack(C.dim)) end end)
        tabButtons[t[1]] = b
        tx = tx + b:GetWidth() + 26
        local page = CreateFrame("Frame", nil, frame)
        page:SetPoint("TOPLEFT", 0, tabY - 44); page:SetPoint("BOTTOMRIGHT", 0, 60)
        pages[t[1]] = page
    end
    self.tabButtons = tabButtons
    self:OnRefresh(function()
        if o.tabShown and kit.activeTab and not o.tabShown(kit.activeTab) then
            for _, t in ipairs(o.tabs) do if o.tabShown(t[1]) then kit.activeTab = t[1]; break end end
        end
        for key, b in pairs(tabButtons) do
            local shown = not (o.tabShown and not o.tabShown(key))
            local on = (key == kit.activeTab)
            b:SetShown(shown)
            b.under:SetShown(on)
            b.label:SetTextColor(unpack(on and C.text or C.dim))
            pages[key]:SetShown(on and shown)
        end
    end)

    local footer = CreateFrame("Frame", nil, frame)
    footer:SetPoint("BOTTOMLEFT"); footer:SetPoint("BOTTOMRIGHT"); footer:SetHeight(56)
    local fbg = self:Fill(footer, C.panel, "BACKGROUND", -5); fbg:SetAllPoints()
    local fl = self:Fill(footer, { 1, 1, 1, 0.06 }, "BORDER"); fl:SetHeight(1); fl:SetPoint("TOPLEFT"); fl:SetPoint("TOPRIGHT")
    self.footer = footer

    function frame.Refresh() for _, fn in ipairs(kit.refreshers) do fn() end end
    frame:SetScript("OnShow", function(s) s.Refresh() end)
    frame:SetScript("OnSizeChanged", function(_, w) kit:Reflow(w) end)
    frame:SetScript("OnHide", function() if lib.openList then lib.openList:Hide(); lib.openList = nil end end)
    frame:Hide()
    return pages, footer
end

-- ------------------------------------------------------------ Free Hub
function Kit:RegisterHub(id, build, minimapFn)
    local kit = self
    local function Embed(parent)
        if not kit.frame then build() end
        local frame = kit.frame
        frame.fhEmbedded = true
        frame:SetParent(parent)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
        frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
        frame:SetFrameStrata(parent:GetFrameStrata())
        frame:SetFrameLevel(parent:GetFrameLevel() + 1)
        frame.fhShadow:Hide()
        frame.fhClose:Hide()
        frame.fhMover = FreeHub:GetFrame()
        frame.fhNaturalW, frame.fhNaturalH = kit.W, kit.H
        frame:Show()
        return frame
    end
    local function Unembed()
        local frame = kit.frame
        if not frame or not frame.fhEmbedded then return end
        frame.fhEmbedded = nil
        frame:Hide()
        frame:SetParent(UIParent)
        frame:ClearAllPoints()
        frame:SetSize(kit.W, kit.H)
        frame:SetPoint("CENTER")
        frame:SetFrameStrata("DIALOG")
        frame.fhShadow:Show()
        frame.fhClose:Show()
        frame.fhMover = nil
    end
    if FreeHub and FreeHub.Register then
        FreeHub:Register(id, { embed = Embed, unembed = Unembed, minW = kit.W, minH = kit.H, minimap = minimapFn })
        return true
    end
end

function Kit:Toggle(id, build)
    if FreeHub and FreeHub.Toggle and FreeHub.IsRegistered and FreeHub:IsRegistered(id) then FreeHub:Toggle(id); return end
    if not self.frame then build() end
    self.frame:SetShown(not self.frame:IsShown())
end
