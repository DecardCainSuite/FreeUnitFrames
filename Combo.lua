-- FreeUnitFrames - combo points: drawing, styles and animations.
-- oUF's ClassPower element still decides WHEN the bar exists (class, form, vehicle); this file reads the value
-- and draws it (Override), so every style shares the same data path.
--
-- Combo points belong to the target on WoW Forever: the value is read again on every target change
-- (PLAYER_TARGET_CHANGED), and shortly after it in case the game updates it a moment later.

local ADDON, ns = ...
local oUF = ns.oUF
local WHITE = ns.WHITE
local MEDIA = ns.MEDIA

local COMBO = (Enum and Enum.PowerType and Enum.PowerType.ComboPoints) or 4
local TOKEN = { [COMBO] = "COMBO_POINTS" }
local MAX_PIPS = 10

-- shape of one point for each style (nil = solid rectangle)
local SHAPE = { CIRCLES = MEDIA .. "circle", DIAMONDS = MEDIA .. "diamond", STARS = MEDIA .. "star" }
ns.COMBO_STYLES = {
    { key = "BARS", label = "Bars (fill the width)" }, { key = "SQUARES", label = "Squares" },
    { key = "CIRCLES", label = "Circles" }, { key = "DIAMONDS", label = "Diamonds" }, { key = "STARS", label = "Stars" },
    { key = "VERTICAL", label = "Vertical bars" }, { key = "TALLY", label = "Tally marks (hand-written)" },
}

local now = GetTime
-- WoW runs Lua 5.1 (math.atan2); the test client runs 5.4 (math.atan with two arguments)
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

-- ------------------------------------------------------------ reading the value
-- Returns current, maximum (numbers) or nil when the bar has nothing to show.
local function Safe(v)
    if v == nil then return nil end
    if oUF.NotSecretValue and not oUF:NotSecretValue(v) then return nil end
    return tonumber(v)
end
local function ReadPoints(cp)
    local id = cp.classPowerID
    if not id or cp.__isEnabled == false then return nil end
    local cur
    if id == COMBO then
        -- per target: no target = no points
        local hasTarget = true
        if UnitExists then local ok, e = pcall(UnitExists, "target"); hasTarget = ok and e and true or false end
        if GetComboPoints then
            local ok, v = pcall(GetComboPoints, "player", "target")
            if ok then cur = Safe(v) end
        end
        if cur == nil and hasTarget then
            local ok, v = pcall(UnitPower, "player", id)
            if ok then cur = Safe(v) end
        end
        if not hasTarget then cur = 0 end
    else
        local ok, v = pcall(UnitPower, "player", id)
        if ok then cur = Safe(v) end
    end
    local max
    local ok, m = pcall(UnitPowerMax, "player", id)
    if ok then max = Safe(m) end
    if not max or max < 1 then max = (id == COMBO) and (MAX_COMBO_POINTS or 5) or 5 end
    max = math.max(1, math.min(MAX_PIPS, math.floor(max)))
    cur = math.max(0, math.min(max, math.floor(cur or 0)))
    return cur, max
end
ns.ComboReadPoints = ReadPoints

-- ------------------------------------------------------------ colours
local function Lerp(a, b, t) return a + (b - a) * t end
local function PipColor(cp, c, i, max, full)
    if full and c.colorFull and c.fullColor then return c.fullColor[1], c.fullColor[2], c.fullColor[3] end
    local mode = c.colorMode or "POWER"
    if mode == "CUSTOM" and c.color then return c.color[1], c.color[2], c.color[3] end
    if mode == "GRADIENT" and c.color and c.color2 then
        local t = (max > 1) and (i - 1) / (max - 1) or 0
        return Lerp(c.color[1], c.color2[1], t), Lerp(c.color[2], c.color2[2], t), Lerp(c.color[3], c.color2[3], t)
    end
    if mode == "CLASS" and ns.UnitClassColor then
        local col = ns.UnitClassColor("player", "player")
        if col then return col[1], col[2], col[3] end
    end
    if ns.PowerRGB then
        local r, g, b = ns.PowerRGB(TOKEN[cp.classPowerID] or "COMBO_POINTS")
        if r then return r, g, b end
    end
    return 1, 0.85, 0.2
end

