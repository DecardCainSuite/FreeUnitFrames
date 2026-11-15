--[[ LibFreeGrid-1.0
     Unlock-mode helpers shared by the movers of every Free addon: a full-screen grid, snapping, and a small floating toolbar.

     local Grid = LibStub("LibFreeGrid-1.0"):Attach(db.grid)   -- db.grid: a table in the addon's profile (defaults are filled in)
       db.grid keys: showGrid=false, snapGrid=false, snapFrames=true, gridSize=32, snapDist=10
     Grid:Snap(l, b, w, h, otherRects) -> l, b       l/b = left/bottom of the frame in UIParent units;
                                                      otherRects = { { l, b, w, h }, ... } (or { l=, b=, w=, h= })
                                                      Alt held = no snapping
     local tb = Grid:Toolbar(db.grid, onChange, onLock, "Free Bars")   -- tb:Show() when unlocked, tb:Hide() when locked
     Grid:ShowGrid(size) / Grid:HideGrid()                             -- the overlay is shared by all addons
]]
local MAJOR, MINOR = "LibFreeGrid-1.0", 1
local lib = LibStub and LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

local type, pairs, ipairs, pcall, tostring, tonumber = type, pairs, ipairs, pcall, tostring, tonumber
local floor, abs, max, min = math.floor, math.abs, math.max, math.min

local WHITE = "Interface\\Buttons\\WHITE8x8"
local FONT = "Fonts\\ARIALN.TTF"
local ACCENT = { 1.0, 0.54, 0.24 }

lib.DEFAULTS = { showGrid = false, snapGrid = false, snapFrames = true, gridSize = 32, snapDist = 10 }

local function fillDefaults(t)
    for k, v in pairs(lib.DEFAULTS) do if t[k] == nil then t[k] = v end end
    return t
end

local function screen()
    local w, h = 1920, 1080
    if UIParent and UIParent.GetSize then
        local a, b = UIParent:GetSize()
        if a and b and a > 0 and b > 0 then w, h = a, b end
    end
    return w, h
end

-- ------------------------------------------------------------ overlay (one for everybody)
local overlay
local lines = {}
local overlaySize
local MAXLINES = 900

local function getLine(i)
    local t = lines[i]
    if not t then
        t = overlay:CreateTexture(nil, "BACKGROUND")
        t:SetTexture(WHITE)
        lines[i] = t
    end
    return t
end

local function build(size)
    local sw, sh = screen()
    size = max(8, tonumber(size) or 32)
    local cx, cy = sw / 2, sh / 2
    local n = 0
    local function line(vertical, pos, center)
        if n >= MAXLINES then return end
        n = n + 1
        local t = getLine(n)
        t:ClearAllPoints()
        if center then t:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], 0.55) else t:SetVertexColor(1, 1, 1, 0.07) end
        if vertical then
            t:SetPoint("TOPLEFT", overlay, "TOPLEFT", pos - 0.5, 0)
            t:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", pos - 0.5, 0)
            t:SetWidth(center and 2 or 1)
        else
            t:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", 0, pos - 0.5)
            t:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", 0, pos - 0.5)
            t:SetHeight(center and 2 or 1)
        end
        t:Show()
    end
    line(true, cx, true); line(false, cy, true)
    local k = 1
    while cx + k * size <= sw or cx - k * size >= 0 do
        if cx + k * size <= sw then line(true, cx + k * size) end
        if cx - k * size >= 0 then line(true, cx - k * size) end
        k = k + 1
        if n >= MAXLINES then break end
    end
    k = 1
    while cy + k * size <= sh or cy - k * size >= 0 do
        if cy + k * size <= sh then line(false, cy + k * size) end
        if cy - k * size >= 0 then line(false, cy - k * size) end
        k = k + 1
        if n >= MAXLINES then break end
    end
    for i = n + 1, #lines do lines[i]:Hide() end
    overlaySize = size
    lib.lineCount = n
end

function lib:ShowGrid(size)
    if not (CreateFrame and UIParent) then return end
    if not overlay then
        overlay = CreateFrame("Frame", "LibFreeGridOverlay", UIParent)
        overlay:SetFrameStrata("BACKGROUND")
        overlay:SetAllPoints(UIParent)
        overlay:EnableMouse(false)
        overlay:SetScript("OnSizeChanged", function() if overlay:IsShown() and overlaySize then build(overlaySize) end end)
        lib.overlay = overlay
    end
    size = tonumber(size) or (self and self.settings and self.settings.gridSize) or 32
    if size ~= overlaySize or not overlay:IsShown() then build(size) end
    overlay:Show()
end

function lib:HideGrid()
    if overlay then overlay:Hide() end
end

-- the overlay follows the toolbars that are open: shown when any of them wants the grid
local toolbars = {}
function lib:UpdateOverlay()
    for _, tb in ipairs(toolbars) do
        if tb.frame:IsShown() and tb.settings.showGrid then
            lib.ShowGrid(lib, tb.settings.gridSize)
            return
        end
    end
    lib:HideGrid()
