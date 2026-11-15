-- FreeUnitFrames - spawning, positions, movers, test mode

local ADDON, ns = ...
local oUF = ns.oUF

local frames = {}    -- key -> { frame, ... }   (every styled frame)
local objects = {}   -- key -> single frame or header (what gets positioned)
local holders = {}   -- key -> plain anchor frame
local unlocked, testMode = false, false

local spawningPreview = false
function ns.RegisterFrame(frame)
    if spawningPreview then return end   -- the options preview is not one of the real frames
    local key = frame.fufKey
    frames[key] = frames[key] or {}
    table.insert(frames[key], frame)
end

function ns.IsSpawningPreview() return spawningPreview end
function ns.IsUnlocked() return unlocked end
function ns.IsTestMode() return testMode end
function ns.Object(key) return objects and objects[key] end

-- ------------------------------------------------------------ holders (positions)
local function Holder(key)
    local h = holders[key]
    if not h then
        h = CreateFrame("Frame", "FreeUnitFrames_" .. key .. "Holder", UIParent)
        h:SetSize(10, 10)
        h:SetClampedToScreen(true)
        h:SetMovable(true)
        holders[key] = h
    end
    return h
end

-- A frame can be attached to another one: its holder is then pinned (top-left corner to
-- top-left corner) to the other holder, so moving the parent moves the attached frames too.
local function Creates_Cycle(key, to)
    local n, t = 0, to
    while t and n < 20 do
        if t == key then return true end
        local c = ns.Unit(t)
        t = c and c.attachTo
        n = n + 1
    end
    return false
end
ns.AttachCycle = Creates_Cycle

local function AttachTarget(key)
    local cfg = ns.Unit(key)
    local to = cfg and cfg.attachTo
    if not to or to == key or not ns.Unit(to) or Creates_Cycle(key, to) then return nil end
    return to
end
ns.AttachTarget = AttachTarget

local function PlaceHolder(key)
    local cfg = ns.Unit(key)
    local h = Holder(key)
    h:ClearAllPoints()
    local to = AttachTarget(key)
    if to then
        local ap = cfg.attachPos or { 0, 0 }
        h:SetPoint("TOPLEFT", Holder(to), "TOPLEFT", ap[1] or 0, ap[2] or 0)
        return
    end
    local pos = cfg.pos
    h:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3])
end

-- rect of a holder in UIParent units
local function HolderRect(key)
    local h = holders[key]
    if not h then return nil end
    local l, b, w, hh = h:GetRect()
    if not l then return nil end
    local s = h:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return l * s, b * s, w * s, hh * s
end

-- store where a holder is (rect l, b, w, h) as its saved place: screen anchor, or offset from its parent
local function StorePlace(key, l, b, w, hh)
    local cfg = ns.Unit(key)
    local to = AttachTarget(key)
    if to then
        local pl, pb, pw, ph = HolderRect(to)
        if pl then
            cfg.attachPos = { math.floor(l - pl + 0.5), math.floor((b + hh) - (pb + ph) + 0.5) }
            return
        end
    end
    if type(cfg.pos) ~= "table" then cfg.pos = { "CENTER", 0, 0 } end
    local point = cfg.pos[1] or "CENTER"
    local sx, sy = UIParent:GetSize()
    local x, y
    if point:find("LEFT") then x = l elseif point:find("RIGHT") then x = l + w - sx else x = l + w / 2 - sx / 2 end
    if point:find("TOP") then y = b + hh - sy elseif point:find("BOTTOM") then y = b else y = b + hh / 2 - sy / 2 end
    cfg.pos = { point, math.floor(x + 0.5), math.floor(y + 0.5) }
end

-- attach `key` to the frame `to` (nil = detach). The frame stays exactly where it is.
function ns.Attach(key, to)
    if InCombatLockdown() then return false end
    local cfg = ns.Unit(key)
    if not cfg then return false end
    if to == key or (to and (not ns.Unit(to) or Creates_Cycle(key, to))) then return false end
    local l, b, w, hh = HolderRect(key)
    cfg.attachTo = to
    if l then StorePlace(key, l, b, w, hh) elseif to then cfg.attachPos = { 0, 0 } end
    PlaceHolder(key)
    if ns.UpdateMover then ns.UpdateMover(key) end
    if ns.OnChanged then ns.OnChanged() end
    return true