-- ------------------------------------------------------------ tally marks: shapes
-- Lines a tally can be drawn with. 1 = hand-drawn: an atlas of 12 strokes (128x16 each, stacked in 128x256),
-- one picked per mark (and maybe mirrored). In every stroke, left = where the pencil starts.
local TALLY_LINES = { MEDIA .. "strokes", MEDIA .. "stroke-pencil", MEDIA .. "stroke", WHITE }
ns.COMBO_TALLY_LINES = {
    { key = 1, label = "Hand-drawn (12 strokes)" }, { key = 2, label = "Pencil" }, { key = 3, label = "Chalk" }, { key = 4, label = "Plain" },
}
local VARIANTS, ATLAS_ROWS = 12, 16
local rnd = math.random
local function R(a, b) return a + (b - a) * rnd() end

-- A new, slightly irregular hand: every mark gets its own angle, length, height, position and stroke.
-- returns marks { x1, y1, x2, y2, thickness factor, texture top, texture bottom } (x1, y1 = start) and their box
local function TallyShapes(c, max, size)
    local sp = (c.tallyGap and c.tallyGap > 0) and c.tallyGap or math.max(4, size * 0.4)
    local irr = tonumber(c.irregular) or 1
    local varied = (c.line or 1) == 1
    local lean = R(-0.06, 0.06) * irr
    local segs, x, first = {}, 0, 0
    for i = 1, max do
        local j = (i - 1) % 5 + 1
        if j == 1 then first = x end
        local s
        if j < 5 then
            local mx = x + R(-0.12, 0.12) * sp * irr
            local len = size * (1 - R(0, 0.2) * irr + R(0, 0.06) * math.min(1, irr))
            local cy = size / 2 + R(-0.08, 0.08) * size * irr
            local a = lean + R(-0.13, 0.13) * irr          -- angle from vertical
            local dx, dy = math.sin(a) * len / 2, math.cos(a) * len / 2
            s = { mx + dx, cy + dy, mx - dx, cy - dy, 1 + R(-0.15, 0.15) * math.min(1, irr) }   -- top to bottom
            x = x + sp
        else
            -- the fifth strikes the four others, written left to right
            local last = x - sp
            local ang
            if rnd() < 0.25 * math.min(1, irr) then ang = -R(0.08, 0.30) else ang = R(0.15, 0.50) end
            ang = ang * (0.6 + 0.4 * math.min(1, irr)) + (irr == 0 and 0.12 or 0)
            local x1 = first - sp * (irr == 0 and 0.55 or R(0.35, 0.75))
            local x2 = last + sp * (irr == 0 and 0.55 or R(0.30, 0.80))
            local cy = size * (irr == 0 and 0.48 or R(0.38, 0.58))
            local h = math.tan(ang) * (x2 - x1) / 2
            s = { x1, cy - h, x2, cy + h, 1 + R(-0.1, 0.1) * math.min(1, irr) }
            x = x - sp + sp * 1.8
        end
        if varied then
            local v = rnd(VARIANTS)
            local top, bottom = ((v - 1) * 16 + 0.5) / (ATLAS_ROWS * 16), (v * 16 - 0.5) / (ATLAS_ROWS * 16)
            if rnd() < 0.5 then top, bottom = bottom, top end   -- mirrored
            s[6], s[7] = top, bottom
        else
            s[6], s[7] = 0, 1
        end
        segs[i] = s
    end
    local minX, maxX = 1e9, -1e9
    for _, s in ipairs(segs) do minX = math.min(minX, s[1], s[3]); maxX = math.max(maxX, s[1], s[3]) end
    return segs, minX, maxX - minX
end

-- the part t (0..1) of a stroke: the texture is revealed from its start, like a pencil moving.
-- extra = how much longer on each end (outlines, so the tips get an edge too)
local function DrawLine(tex, holder, ox, oy, s, thick, t, extra)
    local x1, y1, x2, y2 = s[1], s[2], s[3], s[4]
    local dx, dy = (x2 - x1) * t, (y2 - y1) * t
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.3 then tex:Hide(); return end
    tex:ClearAllPoints()
    tex:SetTexCoord(0, t, s[6] or 0, s[7] or 1)
    tex:SetSize(len + (extra or 0) * 2, thick * (s[5] or 1))
    tex:SetPoint("CENTER", holder, "BOTTOMLEFT", ox + x1 + dx / 2, oy + y1 + dy / 2)
    if tex.SetRotation then tex:SetRotation(atan2(y2 - y1, x2 - x1)) end
    tex:Show()
