--[[ LibFreeProfiles-1.0
     Profiles for the Free addons (Free Swing Timer, Free Unit Frames, Free Minimap, Free Bars...):
     - a store { profiles = { [name] = data }, profileKeys = { [character] = name } } kept in the addon's saved variables
     - every character picks a profile; profiles can be created, copied, reset and deleted
     - a profile can be exported as one line of text and imported on another account
     Import never runs code: the text is read by a small parser that only knows tables, strings, numbers and booleans.
]]
local MAJOR, MINOR = "LibFreeProfiles-1.0", 2
local lib = LibStub and LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

local type, pairs, ipairs, tostring, tonumber = type, pairs, ipairs, tostring, tonumber
local format, byte, char, sub, find = string.format, string.byte, string.char, string.sub, string.find
local concat, sort = table.concat, table.sort

-- ------------------------------------------------------------ helpers
local function deepcopy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = deepcopy(x) end
    return t
end
lib.Copy = deepcopy

function lib.CharKey()
    local name = UnitName and UnitName("player")
    local realm = GetRealmName and GetRealmName()
    if not name or name == "" or name == UNKNOWNOBJECT then return nil end
    return name .. " - " .. (realm or "?")
end

-- ------------------------------------------------------------ serializer
local function esc(s)
    return (s:gsub('[%c"\\]', function(c)
        if c == "\\" then return "\\\\" elseif c == '"' then return '\\"'
        elseif c == "\n" then return "\\n" elseif c == "\r" then return "\\r" elseif c == "\t" then return "\\t" end
        return format("\\%03d", byte(c))
    end))
end

local function num(v)
    if v ~= v or v == math.huge or v == -math.huge then return "0" end
    if v == math.floor(v) and v > -1e15 and v < 1e15 then return format("%d", v) end
    return format("%.6g", v)
end

local function keyOrder(a, b)
    local ta, tb = type(a), type(b)
    if ta ~= tb then return ta < tb end
    if ta == "boolean" then return (a and 1 or 0) < (b and 1 or 0) end
    return a < b
end