end

-- frames that may be chosen as parent of `key`
function ns.AttachChoices(key)
    local out = {}
    for _, u in ipairs(ns.UNITS) do
        if u ~= key and not Creates_Cycle(key, u) then out[#out + 1] = u end
    end
    return out
end

-- size of the holder = size of what it holds (headers: estimated)
local function HolderSize(key)
    local cfg = ns.Unit(key)
    local w, h = cfg.width, cfg.height
    local g = cfg.group
    if key == "party" or key == "boss" then
        local n = (key == "party") and 5 or 5
        if g.growth == "UP" or g.growth == "DOWN" then h = n * h + (n - 1) * g.spacing else w = n * w + (n - 1) * g.spacing end
    elseif key == "raid" then
        local per, groups = g.unitsPerGroup, g.numGroups
        if g.growth == "UP" or g.growth == "DOWN" then
            h = per * h + (per - 1) * g.spacing
            w = groups * w + (groups - 1) * g.groupSpacing
        else
            w = per * w + (per - 1) * g.spacing
            h = groups * h + (groups - 1) * g.groupSpacing
        end
    end
    return w, h
end

-- ------------------------------------------------------------ headers
local GROWTH = {
    DOWN  = { point = "TOP",    x = 0,  y = -1, start = "TOP" },
    UP    = { point = "BOTTOM", x = 0,  y = 1,  start = "BOTTOM" },
    RIGHT = { point = "LEFT",   x = 1,  y = 0,  start = "LEFT" },
    LEFT  = { point = "RIGHT",  x = -1, y = 0,  start = "RIGHT" },
}
local COLUMN_ANCHOR = { RIGHT = "LEFT", LEFT = "RIGHT", DOWN = "TOP", UP = "BOTTOM" }

local function CornerFor(growth, groupGrowth)
    local v = (growth == "UP" or groupGrowth == "UP") and "BOTTOM" or "TOP"
    local h = (growth == "LEFT" or groupGrowth == "LEFT") and "RIGHT" or "LEFT"
    return v .. h
end

local function ConfigFunc(cfg)
    return format([[
        self:SetWidth(%d)
        self:SetHeight(%d)
    ]], cfg.width, cfg.height)
end

local function HeaderVisibility(key)
    local cfg = ns.Unit(key)
    if not cfg.enable then return "custom hide" end
    if testMode then return "custom show" end
    if key == "party" then
        return cfg.group.showSolo and "custom [@raid6,exists] hide; show" or "custom [@raid6,exists] hide; [group] show; hide"
    elseif key == "raid" then
        return cfg.group.raidOnly and "custom [@raid6,exists] show; hide" or "custom [group] show; hide"
    end
end

local function ApplyHeaderAttributes(header, key)
    local cfg = ns.Unit(key)
    local g = cfg.group
    local gr = GROWTH[g.growth] or GROWTH.DOWN
    header:SetAttribute("oUF-initialConfigFunction", ConfigFunc(cfg))
    header:SetAttribute("point", gr.point)
    header:SetAttribute("xOffset", gr.x * g.spacing)
    header:SetAttribute("yOffset", gr.y * g.spacing)
    header:SetAttribute("showPlayer", g.showPlayer and true or false)
    if key == "raid" then
        header:SetAttribute("groupFilter", g.groupFilter)
        header:SetAttribute("groupBy", g.groupBy ~= "NONE" and g.groupBy or nil)
        header:SetAttribute("groupingOrder", g.groupBy == "CLASS"
            and "WARRIOR,PALADIN,ROGUE,HUNTER,SHAMAN,DRUID,PRIEST,MAGE,WARLOCK,DEATHKNIGHT,MONK,DEMONHUNTER,EVOKER"
            or (g.groupBy == "ASSIGNEDROLE" and "TANK,HEALER,DAMAGER,NONE" or "1,2,3,4,5,6,7,8"))
        header:SetAttribute("maxColumns", g.numGroups)
        header:SetAttribute("unitsPerColumn", g.unitsPerGroup)
        header:SetAttribute("columnSpacing", g.groupSpacing)
        header:SetAttribute("columnAnchorPoint", COLUMN_ANCHOR[g.groupGrowth] or "LEFT")
        header:SetAttribute("sortMethod", "INDEX")
    end
    -- resize existing children (out of combat only)
    for i = 1, select("#", header:GetChildren()) do
        local child = select(i, header:GetChildren())
        if child and child.fufKey then child:SetSize(cfg.width, cfg.height) end
    end
end

local function TestAttributes(header, key)
    if testMode then
        local n = (key == "raid") and math.min(40, ns.Unit(key).group.unitsPerGroup * ns.Unit(key).group.numGroups) or 5
        header:SetAttribute("startingIndex", -(n - 1))
        header:SetAttribute("showSolo", true)
        header:SetAttribute("showParty", true)
        header:SetAttribute("showRaid", true)
    else
        header:SetAttribute("startingIndex", 1)
        header:SetAttribute("showSolo", key == "party" and ns.Unit(key).group.showSolo or false)
        header:SetAttribute("showParty", key == "party")
        header:SetAttribute("showRaid", key == "raid")
    end
end

local function SpawnHeader(key)
    local cfg = ns.Unit(key)
    local attrs = {
        ["oUF-initialConfigFunction"] = ConfigFunc(cfg),
        showParty = key == "party",
        showRaid = key == "raid",
        showPlayer = cfg.group.showPlayer,
        showSolo = (key == "party") and cfg.group.showSolo or false,
    }
    local header = oUF:SpawnHeader("FreeUnitFrames_" .. key, nil, attrs)
    header.fufKey = key
    return header
end

-- ------------------------------------------------------------ boss (5 single frames)
local function SpawnBoss()
    local list = {}
    for i = 1, 5 do
        local f = oUF:Spawn("boss" .. i, "FreeUnitFrames_Boss" .. i)
        list[i] = f
    end
    return list
end

local function PlaceBoss(list, cfg)
    local g = cfg.group
    local gr = GROWTH[g.growth] or GROWTH.DOWN
    local h = holders.boss
    for i, f in ipairs(list) do
        f:ClearAllPoints()
        if i == 1 then
            f:SetPoint(CornerFor(g.growth), h, CornerFor(g.growth), 0, 0)
        else
            local prev = list[i - 1]
            local opp = ({ TOP = "BOTTOM", BOTTOM = "TOP", LEFT = "RIGHT", RIGHT = "LEFT" })[gr.point]
            f:SetPoint(gr.point, prev, opp, gr.x * g.spacing, gr.y * g.spacing)
        end
    end
end

-- ------------------------------------------------------------ enable / disable single frames
local function SetSingleEnabled(f, on, unit)
    if on then
        if testMode then
            UnregisterUnitWatch(f)
            f:SetAttribute("unit", "player")
            f:Show()
        else
            f:SetAttribute("unit", unit)
            RegisterUnitWatch(f)
        end
    else
        UnregisterUnitWatch(f)
        f:Hide()
    end
end

-- ------------------------------------------------------------ public update API
-- global scale x frame scale. The object is scaled, its holder (position) is not:
-- the object is pinned to the holder with no offset, so it grows around that point.
function ns.UnitScale(key)
    local g, u = ns.Global(), ns.Unit(key)
    local s = (g and tonumber(g.scale) or 1) * (u and tonumber(u.scale) or 1)
    if not s or s <= 0 then s = 1 end
    return s
end

local function PositionObject(key)
    local obj = objects[key]
    local cfg = ns.Unit(key)
    PlaceHolder(key)
    local h = holders[key]
    local w, hh = HolderSize(key)
    local s = ns.UnitScale(key)
    h:SetSize(w * s, hh * s)
    if key == "boss" then
        for _, f in ipairs(obj) do f:SetScale(s) end
    else
        obj:SetScale(s)
    end
    if key == "boss" then
        PlaceBoss(obj, cfg)
    elseif key == "party" or key == "raid" then
        obj:ClearAllPoints()
        obj:SetPoint(CornerFor(cfg.group.growth, cfg.group.groupGrowth), h, CornerFor(cfg.group.growth, cfg.group.groupGrowth), 0, 0)
    else
        obj:ClearAllPoints()
        obj:SetPoint("CENTER", h, "CENTER", 0, 0)
    end
end

function ns.UpdateUnit(key)
    if not objects[key] then return end
    if InCombatLockdown() then ns.Queue(key); return end
    local cfg = ns.Unit(key)
    local obj = objects[key]
    if key == "party" or key == "raid" then
        ApplyHeaderAttributes(obj, key)
        TestAttributes(obj, key)
        obj:SetVisibility(HeaderVisibility(key))
    elseif key == "boss" then
        for i, f in ipairs(obj) do SetSingleEnabled(f, cfg.enable, "boss" .. i) end
    else
        SetSingleEnabled(obj, cfg.enable, key)
    end
    PositionObject(key)
    for _, f in ipairs(frames[key] or {}) do ns.Safe("apply " .. key, ns.ApplyFrame, f) end
    -- combo points can sit on the target frame: follow its size
    if key == "target" then
        for _, f in ipairs(frames.player or {}) do ns.Safe("apply player", ns.ApplyFrame, f) end
    end
    if ns.UpdateMover then ns.UpdateMover(key) end
end

function ns.UpdateAll()
    if InCombatLockdown() then ns.Queue(); return end
    for _, key in ipairs(ns.UNITS) do ns.Safe("update " .. key, ns.UpdateUnit, key) end
end

function ns.SpawnAll()
    for _, key in ipairs(ns.UNITS) do
        Holder(key)
        PlaceHolder(key)
        ns.Safe("spawn " .. key, function()
            if key == "party" or key == "raid" then
                objects[key] = SpawnHeader(key)
            elseif key == "boss" then
                objects[key] = SpawnBoss()
            else
                objects[key] = oUF:Spawn(key, "FreeUnitFrames_" .. key)
            end
        end)
    end
    ns.UpdateAll()
end

-- ------------------------------------------------------------ test mode
function ns.SetTestMode(on)
    if InCombatLockdown() then
        print("|cffff8a3dFreeUnitFrames|r: not available in combat.")
        return
    end
    testMode = on and true or false
    ns.UpdateAll()
    if ns.OnChanged then ns.OnChanged() end
end

-- leave test mode and lock movers when combat starts
-- (PLAYER_REGEN_DISABLED fires just before the combat lockdown begins)
local guard = CreateFrame("Frame")
guard:RegisterEvent("PLAYER_REGEN_DISABLED")
guard:SetScript("OnEvent", function()
    if testMode and not InCombatLockdown() then
        testMode = false
        ns.UpdateAll()
        if ns.OnChanged then ns.OnChanged() end
    end
    if unlocked then
        unlocked = false
        if ns.HideGridToolbar then ns.HideGridToolbar() end
        if not InCombatLockdown() then ns.UpdateAll() end
        if ns.UpdateMovers then ns.UpdateMovers() end
    end
end)

-- ------------------------------------------------------------ movers
local movers = {}
local barMovers = {}
local C_ACCENT = { 1.00, 0.54, 0.24 }

-- Unlock mode helpers from LibFreeGrid: optional grid overlay, snap to grid / to other frames, and a small
-- toolbar (with a Lock button) shown while unlocked. Settings live in FreeUnitFramesDB.grid (account-wide).
local LFG = LibStub and LibStub("LibFreeGrid-1.0", true)
local grid, gridBar
local function Grid()
    if not LFG then return nil end
    if not grid then
        local db = ns.GetDB()
        if not db then return nil end
        db.grid = db.grid or {}
        grid = LFG:Attach(db.grid)
    end
    return grid
end
ns.Grid = Grid
local function GridToolbar()
    local g = Grid()
    if not g then return nil end
    if not gridBar then
        gridBar = g:Toolbar(g.settings, function() end, function() ns.SetUnlocked(false) end, "Free Unit Frames")
    end
    return gridBar
end
ns.GridToolbar = GridToolbar
function ns.HideGridToolbar() if gridBar then gridBar:Hide() end end
-- rects (left, bottom, width, height in UIParent units) of the other visible movers
local function OtherRects(skipKey, skipFrame)
    local out = {}
    local function add(f, ref)
        if f == skipFrame or not f:IsShown() then return end
        local l, b, w, h = f:GetRect()
        if not l then return end
        local s = (ref or f):GetEffectiveScale() / UIParent:GetEffectiveScale()
        out[#out + 1] = { l * s, b * s, w * s, h * s }
    end
    for k, om in pairs(movers) do
        if k ~= skipKey and holders[k] then add(holders[k]) end
    end
    return out, add
end

-- Snap a moved frame (rect in screen units) to the edges and centres of the other frames
-- and to the centre of the screen. Returns the corrected left / bottom.
local SNAP = 10
local function Snap(key, l, b, w, h)
    local sx, sy = UIParent:GetSize()
    local xs, ys = { sx / 2 - w / 2 }, { sy / 2 - h / 2 }
    for k, om in pairs(movers) do
        local oh = holders[k]
        if k ~= key and om:IsShown() and oh then
            local ol, ob, ow, ohh = oh:GetRect()
            if ol then
                local s = oh:GetEffectiveScale() / UIParent:GetEffectiveScale()
                ol, ob, ow, ohh = ol * s, ob * s, ow * s, ohh * s
                -- same left / right edge, side by side (touching), same centre
                for _, x in ipairs({ ol, ol + ow - w, ol + ow, ol - w, ol + ow / 2 - w / 2 }) do xs[#xs + 1] = x end
                for _, y in ipairs({ ob, ob + ohh - h, ob + ohh, ob - h, ob + ohh / 2 - h / 2 }) do ys[#ys + 1] = y end
            end
        end
    end
    local function best(v, list)
        local bestV, bestD = v, SNAP + 1
        for _, c in ipairs(list) do
            local d = math.abs(c - v)
            if d < bestD then bestV, bestD = c, d end
        end
        return bestV
    end
    return best(l, xs), best(b, ys)
end

local function Mover(key)
    local m = movers[key]
    if m then return m end
    local h = holders[key]
    if not h then return nil end
    m = CreateFrame("Button", nil, UIParent)
    m:SetFrameStrata("HIGH")   -- under the options window (DIALOG), over the frames
    m:SetAllPoints(h)
    m:RegisterForDrag("LeftButton")
    m:EnableMouse(true)
    local bg = m:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetTexture(ns.WHITE); bg:SetVertexColor(0.07, 0.074, 0.085, 0.55)
    ns.Edges(m, "BORDER", 1)
    ns.EdgeColor(m, C_ACCENT[1], C_ACCENT[2], C_ACCENT[3], 0.9)
    local label = m:CreateFontString(nil, "OVERLAY")
    label:SetFont("Fonts\\ARIALN.TTF", 12, "OUTLINE")
    label:SetPoint("CENTER")
    label:SetText(ns.UNIT_LABEL[key])
    label:SetTextColor(C_ACCENT[1], C_ACCENT[2], C_ACCENT[3])
    m:SetScript("OnDragStart", function() if not InCombatLockdown() then h:StartMoving() end end)
    m:SetScript("OnDragStop", function()
        h:StopMovingOrSizing()
        -- store relative to the chosen anchor point of the screen (or to the parent frame)
        local l, b, w, hh = HolderRect(key)
        if not l then return end
        local g = Grid()
        if g then
            local others = OtherRects(key)
            for id, bm in pairs(barMovers) do
                if bm:IsShown() then
                    local bl, bb, bw, bh = bm:GetRect()
                    if bl then others[#others + 1] = { bl, bb, bw, bh } end
                end
            end
            l, b = g:Snap(l, b, w, hh, others)                           -- LibFreeGrid (Alt = free)
        elseif not IsAltKeyDown() then l, b = Snap(key, l, b, w, hh) end -- hold Alt to place freely
        StorePlace(key, l, b, w, hh)
        PlaceHolder(key)
        if ns.OnChanged then ns.OnChanged() end
    end)
    m:SetScript("OnMouseWheel", function(_, d)
        local cfg = ns.Unit(key)
        if AttachTarget(key) then
            cfg.attachPos = cfg.attachPos or { 0, 0 }
            if IsShiftKeyDown() then cfg.attachPos[1] = cfg.attachPos[1] + d else cfg.attachPos[2] = cfg.attachPos[2] + d end
        else
            if IsShiftKeyDown() then cfg.pos[2] = cfg.pos[2] + d else cfg.pos[3] = cfg.pos[3] + d end
        end
        PlaceHolder(key)
        if ns.OnChanged then ns.OnChanged() end
    end)
    m:RegisterForClicks("RightButtonUp")
    m:SetScript("OnClick", function(self, button)
        if button == "RightButton" then ns.ShowAttachMenu(key, self) end
    end)
    m.sub = m:CreateFontString(nil, "OVERLAY")
    m.sub:SetFont("Fonts\\ARIALN.TTF", 10, "OUTLINE")
    m.sub:SetPoint("TOP", label, "BOTTOM", 0, -1)
    m.sub:SetTextColor(0.85, 0.85, 0.9)
    m:EnableMouseWheel(true)
    m:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(ns.UNIT_LABEL[key], C_ACCENT[1], C_ACCENT[2], C_ACCENT[3])
        GameTooltip:AddLine("Drag to move: snaps to the other frames, the screen centre and the grid when enabled in the Unlock toolbar (hold Alt to place freely). Mouse wheel: up/down, Shift + wheel: left/right.", 1, 1, 1, true)
        local to = AttachTarget(key)
        if to then
            GameTooltip:AddLine("Attached to " .. ns.UNIT_LABEL[to] .. ": it moves with it.", 0.6, 1, 0.6, true)
            GameTooltip:AddLine("Right-click: attach to another frame, or detach.", 0.8, 0.8, 0.85, true)
        else
            GameTooltip:AddLine("Right-click: attach to another frame, so they move together.", 0.8, 0.8, 0.85, true)
        end
        GameTooltip:Show()
    end)
    m:SetScript("OnLeave", function() GameTooltip:Hide() end)
    movers[key] = m
    return m
end

-- movers for bars that float freely on the screen (power, castbar, combo points of single frames)
local BAR_LABEL = { power = "power", castbar = "castbar", classPower = "combo points", enchants = "weapon enchants", happiness = "happiness" }
local BAR_KINDS = { "power", "castbar", "classPower", "enchants", "happiness" }
-- the settings table of a floating element (weapon enchants live inside the buffs settings)
local function BarCfg(cfg, which)
    if which == "enchants" then return cfg.buffs and cfg.buffs.enchants end
    return cfg[which]
end
local function BarRegion(f, which)
    if which == "power" then return f.Power
    elseif which == "castbar" then return f.Castbar
    elseif which == "enchants" then return f.fufEnchants
    elseif which == "happiness" then return ns.HappinessFrame and ns.HappinessFrame()
    else return f.ClassPower and f.ClassPower.fufHolder end
end
local function BarFloating(cfg, which)
    local c = BarCfg(cfg, which)
    if not c or not c.enable then return false end
    if which == "power" then return c.detach == "SCREEN" end
    if which == "enchants" or which == "happiness" then return c.place == "SCREEN" end
    return c.onScreen and true or false
end
local function BarMover(key, which)
    local id = key .. "." .. which
    local m = barMovers[id]
    if m then return m end
    m = CreateFrame("Button", nil, UIParent)
    m:SetFrameStrata("HIGH")   -- under the options window (DIALOG), over the frames
    m:SetMovable(true)
    m:RegisterForDrag("LeftButton")
    m:EnableMouse(true)
    local bg = m:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetTexture(ns.WHITE); bg:SetVertexColor(0.07, 0.074, 0.085, 0.55)
    ns.Edges(m, "BORDER", 1)
    ns.EdgeColor(m, C_ACCENT[1], C_ACCENT[2], C_ACCENT[3], 0.9)
    local label = m:CreateFontString(nil, "OVERLAY")
    label:SetFont("Fonts\\ARIALN.TTF", 11, "OUTLINE")
    label:SetPoint("CENTER")
    label:SetText(ns.UNIT_LABEL[key] .. " " .. BAR_LABEL[which])
    label:SetTextColor(C_ACCENT[1], C_ACCENT[2], C_ACCENT[3])
    local function save()
        local c = BarCfg(ns.Unit(key), which)
        c.screen = c.screen or { "CENTER", 0, 0 }
        local point = c.screen[1] or "CENTER"
        local sx, sy = UIParent:GetSize()
        local l, b, w, hh = m:GetRect()
        if not l then return end
        local x, y
        if point:find("LEFT") then x = l elseif point:find("RIGHT") then x = l + w - sx else x = l + w / 2 - sx / 2 end
        if point:find("TOP") then y = b + hh - sy elseif point:find("BOTTOM") then y = b else y = b + hh / 2 - sy / 2 end
        c.screen = { point, math.floor(x + 0.5), math.floor(y + 0.5) }
    end
    m:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        local l, t = self:GetLeft(), self:GetTop()
        local w, h = self:GetSize()
        self:ClearAllPoints()
        self:SetSize(w, h)
        if l and t then self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t) end
        self:StartMoving()
    end)
    m:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local g = Grid()
        local l, b, w, h = self:GetRect()
        if g and l then
            local others = OtherRects(nil, self)
            for id, bm in pairs(barMovers) do
                if bm ~= self and bm:IsShown() then
                    local bl, bb, bw, bh = bm:GetRect()
                    if bl then others[#others + 1] = { bl, bb, bw, bh } end
                end
            end
            local nl, nb = g:Snap(l, b, w, h, others)
            if nl ~= l or nb ~= b then
                self:ClearAllPoints()
                self:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", nl, nb)
            end
        end
        save()
        ns.UpdateUnit(key)
        if ns.OnChanged then ns.OnChanged() end
    end)
    m:SetScript("OnMouseWheel", function(_, d)
        local c = BarCfg(ns.Unit(key), which)
        c.screen = c.screen or { "CENTER", 0, 0 }
        if IsShiftKeyDown() then c.screen[2] = (c.screen[2] or 0) + d else c.screen[3] = (c.screen[3] or 0) + d end
        ns.UpdateUnit(key)
        if ns.OnChanged then ns.OnChanged() end
    end)
    m:EnableMouseWheel(true)
    m:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(ns.UNIT_LABEL[key] .. " " .. BAR_LABEL[which], C_ACCENT[1], C_ACCENT[2], C_ACCENT[3])
        GameTooltip:AddLine("Drag to move. Mouse wheel: up/down, Shift + wheel: left/right.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    m:SetScript("OnLeave", function() GameTooltip:Hide() end)
    barMovers[id] = m
    return m
end
local function UpdateBarMovers(key)
    local cfg = ns.Unit(key)
    local f = objects[key]
    for _, which in ipairs(BAR_KINDS) do
        local id = key .. "." .. which
        local region = f and type(f) == "table" and f.GetObjectType and BarRegion(f, which)
        -- the happiness icon lives on its own: it can be moved even with the pet frame turned off
        local show = unlocked and (cfg.enable or which == "happiness") and ns.CanFloat and ns.CanFloat(key) and region and BarFloating(cfg, which)
        if show then
            local m = BarMover(key, which)
            m:ClearAllPoints()
            m:SetAllPoints(region)
            m:Show()
        elseif barMovers[id] then
            barMovers[id]:Hide()
        end
    end
end

-- ------------------------------------------------------------ attach menu (right-click on a mover)
local menu
local function AttachMenu()
    if menu then return menu end
    menu = CreateFrame("Frame", "FreeUnitFramesAttachMenu", UIParent)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    menu:SetWidth(190)
    local bg = menu:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetTexture(ns.WHITE); bg:SetVertexColor(0.09, 0.094, 0.105, 0.97)
    ns.Edges(menu, "BORDER", 1)
    ns.EdgeColor(menu, C_ACCENT[1], C_ACCENT[2], C_ACCENT[3], 0.8)
    menu.title = menu:CreateFontString(nil, "OVERLAY")
    menu.title:SetFont("Fonts\\ARIALN.TTF", 12, "OUTLINE")
    menu.title:SetPoint("TOPLEFT", 10, -8)
    menu.title:SetTextColor(C_ACCENT[1], C_ACCENT[2], C_ACCENT[3])
    menu.rows = {}
    tinsert(UISpecialFrames, "FreeUnitFramesAttachMenu")
    -- close when the mouse has left it for a moment
    menu:SetScript("OnUpdate", function(self, el)
        if self:IsMouseOver(6, -6, -6, 6) then self.away = 0 else
            self.away = (self.away or 0) + el
            if self.away > 1.2 then self:Hide() end
        end
    end)
    return menu
end

function ns.ShowAttachMenu(key, owner)
    if InCombatLockdown() then return end
    local mn = AttachMenu()
    local items = {}
    local cur = AttachTarget(key)
    for _, u in ipairs(ns.AttachChoices(key)) do
        items[#items + 1] = { text = "Attach to " .. ns.UNIT_LABEL[u], to = u, on = (cur == u) }
    end
    if cur then items[#items + 1] = { text = "Detach (place on the screen)", detach = true } end
    mn.title:SetText(ns.UNIT_LABEL[key])
    for i, it in ipairs(items) do
        local r = mn.rows[i]
        if not r then
            r = CreateFrame("Button", nil, mn)
            r:SetHeight(20)
            r.hl = r:CreateTexture(nil, "HIGHLIGHT"); r.hl:SetAllPoints(); r.hl:SetTexture(ns.WHITE); r.hl:SetVertexColor(1, 1, 1, 0.08)
            r.text = r:CreateFontString(nil, "OVERLAY"); r.text:SetFont("Fonts\\ARIALN.TTF", 12, ""); r.text:SetPoint("LEFT", 10, 0)
            mn.rows[i] = r
        end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 1, -24 - (i - 1) * 20); r:SetPoint("TOPRIGHT", -1, -24 - (i - 1) * 20)
        r.text:SetText(it.text)
        if it.on then r.text:SetTextColor(C_ACCENT[1], C_ACCENT[2], C_ACCENT[3])
        elseif it.detach then r.text:SetTextColor(1, 0.55, 0.5)
        else r.text:SetTextColor(0.9, 0.9, 0.92) end
        r:SetScript("OnClick", function()
            mn:Hide()
            if it.detach then ns.Attach(key, nil) else ns.Attach(key, it.to) end
        end)
        r:Show()
    end
    for i = #items + 1, #mn.rows do mn.rows[i]:Hide() end
    mn:SetHeight(30 + #items * 20)
    mn:ClearAllPoints()
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    mn:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / s - 10, y / s + 10)
    mn.away = 0
    mn:Show()
end

function ns.UpdateMover(key)
    local cfg = ns.Unit(key)
    local m = (unlocked and cfg.enable and objects[key]) and Mover(key)
    if m then
        local to = AttachTarget(key)
        m.sub:SetText(to and ("attached to " .. ns.UNIT_LABEL[to]) or "")
        m:Show()
    elseif movers[key] then movers[key]:Hide() end
    UpdateBarMovers(key)
end

function ns.UpdateMovers()
    for _, key in ipairs(ns.UNITS) do ns.UpdateMover(key) end
    if ns.OnChanged then ns.OnChanged() end
end

function ns.SetUnlocked(on)
    if on and InCombatLockdown() then
        print("|cffff8a3dFreeUnitFrames|r: frames cannot be moved in combat.")
        return
    end
    unlocked = on and true or false
    if not unlocked and menu then menu:Hide() end
    local bar = GridToolbar()
    if bar then if unlocked then bar:Show() else bar:Hide() end end
    ns.UpdateAll()          -- shows / hides the sample indicator icons
    ns.UpdateMovers()
end

-- ------------------------------------------------------------ options preview
-- A plain (non secure) copy of a unit frame showing the player, drawn inside the options.
-- It is not clickable, works in combat, and shows sample auras / cast / icons.
local previewFrame, previewFailed
function ns.PreviewFrame(parent)
    if previewFrame or previewFailed then return previewFrame end
    if not oUF or not oUF.Spawn then previewFailed = true; return nil end
    -- check that the plain template exists on this client
    local okT = pcall(CreateFrame, "Frame", nil, nil, "BackdropTemplate")
    local template = okT and "BackdropTemplate" or nil
    if not template then previewFailed = true; return nil end
    spawningPreview = true
    local f
    ns.Safe("preview", function() f = oUF:Spawn("player", "FreeUnitFrames_OptionsPreview", template) end)
    spawningPreview = false
    if not f then previewFailed = true; return nil end
    if UnregisterUnitWatch then pcall(UnregisterUnitWatch, f) end
    f.fufIsPreview = true
    f:EnableMouse(false)
    f:SetParent(parent)
    f:ClearAllPoints()
    f:SetPoint("CENTER", parent, "CENTER", 0, 0)
    previewFrame = f
    return f
end

-- show `key`'s settings on the preview frame, scaled to fit `maxW`
function ns.UpdatePreview(key, maxW)
    local f = previewFrame
    if not f then return end
    if not key or key == "global" then key = "player" end
    local cfg = ns.Unit(key)
    if not cfg then return end
    f.fufKey = key
    local w = cfg.width or 200
    local s = ns.UnitScale(key)
    if maxW and w * s > maxW then s = maxW / w end
    f:SetScale(math.max(0.3, s))
    ns.Safe("apply preview", ns.ApplyFrame, f)
    f:Show()
end