end

-- no pixel snapping: growing lines and popping points move smoothly instead of jumping pixel by pixel
local function Smooth(t)
    if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) end
    if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0) end
    return t
end

-- ------------------------------------------------------------ widgets
local function NewPip(holder)
    local pip = CreateFrame("Frame", nil, holder)
    pip.outline = Smooth(pip:CreateTexture(nil, "BACKGROUND", nil, -2))
    pip.bg = Smooth(pip:CreateTexture(nil, "BACKGROUND", nil, 0))
    pip.fill = Smooth(pip:CreateTexture(nil, "ARTWORK", nil, 0))
    pip:Hide()
    return pip
end
local function NewStroke(holder)
    local s = {}
    s.shadow = Smooth(holder:CreateTexture(nil, "ARTWORK", nil, 1))
    s.ghost = Smooth(holder:CreateTexture(nil, "ARTWORK", nil, 2))
    s.ink = Smooth(holder:CreateTexture(nil, "ARTWORK", nil, 3))
    for _, t in pairs(s) do t:Hide() end
    return s
end

-- ------------------------------------------------------------ drawing one point
local function ShowPip(cp, i, k)       -- k = how much of the point is drawn (0 = empty, 1 = full)
    local L = cp.fufLayout
    if not L then return end
    if L.style == "TALLY" then
        local s = cp.fufStrokes[i]
        local seg = L.segs and L.segs[i]
        if not (s and seg) then return end
        if k > 0 then
            DrawLine(s.ink, cp.fufHolder, L.ox, L.oy, seg, L.thick, math.min(1, k))
            s.ink:SetAlpha(1)
            if L.shadow then
                DrawLine(s.shadow, cp.fufHolder, L.ox, L.oy, seg, L.thick + 2 * L.shadow, math.min(1, k), L.shadow)
                s.shadow:SetAlpha(1)
            else s.shadow:Hide() end
        else
            s.ink:Hide(); s.shadow:Hide()
        end
        return
    end
    local pip = cp[i]
    if not pip then return end
    local f = pip.fill
    local w, h = pip:GetWidth(), pip:GetHeight()
    -- inset: the fill is smaller than the point, the empty colour shows around it
    local ins = L.inset or 0
    local iw, ih = math.max(1, w - 2 * ins), math.max(1, h - 2 * ins)
    f:ClearAllPoints()
    if k <= 0 then f:Hide(); return end
    if L.style == "BARS" then
        -- fills from the left
        f:SetPoint("TOPLEFT", pip, "TOPLEFT", ins, -ins)
        f:SetSize(math.max(0.5, iw * math.min(1, k)), ih)
        f:SetAlpha(1)
    else
        -- pops in: a bit larger, then settles
        local grow = (k < 1) and (1 + 0.5 * (1 - k)) or 1
        f:SetPoint("CENTER", pip, "CENTER", 0, 0)
        f:SetSize(iw * grow, ih * grow)
        f:SetAlpha(math.min(1, k * 1.4))
    end
    f:Show()
end

local function ColorAll(cp, cur, max)
    local c = cp.fufCfg
    local full = cur >= max
    for i = 1, max do
        local r, g, b = PipColor(cp, c, i, max, full)
        if cp.fufLayout.style == "TALLY" then
            local s = cp.fufStrokes[i]
            if s then s.ink:SetVertexColor(r, g, b, 1) end
        else
            local pip = cp[i]
            if pip then pip.fill:SetVertexColor(r, g, b, 1) end
        end
    end
end

-- ------------------------------------------------------------ animations
-- a pencil line: quick start, slows down at the end
local function Ease(p) return 1 - (1 - p) * (1 - p) end
local function AnimTick(holder)
    local cp = holder.fufCP
    local list = cp.fufAnims
    local t = now()
    local busy = false
    for i, a in pairs(list) do
        local p = (t - a.start) / a.dur
        if p < 0 then
            busy = true
        elseif p >= 1 then
            ShowPip(cp, i, a.to)
            if a.to <= 0 then cp:fufFadeDone(i) end
            list[i] = nil
        else
            busy = true
            if a.to > 0 then
                ShowPip(cp, i, Ease(p))
            else
                cp:fufFade(i, 1 - p)
            end
        end
    end
    if not busy and not next(list) then holder:SetScript("OnUpdate", nil) end