end

-- ------------------------------------------------------------ snapping
local function rectOf(r)
    if type(r) ~= "table" then return end
    local l, b, w, h = r.l or r[1], r.b or r[2], r.w or r[3], r.h or r[4]
    if l and b and w and h then return l, b, w, h end
end

local function best(v, cands, dist)
    local bv, bd = nil, dist + 1
    for _, c in ipairs(cands) do
        local d = abs(c - v)
        if d < bd then bv, bd = c, d end
    end
    return bv
end

local function gridAxis(v, len, size, center)
    -- snap the near edge, the middle or the far edge of the frame, whichever is closest to a grid line
    local bestShift, bestD
    for _, off in ipairs({ 0, len / 2, len }) do
        local p = v + off
        local line = center + floor((p - center) / size + 0.5) * size
        local d = abs(line - p)
        if not bestD or d < bestD then bestD, bestShift = d, line - p end
    end
    return v + bestShift
end

local function snap(s, l, b, w, h, others)
    if IsAltKeyDown and IsAltKeyDown() then return l, b end
    local dist = tonumber(s.snapDist) or 10
    local sx, sy = screen()
    local nl, nb = l, b
    local doneX, doneY
    if s.snapFrames ~= false then
        local xs = { sx / 2 - w / 2, 0, sx - w }
        local ys = { sy / 2 - h / 2, 0, sy - h }
        for _, r in ipairs(others or {}) do
            local ol, ob, ow, oh = rectOf(r)
            if ol then
                for _, x in ipairs({ ol, ol + ow - w, ol + ow, ol - w, ol + ow / 2 - w / 2 }) do xs[#xs + 1] = x end
                for _, y in ipairs({ ob, ob + oh - h, ob + oh, ob - h, ob + oh / 2 - h / 2 }) do ys[#ys + 1] = y end
            end
        end
        local bx, by = best(l, xs, dist), best(b, ys, dist)
        if bx then nl, doneX = bx, true end
        if by then nb, doneY = by, true end
    end
    if s.snapGrid then
        local size = max(8, tonumber(s.gridSize) or 32)
        if not doneX then nl = gridAxis(l, w, size, sx / 2) end
        if not doneY then nb = gridAxis(b, h, size, sy / 2) end
    end
    return nl, nb
end

-- ------------------------------------------------------------ instances
local Grid = {}
Grid.__index = Grid

function lib:Attach(settings)
    settings = settings or {}
    fillDefaults(settings)
    return setmetatable({ settings = settings }, Grid)
end

function Grid:ShowGrid(size) return lib.ShowGrid(self, size or self.settings.gridSize) end
function Grid:HideGrid() return lib:HideGrid() end
function Grid:Snap(l, b, w, h, others) return snap(self.settings, l, b, w, h, others) end
function lib:Snap(settings, l, b, w, h, others) return snap(fillDefaults(settings or {}), l, b, w, h, others) end

-- ------------------------------------------------------------ toolbar
local C = { bg = { 0.070, 0.074, 0.085, 0.97 }, control = { 0.145, 0.151, 0.170, 1 }, hover = { 0.19, 0.197, 0.222, 1 },
            text = { 0.93, 0.937, 0.955 }, dim = { 0.70, 0.712, 0.75 }, muted = { 0.5, 0.515, 0.56 }, onAccent = { 0.1, 0.05, 0.02 } }

local function Fill(f, col, layer, sub)
    local t = f:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
    t:SetTexture(WHITE); t:SetVertexColor(col[1], col[2], col[3], col[4] or 1)
    return t
end
local function Edge(f, a)
    for _, p in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
        local e = f:CreateTexture(nil, "BORDER")
        e:SetTexture(WHITE); e:SetVertexColor(1, 1, 1, a)
        e:SetPoint(p[1]); e:SetPoint(p[2])
        if p[3] then e:SetHeight(1) else e:SetWidth(1) end
    end
end
local function Txt(f, size, col)
    local fs = f:CreateFontString(nil, "OVERLAY")
    if not fs:SetFont(FONT, size, "") and STANDARD_TEXT_FONT then fs:SetFont(STANDARD_TEXT_FONT, size, "") end
    fs:SetTextColor(col[1], col[2], col[3])
    fs:SetJustifyH("LEFT")
    return fs
end

local TB = {}
TB.__index = TB
function TB:Show() self.frame:Show(); self:Refresh(); lib:UpdateOverlay() end
function TB:Hide() self.frame:Hide(); lib:UpdateOverlay() end
function TB:IsShown() return self.frame:IsShown() end
function TB:Refresh()
    local s = self.settings
    for _, c in ipairs(self.checks) do c.paint(s[c.key] and true or false) end
    local v = tonumber(s.gridSize) or 32
    self.updating = true
    self.slider:SetValue(v)
    self.updating = false
    self.sizeText:SetText(tostring(floor(v + 0.5)))
end

-- settings: the grid settings table; onChange(key, value) after every change; onLock(): "Lock" button (optional);
-- name: addon name shown next to the title (optional)
function Grid:Toolbar(settings, onChange, onLock, name)
    return lib:Toolbar(settings or self.settings, onChange, onLock, name)
end

function lib:Toolbar(settings, onChange, onLock, name)
    settings = fillDefaults(settings or {})
    local idx = #toolbars + 1
    local tb = setmetatable({ settings = settings, checks = {} }, TB)
    local f = CreateFrame("Frame", "LibFreeGridToolbar" .. idx, UIParent)
    tb.frame = f
    toolbars[idx] = tb
    f:SetSize(230, 196)
    f:SetPoint("TOP", UIParent, "TOP", (idx - 1) * 24, -90 - (idx - 1) * 34)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(s) s:StartMoving() end)
    f:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)
    f:SetScript("OnHide", function() lib:UpdateOverlay() end)
    Fill(f, C.bg, "BACKGROUND", -6):SetAllPoints()
    Edge(f, 0.1)
    local top = Fill(f, ACCENT, "BORDER", 2); top:SetHeight(2); top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT")
    local title = Txt(f, 14, C.text); title:SetPoint("TOPLEFT", 12, -12); title:SetText("Unlock")
    local sub = Txt(f, 11, C.muted); sub:SetPoint("LEFT", title, "RIGHT", 8, -1); sub:SetText(name or "")

    local function changed(key, value)
        settings[key] = value
        if onChange then pcall(onChange, key, value, settings) end
        lib:UpdateOverlay()
    end

    local function check(label, key, y)
        local b = CreateFrame("Button", nil, f)
        b:SetSize(206, 22)
        b:SetPoint("TOPLEFT", 12, y)
        local box = Fill(b, C.control, "ARTWORK"); box:SetSize(16, 16); box:SetPoint("LEFT")
        local mark = Fill(b, ACCENT, "OVERLAY"); mark:SetSize(8, 8); mark:SetPoint("CENTER", box, "CENTER")
        local fs = Txt(b, 13, C.text); fs:SetPoint("LEFT", box, "RIGHT", 8, 0); fs:SetText(label)
        local c = { key = key, paint = function(on) mark:SetShown(on) end }
        b:SetScript("OnClick", function() local on = not settings[key]; changed(key, on and true or false); c.paint(on) end)
        b:SetScript("OnEnter", function() box:SetVertexColor(C.hover[1], C.hover[2], C.hover[3], 1) end)
        b:SetScript("OnLeave", function() box:SetVertexColor(C.control[1], C.control[2], C.control[3], 1) end)
        tb.checks[#tb.checks + 1] = c
        return b
    end
    check("Show grid", "showGrid", -40)
    check("Snap to grid", "snapGrid", -64)
    check("Snap to frames", "snapFrames", -88)

    local lbl = Txt(f, 12, C.dim); lbl:SetPoint("TOPLEFT", 12, -120); lbl:SetText("Grid size")
    local sizeText = Txt(f, 12, C.text); sizeText:SetPoint("TOPRIGHT", -12, -120); sizeText:SetJustifyH("RIGHT")
    tb.sizeText = sizeText
    local s = CreateFrame("Slider", nil, f)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(206, 16)
    s:SetPoint("TOPLEFT", 12, -140)
    s:SetMinMaxValues(8, 128)
    s:SetValueStep(4)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    local track = Fill(s, { 1, 1, 1, 0.10 }); track:SetHeight(4); track:SetPoint("LEFT"); track:SetPoint("RIGHT")
    s:SetThumbTexture(WHITE)
    local thumb = s:GetThumbTexture()
    if thumb then thumb:SetSize(6, 14); thumb:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], 1) end
    s:SetScript("OnValueChanged", function(_, v)
        if tb.updating then return end
        v = max(8, min(128, floor((tonumber(v) or 32) / 4 + 0.5) * 4))
        sizeText:SetText(tostring(v))
        if v ~= settings.gridSize then changed("gridSize", v) end
    end)
    tb.slider = s

    local lock = CreateFrame("Button", nil, f)
    lock:SetSize(206, 26)
    lock:SetPoint("BOTTOMLEFT", 12, 10)
    local lbg = Fill(lock, ACCENT, "ARTWORK"); lbg:SetAllPoints()
    local lt = Txt(lock, 13, C.onAccent); lt:SetPoint("CENTER"); lt:SetText("Lock"); lt:SetJustifyH("CENTER")
    lock:SetScript("OnClick", function() if onLock then onLock() end; tb:Hide() end)
    lock:SetScript("OnEnter", function() lbg:SetVertexColor(1, 0.64, 0.38, 1) end)
    lock:SetScript("OnLeave", function() lbg:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], 1) end)
    tb.lock = lock

    f:Hide()
    tb:Refresh()
    return tb
end
