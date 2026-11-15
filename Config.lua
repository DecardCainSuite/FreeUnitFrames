-- FreeUnitFrames - options window (/fuf)
-- Same look as Free Swing Timer: graphite + ember accent, selector and tabs on top.
-- Own frames only (no Blizzard frame is modified).

local ADDON, ns = ...

local MEDIA  = ns.MEDIA
local WHITE  = ns.WHITE
local CIRCLE = MEDIA .. "circle"
local FONT   = "Fonts\\ARIALN.TTF"

local C = {
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
}

local W, H = 900, 720
local PAD = 18
local frame
local scope = "player"       -- "global" or a unit key
local sub = { text = "name", aura = "buffs", ind = "raidIcon" }
local refreshers = {}
ns.OptionsState = sub     -- (tests) which sub-view each tab shows
local function OnRefresh(fn) refreshers[#refreshers + 1] = fn end

-- Elements that follow the two-column layout when the window is resized (inside Free Hub).
-- Each one remembers its position for the natural width W; the right column moves and both columns widen.
local GAP = 48
local COLW0 = (W - 2 * PAD - GAP) / 2
local RX0 = PAD + COLW0 + GAP
local flow, onResize = {}, {}
local function Flow(obj, x, y, width, alignRight)
    flow[#flow + 1] = { o = obj, x = x, y = y, w = width, right = alignRight }
end
local function Reflow(width)
    width = math.max(W, width or W)
    local colW = (width - 2 * PAD - GAP) / 2
    local dC = colW - COLW0
    local rx = PAD + colW + GAP
    for _, e in ipairs(flow) do
        local x = e.x
        if x >= RX0 - 1 then x = x - RX0 + rx end
        if e.right then x = x + dC end
        e.o:SetPoint("TOPLEFT", x, e.y)
        if e.w and e.w >= 150 and not e.o.flowFixed then e.o:SetWidth(e.w + dC) end
    end
    for _, fn in ipairs(onResize) do fn(width) end
end

-- ------------------------------------------------------------ data access
local function Root() return scope == "global" and ns.Global() or ns.Unit(scope) end
local function Resolve(path) return type(path) == "function" and path() or path end
-- "@player:classPower.style" reads / writes another unit than the selected card
-- (combo points are the player's, but they are also set from the Target card)
local function Where(path)
    path = Resolve(path)
    local u, rest = path:match("^@(%w+):(.+)$")
    if u then return ns.Unit(u), rest, u end
    return Root(), path, nil
end
local function Get(path) local root, p = Where(path); return ns.GetPath(root, p) end
local function Apply(unit)
    if unit then ns.UpdateUnit(unit)
    elseif scope == "global" then ns.UpdateAll() else ns.UpdateUnit(scope) end
end
local function Set(path, value)
    local root, p, u = Where(path)
    ns.SetPath(root, p, value)
    Apply(u)
    if frame then frame:Refresh() end
end
local function IsUnit(...)
    for i = 1, select("#", ...) do if scope == select(i, ...) then return true end end
    return false
end

-- ------------------------------------------------------------ primitives
local function SetFont(obj, size, flags)
    obj:SetFont(FONT, size, flags or "")
    if not obj:GetFont() then obj:SetFont(STANDARD_TEXT_FONT, size, flags or "") end
end
local function Text(parent, size, color, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    SetFont(fs, size)
    fs:SetTextColor(unpack(color))
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    return fs
end
local function Fill(parent, color, layer, subl)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, subl or 0)
    t:SetTexture(WHITE)
    t:SetVertexColor(unpack(color))
    return t
end
local function Border(f, alpha, layer)
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
local function BorderColor(f, r, g, b, a) for _, e in ipairs(f.edges) do e:SetVertexColor(r, g, b, a) end end

local function Row(parent, x, y, width, height, shownFn)
    local r = CreateFrame("Frame", nil, parent)
    r:SetPoint("TOPLEFT", x, y)
    r:SetSize(width, height or 30)
    Flow(r, x, y, width)
    if shownFn then OnRefresh(function() r:SetShown(shownFn()) end) end
    return r
end
local function Label(row, text)
    local fs = Text(row, 13, C.text)
    fs:SetPoint("LEFT", 0, 0)
    fs:SetText(text)
    row.label = fs
    return fs
end
local function Caption(parent, text, x, y, shownFn)
    local fs = Text(parent, 11, C.accent)
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text:upper())
    Flow(fs, x, y)
    if shownFn then OnRefresh(function() fs:SetShown(shownFn()) end) end
    return fs
end
local function Hint(parent, text, x, y, width, shownFn)
    local fs = Text(parent, 11, C.muted)
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetWidth(width)
    Flow(fs, x, y, width)
    fs:SetText(text or "")
    if shownFn then OnRefresh(function() fs:SetShown(shownFn()) end) end
    return fs
end

local function Button(parent, label, width, primary, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 28)
    b.bg = Fill(b, primary and C.accent or C.control)
    b.bg:SetAllPoints()
    if not primary then Border(b, 0.08) end
    b.label = Text(b, 13, primary and C.onAccent or C.text)
    b.label:SetPoint("CENTER")
    b.label:SetText(label)
    b.primary = primary
    b:SetScript("OnEnter", function(self) self.bg:SetVertexColor(unpack(self.primary and C.accentHi or C.hover)) end)
    b:SetScript("OnLeave", function(self) self.bg:SetVertexColor(unpack(self.primary and C.accent or C.control)) end)
    b:SetScript("OnClick", onClick)
    return b
end

-- ------------------------------------------------------------ controls
local function Switch(parent, get, set)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(34, 18)
    local function cap(left)
        local t = b:CreateTexture(nil, "ARTWORK")
        t:SetTexture(CIRCLE)
        t:SetTexCoord(left and 0 or 0.5, left and 0.5 or 1, 0, 1)
        t:SetSize(9, 18)
        t:SetPoint(left and "LEFT" or "RIGHT")
        return t
    end
    local l, r = cap(true), cap(false)
    local m = b:CreateTexture(nil, "ARTWORK"); m:SetTexture(WHITE)
    m:SetPoint("TOPLEFT", l, "TOPRIGHT"); m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")
    local knob = b:CreateTexture(nil, "OVERLAY"); knob:SetTexture(CIRCLE); knob:SetSize(14, 14)
    local function paint(on)
        local col = on and C.accent or C.control
        l:SetVertexColor(unpack(col)); r:SetVertexColor(unpack(col)); m:SetVertexColor(unpack(col))
        knob:ClearAllPoints()
        if on then knob:SetPoint("RIGHT", -2, 0); knob:SetVertexColor(unpack(C.onAccent))
        else knob:SetPoint("LEFT", 2, 0); knob:SetVertexColor(unpack(C.dim)) end
    end
    b:SetScript("OnClick", function() set(not get()) end)
    OnRefresh(function() paint(get() and true or false) end)
    return b
end

local function SwitchRow(parent, text, x, y, width, path, shownFn)
    local row = Row(parent, x, y, width, 24, shownFn)
    Label(row, text)
    local s = Switch(row, function() return Get(path) end, function(v) Set(path, v) end)
    s:SetPoint("RIGHT", 0, 0)
    return row
end

local function Segmented(parent, items, width, get, set, height)
    height = height or 26
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width, height)
    local bg = Fill(f, C.control); bg:SetAllPoints()
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
        b.sel = Fill(b, C.accent, "ARTWORK"); b.sel:SetAllPoints()
        b.hl = Fill(b, { 1, 1, 1, 0.05 }, "ARTWORK", 1); b.hl:SetAllPoints(); b.hl:Hide()
        b.label = Text(b, 12, C.dim); b.label:SetPoint("CENTER"); b.label:SetText(it[2])
        if it.icon then
            -- small picture of what the choice is (indicators)
            local ic = b:CreateTexture(nil, "OVERLAY")
            ic:SetSize(height - 10, height - 10)
            ic:SetTexture(it.icon[1])
            if it.icon[2] then ic:SetTexCoord(it.icon[2], it.icon[3], it.icon[4], it.icon[5]) end
            b.label:ClearAllPoints(); b.label:SetPoint("CENTER", (height - 6) / 2, 0)
            ic:SetPoint("RIGHT", b.label, "LEFT", -5, 0)
        end
        b:SetScript("OnEnter", function(self) self.hl:Show() end)
        b:SetScript("OnLeave", function(self) self.hl:Hide() end)
        b:SetScript("OnClick", function() set(it[1]) end)
        b.value = it[1]
        buttons[i] = b
    end
    layout()
    OnRefresh(function()
        local v = get()
        for _, b in ipairs(buttons) do
            local on = (b.value == v) or (b.value == false and v == nil)
            b.sel:SetShown(on)
            b.label:SetTextColor(unpack(on and C.onAccent or C.dim))
        end
    end)
    return f
end

local function SegRow(parent, text, x, y, width, items, path, shownFn, labelW)
    local row = Row(parent, x, y, width, 26, shownFn)
    labelW = labelW or 120
    Label(row, text)
    local seg = Segmented(row, items, width - labelW, function() return Get(path) end, function(v) Set(path, v) end)
    seg:SetPoint("RIGHT", 0, 0); seg:SetPoint("LEFT", labelW, 0)
    return row
end

local function InputBox(parent, width, height)
    local eb = CreateFrame("EditBox", nil, parent)
    eb:SetSize(width, height or 24)
    eb:SetAutoFocus(false)
    eb:SetTextInsets(6, 6, 0, 0)
    SetFont(eb, 13)
    eb:SetTextColor(unpack(C.text))
    local bg = Fill(eb, C.control); bg:SetAllPoints()
    Border(eb, 0.08)
    eb:SetScript("OnEditFocusGained", function(self) BorderColor(self, C.accent[1], C.accent[2], C.accent[3], 0.9); self:HighlightText() end)
    eb:SetScript("OnEditFocusLost", function(self) BorderColor(self, 1, 1, 1, 0.08); self:HighlightText(0, 0) end)
    return eb
end

local function num(text)
    local t = (text or ""):gsub(",", ".")
    t = t:gsub("[^%d%.%-]", "")
    return tonumber(t)
end
local function fmtNum(v)
    if type(v) ~= "number" then return tostring(v or "") end
    if math.floor(v) == v then return tostring(v) end
    local s = string.format("%.2f", v):gsub("0+$", "")
    return (s:gsub("%.$", ""))
end

-- Slider with an indicative range + a free value box (no limit when typing)
local function SliderRow(parent, text, x, y, width, path, o, shownFn)
    local row = Row(parent, x, y, width, 26, shownFn)
    Label(row, text)
    o.fmt = o.fmt or fmtNum
    o.parse = o.parse or function(t) return num(t) end
    local box = InputBox(row, 64)
    box:SetJustifyH("CENTER")
    box:SetPoint("RIGHT", 0, 0)
    local s = CreateFrame("Slider", nil, row)
    s:SetOrientation("HORIZONTAL")
    s:SetHeight(18)
    s:SetPoint("LEFT", 120, 0)
    s:SetPoint("RIGHT", box, "LEFT", -12, 0)
    s:SetMinMaxValues(o.lo, o.hi)
    s:SetValueStep(o.step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    s:EnableMouseWheel(true)
    local track = Fill(s, { 1, 1, 1, 0.10 }); track:SetHeight(4); track:SetPoint("LEFT"); track:SetPoint("RIGHT")
    local fill = Fill(s, C.accent, "ARTWORK"); fill:SetHeight(4); fill:SetPoint("LEFT")
    s:SetThumbTexture(WHITE)
    local thumb = s:GetThumbTexture()
    thumb:SetSize(6, 16)
    thumb:SetVertexColor(unpack(C.text))
    local toS = o.toSlider or function(v) return v end
    local fromS = o.fromSlider or function(v) return v end
    local updating = false
    local function paint(v)
        local frac = (math.max(o.lo, math.min(o.hi, v)) - o.lo) / (o.hi - o.lo)
        fill:SetWidth(math.max(0.01, frac * s:GetWidth()))
    end
    s:SetScript("OnSizeChanged", function() paint(s:GetValue() or o.lo) end)
    s:SetScript("OnValueChanged", function(_, v)
        paint(v)
        if updating then return end
        v = math.floor(v / o.step + 0.5) * o.step
        Set(path, fromS(v))
    end)
    s:SetScript("OnMouseWheel", function(_, d)
        local v = toS(Get(path) or 0) + d * o.step * (IsShiftKeyDown() and 10 or 1)
        local parsed = o.parse(fmtNum(v))
        if parsed ~= nil then Set(path, parsed) end
    end)
    s:SetScript("OnEnter", function() thumb:SetVertexColor(unpack(C.accent)) end)
    s:SetScript("OnLeave", function() thumb:SetVertexColor(unpack(C.text)) end)
    box:SetScript("OnEnterPressed", function(self)
        local v = o.parse(self:GetText())
        self:ClearFocus()
        if v ~= nil then Set(path, v) else frame:Refresh() end
    end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus(); frame:Refresh() end)
    OnRefresh(function()
        if not row:IsShown() and shownFn then return end
        local raw = Get(path)
        if raw == nil then return end
        local v = toS(raw)
        updating = true
        s:SetValue(math.max(o.lo, math.min(o.hi, v)))
        updating = false
        paint(v)
        if not box:HasFocus() then box:SetText(o.fmt(raw)) end
    end)
    return row
end

local function OpenColorPicker(r, g, b, a, hasAlpha, onChange)
    local function current()
        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
        local na = a
        if hasAlpha then
            if ColorPickerFrame.GetColorAlpha then na = ColorPickerFrame:GetColorAlpha()
            elseif OpacitySliderFrame then na = 1 - OpacitySliderFrame:GetValue() end
        end
        return nr, ng, nb, na
    end
    local info = {
        r = r, g = g, b = b, opacity = a, hasOpacity = hasAlpha,
        swatchFunc = function() onChange(current()) end,
        opacityFunc = function() onChange(current()) end,
        cancelFunc = function() onChange(r, g, b, a) end,
    }
    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow(info)
    else
        ColorPickerFrame.func, ColorPickerFrame.opacityFunc, ColorPickerFrame.cancelFunc = info.swatchFunc, info.opacityFunc, info.cancelFunc
        ColorPickerFrame.hasOpacity, ColorPickerFrame.opacity = hasAlpha, hasAlpha and (1 - (a or 1)) or nil
        ColorPickerFrame:SetColorRGB(r, g, b)
        ColorPickerFrame:Hide(); ColorPickerFrame:Show()
    end
end

local function ColorRow(parent, text, x, y, width, path, hasAlpha, enabledFn, shownFn)
    local row = Row(parent, x, y, width, 24, shownFn)
    local lbl = Label(row, text)
    local b = CreateFrame("Button", nil, row)
    b:SetSize(46, 20)
    b:SetPoint("RIGHT", 0, 0)
    local checker = Fill(b, { 0.3, 0.3, 0.3, 1 }); checker:SetAllPoints()
    local sw = Fill(b, { 1, 1, 1, 1 }, "ARTWORK"); sw:SetPoint("TOPLEFT", 2, -2); sw:SetPoint("BOTTOMRIGHT", -2, 2)
    Border(b, 0.15, "OVERLAY")
    b:SetScript("OnEnter", function(self) BorderColor(self, C.accent[1], C.accent[2], C.accent[3], 1) end)
    b:SetScript("OnLeave", function(self) BorderColor(self, 1, 1, 1, 0.15) end)
    b:SetScript("OnClick", function()
        if enabledFn and not enabledFn() then return end
        local c = Get(path)
        if type(c) ~= "table" then return end
        local root, p, other = Where(path)
        local applyScope = other or scope
        OpenColorPicker(c[1], c[2], c[3], c[4] or 1, hasAlpha, function(r, g, bl, a)
            local t = ns.GetPath(root, p)
            t[1], t[2], t[3] = r, g, bl
            if hasAlpha then t[4] = a end
            if applyScope == "global" then ns.UpdateAll() else ns.UpdateUnit(applyScope) end
            if frame then frame:Refresh() end
        end)
    end)
    OnRefresh(function()
        local c = Get(path)
        if type(c) ~= "table" then return end
        sw:SetVertexColor(c[1], c[2], c[3], hasAlpha and (c[4] or 1) or 1)
        local on = not enabledFn or enabledFn()
        b:SetAlpha(on and 1 or 0.35)
        lbl:SetTextColor(unpack(on and C.text or C.muted))
    end)
    return row
end

-- a FontString written in the typeface at `path` (falls back to the options font)
local function PathFont(fs, path, size)
    if type(path) == "string" and path ~= "" then
        local ok, res = pcall(fs.SetFont, fs, path, size, "")
        if ok and res ~= false then return end
    end
    SetFont(fs, size)
end

-- Dropdown with optional texture preview (items: { key=, label=, path= }).
-- showTextures == true: each row shows its texture; "font": each row (and the selected value) is written in its own
-- typeface (item.path); an item can also carry its own `font` path.
local openList
local function Dropdown(parent, x, y, width, labelText, getItems, get, set, showTextures, shownFn, labelW)
    local row = Row(parent, x, y, width, 26, shownFn)
    labelW = labelText and (labelW or 120) or 0
    if labelText then Label(row, labelText) end
    local bw = width - labelW
    local b = CreateFrame("Button", nil, row)
    b:SetHeight(26)
    b:SetPoint("RIGHT", 0, 0); b:SetPoint("LEFT", labelW, 0)
    local bg = Fill(b, C.control); bg:SetAllPoints()
    Border(b, 0.08)
    local prev = b:CreateTexture(nil, "ARTWORK"); prev:SetPoint("TOPLEFT", 1, -1); prev:SetPoint("BOTTOMRIGHT", -22, 1); prev:SetAlpha(0.35)
    local val = Text(b, 13, C.text); val:SetPoint("LEFT", 8, 0); val:SetPoint("RIGHT", -24, 0); val:SetWordWrap(false)
    local arrow = Text(b, 12, C.dim); arrow:SetPoint("RIGHT", -8, 0); arrow:SetText("v")
    b:SetScript("OnEnter", function() bg:SetVertexColor(unpack(C.hover)) end)
    b:SetScript("OnLeave", function() bg:SetVertexColor(unpack(C.control)) end)

    local list = CreateFrame("Frame", nil, frame)
    list:SetFrameStrata("FULLSCREEN_DIALOG")
    list:SetWidth(bw)
    list:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -2)
    list:EnableMouse(true)
    list:EnableMouseWheel(true)
    list:Hide()
    local lbg = Fill(list, { 0.11, 0.115, 0.13, 1 }); lbg:SetAllPoints()
    Border(list, 0.12)
    local ROWS, RH = 10, 22
    local rows, offset = {}, 0
    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, list)
        r:SetHeight(RH)
        r:SetPoint("TOPLEFT", 1, -1 - (i - 1) * RH); r:SetPoint("TOPRIGHT", -1, -1 - (i - 1) * RH)
        r.tex = r:CreateTexture(nil, "ARTWORK"); r.tex:SetPoint("TOPLEFT", 2, -2); r.tex:SetPoint("BOTTOMRIGHT", -2, 2); r.tex:SetAlpha(0.55)
        r.hl = Fill(r, { 1, 1, 1, 0.08 }, "ARTWORK", 2); r.hl:SetAllPoints(); r.hl:Hide()
        r.text = Text(r, 12, C.text); r.text:SetPoint("LEFT", 8, 0); r.text:SetPoint("RIGHT", -8, 0); r.text:SetWordWrap(false)
        r:SetScript("OnEnter", function(self) self.hl:Show() end)
        r:SetScript("OnLeave", function(self) self.hl:Hide() end)
        r:SetScript("OnClick", function(self) list:Hide(); openList = nil; set(self.key) end)
        rows[i] = r
    end
    local function render()
        local items = getItems()
        offset = math.max(0, math.min(offset, #items - ROWS))
        local shown = math.min(ROWS, #items)
        list:SetHeight(shown * RH + 2)
        for i = 1, ROWS do
            local it = items[i + offset]
            local r = rows[i]
            if it then
                r.key = it.key
                if it.font or showTextures == "font" then PathFont(r.text, it.font or it.path, 12) end
                r.text:SetText(it.label)
                r.text:SetTextColor(unpack(it.key == get() and C.accent or C.text))
                if showTextures == true and it.path then r.tex:SetTexture(it.path); r.tex:SetVertexColor(0.8, 0.8, 0.85); r.tex:Show() else r.tex:Hide() end
                r:Show()
            else
                r:Hide()
            end
        end
    end
    list:SetScript("OnMouseWheel", function(_, d) offset = offset - d * 3; render() end)
    b:SetScript("OnClick", function()
        if list:IsShown() then list:Hide(); openList = nil; return end
        if openList then openList:Hide() end
        local items = getItems()
        offset = 0
        for i, it in ipairs(items) do if it.key == get() then offset = math.max(0, i - 5) end end
        -- the window's strata is copied to its children (Free Hub), so put the list back on top each time
        list:SetWidth(b:GetWidth() or bw)
        list:SetFrameStrata("FULLSCREEN_DIALOG")
        list:SetFrameLevel((frame:GetFrameLevel() or 1) + 100)
        render(); list:Show(); openList = list
    end)
    OnRefresh(function()
        local cur = get()
        local label, path, fpath = nil, nil, nil
        for _, it in ipairs(getItems()) do if it.key == cur then label, path, fpath = it.label, it.path, it.font or (showTextures == "font" and it.path or nil) end end
        PathFont(val, fpath, 13)
        val:SetText(label or (cur and tostring(cur)) or row.placeholder or "")
        if showTextures == true and path then prev:SetTexture(path); prev:SetVertexColor(1, 1, 1); prev:Show() else prev:Hide() end
    end)
    return row
end

local function DropdownRow(parent, text, x, y, width, items, path, showTextures, shownFn)
    local getItems = type(items) == "function" and items or function() return items end
    return Dropdown(parent, x, y, width, text, getItems, function() return Get(path) end, function(v) Set(path, v) end, showTextures, shownFn)
end

local function InputRow(parent, text, x, y, width, path, shownFn)
    local row = Row(parent, x, y, width, 26, shownFn)
    Label(row, text)
    local eb = InputBox(row, width - 120)
    eb:SetPoint("RIGHT", 0, 0); eb:SetPoint("LEFT", 120, 0)
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus(); Set(path, self:GetText()) end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); frame:Refresh() end)
    OnRefresh(function() if not eb:HasFocus() then eb:SetText(Get(path) or ""); eb:SetCursorPosition(0) end end)
    return row
end

-- Border settings block: 4 rows (mode, own colour, colour, thickness)
local function BorderBlock(parent, title, x, yTop, width, base, shownFn, rowH)
    rowH = rowH or 34
    local on = shownFn or function() return true end
    local function P(f) return function() return base .. "." .. f end end
    local function custom() return on() and Get(P("mode")) ~= "HIDE" end
    Caption(parent, title, x, yTop, shownFn)
    SegRow(parent, "Border", x, yTop - 22, width, { { "INHERIT", "General" }, { "SHOW", "Show" }, { "HIDE", "Hide" } }, P("mode"), shownFn)
    SwitchRow(parent, "Own colour", x, yTop - 22 - rowH, width, P("useColor"), custom)
    ColorRow(parent, "Border colour", x, yTop - 22 - 2 * rowH, width, P("color"), true, function() return Get(P("useColor")) end, custom)
    SliderRow(parent, "Thickness", x, yTop - 22 - 3 * rowH, width, P("size"), {
        lo = 0, hi = 8, step = 1,
        fmt = function(v) return (v and v > 0) and fmtNum(v) or "General" end,
        parse = function(t) if (t or ""):lower():find("gen") then return 0 end local v = num(t); return (v and v >= 0) and v or nil end,
    }, custom)
end

-- ------------------------------------------------------------ option lists
local POINTS = {
    { key = "TOPLEFT", label = "Top left" }, { key = "TOP", label = "Top" }, { key = "TOPRIGHT", label = "Top right" },
    { key = "LEFT", label = "Left" }, { key = "CENTER", label = "Center" }, { key = "RIGHT", label = "Right" },
    { key = "BOTTOMLEFT", label = "Bottom left" }, { key = "BOTTOM", label = "Bottom" }, { key = "BOTTOMRIGHT", label = "Bottom right" },
}
local OUTLINES = { { "NONE", "None" }, { "OUTLINE", "Outline" }, { "THICKOUTLINE", "Thick" } }
local any = function(t) return num(t) end
local positive = function(t) local v = num(t); return (v and v > 0) and v or nil end
local zeroPlus = function(t) local v = num(t); return (v and v >= 0) and v or nil end
local percent = {
    lo = 0, hi = 100, step = 1,
    toSlider = function(v) return math.floor(v * 100 + 0.5) end, fromSlider = function(v) return v / 100 end,
    fmt = function(v) return math.floor(v * 100 + 0.5) .. "%" end,
    parse = function(t) local v = num(t); if v and v >= 0 and v <= 100 then return v / 100 end end,
}
local function auto(lo, hi)
    return {
        lo = lo, hi = hi, step = 1,
        fmt = function(v) return (v and v > 0) and fmtNum(v) or "Auto" end,
        parse = function(t) if (t or ""):lower():find("auto") then return 0 end local v = num(t); return (v and v >= 0) and v or nil end,
    }
end

-- ------------------------------------------------------------ window
local function Build()
    frame = CreateFrame("Frame", "FreeUnitFramesOptions", UIParent)
    frame:SetSize(W, H)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    if frame.SetDontSavePosition then frame:SetDontSavePosition(true) end
    tinsert(UISpecialFrames, "FreeUnitFramesOptions")
    local shadow = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    frame.fhShadow = shadow
    shadow:SetTexture(MEDIA .. "shadow"); shadow:SetVertexColor(0, 0, 0, 0.8)
    shadow:SetPoint("TOPLEFT", -36, 36); shadow:SetPoint("BOTTOMRIGHT", 36, -36)
    local bg = Fill(frame, C.bg, "BACKGROUND", -6); bg:SetAllPoints()
    Border(frame, 0.09)
    local topLine = Fill(frame, C.accent, "BORDER", 2); topLine:SetHeight(2); topLine:SetPoint("TOPLEFT"); topLine:SetPoint("TOPRIGHT")

    -- header
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT"); header:SetPoint("TOPRIGHT"); header:SetHeight(54)
    header:EnableMouse(true); header:RegisterForDrag("LeftButton")
    -- inside Free Hub, dragging the header moves the hub window instead
    header:SetScript("OnDragStart", function() (frame.fhMover or frame):StartMoving() end)
    header:SetScript("OnDragStop", function() (frame.fhMover or frame):StopMovingOrSizing() end)
    local icon = header:CreateTexture(nil, "ARTWORK"); icon:SetTexture(MEDIA .. "icon"); icon:SetSize(32, 32); icon:SetPoint("LEFT", PAD, -1)
    local title = Text(header, 17, C.text); title:SetPoint("LEFT", icon, "RIGHT", 10, 7); title:SetText("Free Unit Frames")
    local ver = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or ""
    local subt = Text(header, 11, C.muted); subt:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3); subt:SetText("Unit frames  ·  v" .. ver)
    OnRefresh(function() subt:SetText("Unit frames  ·  v" .. ver .. "  ·  Profile: " .. (ns.CurrentProfile() or "?")) end)
    local close = CreateFrame("Button", nil, header); close:SetSize(26, 26); close:SetPoint("RIGHT", -12, 0)
    local x1 = Fill(close, C.dim, "ARTWORK"); x1:SetSize(14, 2); x1:SetPoint("CENTER"); x1:SetRotation(math.rad(45))
    local x2 = Fill(close, C.dim, "ARTWORK"); x2:SetSize(14, 2); x2:SetPoint("CENTER"); x2:SetRotation(math.rad(-45))
    close:SetScript("OnEnter", function() x1:SetVertexColor(unpack(C.accent)); x2:SetVertexColor(unpack(C.accent)) end)
    close:SetScript("OnLeave", function() x1:SetVertexColor(unpack(C.dim)); x2:SetVertexColor(unpack(C.dim)) end)
    close:SetScript("OnClick", function() frame:Hide() end)
    frame.fhClose = close

    -- selector cards (General + every unit)
    local keys = { "global" }
    for _, u in ipairs(ns.UNITS) do keys[#keys + 1] = u end
    local NB = #keys
    local cardW = (W - 2 * PAD - (NB - 1) * 6) / NB
    local cards = {}
    onResize[#onResize + 1] = function(width)
        local cw = (width - 2 * PAD - (NB - 1) * 6) / NB
        for i, card in ipairs(cards) do
            card:SetWidth(cw)
            card:SetPoint("TOPLEFT", PAD + (i - 1) * (cw + 6), -62)
        end
    end
    for i, key in ipairs(keys) do
        local card = CreateFrame("Button", nil, frame)
        card:SetSize(cardW, 46)
        card:SetPoint("TOPLEFT", PAD + (i - 1) * (cardW + 6), -62)
        cards[i] = card
        card.bg = Fill(card, C.panel); card.bg:SetAllPoints()
        Border(card, 0.06)
        card.mark = Fill(card, C.accent, "ARTWORK"); card.mark:SetHeight(2); card.mark:SetPoint("BOTTOMLEFT"); card.mark:SetPoint("BOTTOMRIGHT")
        card.dot = card:CreateTexture(nil, "ARTWORK"); card.dot:SetTexture(CIRCLE); card.dot:SetSize(8, 8); card.dot:SetPoint("TOPLEFT", 10, -12)
        card.name = Text(card, 13, C.text); card.name:SetPoint("LEFT", card.dot, "RIGHT", 6, 0); card.name:SetPoint("RIGHT", -4, 0); card.name:SetWordWrap(false)
        card.name:SetText(key == "global" and "General" or ns.UNIT_SHORT[key])
        card.state = Text(card, 11, C.muted); card.state:SetPoint("TOPLEFT", 24, -27)
        card:SetScript("OnEnter", function(self) if scope ~= key then self.bg:SetVertexColor(unpack(C.control)) end end)
        card:SetScript("OnLeave", function(self) if scope ~= key then self.bg:SetVertexColor(unpack(C.panel)) end end)
        card:SetScript("OnClick", function() scope = key; if openList then openList:Hide(); openList = nil end; frame:Refresh() end)
        OnRefresh(function()
            local on = (scope == key)
            card.bg:SetVertexColor(unpack(on and C.control or C.panel))
            card.mark:SetShown(on)
            if key == "global" then
                card.dot:SetVertexColor(unpack(C.accent))
                card.state:SetText("Media")
            else
                local enabled = ns.Unit(key).enable
                card.dot:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], enabled and 1 or 0.25)
                card.name:SetTextColor(unpack(enabled and C.text or C.muted))
                card.state:SetText(enabled and "On" or "Off")
            end
        end)
    end

    -- tabs (unit scope) + pages
    local TABS = {
        { "frame", "Frame" }, { "portrait", "Portrait" }, { "bars", "Bars" }, { "texts", "Texts" }, { "auras", "Auras" },
        { "castbar", "Castbar" }, { "detach", "Detach" }, { "indicators", "Indicators" }, { "group", "Group" },
        { "combo", "Combo points" }, { "happiness", "Happiness" },
    }
    -- Group, Combo points and Happiness never show together: they share the last place in the row
    local SHARED = { group = true, combo = true, happiness = true }
    local sharedX
    local pages, tabButtons, activeTab = {}, {}, "frame"
    local tabY = -120
    local line = Fill(frame, { 1, 1, 1, 0.07 }, "BORDER"); line:SetHeight(1)
    line:SetPoint("TOPLEFT", PAD, tabY - 30); line:SetPoint("TOPRIGHT", -PAD, tabY - 30)
    local tx = PAD
    for _, t in ipairs(TABS) do
        local b = CreateFrame("Button", nil, frame)
        b.label = Text(b, 14, C.dim); b.label:SetPoint("LEFT"); b.label:SetText(t[2])
        b:SetSize(b.label:GetStringWidth() + 4, 30)
        local bx = tx
        if SHARED[t[1]] then
            if sharedX then bx = sharedX else sharedX = tx end
        end
        b:SetPoint("TOPLEFT", bx, tabY)
        b.under = Fill(b, C.accent, "ARTWORK"); b.under:SetHeight(2); b.under:SetPoint("BOTTOMLEFT", 0, -1); b.under:SetPoint("BOTTOMRIGHT", 0, -1)
        b:SetScript("OnClick", function() activeTab = t[1]; if openList then openList:Hide(); openList = nil end; frame:Refresh() end)
        b:SetScript("OnEnter", function(self) if activeTab ~= t[1] then self.label:SetTextColor(unpack(C.text)) end end)
        b:SetScript("OnLeave", function(self) if activeTab ~= t[1] then self.label:SetTextColor(unpack(C.dim)) end end)
        tabButtons[t[1]] = b
        if bx == tx then tx = tx + b:GetWidth() + 26 end
        local page = CreateFrame("Frame", nil, frame)
        page:SetPoint("TOPLEFT", 0, tabY - 44); page:SetPoint("BOTTOMRIGHT", 0, 60)
        pages[t[1]] = page
    end
    local globalPage = CreateFrame("Frame", nil, frame)
    globalPage:SetPoint("TOPLEFT", 0, tabY - 4); globalPage:SetPoint("BOTTOMRIGHT", 0, 60)
    local isGroup = function() return scope == "party" or scope == "raid" or scope == "boss" end
    local TAB_OK = {
        group = isGroup,
        combo = function() return scope == "player" or scope == "target" end,
        happiness = function() return scope == "pet" end,
    }
    local function tabOK(k) return not TAB_OK[k] or TAB_OK[k]() end
    OnRefresh(function()
        local unitScope = scope ~= "global"
        if not tabOK(activeTab) then activeTab = "frame" end
        line:SetShown(unitScope)
        for k, b in pairs(tabButtons) do
            local on = (k == activeTab)
            b:SetShown(unitScope and tabOK(k))
            b.under:SetShown(on)
            b.label:SetTextColor(unpack(on and C.text or C.dim))
            pages[k]:SetShown(unitScope and on)
        end
        globalPage:SetShown(not unitScope)
    end)

    local COLW = COLW0
    local LX, RX = PAD, RX0
    local ROW = 34
    local function y(i) return -22 - (i - 1) * ROW end

    -- ---------------- General (global)
    local p = globalPage
    Caption(p, "Media", LX, 0)
    DropdownRow(p, "Bar texture", LX, y(1), COLW, ns.TextureList, "texture", true)
    DropdownRow(p, "Background texture", LX, y(2), COLW, ns.TextureList, "bgTexture", true)
    DropdownRow(p, "Font", LX, y(3), COLW, ns.FontList, "font", "font")
    SliderRow(p, "Font size", LX, y(4), COLW, "fontSize", { lo = 6, hi = 24, step = 1, parse = positive })
    DropdownRow(p, "Outline", LX, y(5), COLW, ns.OUTLINE_LIST, "outline")
    Hint(p, "Textures and fonts from other addons (LibSharedMedia) appear in the lists automatically.", LX, y(6) + 4, COLW)
    SliderRow(p, "Scale (all frames)", LX, y(7), COLW, "scale", { lo = 0.5, hi = 2, step = 0.05, parse = positive })
    Caption(p, "Layout presets", LX, y(8) - 4)
    Hint(p, "Changes the look of the player, target and target-of-target frames. Positions, castbars and portraits are kept.", LX, y(8) - 20, COLW)
    local pb = Button(p, "Apply ElvUI dark", 160, true, function() ns.ApplyLayoutPreset("elvui"); frame:Refresh() end)
    pb:SetPoint("TOPLEFT", LX, y(9) - 18)
    Caption(p, "Frames", RX, 0)
    ColorRow(p, "Background colour", RX, y(1), COLW, "bgColor", true)
    SwitchRow(p, "Border", RX, y(2), COLW, "border")
    ColorRow(p, "Border colour", RX, y(3), COLW, "borderColor", true, function() return ns.Global().border end)
    SliderRow(p, "Border thickness", RX, y(4), COLW, "borderSize", { lo = 1, hi = 8, step = 1, parse = positive })
    Caption(p, "Other", RX, y(5) - 8)
    local mm = Row(p, RX, y(6) - 8, COLW, 24)
    Label(mm, "Minimap button")
    local mmSwitch = Switch(mm, function() return not ns.GetDB().minimap.hide end, function(v) if ns.SetMinimapShown then ns.SetMinimapShown(v) end; frame:Refresh() end)
    mmSwitch:SetPoint("RIGHT", 0, 0)
    Hint(p, "Slash commands: /fuf (options), /fuf unlock, /fuf test, /fuf reset. Each frame, portrait, castbar and combo bar can override the border in its own tab.", RX, y(7) - 4, COLW)

    -- profiles
    local function profileItems(exceptCurrent)
        local out = {}
        for _, name in ipairs(ns.ProfileList()) do
            if not (exceptCurrent and name == ns.CurrentProfile()) then
                local n = ns.ProfileUsers(name)
                out[#out + 1] = { key = name, label = name .. (n > 0 and ("  (" .. n .. " char.)") or "") }
            end
        end
        return out
    end
    Caption(p, "Profile", RX, y(9) - 4)
    Dropdown(p, RX, y(10) - 4, COLW, "This character", function() return profileItems(false) end,
        function() return ns.CurrentProfile() end, function(v) ns.SetProfile(v); frame:Refresh() end)
    local newRow = Row(p, RX, y(11) - 4, COLW, 26)
    Label(newRow, "New profile")
    local newBox = InputBox(newRow, COLW - 120 - 2 * 76)
    newBox:SetPoint("LEFT", 120, 0)
    local function newName() local t = (newBox:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", ""); return t ~= "" and t or nil end
    local bNew = Button(newRow, "Empty", 72, false, function()
        local n = newName(); if not n then return end
        newBox:SetText(""); newBox:ClearFocus(); ns.SetProfile(n); frame:Refresh()
    end)
    bNew:SetPoint("RIGHT", -76, 0)
    local bDup = Button(newRow, "Copy", 72, true, function()
        local n = newName(); if not n then return end
        newBox:SetText(""); newBox:ClearFocus(); ns.SetProfile(n, ns.CurrentProfile()); frame:Refresh()
    end)
    bDup:SetPoint("RIGHT", 0, 0)
    newBox:SetPoint("RIGHT", bNew, "LEFT", -4, 0)
    newBox:SetScript("OnEnterPressed", function() bDup:Click() end)
    newBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local copyP = Dropdown(p, RX, y(12) - 4, COLW, "Copy settings", function() return profileItems(true) end,
        function() return nil end, function(v) ns.CopyProfileFrom(v); frame:Refresh() end)
    copyP.placeholder = "from another profile..."
    local delP = Dropdown(p, RX, y(13) - 4, COLW - 84, "Delete", function() return profileItems(true) end,
        function() return nil end, function(v) ns.DeleteProfile(v); frame:Refresh() end)
    delP.placeholder = "choose a profile..."
    local bReset
    bReset = Button(p, "Reset", 76, false, function()
        -- two clicks within 4 seconds, so a profile is never wiped by accident
        local now = GetTime and GetTime() or 0
        if bReset.armed and now - bReset.armed < 4 then
            bReset.armed = nil; bReset.label:SetText("Reset")
            ns.ResetProfile(); frame:Refresh()
        else
            bReset.armed = now; bReset.label:SetText("Sure?")
        end
    end)
    bReset:SetPoint("TOPLEFT", RX + COLW - 76, y(13) - 4)
    Flow(bReset, RX + COLW - 76, y(13) - 4, nil, true)
    local ioRow = Row(p, RX, y(14) - 4, COLW, 26)
    Label(ioRow, "Share")
    local bImp = Button(ioRow, "Import", 96, false, function() ns.ImportProfile() end)
    bImp:SetPoint("RIGHT", 0, 0)
    local bExp = Button(ioRow, "Export", 96, false, function() ns.ExportProfile() end)
    bExp:SetPoint("RIGHT", bImp, "LEFT", -6, 0)
    Hint(p, "Each character remembers its profile. \"Copy\" starts the new profile from the current one. Reset puts the current profile back to defaults. Export gives a text to paste on another character or account.", RX, y(15) - 4, COLW)

    -- ---------------- Frame
    p = pages.frame
    local notPlayer = function() return scope == "party" or scope == "raid" end
    Caption(p, "Frame", LX, 0)
    SwitchRow(p, "Enabled", LX, y(1), COLW, "enable")
    SliderRow(p, "Width", LX, y(2), COLW, "width", { lo = 20, hi = 500, step = 1, parse = positive })
    SliderRow(p, "Height", LX, y(3), COLW, "height", { lo = 8, hi = 120, step = 1, parse = positive })
    SliderRow(p, "Scale", LX, y(4), COLW, "scale", { lo = 0.5, hi = 2, step = 0.05, parse = positive })
    Caption(p, "Position", LX, y(5) - 8)
    local attached = function() return ns.AttachTarget and ns.AttachTarget(scope) ~= nil end
    local attachItems = function()
        local out = { { key = "NONE", label = "Nothing (placed on the screen)" } }
        for _, u in ipairs(ns.AttachChoices and ns.AttachChoices(scope) or {}) do out[#out + 1] = { key = u, label = ns.UNIT_LABEL[u] } end
        return out
    end
    local attachRow = Dropdown(p, LX, y(6) - 8, COLW, "Attached to", attachItems,
        function() return (ns.AttachTarget and ns.AttachTarget(scope)) or "NONE" end,
        function(v) ns.Attach(scope, v ~= "NONE" and v or nil); frame:Refresh() end)
    DropdownRow(p, "Screen anchor", LX, y(7) - 8, COLW, POINTS, "pos.1", false, function() return not attached() end)
    Hint(p, "Moves with the frame it is attached to. Offsets below are from its top-left corner. Right-click a frame when unlocked to attach or detach it.", LX, y(7) - 4, COLW, attached)
    SliderRow(p, "Offset X", LX, y(8) - 8, COLW, function() return attached() and "attachPos.1" or "pos.2" end, { lo = -1500, hi = 1500, step = 1, parse = any })
    SliderRow(p, "Offset Y", LX, y(9) - 8, COLW, function() return attached() and "attachPos.2" or "pos.3" end, { lo = -900, hi = 900, step = 1, parse = any })
    Caption(p, "Look", LX, y(10) - 16)
    SliderRow(p, "Bar opacity", LX, y(11) - 16, COLW, "barAlpha", percent)
    Hint(p, "Makes the health and power bars see-through; texts stay fully visible. Scale multiplies the General scale.", LX, y(12) - 12, COLW)
    Caption(p, "Range", RX, 0, notPlayer)
    SwitchRow(p, "Fade when out of range", RX, y(1), COLW, "range.enable", notPlayer)
    SliderRow(p, "Faded opacity", RX, y(2), COLW, "range.alpha", percent, notPlayer)
    BorderBlock(p, "Frame border", RX, y(4) - 8, COLW, "border")


    -- ---------------- Portrait
    p = pages.portrait
    local pOn = function() return Get("portrait.enable") and true or false end
    local pSide = function(...) local v = Get("portrait.side"); for i = 1, select("#", ...) do if v == select(i, ...) then return pOn() end end return false end
    Caption(p, "Placement", LX, 0)
    SwitchRow(p, "Show portrait", LX, y(1), COLW, "portrait.enable")
    SegRow(p, "Style", LX, y(2), COLW, { { "3D", "3D model" }, { "2D", "2D" }, { "class", "Class icon" } }, "portrait.style", pOn)
    SegRow(p, "Position", LX, y(3), COLW, { { "LEFT", "Left" }, { "RIGHT", "Right" }, { "OVERLAY", "Behind" }, { "DETACHED", "Detached" } }, "portrait.side", pOn)
    SliderRow(p, "Width", LX, y(4), COLW, "portrait.width", auto(0, 120), function() return pSide("LEFT", "RIGHT") end)
    SliderRow(p, "Opacity", LX, y(4), COLW, "portrait.alpha", percent, function() return pSide("OVERLAY") end)
    SliderRow(p, "Width", LX, y(4), COLW, "portrait.size", auto(0, 300), function() return pSide("DETACHED") end)
    SliderRow(p, "Height", LX, y(5), COLW, "portrait.detHeight", auto(0, 400), function() return pSide("DETACHED") end)
    SegRow(p, "Side of frame", LX, y(6), COLW, { { "LEFT", "Left" }, { "RIGHT", "Right" }, { "TOP", "Top" }, { "BOTTOM", "Bottom" } }, "portrait.anchor", function() return pSide("DETACHED") end)
    SliderRow(p, "Offset X", LX, y(7), COLW, "portrait.x", { lo = -200, hi = 200, step = 1, parse = any }, function() return pSide("DETACHED") end)
    SliderRow(p, "Offset Y", LX, y(8), COLW, "portrait.y", { lo = -200, hi = 200, step = 1, parse = any }, function() return pSide("DETACHED") end)
    Hint(p, "Auto = the frame height. Detached puts the portrait in its own box next to the frame (make it tall for a full-body model).", LX, y(9) + 4, COLW, pOn)
    BorderBlock(p, "Portrait border", LX, y(10) - 6, COLW, "portrait.border", function() return pOn() and Get("portrait.side") ~= "OVERLAY" end)

    local is3D = function() return pOn() and Get("portrait.style") == "3D" end
    Caption(p, "3D model", RX, 0, is3D)
    SliderRow(p, "Zoom", RX, y(1), COLW, "portrait.zoom", percent, is3D)
    SliderRow(p, "Camera distance", RX, y(2), COLW, "portrait.distance", { lo = 0.2, hi = 5, step = 0.05, parse = positive }, is3D)
    SliderRow(p, "Move X", RX, y(3), COLW, "portrait.modelX", { lo = -1, hi = 1, step = 0.01, parse = any }, is3D)
    SliderRow(p, "Move Y", RX, y(4), COLW, "portrait.modelY", { lo = -1, hi = 1, step = 0.01, parse = any }, is3D)
    SliderRow(p, "Rotation", RX, y(5), COLW, "portrait.rotation", { lo = -180, hi = 180, step = 1, parse = any }, is3D)
    SliderRow(p, "Desaturate", RX, y(6), COLW, "portrait.desaturate", percent, is3D)
    SwitchRow(p, "Pause animation", RX, y(7), COLW, "portrait.paused", is3D)
    Hint(p, "Zoom 0% shows the whole body, 100% the face. Turn the background off and use Detached for a free-standing model.", RX, y(8) + 4, COLW, is3D)
    Caption(p, "Background", RX, y(9) - 4, function() return pOn() and Get("portrait.side") ~= "OVERLAY" end)
    SwitchRow(p, "Show background", RX, y(10) - 4, COLW, "portrait.background", function() return pOn() and Get("portrait.side") ~= "OVERLAY" end)
    ColorRow(p, "Background colour", RX, y(11) - 4, COLW, "portrait.bgColor", true, nil, function()
        return pOn() and Get("portrait.side") ~= "OVERLAY" and Get("portrait.background") ~= false
    end)

    -- ---------------- Bars
    p = pages.bars
    local hTint = function() return Get("health.bgMode") == "tint" end
    local pTint = function() return Get("power.bgMode") == "tint" end
    local BGMODE = { { "dark", "Fixed colour" }, { "tint", "Bar colour, darker" } }
    Caption(p, "Health", LX, 0)
    SwitchRow(p, "Class colour (players)", LX, y(1), COLW, "health.colorClass")
    SwitchRow(p, "Reaction colour (NPCs)", LX, y(2), COLW, "health.colorReaction")
    SwitchRow(p, "Grey when tapped", LX, y(3), COLW, "health.colorTapped")
    ColorRow(p, "Fallback colour", LX, y(4), COLW, "health.color", false)
    SegRow(p, "Empty part", LX, y(5), COLW, BGMODE, "health.bgMode")
    ColorRow(p, "Empty part colour", LX, y(6), COLW, "health.bgColor", true, nil, function() return not hTint() end)
    SliderRow(p, "Brightness", LX, y(6), COLW, "health.bgMult", percent, hTint)
    SwitchRow(p, "Fill right to left", LX, y(7), COLW, "health.reverse")
    SwitchRow(p, "Vertical bar", LX, y(8), COLW, "health.vertical")
    Hint(p, "Fallback colour is only used when no rule above applies: with class and reaction colours on, players use their class colour and NPCs green / yellow / red.", LX, y(9) + 4, COLW)

    Caption(p, "Power", RX, 0)
    local pwOn = function() return Get("power.enable") and true or false end
    SwitchRow(p, "Show power bar", RX, y(1), COLW, "power.enable")
    SegRow(p, "Position", RX, y(2), COLW, { { "BOTTOM", "Bottom" }, { "TOP", "Top" }, { "LEFT", "Left" }, { "RIGHT", "Right" } }, "power.position", pwOn)
    SliderRow(p, "Thickness", RX, y(3), COLW, "power.height", { lo = 1, hi = 40, step = 1, parse = positive }, pwOn)
    SliderRow(p, "Gap", RX, y(4), COLW, "power.gap", { lo = 0, hi = 10, step = 1, parse = zeroPlus }, pwOn)
    local colorMode = Row(p, RX, y(5), COLW, 26, pwOn)
    Label(colorMode, "Colour")
    local cm = Segmented(colorMode, { { "power", "Power type" }, { "class", "Class" }, { "custom", "Custom" } }, COLW - 120,
        function()
            local pc = Get("power")
            if not pc then return nil end
            return pc.colorPower and "power" or (pc.colorClass and "class" or "custom")
        end,
        function(v)
            local pc = Get("power")
            if not pc then return end
            pc.colorPower, pc.colorClass = (v == "power"), (v == "class")
            Apply(); frame:Refresh()
        end)
    cm:SetPoint("RIGHT", 0, 0); cm:SetPoint("LEFT", 120, 0)
    ColorRow(p, "Custom colour", RX, y(6), COLW, "power.color", false, nil, function()
        local pc = Get("power"); return pc and pc.enable and not pc.colorPower and not pc.colorClass
    end)
    SegRow(p, "Empty part", RX, y(7), COLW, BGMODE, "power.bgMode", pwOn)
    ColorRow(p, "Empty part colour", RX, y(8), COLW, "power.bgColor", true, nil, function() return pwOn() and not pTint() end)
    SliderRow(p, "Brightness", RX, y(8), COLW, "power.bgMult", percent, function() return pwOn() and pTint() end)
    Hint(p, "Combo points have their own tab (Player or Target card).", RX, y(9) + 4, COLW, function() return scope == "player" end)

    -- ---------------- Texts
    p = pages.texts
    local BUILTIN = { name = "Name", health = "Health", power = "Power", level = "Level" }
    local function customIndex()
        local id = tostring(sub.text or ""):match("^c:(.+)$")
        if not id then return nil end
        for i, t in ipairs(Get("texts.custom") or {}) do if tostring(t.id) == id then return i end end
    end
    local function textPath()
        if BUILTIN[sub.text] then return "texts." .. sub.text end
        local i = customIndex()
        if i then return "texts.custom." .. i end
        sub.text = "name"
        return "texts.name"
    end
    local TP = function(field) return function() return textPath() .. "." .. field end end
    local isCustom = function() return customIndex() ~= nil end
    local textOn = function() return Get(TP("enable")) and true or false end
    local function textItems()
        local out = {}
        for _, k in ipairs({ "name", "health", "power", "level" }) do out[#out + 1] = { key = k, label = BUILTIN[k] } end
        for i, t in ipairs(Get("texts.custom") or {}) do out[#out + 1] = { key = "c:" .. tostring(t.id), label = t.name or ("Text " .. i) } end
        return out
    end
    local selRow = Dropdown(p, LX, 0, COLW - 196, nil, textItems, function() return sub.text end, function(v) sub.text = v; frame:Refresh() end)
    local add = Button(p, "+ Add text", 100, true, function()
        local list = Get("texts.custom")
        local t = ns.NewText("Text " .. (#list + 1))
        table.insert(list, t)
        sub.text = "c:" .. t.id
        Apply(); frame:Refresh()
    end)
    add:SetPoint("LEFT", selRow, "RIGHT", 8, 0)
    local del = Button(p, "Delete", 80, false, function()
        local i = customIndex()
        if not i then return end
        table.remove(Get("texts.custom"), i)
        sub.text = "name"
        Apply(); frame:Refresh()
    end)
    del:SetPoint("LEFT", add, "RIGHT", 8, 0)
    OnRefresh(function() del:SetShown(isCustom()) end)

    InputRow(p, "Label", LX, y(2), COLW, TP("name"), isCustom)
    SwitchRow(p, "Show this text", LX, y(3), COLW, TP("enable"))
    Dropdown(p, LX, y(4), COLW, "Preset",
        function() return ns.TAG_PRESETS[BUILTIN[sub.text] and sub.text or "custom"] or {} end,
        function() return Get(TP("format")) end,
        function(v) Set(TP("format"), v) end, false, textOn)
    InputRow(p, "Format", LX, y(5), COLW, TP("format"), textOn)
    Hint(p, "Any oUF tag works, e.g. [raidcolor][name], [fuf:hp], [fuf:perhp], [fuf:pp], [smartlevel], [classification], [dead]. Text outside brackets is shown as is. Press Enter to apply.", LX, y(6) + 4, COLW, textOn)
    Caption(p, "Colour", LX, y(8) - 4, textOn)
    local function colorMode()
        local t = Get(textPath()) or {}
        return t.colorMode or (t.useColor and "CUSTOM" or "TAGS")
    end
    local cmRow = Row(p, LX, y(9) - 4, COLW, 26, textOn)
    Label(cmRow, "Colour")
    local cmSeg = Segmented(cmRow, { { "TAGS", "From format" }, { "CUSTOM", "Custom" }, { "CLASS", "Class" }, { "POWER", "Power" } }, COLW - 120,
        colorMode, function(v)
            local t = Get(textPath()); if not t then return end
            t.colorMode = v; t.useColor = (v == "CUSTOM")
            Apply(); frame:Refresh()
        end)
    cmSeg:SetPoint("RIGHT", 0, 0); cmSeg:SetPoint("LEFT", 120, 0)
    local isCustomColor = function() return textOn() and colorMode() == "CUSTOM" end
    ColorRow(p, "Text colour", LX, y(10) - 4, COLW, TP("color"), false, nil, isCustomColor)
    -- quick picks for the custom colour: Blizzard's power colour of your current power, or your class colour
    local pick = Row(p, LX, y(11) - 4, COLW, 26, isCustomColor)
    Label(pick, "Quick pick")
    local function setColor(c) if c then Set(TP("color"), { c[1], c[2], c[3] }) ; frame:Refresh() end end
    local bPow = Button(pick, "Power colour", 110, false, function()
        local ok, _, token = pcall(UnitPowerType, "player")
        local pc = ok and token and PowerBarColor and PowerBarColor[token]
        if pc then setColor({ pc.r, pc.g, pc.b }) end
    end)
    bPow:SetPoint("LEFT", 120, 0)
    local bCls = Button(pick, "Class colour", 110, false, function() setColor(ns.UnitClassColor("player", "player")) end)
    bCls:SetPoint("LEFT", bPow, "RIGHT", 8, 0)
    Hint(p, "From format: white, or the colours written in the format ([raidcolor], [powercolor]...). Class and Power colour the whole text for each unit.", LX, y(12) - 4, COLW, textOn)

    Caption(p, "Placement", RX, 0, textOn)
    SegRow(p, "Attach to", RX, y(1), COLW, { { "HEALTH", "Health bar" }, { "POWER", "Power bar" }, { "FRAME", "Whole frame" } }, TP("attach"), textOn)
    DropdownRow(p, "Anchor", RX, y(2), COLW, POINTS, TP("point"), false, textOn)
    SliderRow(p, "Offset X", RX, y(3), COLW, TP("x"), { lo = -150, hi = 150, step = 1, parse = any }, textOn)
    SliderRow(p, "Offset Y", RX, y(4), COLW, TP("y"), { lo = -100, hi = 100, step = 1, parse = any }, textOn)
    SliderRow(p, "Max width", RX, y(5), COLW, TP("width"), { lo = 0, hi = 400, step = 1, parse = zeroPlus,
        fmt = function(v) return (v and v > 0) and fmtNum(v) or "None" end }, textOn)
    Caption(p, "Font", RX, y(6) - 4, textOn)
    DropdownRow(p, "Font", RX, y(7) - 4, COLW, function()
        local out = { { key = "INHERIT", label = "General setting" } }
        for _, it in ipairs(ns.FontList()) do out[#out + 1] = it end
        return out
    end, TP("font"), "font", textOn)
    SliderRow(p, "Size", RX, y(8) - 4, COLW, TP("size"), auto(0, 40), textOn)
    DropdownRow(p, "Outline", RX, y(9) - 4, COLW, function()
        local out = { { key = "INHERIT", label = "General setting" } }
        for _, it in ipairs(ns.OUTLINE_LIST) do out[#out + 1] = it end
        return out
    end, TP("outline"), false, textOn)
    Hint(p, "\"General setting\" and size Auto follow the General tab. Shadow is the softest look; Pixel outline suits pixel fonts. Max width cuts long names.", RX, y(10), COLW, textOn)

    -- ---------------- Auras
    p = pages.auras
    sub.auraView = sub.auraView or "layout"
    -- the weapon enchant row exists on the player frame only
    local function EffAura()
        if sub.aura == "enchants" and scope ~= "player" then return "buffs" end
        return sub.aura
    end
    local AP = function(field) return function() return EffAura() .. "." .. field end end
    local EP = function(field) return function() return "buffs.enchants." .. field end end
    local asel2 = Segmented(p, { { "buffs", "Buffs" }, { "debuffs", "Debuffs" } }, COLW,
        function() return EffAura() end, function(v) sub.aura = v; frame:Refresh() end, 28)
    asel2:SetPoint("TOPLEFT", LX, 0); Flow(asel2, LX, 0, COLW)
    local asel3 = Segmented(p, { { "buffs", "Buffs" }, { "debuffs", "Debuffs" }, { "enchants", "Weapon enchants" } }, COLW,
        function() return EffAura() end, function(v) sub.aura = v; frame:Refresh() end, 28)
    asel3:SetPoint("TOPLEFT", LX, 0); Flow(asel3, LX, 0, COLW)
    OnRefresh(function() asel2:SetShown(scope ~= "player"); asel3:SetShown(scope == "player") end)
    local isEnc = function() return EffAura() == "enchants" end
    local vsel = Segmented(p, { { "layout", "Layout" }, { "text", "Text" }, { "filter", "Filter" } }, COLW,
        function() return sub.auraView end, function(v) sub.auraView = v; frame:Refresh() end, 28)
    vsel:SetPoint("TOPLEFT", RX, 0); Flow(vsel, RX, 0, COLW)
    OnRefresh(function() vsel:SetShown(not isEnc()) end)
    local lay = function() return not isEnc() and sub.auraView == "layout" end
    local txt = function() return not isEnc() and sub.auraView == "text" end
    local fil = function() return not isEnc() and sub.auraView == "filter" end

    -- layout view
    SwitchRow(p, "Show", LX, y(2), COLW, AP("enable"), lay)
    SliderRow(p, "Icon size", LX, y(3), COLW, AP("size"), { lo = 8, hi = 64, step = 1, parse = positive }, lay)
    SliderRow(p, "Per row", LX, y(4), COLW, AP("perRow"), { lo = 1, hi = 20, step = 1, parse = positive }, lay)
    SliderRow(p, "Rows", LX, y(5), COLW, AP("rows"), { lo = 1, hi = 6, step = 1, parse = positive }, lay)
    SliderRow(p, "Spacing", LX, y(6), COLW, AP("spacing"), { lo = 0, hi = 10, step = 1, parse = zeroPlus }, lay)
    SwitchRow(p, "Duration numbers", LX, y(7), COLW, AP("showDuration"), lay)
    SwitchRow(p, "Stack count", LX, y(8), COLW, AP("showCount"), lay)
    SwitchRow(p, "Colour border by type", LX, y(9), COLW, AP("typeBorder"), lay)
    Hint(p, "Sizes, fonts, outline and colours of the numbers are in the Text view. \"Test frames\" or \"Unlock\" draws sample icons where the auras go.", LX, y(10), COLW, lay)
    Caption(p, "Placement", RX, y(2) + 12, lay)
    SegRow(p, "Side", RX, y(2) - 10, COLW, { { "TOP", "Above" }, { "BOTTOM", "Below" }, { "LEFT", "Left" }, { "RIGHT", "Right" } }, AP("side"), lay)
    SegRow(p, "Grow", RX, y(3) - 10, COLW, { { "RIGHT", "Right" }, { "LEFT", "Left" } }, AP("growthX"), lay)
    SegRow(p, "New rows", RX, y(4) - 10, COLW, { { "UP", "Up" }, { "DOWN", "Down" } }, AP("growthY"), lay)
    SliderRow(p, "Offset X", RX, y(5) - 10, COLW, AP("x"), { lo = -200, hi = 200, step = 1, parse = any }, lay)
    SliderRow(p, "Offset Y", RX, y(6) - 10, COLW, AP("y"), { lo = -200, hi = 200, step = 1, parse = any }, lay)
    SegRow(p, "Attach to", RX, y(7) - 10, COLW, { { "FRAME", "Frame" }, { "BUFFS", "Buffs" } }, AP("anchorTo"), function() return lay() and EffAura() == "debuffs" end)
    Hint(p, "\"Attach to Buffs\" stacks debuffs on top of the buff block.", RX, y(8) - 6, COLW, function() return lay() and EffAura() == "debuffs" end)

    -- text view: duration numbers and stack counts of the buffs / debuffs
    local function FontChoices()
        local out = { { key = "INHERIT", label = "General setting" } }
        for _, it in ipairs(ns.FontList()) do out[#out + 1] = it end
        return out
    end
    local function OutlineChoices()
        local out = { { key = "INHERIT", label = "General setting" } }
        for _, it in ipairs(ns.OUTLINE_LIST) do out[#out + 1] = it end
        return out
    end
    -- one block of text settings (kind = "duration" or "count"); pf(field) gives the path of a field
    local function TextBlock(x, yTop, title, kind, pf, shown, showKey, withPlace)
        Caption(p, title, x, yTop + 12, shown)
        local k = 0
        local function nextY() k = k + 1; return yTop - 10 - (k - 1) * ROW end
        SwitchRow(p, "Show", x, nextY(), COLW, pf(showKey), shown)
        SliderRow(p, "Size", x, nextY(), COLW, pf(kind .. "Size"), auto(0, 32), shown)
        if withPlace then
            SegRow(p, "Place", x, nextY(), COLW, { { "CENTER", "Centre" }, { "TOP", "Top" }, { "BOTTOM", "Bottom" } }, pf("durationPoint"), shown)
        end
        DropdownRow(p, "Font", x, nextY(), COLW, FontChoices, pf(kind .. "Font"), "font", shown)
        DropdownRow(p, "Outline", x, nextY(), COLW, OutlineChoices, pf(kind .. "Outline"), false, shown)
        ColorRow(p, "Colour", x, nextY(), COLW, pf(kind .. "Color"), false, nil, shown)
        return yTop - 10 - k * ROW
    end
    TextBlock(LX, y(2), "Duration numbers", "duration", AP, txt, "showDuration", true)
    TextBlock(RX, y(2), "Stack count", "count", AP, txt, "showCount", false)
    Hint(p, "Outline keeps the numbers readable over bright icons. Font and outline \"General setting\" follow the General tab; size Auto follows the icon size.", LX, y(8) - 6, COLW, txt)

    -- weapon enchants view (player only)
    local enc = function() return isEnc() end
    local encPlace = function(m) return function() return enc() and Get("buffs.enchants.place") == m end end
    local encDetached = function() return enc() and (Get("buffs.enchants.place") or "BUFFS") ~= "BUFFS" end
    Caption(p, "Weapon enchants", LX, y(2) + 12, enc)
    SwitchRow(p, "Show", LX, y(2) - 10, COLW, EP("enable"), enc)
    SegRow(p, "Placement", LX, y(3) - 10, COLW, { { "BUFFS", "After buffs" }, { "FRAME", "Next to frame" }, { "SCREEN", "On screen" } }, EP("place"), enc)
    SliderRow(p, "Icon size", LX, y(4) - 10, COLW, EP("size"), auto(0, 64), encDetached)
    SliderRow(p, "Spacing", LX, y(5) - 10, COLW, EP("spacing"), { lo = 0, hi = 10, step = 1, parse = zeroPlus }, encDetached)
    SegRow(p, "Grow", LX, y(6) - 10, COLW, { { "RIGHT", "Right" }, { "LEFT", "Left" }, { "UP", "Up" }, { "DOWN", "Down" } }, EP("growth"), encDetached)
    DropdownRow(p, "Anchor", LX, y(7) - 10, COLW, POINTS, EP("anchor"), false, encPlace("FRAME"))
    SliderRow(p, "Offset X", LX, y(8) - 10, COLW, EP("x"), { lo = -300, hi = 300, step = 1, parse = any }, encPlace("FRAME"))
    SliderRow(p, "Offset Y", LX, y(9) - 10, COLW, EP("y"), { lo = -300, hi = 300, step = 1, parse = any }, encPlace("FRAME"))
    SliderRow(p, "Screen X", LX, y(7) - 10, COLW, EP("screen.2"), { lo = -1500, hi = 1500, step = 1, parse = any }, encPlace("SCREEN"))
    SliderRow(p, "Screen Y", LX, y(8) - 10, COLW, EP("screen.3"), { lo = -900, hi = 900, step = 1, parse = any }, encPlace("SCREEN"))
    Hint(p, "Poisons and weapon oils. \"After buffs\" follows the buff icons; the other two are free of the buffs: next to the player frame (anchor + offsets), or anywhere on the screen (Unlock to drag it). Samples show in Test / Unlock mode.", LX, y(10) - 10, COLW, enc)
    local yc = TextBlock(RX, y(2), "Duration numbers", "duration", EP, enc, "showDuration", true)
    Caption(p, "Charges (poisons)", RX, yc - 2 + 12 - 6, enc)
    do
        local k = 0
        local top = yc - 10 - 6
        local function ny() k = k + 1; return top - (k - 1) * ROW end
        SwitchRow(p, "Show", RX, ny(), COLW, EP("showCount"), enc)
        SliderRow(p, "Size", RX, ny(), COLW, EP("countSize"), auto(0, 32), enc)
        DropdownRow(p, "Font", RX, ny(), COLW, FontChoices, EP("countFont"), "font", enc)
        DropdownRow(p, "Outline", RX, ny(), COLW, OutlineChoices, EP("countOutline"), false, enc)
        ColorRow(p, "Colour", RX, ny(), COLW, EP("countColor"), false, nil, enc)
    end

    -- filter view
    local function SetFilter(field, value)
        local c = Get(EffAura())
        if not c then return end
        ns.SetPath(c, field, value)
        c.preset = "custom"
        Apply(); frame:Refresh()
    end
    local presetItems = function()
        local out = {}
        for _, pr in ipairs(ns.AURA_PRESETS) do out[#out + 1] = { key = pr.key, label = pr.label } end
        out[#out + 1] = { key = "custom", label = "Custom (set below)" }
        return out
    end
    Caption(p, "Preset", LX, y(2) + 12, fil)
    Dropdown(p, LX, y(2) - 10, COLW, "Show", presetItems, function() return Get(AP("preset")) end, function(v)
        local c = Get(EffAura())
        if c and v ~= "custom" then ns.ApplyAuraPreset(c, v) elseif c then c.preset = "custom" end
        Apply(); frame:Refresh()
    end, false, fil)
    Caption(p, "Rules", LX, y(3) - 14, fil)
    local whoRow = Row(p, LX, y(4) - 14, COLW, 26, fil)
    Label(whoRow, "Cast by")
    local whoSeg = Segmented(whoRow, { { "all", "Anyone" }, { "mine", "Me" }, { "others", "Others" } }, COLW - 120,
        function() return Get(AP("who")) end, function(v) SetFilter("who", v) end)
    whoSeg:SetPoint("RIGHT", 0, 0); whoSeg:SetPoint("LEFT", 120, 0)
    local durRow = Row(p, LX, y(5) - 14, COLW, 26, fil)
    Label(durRow, "Duration")
    local durSeg = Segmented(durRow, { { "any", "Any" }, { "timed", "Has an end" }, { "permanent", "No end" } }, COLW - 120,
        function() return Get(AP("durationMode")) end, function(v) SetFilter("durationMode", v) end)
    durSeg:SetPoint("RIGHT", 0, 0); durSeg:SetPoint("LEFT", 120, 0)
    local maxRow = SliderRow(p, "Max duration (s)", LX, y(6) - 14, COLW, AP("maxDuration"), {
        lo = 0, hi = 600, step = 5,
        fmt = function(v) return (v and v > 0) and fmtNum(v) or "None" end,
        parse = zeroPlus,
    }, fil)
    Hint(p, "Max duration hides longer effects (e.g. 60 = only effects of 1 minute or less). Durations the game keeps secret are always shown.", LX, y(7) - 10, COLW, fil)

    Caption(p, "Only these kinds (none ticked = all)", RX, y(2) + 12, fil)
    local KINDS = {
        { "dispellable", "I can dispel it" }, { "raid", "Raid-relevant" }, { "cc", "Crowd control" },
        { "defensive", "Big defensive" }, { "external", "External defensive" }, { "cancelable", "Can be cancelled" },
    }
    for i, k in ipairs(KINDS) do
        local row = Row(p, RX, y(i + 1) - 10, COLW, 24, fil)
        Label(row, k[2])
        Switch(row, function() local t = Get(AP("types")); return t and t[k[1]] end,
            function(v) SetFilter("types." .. k[1], v or nil) end):SetPoint("RIGHT", 0, 0)
    end
    Hint(p, "Kinds come from the game's own flags. Ticking several shows auras matching any of them.", RX, y(8) - 6, COLW, fil)

    -- ---------------- Castbar
    p = pages.castbar
    Caption(p, "Castbar", LX, 0)
    SwitchRow(p, "Show castbar", LX, y(1), COLW, "castbar.enable")
    SliderRow(p, "Width", LX, y(2), COLW, "castbar.width", auto(0, 600))
    SliderRow(p, "Height", LX, y(3), COLW, "castbar.height", { lo = 4, hi = 60, step = 1, parse = positive })
    SliderRow(p, "Offset X", LX, y(4), COLW, "castbar.x", { lo = -300, hi = 300, step = 1, parse = any })
    SliderRow(p, "Offset Y", LX, y(5), COLW, "castbar.y", { lo = -300, hi = 300, step = 1, parse = any })
    Hint(p, "Auto width = frame width. The castbar sits under the frame; use the offsets to move it.", LX, y(6) + 4, COLW)
    Caption(p, "Content", RX, 0)
    SwitchRow(p, "Spell icon", RX, y(1), COLW, "castbar.icon")
    SwitchRow(p, "Spell name", RX, y(2), COLW, "castbar.showName")
    SwitchRow(p, "Cast time", RX, y(3), COLW, "castbar.showTime")
    SegRow(p, "Colour", RX, y(4), COLW, { { false, "Custom" }, { true, "Class (players)" } }, "castbar.colorClass")
    ColorRow(p, "Bar colour", RX, y(5), COLW, "castbar.color", false)
    ColorRow(p, "Not interruptible", RX, y(6), COLW, "castbar.shieldColor", false)
    BorderBlock(p, "Castbar border", RX, y(7) - 6, COLW, "castbar.border")

    -- ---------------- Detach (bars outside the frame)
    p = pages.detach
    local single = function() return ns.CanFloat and ns.CanFloat(scope) end
    local pwDet = function() return Get("power.enable") and (Get("power.detach") or "NONE") ~= "NONE" end
    local pwMode = function(m) return function()
        local d = Get("power.enable") and Get("power.detach") or "NONE"
        if d == "SCREEN" and not single() then d = "FRAME" end
        return d == m
    end end
    Caption(p, "Power bar", LX, 0)
    SegRow(p, "Placement", LX, y(1), COLW, { { "NONE", "In the frame" }, { "FRAME", "Next to it" }, { "SCREEN", "On screen" } }, "power.detach",
        function() return Get("power.enable") and true or false end)
    SegRow(p, "Side of frame", LX, y(2), COLW, { { "BOTTOM", "Below" }, { "TOP", "Above" }, { "LEFT", "Left" }, { "RIGHT", "Right" } }, "power.detAnchor", pwMode("FRAME"))
    SliderRow(p, "Width", LX, y(3), COLW, "power.detW", auto(0, 800), pwDet)
    SliderRow(p, "Height", LX, y(4), COLW, "power.detH", auto(0, 200), pwDet)
    SliderRow(p, "Offset X", LX, y(5), COLW, "power.detX", { lo = -300, hi = 300, step = 1, parse = any }, pwMode("FRAME"))
    SliderRow(p, "Offset Y", LX, y(6), COLW, "power.detY", { lo = -300, hi = 300, step = 1, parse = any }, pwMode("FRAME"))
    SliderRow(p, "Screen X", LX, y(5), COLW, "power.screen.2", { lo = -1500, hi = 1500, step = 1, parse = any }, pwMode("SCREEN"))
    SliderRow(p, "Screen Y", LX, y(6), COLW, "power.screen.3", { lo = -900, hi = 900, step = 1, parse = any }, pwMode("SCREEN"))
    Hint(p, "Auto width = frame width, auto height = the power bar thickness (Bars tab). Taller than wide makes a vertical bar. \"On screen\" exists for single frames (player, target, focus, pet...); group frames use \"Next to it\".", LX, y(7) + 4, COLW,
        function() return Get("power.enable") and true or false end)
    BorderBlock(p, "Power bar border", LX, y(9) - 6, COLW, "power.border", pwDet)

    local cbOn = function() return single() and Get("castbar.enable") and true or false end
    local cbFree = function() return cbOn() and Get("castbar.onScreen") and true or false end
    Caption(p, "Castbar", RX, 0, single)
    SwitchRow(p, "Free on the screen", RX, y(1), COLW, "castbar.onScreen", cbOn)
    SliderRow(p, "Screen X", RX, y(2), COLW, "castbar.screen.2", { lo = -1500, hi = 1500, step = 1, parse = any }, cbFree)
    SliderRow(p, "Screen Y", RX, y(3), COLW, "castbar.screen.3", { lo = -900, hi = 900, step = 1, parse = any }, cbFree)
    Hint(p, "Size, colours and border stay in the Castbar tab. Turn the castbar on there first.", RX, y(4) + 4, COLW, single)
    Hint(p, "Screen positions are measured from the centre of the screen. Unlock to drag free bars with the mouse. Combo points: see their own tab.", RX, y(5) - 4, COLW, single)

    -- ---------------- Indicators
    p = pages.indicators
    local IND = {
        { "raidIcon", "Raid marker", icon = { "Interface\\TargetingFrame\\UI-RaidTargetingIcons", 0.75, 1, 0.25, 0.5 } },
        { "leader", "Leader", icon = { "Interface\\GroupFrame\\UI-Group-LeaderIcon" } },
        { "readyCheck", "Ready check", icon = { "Interface\\RaidFrame\\ReadyCheck-Ready" } },
        { "combat", "Combat", icon = { "Interface\\CharacterFrame\\UI-StateIcon", 0.5, 1, 0, 0.49 } },
        { "resting", "Resting", icon = { "Interface\\CharacterFrame\\UI-StateIcon", 0, 0.5, 0, 0.421875 } },
    }
    local IP = function(field) return function() return sub.ind .. "." .. field end end
    local isel = Segmented(p, IND, COLW + 40, function() return sub.ind end, function(v) sub.ind = v; frame:Refresh() end, 28)
    isel:SetPoint("TOPLEFT", LX, 0); Flow(isel, LX, 0, COLW + 40)
    local indOK = function() return (sub.ind ~= "combat" and sub.ind ~= "resting") or scope == "player" end
    SwitchRow(p, "Show", LX, y(2), COLW, IP("enable"), indOK)
    SliderRow(p, "Size", LX, y(3), COLW, IP("size"), { lo = 6, hi = 64, step = 1, parse = positive }, indOK)
    DropdownRow(p, "Anchor", LX, y(4), COLW, POINTS, IP("point"), false, indOK)
    SliderRow(p, "Offset X", LX, y(5), COLW, IP("x"), { lo = -100, hi = 100, step = 1, parse = any }, indOK)
    SliderRow(p, "Offset Y", LX, y(6), COLW, IP("y"), { lo = -100, hi = 100, step = 1, parse = any }, indOK)
    Hint(p, "Combat and Resting exist on the Player frame only.", LX, y(2) + 4, COLW, function() return not indOK() end)
    Caption(p, "Threat", RX, y(2) + 22)
    SwitchRow(p, "Glow when you have threat", RX, y(2), COLW, "threat.enable")
    Hint(p, "A coloured glow around the frame: yellow, orange, then red as threat rises.", RX, y(3) + 4, COLW)
    Caption(p, "Preview", RX, y(5))
    Hint(p, "\"Test frames\" or \"Unlock\" shows sample icons (skull, leader crown, ready check, combat, resting) so you can place them. The real icons come back afterwards.", RX, y(5) - 18, COLW)

    -- ---------------- Group
    p = pages.group
    local GROW = { { "DOWN", "Down" }, { "UP", "Up" }, { "RIGHT", "Right" }, { "LEFT", "Left" } }
    Caption(p, "Layout", LX, 0)
    SegRow(p, "Grow", LX, y(1), COLW, GROW, "group.growth")
    SliderRow(p, "Spacing", LX, y(2), COLW, "group.spacing", { lo = 0, hi = 60, step = 1, parse = zeroPlus })
    SegRow(p, "Groups grow", LX, y(3), COLW, GROW, "group.groupGrowth", function() return scope == "raid" end)
    SliderRow(p, "Group spacing", LX, y(4), COLW, "group.groupSpacing", { lo = 0, hi = 60, step = 1, parse = zeroPlus }, function() return scope == "raid" end)
    SliderRow(p, "Units per group", LX, y(5), COLW, "group.unitsPerGroup", { lo = 1, hi = 40, step = 1, parse = positive }, function() return scope == "raid" end)
    SliderRow(p, "Number of groups", LX, y(6), COLW, "group.numGroups", { lo = 1, hi = 8, step = 1, parse = positive }, function() return scope == "raid" end)
    Caption(p, "Content", RX, 0, function() return scope ~= "boss" end)
    SwitchRow(p, "Include myself", RX, y(1), COLW, "group.showPlayer", function() return scope ~= "boss" end)
    SwitchRow(p, "Show when solo", RX, y(2), COLW, "group.showSolo", function() return scope == "party" end)
    SegRow(p, "Sort by", RX, y(2), COLW, { { "GROUP", "Group" }, { "CLASS", "Class" }, { "ASSIGNEDROLE", "Role" }, { "NONE", "None" } }, "group.groupBy", function() return scope == "raid" end)
    InputRow(p, "Groups shown", RX, y(3), COLW, "group.groupFilter", function() return scope == "raid" end)
    SwitchRow(p, "Only in raids of 6+", RX, y(4), COLW, "group.raidOnly", function() return scope == "raid" end)
    Hint(p, "Party frames hide in raids of 6+; raid frames take over. \"Groups shown\" is a list like 1,2,3,4,5.", RX, y(5) + 4, COLW, function() return scope ~= "boss" end)
    Hint(p, "Boss frames appear during encounters. Use Test to see them.", RX, 0, COLW, function() return scope == "boss" end)

    -- ---------------- Combo points (player and target cards: both edit the player's combo points)
    -- Four views keep the page light: Look (sizes, style options), Colours (every part), Animation, Placement.
    p = pages.combo
    sub.comboView = sub.comboView or "look"
    local CP = function(field) return "@player:classPower." .. field end
    local cpOn = function() return Get(CP("enable")) and true or false end
    local function styleIs(...) local v = Get(CP("style")) or "BARS"; for i = 1, select("#", ...) do if v == select(i, ...) then return true end end return false end
    local function view(v, more) return function() return cpOn() and sub.comboView == v and (not more or more()) end end
    local tally = function() return styleIs("TALLY") end
    local notTally = function() return not styleIs("TALLY") end
    local bars = function() return styleIs("BARS") end
    local shapes = function() return not styleIs("BARS", "TALLY") end
    Caption(p, "Combo points", LX, 0)
    SwitchRow(p, "Show combo points", LX, y(1), COLW, CP("enable"))
    DropdownRow(p, "Look", LX, y(2), COLW, ns.COMBO_STYLES, CP("style"), false, cpOn)
    local cvsel = Segmented(p, { { "look", "Look" }, { "colours", "Colours" }, { "anim", "Animation" }, { "place", "Placement" } }, COLW,
        function() return sub.comboView end, function(v) sub.comboView = v; frame:Refresh() end, 28)
    cvsel:SetPoint("TOPLEFT", RX, 0); Flow(cvsel, RX, 0, COLW)
    OnRefresh(function() cvsel:SetShown(cpOn()) end)

    -- Look: sizes, and the options of the chosen style
    Caption(p, "Size", LX, y(3) - 4, view("look"))
    SliderRow(p, "Height", LX, y(4) - 4, COLW, CP("height"), { lo = 2, hi = 30, step = 1, parse = positive }, view("look", bars))
    SliderRow(p, "Size", LX, y(4) - 4, COLW, CP("size"), { lo = 6, hi = 60, step = 1, parse = positive }, view("look", shapes))
    SliderRow(p, "Mark height", LX, y(4) - 4, COLW, CP("size"), { lo = 6, hi = 60, step = 1, parse = positive }, view("look", tally))
    SliderRow(p, "Spacing", LX, y(5) - 4, COLW, CP("gap"), { lo = 0, hi = 20, step = 1, parse = zeroPlus }, view("look", notTally))
    SliderRow(p, "Space between marks", LX, y(5) - 4, COLW, CP("tallyGap"), auto(0, 30), view("look", tally))
    SliderRow(p, "Line thickness", LX, y(6) - 4, COLW, CP("thickness"), { lo = 1, hi = 12, step = 0.5, parse = positive }, view("look", tally))
    SliderRow(p, "Fill inset", LX, y(6) - 4, COLW, CP("inset"), { lo = 0, hi = 0.45, step = 0.05, parse = zeroPlus,
        fmt = function(v) return math.floor(v * 100 + 0.5) .. "%" end }, view("look", notTally))
    SegRow(p, "Align", LX, y(7) - 4, COLW, { { "LEFT", "Left" }, { "CENTER", "Centre" }, { "RIGHT", "Right" } }, CP("align"),
        view("look", function() return not styleIs("BARS") end))
    SliderRow(p, "Width", LX, y(8) - 4, COLW, CP("width"), auto(0, 600), view("look"))
    Hint(p, "Fill inset makes the coloured part smaller than the point: the empty colour shows around it like a frame. Width Auto follows the frame the points sit on.",
        LX, y(9) - 4, COLW, view("look", notTally))
    Caption(p, "Tally marks", RX, y(3) - 4, view("look", tally))
    DropdownRow(p, "Line", RX, y(4) - 4, COLW, ns.COMBO_TALLY_LINES, CP("line"), false, view("look", tally))
    SliderRow(p, "Irregularity", RX, y(5) - 4, COLW, CP("irregular"), { lo = 0, hi = 2, step = 0.05, parse = zeroPlus }, view("look", tally))
    SwitchRow(p, "New shapes for each series", RX, y(6) - 4, COLW, CP("newShapes"), view("look", tally))
    Hint(p, "Hand-drawn: each mark takes one of 12 pencil strokes, maybe mirrored. Irregularity 0 = neat marks, 1 = hand-written, 2 = messy. With new shapes, the marks change every time the tally starts again from zero.",
        RX, y(7) - 4, COLW, view("look", tally))
    Hint(p, "Options of the tally marks (line, irregularity, new shapes) show when \"Tally marks\" is chosen.", RX, y(3) - 4, COLW, view("look", notTally))

    -- Colours: filled points, empty points, outline
    local cpColor = function(...) local v = Get(CP("colorMode")) or "POWER"; for i = 1, select("#", ...) do if v == select(i, ...) then return true end end return false end
    Caption(p, "Filled points", LX, y(3) - 4, view("colours"))
    SegRow(p, "Colour", LX, y(4) - 4, COLW, { { "POWER", "Combo" }, { "CUSTOM", "Custom" }, { "GRADIENT", "Gradient" }, { "CLASS", "Class" } }, CP("colorMode"), view("colours"))
    ColorRow(p, "Colour", LX, y(5) - 4, COLW, CP("color"), false, nil, view("colours", function() return cpColor("CUSTOM") end))
    ColorRow(p, "First point", LX, y(5) - 4, COLW, CP("color"), false, nil, view("colours", function() return cpColor("GRADIENT") end))
    ColorRow(p, "Last point", LX, y(6) - 4, COLW, CP("color2"), false, nil, view("colours", function() return cpColor("GRADIENT") end))
    SwitchRow(p, "Other colour when full", LX, y(7) - 4, COLW, CP("colorFull"), view("colours"))
    ColorRow(p, "Full colour", LX, y(8) - 4, COLW, CP("fullColor"), false, nil, view("colours", function() return Get(CP("colorFull")) and true or false end))
    Caption(p, "Empty points", RX, y(3) - 4, view("colours"))
    SwitchRow(p, "Show empty points", RX, y(4) - 4, COLW, CP("showEmpty"), view("colours", notTally))
    SwitchRow(p, "Show empty marks", RX, y(4) - 4, COLW, CP("tallyEmpty"), view("colours", tally))
    ColorRow(p, "Empty colour", RX, y(5) - 4, COLW, CP("emptyColor"), true, nil, view("colours", function()
        if styleIs("TALLY") then return Get(CP("tallyEmpty")) and true or false end
        return Get(CP("showEmpty")) and true or false
    end))
    BorderBlock(p, "Outline", RX, y(6) - 4, COLW, CP("border"), view("colours"))
    Hint(p, "The outline follows the shape: square edges for bars, the shape itself for circles, diamonds and stars, and a dark edge around each tally mark so it reads on any background.",
        RX, y(11), COLW, view("colours"))

    -- Animation
    Caption(p, "Animation", LX, y(3) - 4, view("anim"))
    SwitchRow(p, "Animate new points", LX, y(4) - 4, COLW, CP("animate"), view("anim"))
    SliderRow(p, "Speed", LX, y(5) - 4, COLW, CP("animSpeed"), { lo = 0.25, hi = 3, step = 0.05, parse = positive,
        fmt = function(v) return fmtNum(v) .. "x" end }, view("anim", function() return Get(CP("animate")) and true or false end))
    Hint(p, "Tally marks are written stroke by stroke, like a pencil, with a short pause between strokes. Bars fill from the left, the other looks pop in. Spent points fade out. Changing target always shows the new target's points at once.",
        LX, y(6) - 4, COLW, view("anim"))

    -- Placement
    Caption(p, "Placement", LX, y(3) - 4, view("place"))
    SwitchRow(p, "Free on the screen", LX, y(4) - 4, COLW, CP("onScreen"), view("place"))
    DropdownRow(p, "Position", LX, y(5) - 4, COLW, {
        { key = "TARGET_TOP", label = "Above the target frame" }, { key = "TARGET_BOTTOM", label = "Below the target frame" },
        { key = "PLAYER_TOP", label = "Above the player frame" }, { key = "PLAYER_BOTTOM", label = "Below the player frame" },
    }, CP("where"), false, view("place", function() return not Get(CP("onScreen")) end))
    SliderRow(p, "Screen X", LX, y(5) - 4, COLW, CP("screen.2"), { lo = -1500, hi = 1500, step = 1, parse = any }, view("place", function() return Get(CP("onScreen")) and true or false end))
    SliderRow(p, "Screen Y", LX, y(6) - 4, COLW, CP("screen.3"), { lo = -900, hi = 900, step = 1, parse = any }, view("place", function() return Get(CP("onScreen")) and true or false end))
    DropdownRow(p, "Show", LX, y(7) - 4, COLW, {
        { key = "COMBAT_HOSTILE", label = "In combat, with an enemy target" }, { key = "HOSTILE", label = "With an enemy target" },
        { key = "ALWAYS", label = "Always" },
    }, CP("visibility"), false, view("place"))
    Hint(p, "Free on the screen: Unlock to drag the points with the mouse.", LX, y(8) - 4, COLW, view("place"))

    -- ---------------- Pet happiness (pet card)
    p = pages.happiness
    local hOn = function() return Get("happiness.enable") and true or false end
    local hPlace = function(m) return function() return hOn() and (Get("happiness.place") or "FRAME") == m end end
    Caption(p, "Pet happiness", LX, 0)
    SwitchRow(p, "Show happiness icon", LX, y(1), COLW, "happiness.enable")
    SegRow(p, "Look", LX, y(2), COLW, { { "FACE", "Face" }, { "DOT", "Coloured dot" } }, "happiness.style", hOn)
    SliderRow(p, "Size", LX, y(3), COLW, "happiness.size", { lo = 8, hi = 80, step = 1, parse = positive }, hOn)
    SwitchRow(p, "Hide when happy", LX, y(4), COLW, "happiness.hideHappy", hOn)
    SwitchRow(p, "Tooltip on mouse-over", LX, y(5), COLW, "happiness.tooltip", hOn)
    Hint(p, "Hunter pets only: green / happy, yellow / content, red / unhappy. The tooltip tells the damage your pet deals and whether it is gaining loyalty.", LX, y(6) + 4, COLW, hOn)
    Caption(p, "Placement", RX, 0, hOn)
    SegRow(p, "Placement", RX, y(1), COLW, { { "FRAME", "On the pet frame" }, { "SCREEN", "Anywhere" } }, "happiness.place", hOn)
    DropdownRow(p, "Anchor", RX, y(2), COLW, POINTS, "happiness.point", false, hPlace("FRAME"))
    SliderRow(p, "Offset X", RX, y(3), COLW, "happiness.x", { lo = -300, hi = 300, step = 1, parse = any }, hPlace("FRAME"))
    SliderRow(p, "Offset Y", RX, y(4), COLW, "happiness.y", { lo = -300, hi = 300, step = 1, parse = any }, hPlace("FRAME"))
    SliderRow(p, "Screen X", RX, y(2), COLW, "happiness.screen.2", { lo = -1500, hi = 1500, step = 1, parse = any }, hPlace("SCREEN"))
    SliderRow(p, "Screen Y", RX, y(3), COLW, "happiness.screen.3", { lo = -900, hi = 900, step = 1, parse = any }, hPlace("SCREEN"))
    Hint(p, "\"Anywhere\" frees the icon from the pet frame: Unlock and drag it, or type the position. It stays visible even if the pet frame is turned off.", RX, y(5) + 4, COLW, hPlace("SCREEN"))
    Hint(p, "The anchor is the point of the pet frame the icon is centred on. \"Test frames\" shows a sample icon.", RX, y(5) + 4, COLW, hPlace("FRAME"))

    -- footer
    local footer = CreateFrame("Frame", nil, frame)
    footer:SetPoint("BOTTOMLEFT"); footer:SetPoint("BOTTOMRIGHT"); footer:SetHeight(56)
    local fbg = Fill(footer, C.panel, "BACKGROUND", -5); fbg:SetAllPoints()
    local fl = Fill(footer, { 1, 1, 1, 0.06 }, "BORDER"); fl:SetHeight(1); fl:SetPoint("TOPLEFT"); fl:SetPoint("TOPRIGHT")
    local copyItems = function()
        local out = {}
        for _, u in ipairs(ns.UNITS) do if u ~= scope then out[#out + 1] = { key = u, label = "Copy from " .. ns.UNIT_LABEL[u] } end end
        return out
    end
    local copyRow = Dropdown(footer, PAD, -15, 220, nil, copyItems, function() return nil end, function(v)
        ns.CopyUnit(v, scope); ns.UpdateUnit(scope); frame:Refresh()
    end, false, function() return scope ~= "global" end)
    copyRow.placeholder = "Copy look from..."
    copyRow.flowFixed = true
    -- resets ask for a second click within 4 seconds
    local function Confirm(b, text, fn)
        local now = GetTime and GetTime() or 0
        if b.armed and now - b.armed < 4 then
            b.armed = nil; b.label:SetText(text); fn()
        else
            b.armed = now; b.label:SetText("Click again")
            if C_Timer and C_Timer.After then
                C_Timer.After(4, function() if b.armed and (GetTime() - b.armed) >= 3.9 then b.armed = nil; b.label:SetText(text) end end)
            end
        end
    end
    local resetTab
    resetTab = Button(footer, "Reset tab", 96, false, function()
        Confirm(resetTab, "Reset tab", function()
            if scope == "global" then ns.ResetGlobal(); ns.UpdateAll()
            elseif activeTab == "combo" then ns.ResetTab("player", "combo"); ns.UpdateUnit("player")
            else ns.ResetTab(scope, activeTab); ns.UpdateUnit(scope) end
            frame:Refresh()
        end)
    end)
    resetTab:SetPoint("LEFT", PAD + 228, 0)
    local resetFrame
    resetFrame = Button(footer, "Reset frame", 104, false, function()
        Confirm(resetFrame, "Reset frame", function()
            if scope == "global" then return end
            ns.ResetUnit(scope); ns.UpdateUnit(scope); frame:Refresh()
        end)
    end)
    resetFrame:SetPoint("LEFT", resetTab, "RIGHT", 8, 0)
    resetTab:SetScript("OnEnter", function(self)
        self.bg:SetVertexColor(unpack(C.hover))
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(scope == "global" and "Reset the General page (media, borders, scale)" or "Reset only this tab of " .. (ns.UNIT_LABEL[scope] or scope), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    resetTab:SetScript("OnLeave", function(self) self.bg:SetVertexColor(unpack(C.control)); GameTooltip:Hide() end)
    resetFrame:SetScript("OnEnter", function(self)
        self.bg:SetVertexColor(unpack(C.hover))
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Reset every tab of " .. (ns.UNIT_LABEL[scope] or scope) .. " (its position too)", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    resetFrame:SetScript("OnLeave", function(self) self.bg:SetVertexColor(unpack(C.control)); GameTooltip:Hide() end)
    OnRefresh(function()
        resetFrame:SetShown(scope ~= "global")
        resetTab.armed, resetFrame.armed = nil, nil
        resetTab.label:SetText("Reset tab"); resetFrame.label:SetText("Reset frame")
    end)
    local lock = Button(footer, "Unlock", 120, true, function() ns.SetUnlocked(not ns.IsUnlocked()) end)
    lock:SetPoint("RIGHT", -PAD, 0)
    OnRefresh(function() lock.label:SetText(ns.IsUnlocked() and "Lock" or "Unlock") end)
    local test = Button(footer, "Test frames", 110, false, function() ns.SetTestMode(not ns.IsTestMode()) end)
    test:SetPoint("RIGHT", lock, "LEFT", -8, 0)
    OnRefresh(function()
        local on = ns.IsTestMode()
        test.label:SetText(on and "Stop test" or "Test frames")
        test.bg:SetVertexColor(unpack(on and C.hover or C.control))
    end)

    -- live preview, docked beside the options (a plain copy of the frame, showing you)
    local pv = CreateFrame("Frame", nil, frame)
    pv:SetSize(300, 366)
    pv:EnableMouse(true)
    local pvbg = Fill(pv, C.bg, "BACKGROUND", -6); pvbg:SetAllPoints()
    Border(pv, 0.09)
    local pvTop = Fill(pv, C.accent, "BORDER", 2); pvTop:SetHeight(2); pvTop:SetPoint("TOPLEFT"); pvTop:SetPoint("TOPRIGHT")
    local pvCap = Text(pv, 10, C.muted); pvCap:SetPoint("TOPLEFT", 10, -10); pvCap:SetText("PREVIEW (SAMPLE UNIT)")
    local pvName = Text(pv, 12, C.text); pvName:SetPoint("TOPRIGHT", -10, -9)
    local stage = CreateFrame("Frame", nil, pv)
    stage:SetPoint("TOPLEFT", 8, -28); stage:SetPoint("BOTTOMRIGHT", -8, 112)
    if stage.SetClipsChildren then stage:SetClipsChildren(true) end
    local stbg = Fill(stage, { 0.045, 0.048, 0.056, 1 }); stbg:SetAllPoints()
    local pvHint = Text(pv, 10, C.muted); pvHint:SetPoint("BOTTOMLEFT", 10, 10); pvHint:SetWidth(280)
    pvHint:SetText("A made-up unit: 65% health, 40% power, sample name, auras, cast, combo points and icons. Pick the class and type to see class and reaction colours.")
    -- what the sample unit is: its class (class colours, power type) and kind (player, friendly / neutral / hostile NPC...)
    local function simClasses() return ns.SimClassList() end
    local clsRow = Dropdown(pv, 8, -258, 284, "Class", simClasses, function() return ns.GetSim().class end,
        function(v) ns.SetSim("class", v); frame:Refresh() end, false, nil, 44)
    clsRow.flowFixed = true
    local typeRow = Dropdown(pv, 8, -288, 284, "Unit", function() return ns.SIM_TYPES end, function() return ns.GetSim().type end,
        function(v) ns.SetSim("type", v); frame:Refresh() end, false, nil, 44)
    typeRow.flowFixed = true
    local function PreviewWanted() local db = ns.GetDB(); return not (db and db.previewHidden) end
    local function Dock()
        local ref = frame.fhMover or frame
        pv:ClearAllPoints()
        local r = ref:GetRight()
        local uiR = UIParent:GetRight()
        if r and uiR then
            local k = ref:GetEffectiveScale() / pv:GetEffectiveScale()
            local free = uiR * UIParent:GetEffectiveScale() / pv:GetEffectiveScale() - r * k
            if free >= 312 then pv:SetPoint("TOPLEFT", ref, "TOPRIGHT", 10, 0); return end
        end
        pv:SetPoint("TOPRIGHT", ref, "TOPLEFT", -10, 0)
    end
    OnRefresh(function()
        local f = PreviewWanted() and ns.PreviewFrame and ns.PreviewFrame(stage)
        pv:SetShown(f and true or false)
        if not f then return end
        Dock()
        local key = (scope == "global") and "player" or scope
        pvName:SetText(ns.UNIT_LABEL[key] or key)
        ns.UpdatePreview(key, 250)
    end)
    local pvBtn = Button(footer, "Preview", 90, false, function()
        local db = ns.GetDB()
        if db then db.previewHidden = not db.previewHidden end
        frame:Refresh()
    end)
    pvBtn:SetPoint("RIGHT", test, "LEFT", -8, 0)
    OnRefresh(function() pvBtn.bg:SetVertexColor(unpack(PreviewWanted() and C.hover or C.control)) end)

    function frame:Refresh()
        for _, fn in ipairs(refreshers) do fn() end
    end
    frame:SetScript("OnShow", function(self) self:Refresh() end)
    frame:SetScript("OnSizeChanged", function(_, w) Reflow(w) end)
    frame:SetScript("OnHide", function() if openList then openList:Hide(); openList = nil end end)
    frame:Hide()
end

-- ------------------------------------------------------------ Free Hub integration
-- When Free Hub is installed, these options open inside its window (sidebar on the left).
local function Embed(parent)
    if not ns.GetDB() then return end
    if not frame then Build() end
    frame.fhEmbedded = true
    frame:SetParent(parent)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)   -- fills the hub; the layout follows its size
    frame:SetFrameStrata(parent:GetFrameStrata())
    frame:SetFrameLevel(parent:GetFrameLevel() + 1)
    frame.fhShadow:Hide()
    frame.fhClose:Hide()
    frame.fhMover = FreeHub:GetFrame()
    frame.fhNaturalW, frame.fhNaturalH = W, H
    frame:Show()
    return frame
end
local function Unembed()
    if not frame or not frame.fhEmbedded then return end
    frame.fhEmbedded = nil
    frame:Hide()
    frame:SetParent(UIParent)
    frame:ClearAllPoints()
    frame:SetSize(W, H)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame.fhShadow:Show()
    frame.fhClose:Show()
    frame.fhMover = nil
end
if FreeHub and FreeHub.Register then
    FreeHub:Register("FreeUnitFrames", {
        embed = Embed,
        unembed = Unembed,
        minW = W, minH = H,   -- natural size of these options; the hub never gets smaller than this
        minimap = function(show) if ns.ApplyMinimapVisibility then ns.ApplyMinimapVisibility(show) end end,
    })
end

ns.ToggleConfig = function()
    if not ns.GetDB() then return end
    if FreeHub and FreeHub.Toggle and FreeHub:IsRegistered("FreeUnitFrames") then FreeHub:Toggle("FreeUnitFrames"); return end
    if not frame then Build() end
    frame:SetShown(not frame:IsShown())
end

ns.OnChanged = function()
    if frame and frame:IsShown() then frame:Refresh() end
end