end

local function StartAnim(cp, i, to, delay, dur)
    cp.fufAnims[i] = { start = now() + (delay or 0), dur = dur, to = to }
    if to > 0 then ShowPip(cp, i, 0) end
    cp.fufHolder:SetScript("OnUpdate", AnimTick)
end

-- fading out a spent point (alpha of what is drawn)
local function Fade(cp, i, a)
    if cp.fufLayout.style == "TALLY" then
        local s = cp.fufStrokes[i]
        if s then s.ink:SetAlpha(a); s.shadow:SetAlpha(a) end
    elseif cp[i] then
        cp[i].fill:SetAlpha(a)
    end
end
local function FadeDone(cp, i)
    Fade(cp, i, 1)
    ShowPip(cp, i, 0)
end

-- how long a tally stroke takes to write: longer strokes take a bit longer
local function StrokeTime(L, i, speed)
    local s = L.segs[i]
    local len = math.sqrt((s[3] - s[1]) ^ 2 + (s[4] - s[2]) ^ 2)
    return (0.07 + len / 240) / speed
end

-- ------------------------------------------------------------ render
-- draw `cur` of `max`; animate = new points are drawn / spent ones fade, otherwise everything snaps
local function Render(cp, cur, max, animate)
    if not cp.fufLayout then return end
    local shown = cp.fufShown or 0
    local c = cp.fufCfg
    -- tally: a new series (starting from nothing) gets new shapes
    if cp.fufLayout.style == "TALLY" and shown == 0 and cur > 0 and c.newShapes ~= false then cp.fufReroll = true end
    if max ~= cp.fufLayout.max or cp.fufReroll then ns.ComboLayout(cp, max) end
    local L = cp.fufLayout
    cp.fufCanvas:Show()
    -- oUF hides the points when the class loses them (ClassPowerDisable): show them again
    if L.style ~= "TALLY" then for i = 1, max do cp[i]:Show() end end
    ColorAll(cp, cur, max)
    local speed = math.max(0.25, tonumber(c.animSpeed) or 1)
    local tally = L.style == "TALLY"
    if not (animate and c.animate) then
        for i, _ in pairs(cp.fufAnims) do cp.fufAnims[i] = nil; Fade(cp, i, 1) end
        cp.fufHolder:SetScript("OnUpdate", nil)
        for i = 1, max do ShowPip(cp, i, i <= cur and 1 or 0) end
    else
        -- spent points fade out together; new ones are written one after the other
        -- (tally: the pencil is lifted a moment between two strokes)
        local d = 0
        for i = 1, max do
            local was = i <= shown
            local is = i <= cur
            if is and not was then
                local dur = tally and StrokeTime(L, i, speed) or 0.18 / speed
                StartAnim(cp, i, 1, d, dur)
                d = d + (tally and (dur + 0.06 / speed) or dur * 0.35)
            elseif was and not is then
                StartAnim(cp, i, 0, 0, (tally and 0.25 or 0.22) / speed)
            elseif not cp.fufAnims[i] then
                ShowPip(cp, i, is and 1 or 0)
            end
        end
    end
    -- nothing above max
    for i = max + 1, MAX_PIPS do
        if cp[i] then cp[i]:Hide() end
        local s = cp.fufStrokes[i]
        if s then s.ink:Hide(); s.shadow:Hide(); s.ghost:Hide() end
    end
    cp.fufShown = cur
    cp.fufCur, cp.fufMax = cur, max
end
ns.ComboRender = Render

