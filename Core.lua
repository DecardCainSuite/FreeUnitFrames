-- FreeUnitFrames - core: settings, media, tags, events
-- Unit frames built on oUF (MIT). Layout and options are our own code.

local ADDON, ns = ...
local oUF = ns.oUF
ns.oUF = oUF

ns.MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
ns.WHITE = "Interface\\Buttons\\WHITE8x8"

-- ------------------------------------------------------------ units
-- order = order of the selector in the options window
ns.UNITS = { "player", "target", "targettarget", "focus", "focustarget", "pet", "party", "raid", "boss" }
ns.UNIT_LABEL = {
    player = "Player", target = "Target", targettarget = "Target of Target", focus = "Focus",
    focustarget = "Focus Target", pet = "Pet", party = "Party", raid = "Raid", boss = "Boss",
}
ns.UNIT_SHORT = {
    player = "Player", target = "Target", targettarget = "ToT", focus = "Focus",
    focustarget = "Focus T.", pet = "Pet", party = "Party", raid = "Raid", boss = "Boss",
}
ns.GROUP_UNITS = { party = true, raid = true, boss = true }

-- ------------------------------------------------------------ defaults
local function text(enable, format, point, x, y, size)
    return {
        enable = enable, format = format, point = point, x = x, y = y, size = size or 0,
        attach = "HEALTH",          -- HEALTH, POWER or FRAME
        font = "INHERIT",           -- INHERIT (General) or a font key
        width = 0,                  -- max width (0 = no limit, long text is cut)
        outline = "INHERIT",        -- INHERIT (General), NONE, OUTLINE, THICKOUTLINE
        useColor = false,           -- off: white, or the colour codes of the tags ([raidcolor]...)
        color = { 1, 1, 1 },
    }
end
ns.NewText = function(name)
    local t = text(true, "[name]", "CENTER", 0, 0)
    t.name = name
    t.id = tostring(math.floor((GetTime and GetTime() or 0) * 1000)) .. tostring(math.random(100, 999))
    return t
end

-- Aura filter presets. Each sets: who (all / mine / others), types (only auras with one
-- of these game flags; none ticked = no restriction), durationMode (any / timed / permanent)
-- and maxDuration (seconds, 0 = no limit).
ns.AURA_PRESETS = {
    { key = "all",         label = "Everything (Blizzard-like)", who = "all",    types = {}, durationMode = "any" },
    { key = "mine",        label = "Mine only",                  who = "mine",   types = {}, durationMode = "any" },
    { key = "others",      label = "Others only",                who = "others", types = {}, durationMode = "any" },
    { key = "dispellable", label = "What I can dispel",          who = "all",    types = { dispellable = true }, durationMode = "any" },
    { key = "raid",        label = "Raid-relevant",              who = "all",    types = { raid = true }, durationMode = "any" },
    { key = "cc",          label = "Crowd control",              who = "all",    types = { cc = true }, durationMode = "any" },
    { key = "defensive",   label = "Defensive cooldowns",        who = "all",    types = { defensive = true, external = true }, durationMode = "any" },
    { key = "timed",       label = "Timed only (no permanent)",  who = "all",    types = {}, durationMode = "timed" },
    { key = "permanent",   label = "Permanent only",             who = "all",    types = {}, durationMode = "permanent" },
    { key = "myshort",     label = "My short effects (< 1 min)", who = "mine",   types = {}, durationMode = "timed", maxDuration = 60 },
}
function ns.ApplyAuraPreset(c, key)
    for _, pr in ipairs(ns.AURA_PRESETS) do
        if pr.key == key then
            c.preset = key
            c.who = pr.who
            c.types = {}
            for k, v in pairs(pr.types) do c.types[k] = v end
            c.durationMode = pr.durationMode
            c.maxDuration = pr.maxDuration or 0
            return true
        end
    end
end
-- old settings (v0.1 had a single "filter" value)
local function MigrateAuraFilter(c)
    if c and c.filter ~= nil then
        ns.ApplyAuraPreset(c, c.filter == "dispellable" and "dispellable" or c.filter)
        c.filter = nil
    end
end

local function auras(enable, size, perRow, rows, side, gx, gy, x, y, filter)
    return {
        enable = enable, size = size, perRow = perRow, rows = rows, spacing = 2,
        side = side, growthX = gx, growthY = gy, x = x, y = y, filter = filter,
        anchorTo = "FRAME", showDuration = true, showCount = true, typeBorder = true,
        durationSize = 0, countSize = 0, durationPoint = "CENTER",   -- 0 = size from the icon size
        -- text look (duration numbers and stack counts): font INHERIT = General font; outline INHERIT = General outline
        durationFont = "INHERIT", durationOutline = "OUTLINE", durationColor = { 1, 1, 1 },
        countFont = "INHERIT", countOutline = "OUTLINE", countColor = { 1, 1, 1 },
    }
end

-- Temporary weapon enchants / poisons of the player (own row of icons). place: BUFFS = after the buff rows
-- (buff icon size and spacing), FRAME = detached, next to the unit frame, SCREEN = free on the screen (mover).
-- Never anchored to an aura container.
local function enchants()
    return {
        enable = true, place = "BUFFS",
        size = 0, spacing = 2,                      -- size 0 = the buff icon size (detached rows only)
        growth = "RIGHT",                           -- RIGHT, LEFT, UP, DOWN
        anchor = "BOTTOM", x = 0, y = -4,           -- FRAME: point of the unit frame the row hangs from
        screen = { "CENTER", 0, -120 },             -- SCREEN: point, x, y from the screen
        showDuration = true, showCount = true,      -- showCount = charges (poisons)
        durationSize = 0, countSize = 0, durationPoint = "CENTER",
        durationFont = "INHERIT", durationOutline = "OUTLINE", durationColor = { 1, 1, 1 },
        countFont = "INHERIT", countOutline = "OUTLINE", countColor = { 1, 1, 1 },
    }