local function ser(v, out, depth)
    local t = type(v)
    if t == "string" then out[#out + 1] = '"' .. esc(v) .. '"'
    elseif t == "number" then out[#out + 1] = num(v)
    elseif t == "boolean" then out[#out + 1] = v and "true" or "false"
    elseif t == "table" then
        if depth > 40 then out[#out + 1] = "{}"; return end
        local keys = {}
        for k, x in pairs(v) do
            local tk, tx = type(k), type(x)
            if (tk == "string" or tk == "number" or tk == "boolean")
               and (tx == "string" or tx == "number" or tx == "boolean" or tx == "table") then
                keys[#keys + 1] = k
            end
        end
        sort(keys, keyOrder)
        out[#out + 1] = "{"
        for _, k in ipairs(keys) do
            out[#out + 1] = "["; ser(k, out, depth + 1); out[#out + 1] = "]="
            ser(v[k], out, depth + 1)
            out[#out + 1] = ","
        end
        out[#out + 1] = "}"
    else
        out[#out + 1] = "false"
    end
end

function lib.Serialize(v)
    local out = {}
    ser(v, out, 0)
    return concat(out)
end

-- ------------------------------------------------------------ parser (data only)
local function parse(s)
    local pos, len = 1, #s
    local function ws() local _, e = find(s, "^%s*", pos); pos = e + 1 end
    local function fail(msg) error({ msg = msg .. " at " .. pos }, 0) end
    local value
    local function str()
        pos = pos + 1
        local buf = {}
        while true do
            if pos > len then fail("unfinished text") end
            local c = sub(s, pos, pos)
            if c == '"' then pos = pos + 1; break end
            if c == "\\" then
                local n = sub(s, pos + 1, pos + 1)
                if n == "n" then buf[#buf + 1] = "\n"; pos = pos + 2
                elseif n == "r" then buf[#buf + 1] = "\r"; pos = pos + 2
                elseif n == "t" then buf[#buf + 1] = "\t"; pos = pos + 2
                elseif n == "\\" or n == '"' then buf[#buf + 1] = n; pos = pos + 2
                elseif find(n, "%d") then
                    local d = sub(s, pos + 1, pos + 3)
                    if not find(d, "^%d%d%d$") then fail("bad escape") end
                    buf[#buf + 1] = char(tonumber(d) % 256); pos = pos + 4
                else fail("bad escape") end
            else
                buf[#buf + 1] = c; pos = pos + 1
            end
        end
        return concat(buf)
    end
    local depth = 0
    local function tbl()
        depth = depth + 1
        if depth > 60 then fail("too deep") end
        pos = pos + 1
        local t = {}
        while true do
            ws()
            local c = sub(s, pos, pos)
            if c == "}" then pos = pos + 1; break end
            if c ~= "[" then fail("expected [") end
            pos = pos + 1; ws()
            local k = value()
            if type(k) == "table" then fail("bad key") end
            ws()
            if sub(s, pos, pos + 1) ~= "]=" then fail("expected ]=") end
            pos = pos + 2; ws()
            t[k] = value()
            ws()
            if sub(s, pos, pos) == "," then pos = pos + 1 end
        end
        depth = depth - 1
        return t
    end
    function value()
        ws()
        local c = sub(s, pos, pos)
        if c == "{" then return tbl()
        elseif c == '"' then return str()
        elseif sub(s, pos, pos + 3) == "true" then pos = pos + 4; return true
        elseif sub(s, pos, pos + 4) == "false" then pos = pos + 5; return false
        else
            local a, e = find(s, "^%-?%d+%.?%d*[eE]?[%-+]?%d*", pos)
            if not a then fail("unexpected character") end
            local n = tonumber(sub(s, a, e))
            if not n then fail("bad number") end
            pos = e + 1
            return n
        end
    end
    local v = value()
    ws()
    if pos <= len then fail("extra text") end
    return v
end

function lib.Deserialize(s)
    if type(s) ~= "string" then return false, "no text" end
    local ok, res = pcall(parse, s)
    if not ok then return false, type(res) == "table" and res.msg or tostring(res) end
    return true, res
end

-- "!Free:<addon>:1!" + data
function lib.Encode(addonId, data)
    return "!Free:" .. addonId .. ":1!" .. lib.Serialize(data)
end
function lib.Decode(addonId, text)
    text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local id, body = text:match("^!Free:([%w_]+):1!(.*)$")
    if not id then return false, "This is not a profile string." end
    if id ~= addonId then return false, "This profile is for " .. id .. ", not for " .. addonId .. "." end
    local ok, data = lib.Deserialize(body)
    if not ok then return false, "The text is damaged (" .. tostring(data) .. ")." end
    if type(data) ~= "table" then return false, "The text holds no settings." end
    return true, data
end

-- ------------------------------------------------------------ profile manager
-- store       : table in the saved variables (profiles / profileKeys are created in it)
-- onSwitch(d) : called with the active profile's table after every change of profile
-- prepare(d)  : fills defaults in a profile table (optional)
local Manager = {}
Manager.__index = Manager

-- opts (optional 6th argument): { perCharacter = true } -> every new character gets its own profile named after
--   it, copied from the default profile (see Manager:EnsureCharacter). Characters that already have a profile are untouched.
function lib:New(addonId, store, onSwitch, prepare, defaultName, opts)
    local m = setmetatable({ id = addonId, store = store, onSwitch = onSwitch, prepare = prepare, defaultName = defaultName or "Default",
                             perCharacter = type(opts) == "table" and opts.perCharacter and true or false }, Manager)
    store.profiles = store.profiles or {}
    store.profileKeys = store.profileKeys or {}
    if m.perCharacter then m:EnsureCharacter() end
    return m
end

-- Gives the current character a profile of its own when perCharacter is on (idempotent). Returns the profile name.
-- Does nothing while the character name is still unknown (call again after PLAYER_LOGIN).
function Manager:EnsureCharacter()
    local store = self.store
    store.profiles = store.profiles or {}
    store.profileKeys = store.profileKeys or {}
    local key = lib.CharKey()
    if not key then return nil end
    local cur = store.profileKeys[key]
    if cur and store.profiles[cur] then return cur end
    if not self.perCharacter then return self:Current() end
    local name = key:match("^(.-) %- ") or key
    if name == "" then name = key end
    -- the character name may already be taken by another realm's character: use the full key then
    if store.profiles[name] and store.profileKeys[key] == nil then
        local owned = false
        for k, v in pairs(store.profileKeys) do if v == name and k ~= key then owned = true end end
        if owned then name = key end
    end
    if not store.profiles[name] then
        local base = store.profiles[self.defaultName]
        store.profiles[name] = base and deepcopy(base) or {}
        if self.prepare then self.prepare(store.profiles[name]) end
    end
    store.profileKeys[key] = name
    return name
end

function Manager:Key() return lib.CharKey() or "?" end
function Manager:Current()
    if self.perCharacter then self:EnsureCharacter() end
    local n = self.store.profileKeys[self:Key()]
    if n and self.store.profiles[n] then return n end
    return self.defaultName
end
function Manager:Data()
    local name = self:Current()
    local p = self.store.profiles
    p[name] = p[name] or {}
    if self.prepare then self.prepare(p[name]) end
    return p[name]
end
function Manager:List()
    local out = {}
    for name in pairs(self.store.profiles) do out[#out + 1] = name end
    sort(out)
    return out
end
function Manager:Users(name)
    local n = 0
    for _, v in pairs(self.store.profileKeys) do if v == name then n = n + 1 end end
    return n
end
function Manager:Activate()
    local d = self:Data()
    if self.onSwitch then self.onSwitch(d) end
    return d
end
-- select (and create if needed) a profile for this character
function Manager:Set(name, copyFrom)
    if not name or name == "" then return end
    local p = self.store.profiles
    if not p[name] then
        p[name] = (copyFrom and p[copyFrom]) and deepcopy(p[copyFrom]) or {}
    end
    self.store.profileKeys[self:Key()] = name
    return self:Activate()
end
function Manager:CopyFrom(name)
    local cur = self:Current()
    local p = self.store.profiles
    if not p[name] or name == cur then return end
    p[cur] = deepcopy(p[name])
    return self:Activate()
end
function Manager:Reset()
    self.store.profiles[self:Current()] = {}
    return self:Activate()
end
function Manager:Delete(name)
    local p = self.store.profiles
    if not p[name] or name == self:Current() then return end
    p[name] = nil
    for k, v in pairs(self.store.profileKeys) do if v == name then self.store.profileKeys[k] = nil end end
end
function Manager:Export()
    return lib.Encode(self.id, self:Data())
end
-- import as a new profile (or over an existing one) and switch to it
function Manager:Import(text, name)
    local ok, data = lib.Decode(self.id, text)
    if not ok then return false, data end
    name = (name and name ~= "") and name or "Imported"
    self.store.profiles[name] = data
    self.store.profileKeys[self:Key()] = name
    self:Activate()
    return true, name
end

-- ------------------------------------------------------------ text window (export / import)
local C = { bg = { 0.071, 0.075, 0.086, 0.98 }, panel = { 0.098, 0.102, 0.118, 1 }, text = { 0.92, 0.92, 0.94 },
            muted = { 0.55, 0.56, 0.6 }, accent = { 1, 0.54, 0.24 }, control = { 0.14, 0.145, 0.165, 1 }, hover = { 0.19, 0.195, 0.22, 1 },
            bad = { 1, 0.42, 0.38 }, good = { 0.45, 0.85, 0.5 } }
local WHITE = "Interface\\Buttons\\WHITE8x8"

local function Fill(f, col, layer)
    local t = f:CreateTexture(nil, layer or "BACKGROUND")
    t:SetTexture(WHITE); t:SetVertexColor(col[1], col[2], col[3], col[4] or 1)
    return t
end
local function Edge(f, a)
    for _, p in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 }, { "TOPLEFT", "BOTTOMLEFT", 1 }, { "TOPRIGHT", "BOTTOMRIGHT", 1 } }) do
        local t = f:CreateTexture(nil, "BORDER")
        t:SetTexture(WHITE); t:SetVertexColor(1, 1, 1, a)
        t:SetPoint(p[1]); t:SetPoint(p[2])
        if p[3] then t:SetWidth(1) else t:SetHeight(1) end
    end
end
local function Txt(f, size, col)
    local fs = f:CreateFontString(nil, "OVERLAY")
    fs:SetFont("Fonts\\FRIZQT__.TTF", size, "")
    fs:SetTextColor(col[1], col[2], col[3])
    fs:SetJustifyH("LEFT")
    return fs
end
local function Btn(parent, label, w, primary, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, 26)
    b.bg = Fill(b, primary and { 0.75, 0.38, 0.14, 1 } or C.control); b.bg:SetAllPoints()
    Edge(b, 0.08)
    b.label = Txt(b, 12, C.text); b.label:SetPoint("CENTER"); b.label:SetText(label)
    b:SetScript("OnEnter", function() if not primary then b.bg:SetVertexColor(C.hover[1], C.hover[2], C.hover[3], 1) end end)
    b:SetScript("OnLeave", function() if not primary then b.bg:SetVertexColor(C.control[1], C.control[2], C.control[3], 1) end end)
    b:SetScript("OnClick", onClick)
    return b
end

local win
local function Window()
    if win then return win end
    win = CreateFrame("Frame", "LibFreeProfilesWindow", UIParent)
    win:SetSize(560, 380)
    win:SetPoint("CENTER")
    win:SetFrameStrata("FULLSCREEN_DIALOG")
    win:SetToplevel(true)
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:SetMovable(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    tinsert(UISpecialFrames, "LibFreeProfilesWindow")
    local bg = Fill(win, C.bg); bg:SetAllPoints()
    Edge(win, 0.1)
    local top = Fill(win, C.accent, "BORDER"); top:SetHeight(2); top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT")
    win.title = Txt(win, 15, C.text); win.title:SetPoint("TOPLEFT", 16, -14)
    win.sub = Txt(win, 11, C.muted); win.sub:SetPoint("TOPLEFT", 16, -36); win.sub:SetPoint("RIGHT", -16, 0); win.sub:SetWordWrap(true)

    local box = CreateFrame("Frame", nil, win)
    box:SetPoint("TOPLEFT", 16, -64); box:SetPoint("BOTTOMRIGHT", -16, 84)
    local bbg = Fill(box, C.panel); bbg:SetAllPoints()
    Edge(box, 0.08)
    local sf = CreateFrame("ScrollFrame", nil, box)
    sf:SetPoint("TOPLEFT", 8, -8); sf:SetPoint("BOTTOMRIGHT", -8, 8)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFont("Fonts\\ARIALN.TTF", 12, "")
    eb:SetTextColor(C.text[1], C.text[2], C.text[3])
    eb:SetWidth(500)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnCursorChanged", function(self, _, y, _, h)
        local top = sf:GetVerticalScroll()
        local view = sf:GetHeight()
        y = -y
        if y < top then sf:SetVerticalScroll(y) elseif y + h > top + view then sf:SetVerticalScroll(y + h - view) end
    end)
    sf:SetScrollChild(eb)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, d)
        local max = math.max(0, eb:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - d * 30)))
    end)
    sf:SetScript("OnSizeChanged", function(_, w) eb:SetWidth(w) end)
    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function() eb:SetFocus() end)
    win.eb = eb

    win.nameLabel = Txt(win, 12, C.muted); win.nameLabel:SetPoint("BOTTOMLEFT", 16, 56); win.nameLabel:SetText("Profile name")
    local nb = CreateFrame("EditBox", nil, win)
    nb:SetSize(220, 24)
    nb:SetPoint("LEFT", win.nameLabel, "RIGHT", 10, 0)
    nb:SetAutoFocus(false)
    nb:SetFont("Fonts\\ARIALN.TTF", 13, "")
    nb:SetTextColor(C.text[1], C.text[2], C.text[3])
    nb:SetTextInsets(6, 6, 0, 0)
    local nbg = Fill(nb, C.control); nbg:SetAllPoints()
    Edge(nb, 0.08)
    nb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    win.nb = nb

    win.msg = Txt(win, 12, C.muted); win.msg:SetPoint("BOTTOMLEFT", 16, 24); win.msg:SetPoint("RIGHT", -260, 0); win.msg:SetWordWrap(true)
    win.close = Btn(win, "Close", 90, false, function() win:Hide() end)
    win.close:SetPoint("BOTTOMRIGHT", -16, 16)
    win.action = Btn(win, "Import", 110, true, function() if win.onAction then win.onAction() end end)
    win.action:SetPoint("RIGHT", win.close, "LEFT", -8, 0)
    return win
end

function lib:ShowExport(title, text)
    local w = Window()
    w.title:SetText(title or "Export profile")
    w.sub:SetText("Copy this text (Ctrl+A then Ctrl+C) and paste it in the Import window of the same addon, on any character or account.")
    w.eb:SetText(text or "")
    w.nameLabel:Hide(); w.nb:Hide(); w.action:Hide()
    w.msg:SetText("")
    w:Show()
    w.eb:SetFocus()
    w.eb:HighlightText()
end

-- onImport(text, name) -> ok, message
function lib:ShowImport(title, defaultName, onImport)
    local w = Window()
    w.title:SetText(title or "Import profile")
    w.sub:SetText("Paste a profile text (Ctrl+V), give it a name, then press Import. An existing profile with the same name is replaced.")
    w.eb:SetText("")
    w.nameLabel:Show(); w.nb:Show(); w.action:Show()
    w.nb:SetText(defaultName or "Imported")
    w.msg:SetText("")
    w.onAction = function()
        local ok, msg = onImport(w.eb:GetText(), (w.nb:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", ""))
        if ok then
            w.msg:SetTextColor(C.good[1], C.good[2], C.good[3]); w.msg:SetText("Imported as \"" .. tostring(msg) .. "\" and selected.")
        else
            w.msg:SetTextColor(C.bad[1], C.bad[2], C.bad[3]); w.msg:SetText(msg or "Could not import.")
        end
    end
    w:Show()
    w.eb:SetFocus()
end
