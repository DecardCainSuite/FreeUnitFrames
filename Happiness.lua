-- FreeUnitFrames - hunter pet happiness icon.
-- A plain (non secure) icon of its own: on the pet frame (anchor + offsets) or anywhere on the screen
-- (Unlock to drag it). It does not need the pet frame to be turned on when placed on the screen.

local ADDON, ns = ...
local oUF = ns.oUF
local MEDIA = ns.MEDIA

local FACES = "Interface\\PetPaperDollFrame\\UI-PetHappiness"
-- 128x64 sheet: happy, content, unhappy faces side by side
local FACE_COORDS = { [3] = { 0, 0.1875, 0, 0.359375 }, [2] = { 0.1875, 0.375, 0, 0.359375 }, [1] = { 0.375, 0.5625, 0, 0.359375 } }
local DOT_COLORS = { [3] = { 0.30, 0.85, 0.35 }, [2] = { 1.00, 0.82, 0.20 }, [1] = { 0.95, 0.25, 0.20 } }
local NAMES = { [1] = "Unhappy", [2] = "Content", [3] = "Happy" }
local SAMPLE = { 2, 100, 0 }      -- test / unlock / preview: content

local icon

local function Cfg() local u = ns.Unit and ns.Unit("pet"); return u and u.happiness end

-- happiness (1-3), damage %, loyalty rate; nil when there is no hunter pet
local function Read()
    local okUI, hasUI, isHunter = pcall(HasPetUI)
    if not (okUI and hasUI and isHunter) then return nil end
    local fn = (C_PetInfo and C_PetInfo.GetPetHappiness) or GetPetHappiness
    if not fn then return nil end
    local ok, h, dmg, loyalty = pcall(fn)
    if not ok or h == nil then return nil end
    if oUF.NotSecretValue and not (oUF:NotSecretValue(h)) then return nil end
    h = tonumber(h)
    if not h or not NAMES[h] then return nil end
    return h, tonumber(dmg), tonumber(loyalty)
end

local function SetLook(f, c, h)
    local t = f.tex
    if (c.style or "FACE") == "DOT" then
        local col = DOT_COLORS[h]
        t:SetTexture(MEDIA .. "circle")
        t:SetTexCoord(0, 1, 0, 1)
        t:SetVertexColor(col[1], col[2], col[3], 1)
        t:ClearAllPoints(); t:SetPoint("TOPLEFT", 2, -2); t:SetPoint("BOTTOMRIGHT", -2, 2)
        f.ring:Show()
    else
        local tc = FACE_COORDS[h]
        t:SetTexture(FACES)
        t:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
        t:SetVertexColor(1, 1, 1, 1)
        t:ClearAllPoints(); t:SetAllPoints(f)
        f.ring:Hide()
    end
end

local function Update(f)
    f = f or icon
    if not f then return end
    local c = Cfg()
    if not (c and c.enable) then f:Hide(); return end
    local h, dmg, loyalty
    if f.fufSample then h, dmg, loyalty = SAMPLE[1], SAMPLE[2], SAMPLE[3] else h, dmg, loyalty = Read() end
    if not h or (c.hideHappy and h == 3 and not f.fufSample) then f:Hide(); return end
    f.fufState = { h, dmg, loyalty }
    SetLook(f, c, h)
    f:Show()
end
ns.UpdateHappiness = function() Update() end

local function OnEnter(self)
    local c = Cfg()
    if not (c and c.tooltip) or not self.fufState then return end
    local h, dmg, loyalty = unpack(self.fufState)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    local col = DOT_COLORS[h]
    GameTooltip:AddLine("Pet: " .. ((_G["PET_HAPPINESS" .. h]) or NAMES[h]), col[1], col[2], col[3])
    if dmg then GameTooltip:AddLine("Deals " .. dmg .. "% damage", 1, 1, 1) end
    if loyalty and loyalty > 0 then GameTooltip:AddLine("Gaining loyalty", 0.45, 0.85, 0.5)
    elseif loyalty and loyalty < 0 then GameTooltip:AddLine("Losing loyalty", 1, 0.42, 0.38) end
    if h < 3 then GameTooltip:AddLine("Feed your pet to make it happier.", 0.7, 0.71, 0.75, true) end
    GameTooltip:Show()
