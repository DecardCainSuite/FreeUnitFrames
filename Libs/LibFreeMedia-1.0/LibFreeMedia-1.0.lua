--[[ LibFreeMedia-1.0
     Shared fonts and status bar textures for the Free addons.
     - Only fonts that really load are listed (each path is tested once with a hidden FontString, result cached).
     - Bundled fonts: add a line to BUNDLED below ({ key, label, file }); the file is looked for in the
       Media\Fonts folder of every Free addon (first one that loads wins).
     - LibSharedMedia-3.0 fonts / statusbars are merged when the library is present, and our fonts are registered into it.

     local LFM = LibStub("LibFreeMedia-1.0")
     LFM:ListFonts()                      -> { { key, label, path, game }, ... }
     LFM:FontPath(key, fallback)          -> path
     LFM:SetFont(fontString, key, size, flags)
     LFM:ListTextures() / LFM:TexturePath(key)
     LFM:RegisterFont(key, label, path)
     LFM.OUTLINES, LFM:Flags(outlineKey), LFM:ApplyOutline(fs, outlineKey)
]]
local MAJOR, MINOR = "LibFreeMedia-1.0", 4
local lib = LibStub and LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

local type, pairs, ipairs, pcall, tostring = type, pairs, ipairs, pcall, tostring
local sort, lower = table.sort, string.lower

local WHITE = "Interface\\Buttons\\WHITE8x8"
local DEFAULT_KEY = "ARIALN"