end

local BASE = {
    enable = true,
    width = 220, height = 38,
    scale = 1,                  -- size of the whole frame (multiplied by the General scale)
    barAlpha = 1,               -- opacity of the health and power bars (texts stay opaque)
    -- borders: mode INHERIT (General settings), SHOW or HIDE; own colour / thickness optional
    border = { mode = "INHERIT", useColor = false, color = { 0, 0, 0, 1 }, size = 0 },
    pos = { "CENTER", 0, 0 },
    health = { colorClass = true, colorReaction = true, colorTapped = true, color = { 0.20, 0.21, 0.24 },
               bgMode = "dark", bgColor = { 0.12, 0.12, 0.13 }, bgMult = 0.3, reverse = false, vertical = false },
    power = { enable = true, position = "BOTTOM", height = 8, gap = 1, colorPower = true, colorClass = false, color = { 0.30, 0.50, 0.85 },
              bgMode = "dark", bgColor = { 0.12, 0.12, 0.13 }, bgMult = 0.3,
              -- detach: NONE (inside the frame), FRAME (own box next to the frame) or SCREEN (anywhere, single frames)
              detach = "NONE", detAnchor = "BOTTOM", detX = 0, detY = -4, detW = 0, detH = 0, screen = { "CENTER", 0, -200 },
              border = { mode = "INHERIT", useColor = false, color = { 0, 0, 0, 1 }, size = 0 } },
    portrait = { enable = false, style = "3D", side = "LEFT", width = 0,
                 anchor = "LEFT", size = 0, detHeight = 0, x = -4, y = 0, alpha = 0.35,
                 -- 3D model
                 zoom = 1, distance = 1, modelX = 0, modelY = 0, rotation = 0, desaturate = 0, paused = false,
                 background = true, bgColor = { 0.06, 0.06, 0.07, 1 },
                 border = { mode = "INHERIT", useColor = false, color = { 0, 0, 0, 1 }, size = 0 } },
    texts = {
        name   = text(true, "[raidcolor][name]", "TOPLEFT", 4, -3),
        health = text(true, "[fuf:hpstatus]", "BOTTOMRIGHT", -4, 3),
        power  = text(false, "[fuf:pp]", "BOTTOMLEFT", 4, 3),
        level  = text(true, "[difficulty][smartlevel]", "TOPRIGHT", -4, -3),
        custom = {},            -- extra texts added by the user
    },
    castbar = { enable = false, width = 0, height = 18, icon = true, showName = true, showTime = true, x = 0, y = -4,
                color = { 1.00, 0.54, 0.24 }, shieldColor = { 0.60, 0.60, 0.62 },
                colorClass = false,                                  -- players: class colour instead of the bar colour
                onScreen = false, screen = { "CENTER", 0, -240 },   -- free on the screen (single frames)
                border = { mode = "INHERIT", useColor = false, color = { 0, 0, 0, 1 }, size = 0 } },
    buffs   = auras(false, 22, 8, 1, "TOP", "RIGHT", "UP", 0, 2, "all"),
    debuffs = auras(false, 26, 7, 1, "TOP", "RIGHT", "UP", 0, 2, "all"),
    raidIcon  = { enable = true, size = 18, point = "TOP", x = 0, y = 8 },
    leader    = { enable = true, size = 14, point = "TOPLEFT", x = 2, y = 8 },
    combat    = { enable = false, size = 18, point = "CENTER", x = 0, y = 0 },
    resting   = { enable = false, size = 18, point = "TOPLEFT", x = -6, y = 8 },
    readyCheck = { enable = true, size = 18, point = "CENTER", x = 0, y = 0 },
    threat    = { enable = true },
    range     = { enable = false, alpha = 0.45 },
    classPower = { enable = false, height = 6, gap = 2, width = 0, where = "TARGET_TOP", visibility = "COMBAT_HOSTILE", onScreen = false, screen = { "CENTER", 0, -170 }, border = { mode = "INHERIT", useColor = false, color = { 0, 0, 0, 1 }, size = 0 },
                   -- look: BARS (fill the width), SQUARES, CIRCLES, DIAMONDS, STARS, VERTICAL (thin sticks), TALLY (hand-written marks)
                   style = "BARS", size = 16, thickness = 3, align = "CENTER",
                   colorMode = "POWER", color = { 1, 0.85, 0.2 }, color2 = { 1, 0.3, 0.15 },   -- POWER, CUSTOM, GRADIENT (color -> color2), CLASS
                   colorFull = false, fullColor = { 1, 0.25, 0.2 },                              -- other colour once every point is there
                   showEmpty = true, emptyColor = { 0.12, 0.12, 0.13, 1 },
                   inset = 0,                                                                    -- fill smaller than the point (share of its size)
                   animate = true, animSpeed = 1,
                   -- tally marks: line (1 hand-drawn, 2 pencil, 3 chalk, 4 plain), irregularity 0-2, new shapes each series,
                   -- space between marks (0 = auto), empty marks
                   line = 1, irregular = 1, newShapes = true, tallyGap = 0, tallyEmpty = false },
    -- hunter pet happiness: an icon on the pet frame (FRAME) or anywhere on the screen (SCREEN)
    happiness = { enable = false, style = "FACE", size = 20, place = "FRAME", point = "LEFT", x = -4, y = 0,
                  screen = { "CENTER", -485, -150 }, hideHappy = false, tooltip = true },
}