end

local function Build()
    if icon then return icon end
    local f = CreateFrame("Frame", "FreeUnitFrames_PetHappiness", UIParent)
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel(30)
    f:SetSize(20, 20)
    f.ring = f:CreateTexture(nil, "BACKGROUND")
    f.ring:SetTexture(MEDIA .. "circle"); f.ring:SetVertexColor(0, 0, 0, 0.9); f.ring:SetAllPoints()
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints()
    f:SetScript("OnEnter", OnEnter)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- some of these events do not exist on every client
    for _, ev in ipairs({ "UNIT_HAPPINESS", "PET_UI_UPDATE", "PET_BAR_UPDATE", "PLAYER_ENTERING_WORLD", "UNIT_PET" }) do
        pcall(f.RegisterEvent, f, ev)
    end
    if f.RegisterUnitEvent then pcall(f.RegisterUnitEvent, f, "UNIT_POWER_UPDATE", "pet") end
    f:SetScript("OnEvent", function(self) Update(self) end)
    -- safety net: happiness changes slowly, a check every two seconds costs nothing
    if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(2, function() if not f.fufSample then Update(f) end end) end
    f:Hide()
    icon = f
    return f
end
function ns.HappinessFrame() return icon end

-- settings changed (called with the pet frame's settings)
function ns.ApplyHappiness(petFrame)
    local c = Cfg()
    if not c then return end
    if not c.enable then if icon then icon:Hide() end return end
    local f = Build()
    local key = "pet"
    local s = ns.UnitScale and ns.UnitScale(key) or 1
    f:SetScale(s)
    f:SetSize(c.size or 20, c.size or 20)
    if f.EnableMouse then f:EnableMouse(c.tooltip and true or false) end
    f.fufSample = (ns.IsTestMode and ns.IsTestMode()) or (ns.IsUnlocked and ns.IsUnlocked()) or false
    f:ClearAllPoints()
    local petOn = ns.Unit(key).enable and petFrame and petFrame.GetObjectType
    if (c.place or "FRAME") == "FRAME" and petOn then
        f:SetPoint("CENTER", petFrame, c.point or "LEFT", c.x or 0, c.y or 0)
    else
        local pos = c.screen or { "CENTER", -485, -150 }
        f:SetPoint(pos[1] or "CENTER", UIParent, pos[1] or "CENTER", (pos[2] or 0) / s, (pos[3] or 0) / s)
    end
    Update(f)
end

-- options preview of the pet card: a sample icon on the preview frame (on-frame placement only)
function ns.HappinessPreview(frame, cfg)
    local t = frame.fufHappyPreview
    local c = cfg.happiness
    local show = frame.fufKey == "pet" and c and c.enable and (c.place or "FRAME") == "FRAME"
    if not show then if t then t:Hide() end return end
    if not t then
        t = CreateFrame("Frame", nil, frame.fufOverlay or frame)
        t.ring = t:CreateTexture(nil, "BACKGROUND")
        t.ring:SetTexture(MEDIA .. "circle"); t.ring:SetVertexColor(0, 0, 0, 0.9); t.ring:SetAllPoints()
        t.tex = t:CreateTexture(nil, "ARTWORK")
        frame.fufHappyPreview = t
    end
    t:SetFrameLevel((frame.fufOverlay or frame):GetFrameLevel() + 2)
    t:SetSize(c.size or 20, c.size or 20)
    t:ClearAllPoints()
    t:SetPoint("CENTER", frame, c.point or "LEFT", c.x or 0, c.y or 0)
    SetLook(t, c, SAMPLE[1])
    t:Show()
end