-- ------------------------------------------------------------ manifests (edit here)
-- Game fonts, always listed (trusted = known to exist in every client; the others are tested)
local GAME = {
    { key = "ARIALN",   label = "Arial Narrow",  path = "Fonts\\ARIALN.TTF",    trusted = true },
    { key = "FRIZQT",   label = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF",  trusted = true },
    { key = "MORPHEUS", label = "Morpheus",      path = "Fonts\\MORPHEUS.TTF",  trusted = true },
    { key = "SKURRI",   label = "Skurri",        path = "Fonts\\SKURRI.TTF",    trusted = true },
    { key = "F2002",    label = "2002",          path = "Fonts\\2002.TTF" },
    { key = "F2002B",   label = "2002 Bold",     path = "Fonts\\2002B.TTF" },
}
-- Folders searched for bundled fonts: Interface\AddOns\<A>\Media\Fonts\<file>
local FOLDERS = { "FreeMedia", "FreeUnitFrames", "FreeBars", "FreeSwing", "FreeHub", "FreeMinimap", "FreeGuild" }
-- Bundled fonts: { key, label, file [, legacy = { full paths also accepted }] }. ADD NEW FONTS HERE (one line each).
local BUNDLED = {
    { "PTSANS", "PT Sans Narrow", "PTSansNarrow.ttf", path = "Interface\\AddOns\\FreeUnitFrames\\Media\\PTSansNarrow.ttf", legacy = { "Interface\\AddOns\\FreeUnitFrames\\Media\\PTSansNarrow.ttf" } },
    -- optional font pack (FreeMedia addon)
    { "ADVENTURE",    "Adventure",     "adventure.ttf" },
    { "BAZOOKA",      "Bazooka",       "bazooka.ttf" },
    { "COOLINE",      "Cooline",       "cooline.ttf" },
    { "DIEDIEDIE",    "Die Die Die",   "diediedie.ttf" },
    { "DIOGENES",     "Diogenes",      "diogenes.ttf" },
    { "GINKO",        "Ginko",         "ginko.ttf" },
    { "PORKY",        "Porky's",       "porky.ttf" },
    { "TALISMAN",     "Talismanica",   "talisman.ttf" },
    { "TRANSFORMERS", "Transformers",  "transformers.ttf" },
    { "YELLOWJACKET", "Yellowjacket",  "yellowjacket.ttf" },
}
-- Fonts living in other addons: { key, label, full path }
local EXTERNAL = {
    { "EXPRESSWAY", "Expressway (ElvUI)",       "Interface\\AddOns\\ElvUI\\Game\\Shared\\Media\\Fonts\\Expressway.ttf" },
    { "HOMESPUN",   "Homespun (ElvUI, pixel)",  "Interface\\AddOns\\ElvUI\\Game\\Shared\\Media\\Fonts\\Homespun.ttf" },
}

lib.OUTLINES = {
    { key = "NONE", label = "Shadow" }, { key = "CLEAN", label = "None" }, { key = "OUTLINE", label = "Outline" },
    { key = "THICKOUTLINE", label = "Thick outline" }, { key = "MONOCHROMEOUTLINE", label = "Pixel outline" },
}
local OUTLINE_FLAGS = { NONE = "", CLEAN = "", OUTLINE = "OUTLINE", THICKOUTLINE = "THICKOUTLINE", MONOCHROMEOUTLINE = "OUTLINE, MONOCHROME" }

local TEXTURES = {
    { key = "flat",          label = "Flat",           path = WHITE },
    { key = "blizzard",      label = "Blizzard",       path = "Interface\\TargetingFrame\\UI-StatusBar" },
    { key = "blizzard-raid", label = "Blizzard Raid",  path = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
}
local TEXTURE_ALIAS = { ["fuf-flat"] = "flat", WHITE = "flat", BLIZZARD = "blizzard" }

-- ------------------------------------------------------------ validation
local testFS
local function tester()
    if testFS then return testFS end
    if not (CreateFrame and UIParent) then return nil end
    local ok, fs = pcall(function()
        local f = CreateFrame("Frame", nil, UIParent)
        if f.Hide then f:Hide() end
        return f:CreateFontString(nil, "OVERLAY")
    end)
    if ok and fs then testFS = fs end
    return testFS
end

local function norm(p) return lower((tostring(p or ""):gsub("/", "\\"))) end

local function AddonInstalled(name)
    local f = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
    if not f then return true end
    local ok, n, _, _, _, reason = pcall(f, name)
    if not ok or not n then return false end
    return reason ~= "MISSING"
end
lib.AddonInstalled = function(self, name) return AddonInstalled(name) end

local valid = {}   -- [path] = true/false (cache)
lib.validCache = valid
-- trusted = a font file we ship or one registered by another addon (LibSharedMedia): the game may load
-- addon font files lazily and report a failure on the first SetFont, so only a hard error drops it.
local function Loads(path, trusted)
    if type(path) ~= "string" or path == "" then return false end
    if trusted then
        local fs = tester()
        if fs then
            local ok = pcall(fs.SetFont, fs, path, 12, "")
            if not ok then return false end
        end
        return true
    end
    local c = valid[path]
    if c ~= nil then return c end
    local fs = tester()
    local result = true
    if fs then
        local ok, res = pcall(fs.SetFont, fs, path, 12, "")
        if not ok or res == false then
            result = false
        else
            -- res == true -> loaded; res == nil -> unknown, then trust GetFont()
            if res == nil and fs.GetFont then
                local ok2, got = pcall(fs.GetFont, fs)
                if not ok2 or not got or norm(got) ~= norm(path) then result = false end
            end
        end
    end
    valid[path] = result
    return result
end
lib.Loads = function(self, path) return Loads(path) end

-- ------------------------------------------------------------ registry
local custom = {}     -- fonts added through RegisterFont: { key, label, path }
local listCache, listSig

local function LSM() return LibStub and LibStub("LibSharedMedia-3.0", true) end

local function lsmNames(kind)
    local l = LSM()
    if not l or not l.List then return {} end
    local ok, names = pcall(l.List, l, kind)
    return (ok and type(names) == "table") and names or {}
end

function lib:RegisterFont(key, label, path)
    if type(key) ~= "string" or type(path) ~= "string" then return end
    for _, c in ipairs(custom) do if c.key == key then c.label, c.path = label or key, path; listCache = nil; return end end
    custom[#custom + 1] = { key = key, label = label or key, path = path }
    listCache = nil
end

function lib:Refresh() listCache = nil; for k in pairs(valid) do valid[k] = nil end end

local registeredLSM = {}
local function RegisterIntoLSM(items)
    local l = LSM()
    if not l or not l.Register then return end
    local have, haveName = {}, {}
    local ok, hash = pcall(l.HashTable, l, "font")
    if ok and type(hash) == "table" then for n, p in pairs(hash) do have[norm(p)] = true; haveName[lower(n)] = true end end
    for _, it in ipairs(items) do
        if not it.lsm and not registeredLSM[it.path] and not have[norm(it.path)] and not haveName[lower(it.label)] then
            registeredLSM[it.path] = true
            pcall(l.Register, l, "font", it.label, it.path)
        end
    end
end

local function build()
    local items, byKey, byPath = {}, {}, {}
    local function add(key, label, path, game, isLSM, trusted)
        if byKey[key] or not Loads(path, trusted) then return end
        local it = { key = key, label = label, path = path, game = game and true or false, lsm = isLSM }
        items[#items + 1] = it; byKey[key] = it; byPath[norm(path)] = it
    end
    for _, g in ipairs(GAME) do
        if g.trusted then add(g.key, g.label, g.path, true) elseif Loads(g.path) then add(g.key, g.label, g.path, true) end
    end
    for _, b in ipairs(BUNDLED) do
        local cands = {}
        for _, a in ipairs(FOLDERS) do cands[#cands + 1] = "Interface\\AddOns\\" .. a .. "\\Media\\Fonts\\" .. b[3] end
        for _, p in ipairs(b.legacy or {}) do cands[#cands + 1] = p end
        -- the first installed Free addon that is meant to ship it (FreeUnitFrames carries the font pack)
        local done = false
        for _, a in ipairs(FOLDERS) do
            if not done and AddonInstalled(a) and (a == (b.folder or "FreeUnitFrames")) then
                add(b[1], b[2], b.path or ("Interface\\AddOns\\" .. a .. "\\Media\\Fonts\\" .. b[3]), false, false, true); done = true
            end
        end
        if not done then
            for _, p in ipairs(cands) do
                if Loads(p) then add(b[1], b[2], p); break end
            end
        end
    end
    for _, e in ipairs(EXTERNAL) do if AddonInstalled(e.addon or "ElvUI") then add(e[1], e[2], e[3], false, false, true) end end
    for _, c in ipairs(custom) do add(c.key, c.label, c.path) end
    -- our valid fonts become visible to other addons through LibSharedMedia
    RegisterIntoLSM(items)
    -- LibSharedMedia fonts (validated), skipping what we already list (same name or same file)
    local l = LSM()
    if l then
        local names = lsmNames("font")
        for _, name in ipairs(names) do
            local taken = false
            for _, it in ipairs(items) do if lower(it.label) == lower(name) then taken = true; break end end
            if not taken then
                local ok, path = pcall(l.Fetch, l, "font", name, true)
                if ok and type(path) == "string" and not byPath[norm(path)] then add("lsm:" .. name, name, path, false, true, true) end
            end
        end
    end
    -- game fonts first (manifest order), then the rest alphabetically
    local games, rest = {}, {}
    for _, it in ipairs(items) do if it.game then games[#games + 1] = it else rest[#rest + 1] = it end end
    sort(rest, function(a, b) return lower(a.label) < lower(b.label) end)
    for _, it in ipairs(rest) do games[#games + 1] = it end
    return games, byKey
end

local byKeyCache
local function ensure()
    local sig = #lsmNames("font") .. ":" .. #custom
    if not listCache or listSig ~= sig then
        listCache, byKeyCache = build()
        listSig = #lsmNames("font") .. ":" .. #custom   -- after build: registering into LSM changes the count
    end
    return listCache, byKeyCache
end

-- ------------------------------------------------------------ fonts API
function lib:ListFonts()
    local l = ensure()
    return l
end

function lib:FontPath(key, fallback)
    local _, byKey = ensure()
    local it = key and byKey[key]
    if it then return it.path end
    if type(key) == "string" and key:sub(1, 4) == "lsm:" then
        local l = LSM()
        if l then
            local ok, p = pcall(l.Fetch, l, "font", key:sub(5), true)
            if ok and type(p) == "string" and Loads(p) then return p end
        end
    end
    if fallback then return fallback end
    return (byKey[DEFAULT_KEY] or GAME[1]).path
end

function lib:Flags(outlineKey)
    local f = OUTLINE_FLAGS[outlineKey]
    if f ~= nil then return f end
    return type(outlineKey) == "string" and outlineKey or ""
end

local function trySet(fs, path, size, flags)
    if type(path) ~= "string" then return false end
    local ok, res = pcall(fs.SetFont, fs, path, size, flags)
    if not ok or res == false then return false end
    if res == nil and fs.GetFont then
        local ok2, got = pcall(fs.GetFont, fs)
        if ok2 and not got then return false end
    end
    return true
end

-- Never errors. flags: a flags string or an outline key (NONE, CLEAN, OUTLINE...). Returns true when the font was applied.
function lib:SetFont(fs, key, size, flags)
    if not fs or not fs.SetFont then return false end
    size = tonumber(size) or 12
    flags = lib:Flags(flags)
    local ok = trySet(fs, lib:FontPath(key), size, flags)
    if not ok then ok = trySet(fs, lib:FontPath(DEFAULT_KEY), size, flags) end
    if not ok then ok = trySet(fs, STANDARD_TEXT_FONT or GAME[1].path, size, flags) end
    return ok
end

-- Re-applies the current font with the flags of an outline style; shadow only for NONE.
function lib:ApplyOutline(fs, outlineKey)
    if not fs then return end
    if fs.GetFont and fs.SetFont then
        local ok, path, size = pcall(fs.GetFont, fs)
        if ok and path then trySet(fs, path, size or 12, lib:Flags(outlineKey)) end
    end
    if outlineKey == "NONE" or outlineKey == nil then
        if fs.SetShadowOffset then fs:SetShadowOffset(1, -1) end
        if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 1) end
    elseif fs.SetShadowOffset then
        fs:SetShadowOffset(0, 0)
    end
end

-- ------------------------------------------------------------ textures
function lib:ListTextures()
    local out, seen = {}, {}
    for _, t in ipairs(TEXTURES) do out[#out + 1] = { key = t.key, label = t.label, path = t.path }; seen[lower(t.label)] = true end
    local l = LSM()
    if l then
        local rest = {}
        for _, name in ipairs(lsmNames("statusbar")) do
            if not seen[lower(name)] then
                local ok, p = pcall(l.Fetch, l, "statusbar", name, true)
                if ok and type(p) == "string" then rest[#rest + 1] = { key = "lsm:" .. name, label = name, path = p } end
            end
        end
        sort(rest, function(a, b) return lower(a.label) < lower(b.label) end)
        for _, r in ipairs(rest) do out[#out + 1] = r end
    end
    return out
end

function lib:TexturePath(key, fallback)
    key = TEXTURE_ALIAS[key] or key
    for _, t in ipairs(TEXTURES) do if t.key == key then return t.path end end
    if type(key) == "string" and key:sub(1, 4) == "lsm:" then
        local l = LSM()
        if l then
            local ok, p = pcall(l.Fetch, l, "statusbar", key:sub(5), true)
            if ok and type(p) == "string" then return p end
        end
    end
    return fallback or WHITE
end