BASE.buffs.enchants = enchants()

local OVERRIDES = {
    player = {
        pos = { "CENTER", -310, -190 },
        texts = { level = { enable = false } },
        castbar = { enable = true },
        combat = { enable = true }, resting = { enable = true },
        classPower = { enable = true },
        debuffs = { enable = true, filter = "all" },
    },
    target = {
        pos = { "CENTER", 310, -190 },
        castbar = { enable = true },
        buffs = { enable = true, side = "BOTTOM", growthY = "DOWN", y = -4 },
        debuffs = { enable = true, filter = "mine" },
        range = { enable = true },
    },
    targettarget = {
        width = 120, height = 26, pos = { "CENTER", 505, -190 },
        power = { enable = false },
        texts = { name = { point = "CENTER", x = 0, y = 0 }, health = { enable = false }, level = { enable = false } },
        raidIcon = { size = 14 }, range = { enable = true },
    },
    focus = {
        width = 180, height = 30, pos = { "CENTER", 310, -275 },
        castbar = { enable = true },
        debuffs = { enable = true, size = 22, filter = "mine" },
        texts = { level = { enable = false } },
        range = { enable = true },
    },
    focustarget = {
        width = 120, height = 26, pos = { "CENTER", 470, -275 },
        power = { enable = false },
        texts = { name = { point = "CENTER", x = 0, y = 0 }, health = { enable = false }, level = { enable = false } },
        range = { enable = true },
    },
    pet = {
        width = 130, height = 26, pos = { "CENTER", -485, -190 },
        power = { height = 5 },
        texts = { health = { enable = false }, level = { enable = false } },
        range = { enable = true },
        happiness = { enable = true },
    },
    party = {
        width = 190, height = 40, pos = { "LEFT", 30, 120 },
        texts = { level = { enable = false } },
        buffs = { enable = false },
        debuffs = { enable = true, size = 24, side = "RIGHT", growthX = "RIGHT", growthY = "DOWN", x = 4, y = 0, filter = "all" },
        range = { enable = true },
        group = { growth = "DOWN", spacing = 26, showPlayer = true, showSolo = false },
    },
    raid = {
        width = 80, height = 40, pos = { "TOPLEFT", 30, -30 },
        power = { height = 4 },
        texts = {
            name = { format = "[raidcolor][name]", point = "CENTER", x = 0, y = 4, size = 11 },
            health = { format = "[fuf:status]", point = "CENTER", x = 0, y = -8, size = 10 },
            level = { enable = false },
        },
        debuffs = { enable = true, size = 16, perRow = 3, side = "BOTTOM", growthY = "UP", x = 2, y = 6, filter = "dispellable" },
        raidIcon = { size = 14 },
        leader = { size = 12 },
        range = { enable = true },
        group = { growth = "DOWN", spacing = 3, groupSpacing = 6, groupGrowth = "RIGHT", unitsPerGroup = 5, numGroups = 8,
                  groupBy = "GROUP", groupFilter = "1,2,3,4,5,6,7,8", showPlayer = true, raidOnly = true },
    },
    boss = {
        width = 200, height = 36, pos = { "RIGHT", -260, 160 },
        castbar = { enable = true },
        debuffs = { enable = true, filter = "mine", side = "LEFT", growthX = "LEFT", growthY = "DOWN", x = -4, y = 0, size = 24, perRow = 5 },
        range = { enable = true },
        group = { growth = "DOWN", spacing = 34 },
    },
}

local GLOBAL_DEFAULTS = {
    texture = "fuf-flat",
    bgTexture = "fuf-flat",
    font = "ARIALN",
    fontSize = 12,
    outline = "NONE",
    bgColor = { 0.06, 0.06, 0.07, 0.85 },
    borderColor = { 0, 0, 0, 1 },
    border = true,
    borderSize = 1,
    hideBlizzard = true,
    scale = 1,                  -- size of every frame (each frame can add its own scale)
}

local function copy(t)
    if type(t) ~= "table" then return t end
    local r = {}
    for k, v in pairs(t) do r[k] = copy(v) end
    return r
end
ns.Copy = copy

local function merge(dst, src) -- deep merge src into dst (src wins)
    for k, v in pairs(src) do
        if type(v) == "table" and type(dst[k]) == "table" and #v == 0 then merge(dst[k], v) else dst[k] = copy(v) end
    end
    return dst
end

local function fill(dst, def) -- add missing keys only
    for k, v in pairs(def) do
        if dst[k] == nil then dst[k] = copy(v)
        elseif type(v) == "table" and type(dst[k]) == "table" and #v == 0 then fill(dst[k], v) end
    end
    return dst
end

function ns.UnitDefaults(unit)
    local d = copy(BASE)
    merge(d, OVERRIDES[unit] or {})
    MigrateAuraFilter(d.buffs)
    MigrateAuraFilter(d.debuffs)
    return d
end

-- ------------------------------------------------------------ saved settings & profiles
-- FreeUnitFramesDB = {
--   profiles    = { [name] = { units = {...}, global = {...} } },
--   profileKeys = { ["Name - Realm"] = profileName },   -- which profile each character uses
--   minimap, errors, version                           -- account-wide
-- }
local db, prof, charKey
function ns.GetDB() return prof and db end
function ns.Unit(unit) return prof and prof.units[unit] end
function ns.Global() return prof and prof.global end