-- ------------------------------------------------------------ layout (sizes, positions, look of the empty points)
function ns.ComboLayout(cp, max)
    local c = cp.fufCfg
    local holder = cp.fufHolder
    if not c then return end
    max = max or cp.fufMax or 5
    local style = c.style or "BARS"
    local hw, hh = holder:GetWidth(), holder:GetHeight()
    local gap = tonumber(c.gap) or 2
    local L = { style = style, max = max }
    cp.fufLayout = L
    local bShown, bColor, bSize = ns.ResolveBorder(c.border, ns.Global().border)
    local empty = c.emptyColor or { 0.12, 0.12, 0.13, 1 }
    local alignK = (c.align == "LEFT" and 0) or (c.align == "RIGHT" and 1) or 0.5

    if style == "TALLY" then
        for i = 1, MAX_PIPS do if cp[i] then cp[i]:Hide() end end
        local size = hh
        -- same shapes until a new series, or until the settings that shape them change
        local key = table.concat({ max, size, tostring(c.tallyGap), tostring(c.irregular), tostring(c.line) }, "|")
        if cp.fufReroll or not cp.fufTally or cp.fufTally.key ~= key then
            local segs, minX, width = TallyShapes(c, max, size)
            cp.fufTally = { key = key, segs = segs, minX = minX, width = width }
        end
        cp.fufReroll = nil
        local T = cp.fufTally
        L.segs, L.thick = T.segs, math.max(1, tonumber(c.thickness) or 3)
        L.shadow = bShown and math.max(0.5, bSize) or nil
        L.ox, L.oy = (hw - T.width) * alignK - T.minX, 0
        local tex = TALLY_LINES[c.line or 1] or TALLY_LINES[1]
        for i = 1, MAX_PIPS do
            local s = cp.fufStrokes[i]
            if s.fufTex ~= tex then
                for _, t in pairs(s) do if type(t) == "table" and t.SetTexture then t:SetTexture(tex) end end
                s.fufTex = tex
            end
            if i <= max then
                s.shadow:SetVertexColor(bColor[1], bColor[2], bColor[3], bColor[4] or 1)
                -- empty marks: a faint pencil line
                if c.tallyEmpty then
                    s.ghost:SetVertexColor(empty[1], empty[2], empty[3], math.max(0.25, empty[4] or 1))
                    DrawLine(s.ghost, holder, L.ox, L.oy, L.segs[i], L.thick, 1)
                else
                    s.ghost:Hide()
                end
            else
                s.ghost:Hide(); s.ink:Hide(); s.shadow:Hide()
            end
        end
        return
    end

    for i = 1, MAX_PIPS do
        local s = cp.fufStrokes[i]
        if s then s.ghost:Hide(); s.ink:Hide(); s.shadow:Hide() end
    end
    local pw, ph
    if style == "BARS" then
        pw, ph = (hw - gap * (max - 1)) / max, hh
    elseif style == "VERTICAL" then
        pw, ph = math.max(2, math.floor(hh * 0.32 + 0.5)), hh
    else
        pw, ph = hh, hh
    end
    pw = math.max(1, pw)
    -- inset in pixels (a share of the smaller side)
    L.inset = math.floor(math.min(pw, ph) * math.min(0.45, math.max(0, tonumber(c.inset) or 0)) + 0.5)
    local total = pw * max + gap * (max - 1)
    local ox = (style == "BARS") and 0 or math.max(0, (hw - total) * alignK)
    local shape = SHAPE[style]
    local fillTex = (style == "BARS") and ns.Texture() or (shape or WHITE)
    for i = 1, MAX_PIPS do
        local pip = cp[i]
        if i <= max then
            pip:ClearAllPoints()
            pip:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", ox + (i - 1) * (pw + gap), 0)
            pip:SetSize(pw, ph)
            pip.fill:SetTexture(fillTex)
            pip.bg:SetTexture(shape or WHITE)
            pip.bg:ClearAllPoints(); pip.bg:SetAllPoints(pip)
            pip.bg:SetVertexColor(empty[1], empty[2], empty[3], empty[4] or 1)
            pip.bg:SetShown(c.showEmpty and true or false)
            if shape then
                -- round / star shapes: the outline is the same shape, a little larger, behind
                if ns.EdgesShown then ns.EdgesShown(pip, false) end
                pip.outline:SetTexture(shape)
                pip.outline:ClearAllPoints()
                pip.outline:SetPoint("CENTER", pip, "CENTER", 0, 0)
                local o = bSize * (style == "STARS" and 2.4 or 2)
                pip.outline:SetSize(pw + o, ph + o)
                pip.outline:SetVertexColor(bColor[1], bColor[2], bColor[3], bColor[4] or 1)
                pip.outline:SetShown(bShown and true or false)
            else
                pip.outline:Hide()
                ns.ApplyBorder(pip, c.border, ns.Global().border)
            end
            pip:Show()
        else
            pip:Hide()
        end
    end