local function PrepareProfile(pr)
    pr.units = pr.units or {}
    for _, u in ipairs(ns.UNITS) do
        local old = pr.units[u]
        local had = old and old.debuffs and old.debuffs.filter
        local hadB = old and old.buffs and old.buffs.filter
        pr.units[u] = fill(old or {}, ns.UnitDefaults(u))
        if had then pr.units[u].debuffs.filter = had end
        if hadB then pr.units[u].buffs.filter = hadB end
        MigrateAuraFilter(pr.units[u].buffs)
        MigrateAuraFilter(pr.units[u].debuffs)
    end
    pr.global = fill(pr.global or {}, GLOBAL_DEFAULTS)
    pr.global.minimap = nil -- the minimap button is account-wide (db.minimap)
    return pr
end

local function InitDB()
    FreeUnitFramesDB = FreeUnitFramesDB or {}
    db = FreeUnitFramesDB
    db.profiles = db.profiles or {}
    db.profileKeys = db.profileKeys or {}
    -- v0.1/v0.2 kept one set of settings at the root: it becomes the "Default" profile
    local legacy = (db.units or db.global) and true or false
    if db.units or db.global then
        local old = db.global or {}
        db.minimap = db.minimap or old.minimap
        db.profiles.Default = db.profiles.Default or { units = db.units, global = old }
        db.units, db.global = nil, nil
    end
    db.minimap = db.minimap or { hide = false }
    db.grid = db.grid or {}          -- unlock mode: snap / grid settings (LibFreeGrid fills the defaults), account-wide
    db.preview = db.preview or {}    -- options preview: simulated class / unit type (nil = automatic)
    if (db.version or 0) < 2 then
        for _, pr in pairs(db.profiles) do if pr.global then pr.global.outline = "NONE" end end
    end
    db.version = 3
    local name, realm = UnitName("player"), GetRealmName()
    charKey = (name or "?") .. " - " .. (realm or "?")
    local pname = db.profileKeys[charKey]
    if not pname and legacy then
        pname = "Default"        -- settings migrated from v0.1/v0.2 stay on the shared Default profile
    elseif not pname then
        -- first login of this character: its own profile, a deep copy of "Default" (which holds the shipped defaults)
        db.profiles.Default = PrepareProfile(db.profiles.Default or {})
        pname = name or "Default"
        if not name or name == "?" then
            pname = "Default"
        elseif db.profiles[pname] then
            -- a profile with that name exists: reuse it unless another character already uses it
            for k, v in pairs(db.profileKeys) do if v == pname and k ~= charKey then pname = charKey; break end end
        end
        if not db.profiles[pname] then db.profiles[pname] = copy(db.profiles.Default) end
    end
    db.profiles[pname] = db.profiles[pname] or {}
    db.profileKeys[charKey] = pname
    prof = PrepareProfile(db.profiles[pname])
end