end

-- ------------------------------------------------------------ oUF hooks
-- oUF calls this instead of its own update (power events, form / spec changes).
-- This oUF passes the element too: Override(frame, element, event, unit, powerType).
local function Override(self, element, event, unit, powerType)
    local cp = self.ClassPower
    if not cp or not cp.fufLayout then return end
    if event == "ClassPowerDisable" then cp.fufCanvas:Hide(); cp.fufShown = 0; return end
    if unit and unit ~= "player" and unit ~= "vehicle" then return end
    if (event == "UNIT_POWER_FREQUENT" or event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER")
        and powerType and powerType ~= (TOKEN[cp.classPowerID] or powerType) and powerType ~= "COMBO_POINTS" then return end
    ns.ComboRefresh(cp, event ~= "ClassPowerEnable")
end

-- read the value and draw it; right after a target change everything snaps (no animation)
function ns.ComboRefresh(cp, animate)
    if cp.fufSample then return end
    local cur, max = ReadPoints(cp)
    if not cur then cp.fufCanvas:Hide(); cp.fufShown = 0; return end
    if cp.fufSnapUntil and now() < cp.fufSnapUntil then animate = false end
    Render(cp, cur, max, animate)
end

local function OnEvent(holder, event)
    local cp = holder.fufCP
    if event == "PLAYER_TARGET_CHANGED" then
        cp.fufSnapUntil = now() + 0.4
        ns.ComboRefresh(cp, false)
        -- the server can update the points of the new target a moment later
        if C_Timer and C_Timer.After then
            C_Timer.After(0.05, function() ns.ComboRefresh(cp, false) end)
            C_Timer.After(0.25, function() ns.ComboRefresh(cp, false) end)
        end
    else
        ns.ComboRefresh(cp, event ~= "PLAYER_ENTERING_WORLD")
    end
end

function ns.ComboBuild(frame)
    local holder = CreateFrame("Frame", nil, frame)
    holder:SetFrameLevel(frame:GetFrameLevel() + 2)
    -- everything is drawn on a canvas: the holder's visibility belongs to the "Show" setting,
    -- the canvas hides when the class has no points (druid out of cat form...)
    local canvas = CreateFrame("Frame", nil, holder)
    canvas:SetAllPoints(holder)
    local cp = { fufHolder = holder, fufCanvas = canvas, fufStrokes = {}, fufAnims = {} }
    for i = 1, MAX_PIPS do
        cp[i] = NewPip(canvas)
        cp.fufStrokes[i] = NewStroke(canvas)
    end
    cp.Override = Override
    cp.UpdateColor = function() end            -- colours are ours
    cp.fufFade, cp.fufFadeDone = Fade, FadeDone
    holder.fufCP = cp
    holder:RegisterEvent("PLAYER_TARGET_CHANGED")
    holder:RegisterEvent("PLAYER_ENTERING_WORLD")
    if holder.RegisterUnitEvent then
        holder:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
        holder:RegisterUnitEvent("UNIT_MAXPOWER", "player")
    end
    holder:SetScript("OnEvent", OnEvent)
    frame.ClassPower = cp
    return cp
end

-- settings changed: rebuild the layout and redraw (the holder is already placed and sized)
function ns.ComboApply(cp, c)
    cp.fufCfg = c
    cp.fufReroll = true
    cp.fufLayout = { style = c.style or "BARS", max = -1 }
    ns.ComboLayout(cp, cp.fufMax or 5)
    if cp.fufSample then return end
    ns.ComboRefresh(cp, false)
end

-- options preview / test mode: 3 of 5. replay = draw them again with the animation
function ns.ComboSample(cp, c, replay)
    cp.fufSample = true
    cp.fufCfg = c
    ns.ComboLayout(cp, 5)
    if replay then cp.fufShown = 0 end
    Render(cp, 3, 5, replay and true or false)
end
function ns.ComboLive(cp)
    if cp.fufSample then cp.fufSample = nil; cp.fufShown = 0 end
end