function ns.CurrentProfile() return db and db.profileKeys[charKey] end
function ns.ProfileList()
    local out = {}
    for name in pairs(db.profiles) do out[#out + 1] = name end
    table.sort(out)
    return out
end
local function Switched()
    if ns.UpdateAll then ns.UpdateAll() end
    if ns.OnChanged then ns.OnChanged() end
end
-- Use (and create if needed) a profile for this character. copyFrom: start as a copy of that profile.
function ns.SetProfile(name, copyFrom)
    if not name or name == "" then return end
    if InCombatLockdown() then print("|cffff8a3dFreeUnitFrames|r: profiles cannot be changed in combat."); return end
    if not db.profiles[name] then
        db.profiles[name] = (copyFrom and db.profiles[copyFrom]) and copy(db.profiles[copyFrom]) or {}
    end
    db.profileKeys[charKey] = name
    prof = PrepareProfile(db.profiles[name])
    Switched()
end
function ns.CopyProfileFrom(name)
    local cur = ns.CurrentProfile()
    if not db.profiles[name] or name == cur then return end
    db.profiles[cur] = copy(db.profiles[name])
    prof = PrepareProfile(db.profiles[cur])
    Switched()
end
function ns.ResetProfile()
    local cur = ns.CurrentProfile()
    db.profiles[cur] = {}
    prof = PrepareProfile(db.profiles[cur])
    Switched()
end
function ns.DeleteProfile(name)
    if not db.profiles[name] or name == ns.CurrentProfile() then return end
    db.profiles[name] = nil
    for k, v in pairs(db.profileKeys) do if v == name then db.profileKeys[k] = "Default" end end
    db.profiles.Default = db.profiles.Default or {}
    if ns.OnChanged then ns.OnChanged() end
end
-- export / import (one line of text, read back without running any code)
local LFP = LibStub and LibStub("LibFreeProfiles-1.0", true)
function ns.ExportProfile()
    if not LFP then return end
    LFP:ShowExport("Export profile: " .. (ns.CurrentProfile() or "?"), LFP.Encode("FreeUnitFrames", db.profiles[ns.CurrentProfile()]))
end
function ns.ImportProfile()
    if not LFP then return end
    LFP:ShowImport("Import a Free Unit Frames profile", "Imported", function(text, name)
        if InCombatLockdown() then return false, "Not in combat." end
        local ok, data = LFP.Decode("FreeUnitFrames", text)
        if not ok then return false, data end
        if type(data.units) ~= "table" and type(data.global) ~= "table" then return false, "The text holds no unit frame settings." end
        name = (name and name ~= "") and name or "Imported"
        db.profiles[name] = data
        db.profileKeys[charKey] = name
        prof = PrepareProfile(db.profiles[name])
        Switched()
        return true, name
    end)
end
function ns.ProfileUsers(name)
    local n = 0
    for _, v in pairs(db.profileKeys) do if v == name then n = n + 1 end end
    return n
end

function ns.ResetUnit(unit)
    prof.units[unit] = ns.UnitDefaults(unit)
end

-- Copy the look of one unit onto another: colours, textures, fonts, sizes, borders, formats...
-- Never the placement: where the frame is, where its texts, auras, castbar, portrait and bars sit.
local KEEP = { pos = true, enable = true, group = true }
local PLACEMENT = {
    pos = true, point = true, x = true, y = true, side = true, anchor = true, attach = true,
    growthX = true, growthY = true, anchorTo = true, onScreen = true, screen = true, where = true,
    attachTo = true, attachPos = true,
    detach = true, detAnchor = true, detX = true, detY = true, position = true, modelX = true, modelY = true,
    place = true, growth = true,
}
local function copyLook(src, dst)
    for k, v in pairs(src) do
        if not PLACEMENT[k] then
            if type(v) == "table" and type(dst[k]) == "table" and #v == 0 then
                copyLook(v, dst[k])                      -- sub-settings: go inside
            elseif type(v) == "table" and type(dst[k]) == "table" and k == "custom" then
                -- custom texts: keep the placement of the ones that exist on both sides
                for i, t in ipairs(v) do
                    if dst[k][i] then copyLook(t, dst[k][i]) else dst[k][i] = copy(t) end
                end
            else
                dst[k] = copy(v)
            end
        end
    end
end
function ns.CopyUnit(from, to)
    if from == to then return end
    local src, dst = prof.units[from], prof.units[to]
    if not (src and dst) then return end
    for k, v in pairs(src) do
        if not KEEP[k] then
            if type(v) == "table" and type(dst[k]) == "table" then copyLook(v, dst[k]) else dst[k] = copy(v) end
        end
    end
end

-- Reset one tab of the options for one unit (or the General page)
ns.TAB_KEYS = {
    frame = { "width", "height", "scale", "pos", "barAlpha", "border" },
    portrait = { "portrait" },
    bars = { "health", "power" },
    combo = { "classPower" },
    texts = { "texts" },
    auras = { "buffs", "debuffs" },
    castbar = { "castbar" },
    detach = { "power.detach", "power.detAnchor", "power.detX", "power.detY", "power.detW", "power.detH", "power.screen", "power.border",
               "castbar.onScreen", "castbar.screen" },
    indicators = { "raidIcon", "leader", "readyCheck", "combat", "resting", "threat", "range", "happiness" },
    group = { "group" },
}
function ns.ResetTab(unit, tab)
    local d = ns.UnitDefaults(unit)
    local u = prof.units[unit]
    if not (u and d) then return end
    if tab == "frame" then u.attachTo, u.attachPos = nil, nil end
    for _, path in ipairs(ns.TAB_KEYS[tab] or {}) do
        local v = ns.GetPath(d, path)
        if v ~= nil then ns.SetPath(u, path, copy(v)) end
    end
end
function ns.ResetGlobal()
    local keepMinimap = prof.global and prof.global.minimap
    prof.global = copy(GLOBAL_DEFAULTS)
    prof.global.minimap = keepMinimap
end

-- Dotted-path helpers ("health.colorClass")
function ns.GetPath(t, path)
    for key in path:gmatch("[^%.]+") do
        if type(t) ~= "table" then return nil end
        t = t[tonumber(key) or key]
    end
    return t
end
function ns.SetPath(t, path, value)
    local keys = {}
    for key in path:gmatch("[^%.]+") do keys[#keys + 1] = tonumber(key) or key end
    for i = 1, #keys - 1 do
        t[keys[i]] = t[keys[i]] or {}
        t = t[keys[i]]
    end
    t[keys[#keys]] = value
end

-- ------------------------------------------------------------ media
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
ns.LSM = LSM

local BUILTIN_TEX = {
    { key = "fuf-flat",   label = "Flat",   path = ns.WHITE },
    { key = "fuf-smooth", label = "Smooth", path = ns.MEDIA .. "bar-smooth" },
    { key = "fuf-glass",  label = "Glass",  path = ns.MEDIA .. "bar-glass" },
    { key = "fuf-stripe", label = "Stripes", path = ns.MEDIA .. "bar-stripe" },
    { key = "blizzard",   label = "Blizzard", path = "Interface\\TargetingFrame\\UI-StatusBar" },
    { key = "blizzard-raid", label = "Blizzard Raid", path = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
}
local function list(builtin, kind)
    local out, seen = {}, {}
    for _, it in ipairs(builtin) do out[#out + 1] = it; seen[it.label] = true end
    if LSM then
        local names = LSM:List(kind)
        for _, name in ipairs(names) do
            if not seen[name] then out[#out + 1] = { key = "lsm:" .. name, label = name, path = LSM:Fetch(kind, name) } end
        end
    end
    return out
end
function ns.TextureList() return list(BUILTIN_TEX, "statusbar") end
-- fonts: LibFreeMedia lists only the fonts that really load (ARIALN, FRIZQT, MORPHEUS, SKURRI, PTSANS, EXPRESSWAY, HOMESPUN, lsm:*)
local LFM = LibStub and LibStub("LibFreeMedia-1.0", true)
ns.LFM = LFM
function ns.FontList()
    if LFM then return LFM:ListFonts() end
    return { { key = "ARIALN", label = "Arial Narrow", path = "Fonts\\ARIALN.TTF" } }
end

local function fetch(builtin, kind, key, fallback)
    for _, it in ipairs(builtin) do if it.key == key then return it.path end end
    if LSM and type(key) == "string" and key:sub(1, 4) == "lsm:" then
        local p = LSM:Fetch(kind, key:sub(5), true)
        if p then return p end
    end
    return fallback
end
function ns.Texture(key) return fetch(BUILTIN_TEX, "statusbar", key or prof.global.texture, ns.WHITE) end
function ns.FontPath(key)
    key = key or (prof and prof.global and prof.global.font)
    if LFM then return LFM:FontPath(key) end
    return "Fonts\\ARIALN.TTF"
end

-- Outline styles: NONE = plain with a drop shadow, CLEAN = plain without shadow,
-- OUTLINE, THICKOUTLINE, MONOCHROMEOUTLINE (crisp pixel outline, best with pixel fonts)
ns.OUTLINE_LIST = {
    { key = "NONE", label = "Shadow" }, { key = "CLEAN", label = "None" }, { key = "OUTLINE", label = "Outline" },
    { key = "THICKOUTLINE", label = "Thick outline" }, { key = "MONOCHROMEOUTLINE", label = "Pixel outline" },
}
local OUTLINE_FLAGS = { NONE = "", CLEAN = "", OUTLINE = "OUTLINE", THICKOUTLINE = "THICKOUTLINE", MONOCHROMEOUTLINE = "OUTLINE, MONOCHROME" }
function ns.SetFont(fs, size, outlineOverride, fontKey)
    local g = prof.global
    local o = (outlineOverride and outlineOverride ~= "INHERIT") and outlineOverride or g.outline
    local flags = OUTLINE_FLAGS[o] or ""
    size = (size and size > 0) and size or g.fontSize
    local key = (fontKey and fontKey ~= "INHERIT") and fontKey or g.font
    if LFM then
        LFM:SetFont(fs, key, size, flags)
    else
        local path = ns.FontPath(key)
        if not fs:SetFont(path, size, flags) then fs:SetFont(STANDARD_TEXT_FONT, size, flags) end
    end
    if o == "NONE" then fs:SetShadowOffset(1, -1); fs:SetShadowColor(0, 0, 0, 1) else fs:SetShadowOffset(0, 0) end
end

-- ------------------------------------------------------------ tags
-- Values may be "secret" on WoW Forever: never compare or do maths on them,
-- only pass them to Blizzard formatting functions.
do
    local Methods, Events = oUF.Tags.Methods, oUF.Tags.Events
    local ScaleTo100 = CurveConstants and CurveConstants.ScaleTo100
    local Abbr = AbbreviateNumbers or function(v) return v end

    local function status(u)
        if UnitIsDead(u) then return "Dead" elseif UnitIsGhost(u) then return "Ghost"
        elseif not UnitIsConnected(u) then return "Offline" end
    end
    local function hpPercent(u, fmt)
        if UnitHealthPercent and ScaleTo100 then return format(fmt, UnitHealthPercent(u, true, ScaleTo100)) end
        local m = UnitHealthMax(u)
        return format(fmt, m > 0 and UnitHealth(u) / m * 100 or 0)
    end
    local function ppPercent(u, fmt)
        if UnitPowerPercent and ScaleTo100 then return format(fmt, UnitPowerPercent(u, nil, true, ScaleTo100)) end
        local m = UnitPowerMax(u)
        return format(fmt, m > 0 and UnitPower(u) / m * 100 or 0)
    end

    local HP = "UNIT_HEALTH UNIT_MAXHEALTH UNIT_CONNECTION PLAYER_FLAGS_CHANGED"

    -- every tag is wrapped: a failing tag shows nothing instead of raising errors on each update
    local Methods = setmetatable({}, { __newindex = function(_, k, fn)
        oUF.Tags.Methods[k] = function(...)
            local ok, r = pcall(fn, ...)
            if ok then return r end
            if ns.Safe then ns.Safe("tag " .. k, error, r) end
        end
    end })
    local PP = "UNIT_POWER_FREQUENT UNIT_MAXPOWER UNIT_DISPLAYPOWER"

    Methods["fuf:hp"] = function(u) return Abbr(UnitHealth(u)) end
    Events["fuf:hp"] = HP
    Methods["fuf:maxhp"] = function(u) return Abbr(UnitHealthMax(u)) end
    Events["fuf:maxhp"] = HP
    Methods["fuf:perhp"] = function(u) return hpPercent(u, "%.1f%%") end
    Events["fuf:perhp"] = HP
    Methods["fuf:perhp0"] = function(u) return hpPercent(u, "%d%%") end
    Events["fuf:perhp0"] = HP
    Methods["fuf:hpfull"] = function(u) return status(u) or format("%s / %s", Abbr(UnitHealth(u)), Abbr(UnitHealthMax(u))) end
    Events["fuf:hpfull"] = HP
    Methods["fuf:hpstatus"] = function(u) return status(u) or format("%s | %s", Abbr(UnitHealth(u)), hpPercent(u, "%.1f%%")) end
    Events["fuf:hpstatus"] = HP
    Methods["fuf:status"] = function(u) return status(u) or hpPercent(u, "%d%%") end
    Events["fuf:status"] = HP
    -- name of the unit's own target, in its class colour ("Rawg - Rawg" on the target frame)
    Methods["fuf:targetname"] = function(u)
        local t = u .. "target"
        if not UnitExists(t) then return end
        local name = UnitName(t)
        local _, class = UnitClass(t)
        local c = class and oUF:NotSecretValue(class) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if c and c.colorStr then return format("|c%s%s|r", c.colorStr, name) end
        return format("%s", name)
    end
    Events["fuf:targetname"] = "UNIT_TARGET UNIT_NAME_UPDATE"
    -- level coloured by difficulty (yellow = same level), "??" for skull units
    Methods["fuf:level"] = function(u)
        local l = UnitLevel(u)
        if not oUF:NotSecretValue(l) then return format("%s", l) end
        local c = (GetCreatureDifficultyColor and GetCreatureDifficultyColor(l)) or (GetQuestDifficultyColor and GetQuestDifficultyColor(l))
        local text = (l and l > 0) and tostring(l) or "??"
        if c then return format("|cff%02x%02x%02x%s|r", c.r * 255, c.g * 255, c.b * 255, text) end
        return text
    end
    Events["fuf:level"] = "UNIT_LEVEL PLAYER_LEVEL_UP UNIT_FACTION"
    Methods["fuf:pp"] = function(u) return Abbr(UnitPower(u)) end
    Events["fuf:pp"] = PP
    Methods["fuf:perpp"] = function(u) return ppPercent(u, "%d%%") end
    Events["fuf:perpp"] = PP
    Methods["fuf:ppfull"] = function(u) return format("%s / %s", Abbr(UnitPower(u)), Abbr(UnitPowerMax(u))) end
    Events["fuf:ppfull"] = PP
end

-- Presets offered in the options window (any oUF tag string can also be typed)
ns.TAG_PRESETS = {
    name = {
        { key = "[raidcolor][name]", label = "Name (class colour)" },
        { key = "[name]", label = "Name" },
        { key = "[raidcolor][name]|r [fuf:level]", label = "Name + level" },
        { key = "[fuf:level] [raidcolor][name]", label = "Level + name" },
        { key = "[fuf:level] [raidcolor][name]|r - [fuf:targetname]", label = "Level + name - target" },
    },
    health = {
        { key = "[fuf:hpstatus]", label = "2.3K | 100.0%" },
        { key = "[fuf:hp]", label = "2.3K" },
        { key = "[fuf:hpfull]", label = "2.3K / 2.3K" },
        { key = "[fuf:perhp]", label = "100.0%" },
        { key = "[fuf:status]", label = "100% (or Dead/Offline)" },
        { key = "[missinghp]", label = "Missing health" },
    },
    power = {
        { key = "[fuf:pp]", label = "1.9K" },
        { key = "[fuf:ppfull]", label = "1.9K / 1.9K" },
        { key = "[fuf:perpp]", label = "100%" },
        { key = "[powercolor][fuf:pp]", label = "1.9K (power colour)" },
    },
    level = {
        { key = "[fuf:level]", label = "Level (difficulty colour)" },
        { key = "[difficulty][smartlevel]", label = "Level (oUF colour)" },
        { key = "[smartlevel]", label = "Level" },
        { key = "[difficulty][smartlevel] [shortclassification]", label = "Level + elite" },
        { key = "[smartclass]", label = "Class" },
    },
}

-- ------------------------------------------------------------ error capture
-- Errors are printed once and kept in FreeUnitFramesDB.errors (last 30) so they
-- can be read after logging out, even without an error-display addon.
local reported = {}
function ns.Safe(label, fn, ...)
    local args, n = { ... }, select("#", ...)
    local ok, err = xpcall(function() return fn(unpack(args, 1, n)) end, function(e)
        return tostring(e) .. "\n" .. (debugstack and debugstack(2, 8, 0) or "")
    end)
    if not ok then
        if db then
            db.errors = db.errors or {}
            table.insert(db.errors, { time = date and date("%Y-%m-%d %H:%M:%S") or "", where = label, error = err })
            while #db.errors > 30 do table.remove(db.errors, 1) end
        end
        local first = (err or ""):match("^[^\n]*")
        if not reported[label .. first] then
            reported[label .. first] = true
            print("|cffff8a3dFreeUnitFrames|r error (" .. label .. "): " .. first)
        end
    end
    return ok
end

do
    local all = {}
    for _, group in ipairs({ "name", "health", "power", "level" }) do
        for _, it in ipairs(ns.TAG_PRESETS[group]) do all[#all + 1] = it end
    end
    all[#all + 1] = { key = "[fuf:perpp]", label = "Power %" }
    all[#all + 1] = { key = "[classification]", label = "Classification" }
    all[#all + 1] = { key = "[status]", label = "Status (Dead / Offline / Zzz)" }
    ns.TAG_PRESETS.custom = all
end

-- ------------------------------------------------------------ layout presets
-- Change looks only: positions, castbars and portraits are left as they are.
local function T(enable, format, point, x, y, size)
    return { enable = enable, format = format, point = point, x = x, y = y, attach = "HEALTH",
             size = size or 11, font = "EXPRESSWAY", outline = "INHERIT", useColor = false, width = 0 }
end
local function setLook(u, look)
    local c = prof.units[u]
    for k, v in pairs(look) do
        if type(v) == "table" and type(c[k]) == "table" and #v == 0 then
            for k2, v2 in pairs(v) do
                if type(v2) == "table" and type(c[k][k2]) == "table" and #v2 == 0 then
                    for k3, v3 in pairs(v2) do c[k][k2][k3] = copy(v3) end
                else
                    c[k][k2] = copy(v2)
                end
            end
        else
            c[k] = copy(v)
        end
    end
end

-- mana text colour picked from the reference screenshot (brightest pixel of "1.9K": 20, 108, 198)
local function MANA(t) t.useColor = true; t.color = { 20 / 255, 108 / 255, 198 / 255 }; return t end

ns.LAYOUT_PRESETS = {
    { key = "elvui", label = "ElvUI dark (player, target, ToT)", apply = function()
        -- dark health, clearly lighter missing part: the lost health must stand out
        local health = { colorClass = false, colorReaction = false, colorTapped = true, color = { 0.09, 0.09, 0.10 },
                         bgMode = "dark", bgColor = { 0.38, 0.38, 0.41 }, reverse = false, vertical = false }
        local power = { enable = true, position = "BOTTOM", height = 6, gap = 1, colorPower = false, colorClass = false,
                        color = { 0.27, 0.29, 0.33 }, bgMode = "dark", bgColor = { 0.06, 0.06, 0.07 } }
        setLook("player", {
            enable = true, width = 330, height = 40, barAlpha = 0.8, health = health, power = power,
            texts = {
                name   = T(true, "[raidcolor][name]|r [fuf:level]", "TOPRIGHT", -4, -3, 12),
                health = T(true, "[fuf:hpstatus]", "BOTTOMRIGHT", -4, 3, 11),
                power  = MANA(T(true, "[fuf:pp]", "BOTTOMLEFT", 4, 3, 11)),
                level  = T(false, "[difficulty][smartlevel]", "TOPRIGHT", -4, -3),
            },
            buffs = { enable = true, size = 26, perRow = 8, rows = 2, spacing = 2, side = "BOTTOM", growthX = "RIGHT", growthY = "DOWN", x = 0, y = -6, anchorTo = "FRAME" },
            debuffs = { enable = true, size = 30, perRow = 8, rows = 1, spacing = 2, side = "TOP", growthX = "RIGHT", growthY = "UP", x = 0, y = 6, anchorTo = "FRAME" },
        })
        ns.ApplyAuraPreset(prof.units.player.buffs, "all")
        ns.ApplyAuraPreset(prof.units.player.debuffs, "all")
        setLook("target", {
            enable = true, width = 330, height = 40, barAlpha = 0.8, health = health, power = power,
            texts = {
                name   = T(true, "[fuf:level] [raidcolor][name]|r - [fuf:targetname]", "TOPLEFT", 4, -3, 12),
                health = T(true, "[fuf:hpstatus]", "BOTTOMLEFT", 4, 3, 11),
                power  = MANA(T(true, "[fuf:pp]", "BOTTOMRIGHT", -4, 3, 11)),
                level  = T(false, "[difficulty][smartlevel]", "TOPRIGHT", -4, -3),
            },
            buffs = { enable = true, size = 26, perRow = 8, rows = 2, spacing = 2, side = "BOTTOM", growthX = "LEFT", growthY = "DOWN", x = 0, y = -6, anchorTo = "FRAME" },
            debuffs = { enable = true, size = 30, perRow = 8, rows = 1, spacing = 2, side = "TOP", growthX = "LEFT", growthY = "UP", x = 0, y = 6, anchorTo = "FRAME" },
        })
        ns.ApplyAuraPreset(prof.units.target.buffs, "all")
        ns.ApplyAuraPreset(prof.units.target.debuffs, "all")
        setLook("targettarget", {
            enable = true, width = 100, height = 22, barAlpha = 0.8, health = health, power = { enable = false },
            texts = {
                name   = T(true, "[raidcolor][name]", "CENTER", 0, 0, 11),
                health = T(false, "[fuf:hpstatus]", "BOTTOMRIGHT", -4, 3),
                power  = T(false, "[fuf:pp]", "BOTTOMLEFT", 4, 3),
                level  = T(false, "[difficulty][smartlevel]", "TOPRIGHT", -4, -3),
            },
            buffs = { enable = false }, debuffs = { enable = false },
        })
    end },
}

function ns.ApplyLayoutPreset(key)
    for _, pr in ipairs(ns.LAYOUT_PRESETS) do
        if pr.key == key then
            pr.apply()
            ns.UpdateAll()
            if ns.OnChanged then ns.OnChanged() end
            print("|cffff8a3dFreeUnitFrames|r: preset \"" .. pr.label .. "\" applied.")
            return true
        end
    end
end

-- ------------------------------------------------------------ apply / combat queue
local pending = {}
local queueFrame = CreateFrame("Frame")
queueFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    local all = pending.__all
    local units = pending
    pending = {}
    if all then ns.UpdateAll() else for u in pairs(units) do ns.UpdateUnit(u) end end
    print("|cffff8a3dFreeUnitFrames|r: changes made during combat have been applied.")
end)

function ns.Queue(unit)
    if unit then pending[unit] = true else pending.__all = true end
    queueFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

-- ------------------------------------------------------------ boot
local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self, event, name)
    if event == "PLAYER_LOGIN" then
        -- settings are loaded at login: the character name (needed for profiles) is known by then
        InitDB()
        db.errors = {}
        ns.SpawnAll()
        if ns.InitMinimap then ns.Safe("minimap", ns.InitMinimap) end
    end
end)

SLASH_FREEUNITFRAMES1 = "/fuf"
SLASH_FREEUNITFRAMES2 = "/freeunitframes"
SlashCmdList.FREEUNITFRAMES = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "unlock" or msg == "lock" or msg == "move" then
        ns.SetUnlocked(not ns.IsUnlocked())
    elseif msg == "test" then
        ns.SetTestMode(not ns.IsTestMode())
    elseif msg:match("^preset") then
        local key = msg:match("^preset%s+(%S+)") or "elvui"
        if not ns.ApplyLayoutPreset(key) then print("|cffff8a3dFreeUnitFrames|r: unknown preset. Try /fuf preset elvui") end
    elseif msg == "reset" then
        for _, u in ipairs(ns.UNITS) do ns.ResetUnit(u) end
        ns.UpdateAll()
        print("|cffff8a3dFreeUnitFrames|r: all frames reset.")
    else
        ns.ToggleConfig()
    end
end
