-- FreeUnitFrames - layout: builds every widget once, then applies the settings.
-- Values coming from the game can be "secret" on WoW Forever: this file never
-- compares or computes with unit data, oUF and Blizzard functions do that.

local ADDON, ns = ...
local oUF = ns.oUF
local WHITE = ns.WHITE

local DEBUFF_COLORS = {
    Magic   = { 0.20, 0.60, 1.00 },
    Curse   = { 0.60, 0.00, 1.00 },
    Disease = { 0.60, 0.40, 0.00 },
    Poison  = { 0.00, 0.60, 0.00 },
    None    = { 0.80, 0.00, 0.00 },
}

-- ------------------------------------------------------------ aura text look
-- kind = "duration" or "count": font, outline, colour and size come from the aura settings
-- (font / outline INHERIT = the General ones; size 0 = automatic from the icon size).
local function AuraTextStyle(fs, c, kind, iconSize)
    if not fs then return end
    local size = tonumber(c[kind .. "Size"]) or 0
    if size <= 0 then size = math.max(8, math.floor(iconSize * (kind == "duration" and 0.5 or 0.45))) end
    ns.SetFont(fs, size, c[kind .. "Outline"], c[kind .. "Font"])
    local col = c[kind .. "Color"]
    if type(col) == "table" then fs:SetTextColor(col[1] or 1, col[2] or 1, col[3] or 1) end
end

-- ------------------------------------------------------------ helpers
local function Edges(f, layer, size)
    f.fufEdges = f.fufEdges or {}
    size = size or 1
    local spec = { { "TOPLEFT", "TOPRIGHT", "h", 0, size }, { "BOTTOMLEFT", "BOTTOMRIGHT", "h", 0, -size },
                   { "TOPLEFT", "BOTTOMLEFT", "v", -size, 0 }, { "TOPRIGHT", "BOTTOMRIGHT", "v", size, 0 } }
    for i, p in ipairs(spec) do
        local e = f.fufEdges[i] or f:CreateTexture(nil, layer or "BORDER", nil, 7)
        e:SetTexture(WHITE)
        e:ClearAllPoints()
        -- edges sit just outside the frame
        if p[3] == "h" then
            e:SetPoint(p[1], f, p[1], -size, p[5]); e:SetPoint(p[2], f, p[2], size, p[5]); e:SetHeight(size)
        else
            e:SetPoint(p[1], f, p[1], p[4], 0); e:SetPoint(p[2], f, p[2], p[4], 0); e:SetWidth(size)
        end
        f.fufEdges[i] = e
    end
end
local function EdgeColor(f, r, g, b, a)
    if not f.fufEdges then return end
    for _, e in ipairs(f.fufEdges) do e:SetVertexColor(r, g, b, a or 1) end
end
local function EdgesShown(f, shown)
    if not f.fufEdges then return end
    for _, e in ipairs(f.fufEdges) do e:SetShown(shown) end
end
ns.Edges, ns.EdgeColor, ns.EdgesShown = Edges, EdgeColor, EdgesShown

-- Resolve a border setting { mode, useColor, color, size } against the General settings.
-- defaultShown: what INHERIT means for this element (normally the General "Border" switch).
local function ResolveBorder(b, defaultShown)
    local g = ns.Global()
    b = b or {}
    local shown
    if b.mode == "SHOW" then shown = true elseif b.mode == "HIDE" then shown = false else shown = defaultShown end
    local c = (b.useColor and b.color) or g.borderColor
    local size = (b.size and b.size > 0) and b.size or (g.borderSize or 1)
    return shown, c, size
end
ns.ResolveBorder = ResolveBorder

local function ApplyBorder(f, b, defaultShown, layer)
    local shown, c, size = ResolveBorder(b, defaultShown)
    Edges(f, layer or "BORDER", size)
    EdgeColor(f, c[1], c[2], c[3], c[4] or 1)
    EdgesShown(f, shown)
    return shown and size or 0
end
ns.ApplyBorder = ApplyBorder

local function Bar(parent, name)
    local b = CreateFrame("StatusBar", name, parent)
    b:SetStatusBarTexture(WHITE)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetTexture(WHITE)
    return b
end

-- frames that exist once (a bar can float anywhere on the screen); group frames are repeated
local SINGLE = { player = true, target = true, targettarget = true, focus = true, focustarget = true, pet = true }
function ns.CanFloat(key) return SINGLE[key] or false end
-- place a bar freely on the screen; pos = { point, x, y } in screen units (the frame scale is undone)
local function PlaceOnScreen(region, pos, key)
    local s = ns.UnitScale and ns.UnitScale(key) or 1
    region:ClearAllPoints()
    region:SetPoint(pos[1] or "CENTER", UIParent, pos[1] or "CENTER", (pos[2] or 0) / s, (pos[3] or 0) / s)
end

-- sample content (auras, cast, icons) is drawn in test mode, unlock mode and in the options preview
local function Samples(frame)
    return (ns.IsTestMode and ns.IsTestMode()) or (ns.IsUnlocked and ns.IsUnlocked()) or (frame and frame.fufIsPreview) or false
end
ns.Samples = Samples
-- the options preview always keeps its bars on itself (never on the screen, never on another frame)
local function Floats(frame) return SINGLE[frame.fufKey] and not frame.fufIsPreview end

local function SetElement(frame, name, on)
    if on then
        if not frame:IsElementEnabled(name) then frame:EnableElement(name) end
    else
        if frame:IsElementEnabled(name) then frame:DisableElement(name) end
    end
end

local function Indicator(frame, layer)
    local t = frame.fufOverlay:CreateTexture(nil, layer or "OVERLAY", nil, 7)
    t:SetSize(16, 16)
    return t
end

-- ------------------------------------------------------------ auras
-- Filters use the game's own aura flags (computed by oUF with C_UnitAuras, never secret).
-- Durations can be secret for some units: when unknown, the duration rules let the aura through.
local TYPE_FLAGS = {
    dispellable = "auraIsRaidPlayerDispellable",
    raid        = "auraIsRaid",
    cc          = "auraIsCrowdControl",
    defensive   = "auraIsBigDefensive",
    external    = "auraIsExternalDefensive",
    cancelable  = "auraIsCancelable",
}
local function AuraFilter(_, element, _, button, aura, ...)
    local f = element.fufFilter
    if not f then return true end
    -- who cast it
    if f.who ~= "all" then
        local mine = button.isPlayer or (aura and aura.auraIsPlayer) or false
        if f.who == "mine" and not mine then return false end
        if f.who == "others" and mine then return false end
    end
    -- type flags: keep the aura if it has at least one ticked flag
    if f.types and next(f.types) then
        local any, known = false, false
        for k, on in pairs(f.types) do
            if on then
                local v = aura and aura[TYPE_FLAGS[k]]
                if v ~= nil then known = true end
                if v then any = true; break end
            end
        end
        if known and not any then return false end
    end
    -- duration (5th value after aura in the CustomFilter arguments = duration)
    if f.durationMode ~= "any" or (f.maxDuration or 0) > 0 then
        local duration = select(5, ...)
        if duration ~= nil and oUF:NotSecretValue(duration) then
            if f.durationMode == "timed" and duration <= 0 then return false end
            if f.durationMode == "permanent" and duration > 0 then return false end
            if (f.maxDuration or 0) > 0 and duration > f.maxDuration then return false end
        end
    end
    return true
end

local function AuraPostCreate(element, button)
    button.fufBg = button:CreateTexture(nil, "BACKGROUND")
    button.fufBg:SetAllPoints()
    button.fufBg:SetTexture(WHITE)
    button.fufBg:SetVertexColor(0, 0, 0, 1)
    button.Icon:ClearAllPoints()
    button.Icon:SetPoint("TOPLEFT", 1, -1)
    button.Icon:SetPoint("BOTTOMRIGHT", -1, 1)
    button.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.Cooldown:ClearAllPoints()
    button.Cooldown:SetPoint("TOPLEFT", 1, -1)
    button.Cooldown:SetPoint("BOTTOMRIGHT", -1, 1)
    if button.Cooldown.SetDrawEdge then button.Cooldown:SetDrawEdge(false) end
    button.Cooldown:SetReverse(true)
    if button.Overlay then button.Overlay:SetTexture(nil); button.Overlay.Show = button.Overlay.Hide; button.Overlay:Hide() end
    button.Count:ClearAllPoints()
    button.Count:SetPoint("BOTTOMRIGHT", 1, 1)
    if element.fufCfg then AuraTextStyle(button.Count, element.fufCfg, "count", element.size or 20) else ns.SetFont(button.Count, element.fufCountSize) end
    if button.Text then button.Text:Hide() end
    if ns.MasqueAdd then ns.MasqueAdd(button) end
end

local function AuraPostUpdate(element, _, button, _, _, _, _, debuffType)
    button.Cooldown:SetHideCountdownNumbers(not element.fufDuration)
    button.Count:SetShown(element.fufCount)
    if element.fufTypeBorder and button.isDebuff then
        local key = oUF:NotSecretValue(debuffType) and debuffType or "None"
        local c = DEBUFF_COLORS[key] or DEBUFF_COLORS.None
        button.fufBg:SetVertexColor(c[1], c[2], c[3], 1)
    else
        button.fufBg:SetVertexColor(0, 0, 0, 1)
    end
end

local function BuildAurasOUF(frame, key)
    local name = frame:GetName() and (frame:GetName() .. key) or nil
    local el = CreateFrame("Frame", name, frame)
    el:SetSize(1, 1)
    el.CustomFilter = AuraFilter
    el.PostCreateButton = AuraPostCreate
    el.PostUpdateButton = AuraPostUpdate
    el.tooltipAnchor = "ANCHOR_BOTTOMRIGHT"
    frame[key] = el
end

local function ApplyAurasOUF(frame, key, c, buffsEl)
    local el = frame[key]
    if not c.enable then SetElement(frame, key, false); el:Hide(); return end
    local size, sp = c.size, c.spacing
    el.size = size
    el.spacing = sp
    el.num = c.perRow * c.rows
    el.maxCols = c.perRow
    el["growth-x"] = c.growthX
    el["growth-y"] = c.growthY
    el.initialAnchor = (c.growthY == "UP" and "BOTTOM" or "TOP") .. (c.growthX == "RIGHT" and "LEFT" or "RIGHT")
    el.fufFilter = { who = c.who or "all", types = c.types or {}, durationMode = c.durationMode or "any", maxDuration = c.maxDuration or 0 }
    el.fufDuration = c.showDuration
    el.fufCount = c.showCount
    el.fufTypeBorder = c.typeBorder
    el.fufCountSize = math.max(8, math.floor(size * 0.45))
    el.fufCfg = c
    el:SetSize(c.perRow * (size + sp) - sp, c.rows * (size + sp) - sp)
    el:ClearAllPoints()
    local h = (c.growthX == "RIGHT") and "LEFT" or "RIGHT"
    local v = (c.growthY == "UP") and "BOTTOM" or "TOP"
    local anchor = frame
    if key == "Debuffs" and c.anchorTo == "BUFFS" and buffsEl and buffsEl:IsShown() then anchor = buffsEl end
    if c.side == "TOP" then
        el:SetPoint("BOTTOM" .. h, anchor, "TOP" .. h, c.x, c.y)
    elseif c.side == "BOTTOM" then
        el:SetPoint("TOP" .. h, anchor, "BOTTOM" .. h, c.x, c.y)
    elseif c.side == "LEFT" then
        el:SetPoint(v .. "RIGHT", anchor, v .. "LEFT", c.x, c.y)
    else
        el:SetPoint(v .. "LEFT", anchor, v .. "RIGHT", c.x, c.y)
    end
    -- existing buttons: refresh fonts / sizes
    for i = 1, #el do
        local b = el[i]
        if b and b.Count then AuraTextStyle(b.Count, c, "count", size) end
    end
    el:Show()
    SetElement(frame, key, true)
end

-- ------------------------------------------------------------ auras on WoW Forever (Aura Containers)
-- Since patch 12.1 (WoW Forever 1.60), aura data is secret: addons can no longer read
-- auras themselves (oUF's aura element is switched off on these clients). Blizzard gives
-- "Aura Containers" instead: the game fills the buttons, the addon only chooses filters,
-- layout and looks. This is what ElvUI does too.
local USE_CONTAINERS = false
do
    local ok, test = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate, DisableUntrustedLayoutScriptsTemplate")
    if ok and test then USE_CONTAINERS = true; test:Hide() end
end
ns.USE_AURA_CONTAINERS = USE_CONTAINERS

local FLOW = AnchorUtil and AnchorUtil.FlowDirection
local SORT_METHOD = _G.AuraContainerSortMethod
local SORT_DIR = _G.AuraContainerSortDirection
local DISPEL_STYLE = Enum and Enum.CustomAuraButtonDispelTypeTextureStyle
local TYPE_TOKENS = {
    dispellable = "RAID_PLAYER_DISPELLABLE", raid = "RAID", cc = "CROWD_CONTROL",
    defensive = "BIG_DEFENSIVE", external = "EXTERNAL_DEFENSIVE", cancelable = "CANCELABLE",
}

local function StyleButton(container, button)
    local c = container.fufCfg
    if not button.fufIcon then
        local border = button:CreateTexture(nil, "BACKGROUND", nil, -2)
        border:SetTexture(WHITE); border:SetAllPoints(); border:SetVertexColor(0, 0, 0, 1)
        button.fufBorder = border
        local dispel = button:CreateTexture(nil, "BACKGROUND", nil, -1)
        dispel:SetTexture(WHITE); dispel:SetAllPoints()
        button.fufDispel = dispel
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", 1, -1); icon:SetPoint("BOTTOMRIGHT", -1, 1)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        button.fufIcon = icon
        local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        cd:SetAllPoints(icon)
        if cd.SetDrawEdge then cd:SetDrawEdge(false) end
        cd:SetReverse(true)
        button.fufCooldown = cd
        local tf = CreateFrame("Frame", nil, button)
        tf:SetAllPoints(); tf:SetFrameLevel(cd:GetFrameLevel() + 1)
        local count = tf:CreateFontString(nil, "OVERLAY")
        ns.SetFont(count)
        count:SetPoint("BOTTOMRIGHT", 1, 1)
        button.fufCount = count
        if button.SetIcon then button:SetIcon(icon) end
        if button.SetDurationCooldown then button:SetDurationCooldown(cd) end
        if button.SetApplicationCount then button:SetApplicationCount(count) end
        if ns.MasqueAdd then ns.MasqueAdd(button) end
    end
    if not c then return end
    button:SetSize(c.size, c.size)
    if button.SetMouseMotionEnabled then button:SetMouseMotionEnabled(true) end
    -- right-click to cancel only on your own player frame (never on the target, even when it is you)
    if button.SetCancelAuraButtons then
        if container.fufKeyUnit == "player" and container.fufHelpful then
            button:SetCancelAuraButtons("RightButtonUp")
        else
            pcall(button.SetCancelAuraButtons, button, nil)
        end
    end
    AuraTextStyle(button.fufCount, c, "count", c.size)
    button.fufCount:SetShown(c.showCount and true or false)
    button.fufCooldown:SetHideCountdownNumbers(not c.showDuration)
    -- duration numbers: size and place (Blizzard draws them; their format can't be changed)
    local cdText = button.fufCooldown.GetCountdownFontString and button.fufCooldown:GetCountdownFontString()
    if cdText then
        AuraTextStyle(cdText, c, "duration", c.size)
        cdText:ClearAllPoints()
        local dp = c.durationPoint or "CENTER"
        cdText:SetPoint(dp, button, dp, 0, dp == "TOP" and 2 or (dp == "BOTTOM" and -2 or 0))
    end
    -- border coloured by debuff type: Blizzard colours this texture itself
    if button.ClearDispelTypeTextures then button:ClearDispelTypeTextures() end
    button.fufDispel:SetVertexColor(0, 0, 0, 1)
    if c.typeBorder and container.fufHarmful and button.AddDispelTypeTexture then
        button:AddDispelTypeTexture(button.fufDispel, {
            style = DISPEL_STYLE and DISPEL_STYLE.PreserveAsset or nil,
            showWhenHarmful = true, showWhenHelpful = false, showWithoutDispelType = true,
        })
    end
end

local function BuildAurasContainer(frame, key)
    local name = frame:GetName() and (frame:GetName() .. key) or nil
    local ct = CreateFrame("AuraContainer", name, frame, "CustomAuraContainerTemplate, DisableUntrustedLayoutScriptsTemplate")
    ct:Hide()
    ct:SetSize(1, 1)
    ct.fufKnown, ct.fufActive, ct.fufButtons = {}, {}, {}
    ct.fufHarmful = (key == "Debuffs")
    ct.fufHelpful = (key == "Buffs")
    frame[key] = ct
end

-- ------------------------------------------------------------ aura preview (test / unlock mode)
-- Aura containers only show real auras, so the layout is drawn with sample icons.
local SAMPLE_BUFFS = { "Spell_Holy_WordFortitude", "Spell_Nature_Regeneration", "Spell_Holy_MagicalSentry", "Spell_Holy_PowerWordShield",
    "Ability_Warrior_BattleShout", "Spell_Nature_LightningShield", "Spell_Holy_GreaterBlessingofKings", "Spell_Frost_FrostArmor02" }
local SAMPLE_DEBUFFS = { "Spell_Shadow_ShadowWordPain", "Spell_Nature_Slow", "Spell_Shadow_CurseOfTounges", "Spell_Fire_Immolation",
    "Ability_Warrior_Sunder", "Spell_Frost_FrostNova", "Spell_Nature_FaerieFire", "Spell_Shadow_AbominationExplosion" }
local SAMPLE_TYPE = { { 0.20, 0.60, 1.00 }, { 0.60, 0.00, 1.00 }, { 0.60, 0.40, 0.00 }, { 0.00, 0.60, 0.00 }, { 0.80, 0.00, 0.00 } }
local SAMPLE_TIME = { "12", "4m", "", "38", "2m", "", "9", "55" }
local function AuraPreview(frame, key, ct, c, show)
    local pv = frame["fufPreview" .. key]
    if not show then
        if pv then pv:Hide() end
        ct:SetAlpha(1)
        return
    end
    if not pv then
        pv = CreateFrame("Frame", nil, frame)
        pv.icons = {}
        pv.fufPreviewOf = key
        frame["fufPreview" .. key] = pv
    end
    pv:SetFrameLevel(frame:GetFrameLevel() + 6)
    -- same place as the container, but never anchored to it (anchoring to an aura container is forbidden)
    pv:ClearAllPoints()
    local a = ct.fufAnchor
    if a then
        local rel = a[2]
        if rel and rel ~= frame and rel.fufPreviewOf then rel = frame["fufPreview" .. rel.fufPreviewOf] or frame end
        pv:SetPoint(a[1], rel or frame, a[3], a[4], a[5])
    else
        pv:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 6)
    end
    pv:SetSize(c.perRow * (c.size + c.spacing) - c.spacing, c.rows * (c.size + c.spacing) - c.spacing)
    ct:SetAlpha(0)     -- hide the real auras of the test unit while the samples are shown
    local size, sp = c.size, c.spacing
    local n = math.min(c.perRow * c.rows, 8)
    local h = (c.growthX == "RIGHT") and "LEFT" or "RIGHT"
    local v = (c.growthY == "UP") and "BOTTOM" or "TOP"
    local dx = (c.growthX == "RIGHT") and 1 or -1
    local dy = (c.growthY == "UP") and 1 or -1
    local harmful = key == "Debuffs"
    for i = 1, math.max(n, #pv.icons) do
        local b = pv.icons[i]
        if i <= n then
            if not b then
                b = CreateFrame("Frame", nil, pv)
                b.border = b:CreateTexture(nil, "BACKGROUND"); b.border:SetAllPoints(); b.border:SetTexture(WHITE)
                b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetPoint("TOPLEFT", 1, -1); b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
                b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                b.time = b:CreateFontString(nil, "OVERLAY")
                b.count = b:CreateFontString(nil, "OVERLAY")
                pv.icons[i] = b
            end
            local col, row = (i - 1) % c.perRow, math.floor((i - 1) / c.perRow)
            b:SetSize(size, size)
            b:ClearAllPoints()
            b:SetPoint(v .. h, pv, v .. h, dx * col * (size + sp), dy * row * (size + sp))
            b.icon:SetTexture("Interface\\Icons\\" .. (harmful and SAMPLE_DEBUFFS or SAMPLE_BUFFS)[(i - 1) % 8 + 1])
            local bc = (harmful and c.typeBorder) and SAMPLE_TYPE[(i - 1) % 5 + 1] or { 0, 0, 0 }
            b.border:SetVertexColor(bc[1], bc[2], bc[3], 1)
            AuraTextStyle(b.time, c, "duration", size)
            local dp = c.durationPoint or "CENTER"
            b.time:ClearAllPoints(); b.time:SetPoint(dp, b, dp, 0, dp == "TOP" and 2 or (dp == "BOTTOM" and -2 or 0))
            b.time:SetText(c.showDuration and SAMPLE_TIME[(i - 1) % 8 + 1] or "")
            AuraTextStyle(b.count, c, "count", size)
            b.count:ClearAllPoints(); b.count:SetPoint("BOTTOMRIGHT", 1, 1)
            b.count:SetText((c.showCount and i % 3 == 0) and tostring(i % 5 + 1) or "")
            b:Show()
        elseif b then
            b:Hide()
        end
    end
    pv:Show()
end

-- the groups (filters) of one container, from our settings
local function ContainerGroups(key, c)
    local base = (key == "Buffs") and "HELPFUL" or "HARMFUL"
    if c.who == "mine" then base = base .. "|PLAYER" elseif c.who == "others" then base = base .. "|!PLAYER" end
    local groups = {}
    if c.types and next(c.types) then
        for t, on in pairs(c.types) do
            if on and TYPE_TOKENS[t] then groups["fuf_" .. t] = base .. "|" .. TYPE_TOKENS[t] end
        end
    end
    if not next(groups) then groups.fuf_all = base end
    return groups
end

-- ------------------------------------------------------------ weapon enchants (player)
-- The game keeps temporary weapon enchants apart from auras, so the aura containers never show them.
-- They get their own row of icons: after the buff rows (default), detached next to the unit frame, or free on the
-- screen. Always placed relative to the unit frame / the screen, never to an aura container.
local ENCHANT_SLOTS = { 16, 17, 18 }
-- sample enchants (preview, test and unlock mode): { icon, seconds left, charges }
local ENCHANT_SAMPLES = {
    { "Interface\\Icons\\Ability_Poisons", 1500, 3 },
    { "Interface\\Icons\\Spell_Nature_RockBiter", 540, 0 },
}
local OPPOSITE = { TOPLEFT = "BOTTOMRIGHT", TOP = "BOTTOM", TOPRIGHT = "BOTTOMLEFT", LEFT = "RIGHT", CENTER = "CENTER",
                   RIGHT = "LEFT", BOTTOMLEFT = "TOPRIGHT", BOTTOM = "TOP", BOTTOMRIGHT = "TOPLEFT" }
local GROW = { RIGHT = { "LEFT", 1, 0 }, LEFT = { "RIGHT", -1, 0 }, UP = { "BOTTOM", 0, 1 }, DOWN = { "TOP", 0, -1 } }

local function EnchantUpdate(ef)
    if not ef:IsShown() then return end
    local e, geo = ef.fufCfg, ef.fufGeo
    if not (e and geo) then return end
    local data
    if ef.fufSample then
        data = {}
        for i, smp in ipairs(ENCHANT_SAMPLES) do data[i] = { true, smp[2] * 1000, smp[3] } end
        data[3] = {}
    else
        local ok, mh, mhT, mhC, _, oh, ohT, ohC, _, rg, rgT, rgC = pcall(GetWeaponEnchantInfo)
        if not ok then return end
        data = { { mh, mhT, mhC }, { oh, ohT, ohC }, { rg, rgT, rgC } }
    end
    local n = 0
    local size, sp = geo.size, geo.spacing
    local g = GROW[geo.growth] or GROW.RIGHT
    for i, d in ipairs(data) do
        local b = ef.buttons[i]
        local has = false
        pcall(function() has = d[1] and true or false end)
        if has then
            n = n + 1
            b:SetSize(size, size)
            b:ClearAllPoints()
            b:SetPoint(g[1], ef, g[1], g[2] * (n - 1) * (size + sp), g[3] * (n - 1) * (size + sp))
            if ef.fufSample then
                b.icon:SetTexture(ENCHANT_SAMPLES[i][1])
            else
                b.icon:SetTexture(GetInventoryItemTexture("player", ENCHANT_SLOTS[i]))
            end
            b.cd:SetHideCountdownNumbers(not e.showDuration)
            pcall(function()
                if ef.fufSample then
                    if not b.fufSampled then
                        b.fufSampled = true
                        b.fufEnd = nil
                        b.cd:SetCooldown(GetTime() - 300, ENCHANT_SAMPLES[i][2] + 300)
                    end
                    return
                end
                if b.fufSampled then b.fufSampled = nil; b.fufEnd = nil; b.cd:Clear() end
                local ms = d[2]
                if ms and ms > 0 then
                    local now = GetTime()
                    local finish = now + ms / 1000
                    if not b.fufEnd or math.abs(b.fufEnd - finish) > 1 then
                        b.fufEnd = finish
                        b.cd:SetCooldown(now, ms / 1000)
                    end
                else
                    b.fufEnd = nil
                    b.cd:Clear()
                end
            end)
            -- charges (poisons): shown when there is at least one
            b.count:SetText("")
            if e.showCount then pcall(function() if d[3] and d[3] > 0 then b.count:SetText(d[3]) end end) end
            b:Show()
        else
            b.fufEnd, b.fufSampled = nil, nil
            b:Hide()
        end
    end
end

-- where the buff container sits: { point, relativeTo, relativePoint, x, y }
local function ContainerPoint(frame, key, c, buffsEl)
    local h = (c.growthX == "RIGHT") and "LEFT" or "RIGHT"
    local v = (c.growthY == "UP") and "BOTTOM" or "TOP"
    local anchor = frame
    if key == "Debuffs" and c.anchorTo == "BUFFS" and buffsEl and buffsEl:IsShown() then anchor = buffsEl end
    if c.side == "TOP" then return { "BOTTOM" .. h, anchor, "TOP" .. h, c.x, c.y }, anchor
    elseif c.side == "BOTTOM" then return { "TOP" .. h, anchor, "BOTTOM" .. h, c.x, c.y }, anchor
    elseif c.side == "LEFT" then return { v .. "RIGHT", anchor, v .. "LEFT", c.x, c.y }, anchor
    else return { v .. "LEFT", anchor, v .. "RIGHT", c.x, c.y }, anchor end
end

local function BuildEnchantRow(frame)
    local ef = CreateFrame("Frame", nil, frame)
    ef.buttons = {}
    for i = 1, 3 do
        local b = CreateFrame("Button", nil, ef)
        local bg = b:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 1)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetPoint("TOPLEFT", 1, -1); b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
        b.cd:SetAllPoints(b.icon); b.cd:SetReverse(true); b.cd:SetDrawEdge(false)
        -- the stack text lives above the cooldown swipe
        local tf = CreateFrame("Frame", nil, b)
        tf:SetAllPoints(); tf:SetFrameLevel(b.cd:GetFrameLevel() + 1)
        b.count = tf:CreateFontString(nil, "OVERLAY"); ns.SetFont(b.count, 10)
        b.count:SetPoint("BOTTOMRIGHT", -1, 1)
        b.slot = ENCHANT_SLOTS[i]
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
            GameTooltip:SetInventoryItem("player", self.slot)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:Hide()
        ef.buttons[i] = b
    end
    ef:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
    ef:RegisterEvent("PLAYER_ENTERING_WORLD")
    ef:SetScript("OnEvent", EnchantUpdate)
    C_Timer.NewTicker(1, function() EnchantUpdate(ef) end)
    frame.fufEnchants = ef
    return ef
end

-- bc = the buffs settings (bc.enchants = the row's own settings); pt = where the buff container sits
local function ApplyEnchants(frame, bc, pt)
    local e = bc.enchants
    local ef = frame.fufEnchants
    if frame.fufKey ~= "player" or not e or not e.enable then
        if ef then ef:Hide() end
        return
    end
    ef = ef or BuildEnchantRow(frame)
    ef.fufCfg = e
    ef.fufSample = Samples(frame) and true or false
    local place = e.place or "BUFFS"
    local size, sp, growth
    if place == "BUFFS" then
        size, sp = bc.size, bc.spacing
        growth = (bc.growthX == "LEFT") and "LEFT" or "RIGHT"
    else
        size = (e.size and e.size > 0) and e.size or bc.size
        sp = e.spacing or 2
        growth = GROW[e.growth] and e.growth or "RIGHT"
    end
    ef.fufGeo = { size = size, spacing = sp, growth = growth }
    local vertical = (growth == "UP" or growth == "DOWN")
    local len = 3 * size + 2 * sp
    ef:SetSize(vertical and size or len, vertical and len or size)
    ef:ClearAllPoints()
    if place == "SCREEN" and Floats(frame) then
        PlaceOnScreen(ef, e.screen or { "CENTER", 0, -120 }, frame.fufKey)
    elseif place == "BUFFS" then
        local dy = (bc.growthY == "UP") and 1 or -1
        local rows = bc.enable and bc.rows or 0
        ef:SetPoint(pt[1], frame, pt[3], pt[4], pt[5] + dy * rows * (size + sp))
    else
        local a = e.anchor or "BOTTOM"
        ef:SetPoint(OPPOSITE[a] or "TOP", frame, a, e.x or 0, e.y or 0)
    end
    -- text look
    local dp = e.durationPoint or "CENTER"
    for _, b in ipairs(ef.buttons) do
        AuraTextStyle(b.count, e, "count", size)
        b.count:ClearAllPoints(); b.count:SetPoint("BOTTOMRIGHT", -1, 1)
        local cdText = b.cd.GetCountdownFontString and b.cd:GetCountdownFontString()
        if cdText then
            AuraTextStyle(cdText, e, "duration", size)
            cdText:ClearAllPoints()
            cdText:SetPoint(dp, b, dp, 0, dp == "TOP" and 2 or (dp == "BOTTOM" and -2 or 0))
        end
    end
    ef:Show()
    EnchantUpdate(ef)
end

local function ApplyAurasContainer(frame, key, c, buffsEl)
    local ct = frame[key]
    -- weapon enchants of the player: their own row, whether the buffs are shown or not
    if key == "Buffs" then ApplyEnchants(frame, c, (ContainerPoint(frame, key, c, buffsEl))) end
    if not c.enable then
        if ct.SetEnabled then ct:SetEnabled(false) end
        ct:Hide()
        AuraPreview(frame, key, ct, c, false)
        return
    end
    ct.fufCfg = c
    ct.fufKeyUnit = frame.fufKey
    local size, sp = c.size, c.spacing
    local num = c.perRow * c.rows
    ct:SetSize(c.perRow * (size + sp) - sp, c.rows * (size + sp) - sp)
    -- position (same rules as before)
    ct:ClearAllPoints()
    local h = (c.growthX == "RIGHT") and "LEFT" or "RIGHT"
    local v = (c.growthY == "UP") and "BOTTOM" or "TOP"
    local pt, anchor = ContainerPoint(frame, key, c, buffsEl)
    ct:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5])
    ct.fufAnchor = pt
    if anchor ~= frame then anchor.fufPreviewOf = "Buffs" end
    -- unit first, and shown: the container only builds its groups while it is shown (as in ElvUI)
    local unit = frame.unit or frame:GetAttribute("unit")
    ct:SetUnit(unit or "")
    if ct.SetEnabled then ct:SetEnabled(true) end
    ct:Show()
    -- flow layout
    ct:SetFlowLayoutAnchorPoint(v .. h)
    if FLOW then
        ct:SetFlowLayoutGrowthDirection(c.growthX == "LEFT" and FLOW.Left or FLOW.Right, c.growthY == "DOWN" and FLOW.Down or FLOW.Up)
    end
    ct:SetFlowLayoutPadding(0, 0, 0, 0)
    ct:SetFlowLayoutMaximumLineSize(c.perRow * (size + sp))
    local layout = { elementWidth = size, elementHeight = size, elementSpacing = sp, lineSpacing = sp, groupSpacing = sp }
    local candidates = ((c.maxDuration or 0) > 0) and { maxDuration = c.maxDuration } or nil
    local sortM = SORT_METHOD and SORT_METHOD.Default
    local sortD = SORT_DIR and SORT_DIR.Normal
    -- groups
    local groups = ContainerGroups(key, c)
    for gk in pairs(ct.fufActive) do
        if not groups[gk] then ct:SetAuraGroupMaxFrameCount(gk, 0); ct.fufActive[gk] = nil end
    end
    for gk, filter in pairs(groups) do
        if ct.fufKnown[gk] then
            ct:SetAuraGroupCandidateFilters(gk, candidates)
            ct:SetAuraGroupFilterString(gk, filter)
            ct:SetAuraGroupMaxFrameCount(gk, num)
            if sortM then ct:SetAuraGroupSortMethod(gk, sortM, sortD) end
            ct:SetAuraGroupLayout(gk, layout)
        else
            ct:AddAuraGroup(gk, filter, {
                initializeFrame = function(button)
                    ct.fufButtons[button] = true
                    StyleButton(ct, button)
                end,
                candidateFilters = candidates,
                maxFrameCount = num,
                sortMethod = sortM, sortDirection = sortD,
                layout = layout,
            })
            ct.fufKnown[gk] = filter
        end
        ct.fufActive[gk] = filter
    end
    for button in pairs(ct.fufButtons) do StyleButton(ct, button) end
    if ct.UpdateAllAuras then ct:UpdateAllAuras() end
    AuraPreview(frame, key, ct, c, Samples(frame))
end

-- keeps the containers on the right unit (group frames change unit, target changes...)
local function ContainersUpdate(self)
    local unit = self.unit or self:GetAttribute("unit")
    for _, key in ipairs({ "Buffs", "Debuffs" }) do
        local ct = self[key]
        if ct and ct.fufCfg and ct.fufCfg.enable and ct:IsShown() then
            ct:SetUnit(unit or "")
            if ct.UpdateAllAuras then ct:UpdateAllAuras() end
        end
    end
end
if USE_CONTAINERS then
    oUF:AddElement("FUFAuraContainers", ContainersUpdate,
        function(self) return self.FUFAuraContainers and true end,
        function() end)
end

local function BuildAuras(frame, key)
    if USE_CONTAINERS then
        BuildAurasContainer(frame, key)
        frame.FUFAuraContainers = true
    else
        BuildAurasOUF(frame, key)
    end
end
local function ApplyAuras(frame, key, c, buffsEl)
    if USE_CONTAINERS then return ApplyAurasContainer(frame, key, c, buffsEl) end
    return ApplyAurasOUF(frame, key, c, buffsEl)
end

-- ------------------------------------------------------------ castbar
-- class colour of a unit as { r, g, b }, or nil (NPCs, unknown, secret values)
function ns.UnitClassColor(unit, key)
    local token
    if key == "player" or unit == "player" then
        local _, t = UnitClass("player"); token = t
    elseif unit then
        local ok, isPlayer = pcall(UnitIsPlayer, unit)
        if ok and oUF:NotSecretValue(isPlayer) and isPlayer then
            local ok2, _, t = pcall(UnitClass, unit)
            if ok2 and oUF:NotSecretValue(t) then token = t end
        end
    end
    if not token then return nil end
    local col = (oUF.colors and oUF.colors.class and oUF.colors.class[token]) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[token])
    if not col then return nil end
    local r, g, b = col.r or col[1], col.g or col[2], col.b or col[3]
    if col.GetRGB then r, g, b = col:GetRGB() end
    if not r then return nil end
    return { r, g, b }
end

local function CastColor(element)
    local c = element.fufColor
    local frame = element.__owner
    -- class colour for players (NPCs keep the custom colour)
    if element.fufClassColor and frame then
        local cc = ns.UnitClassColor(frame.unit, frame.fufKey)
        if cc then c = cc end
    end
    if c then element:SetStatusBarColor(c[1], c[2], c[3]) end
    if element.fufShieldColor and oUF:NotSecretValue(element.notInterruptible) and element.notInterruptible then
        local s = element.fufShieldColor
        element:SetStatusBarColor(s[1], s[2], s[3])
    end
end

local function BuildCastbar(frame)
    local cb = Bar(frame, frame:GetName() and (frame:GetName() .. "Castbar") or nil)
    cb:SetFrameLevel(frame:GetFrameLevel() + 2)
    Edges(cb, "BORDER", 1)
    cb.Text = cb:CreateFontString(nil, "OVERLAY")
    cb.Text:SetPoint("LEFT", 4, 0)
    cb.Text:SetJustifyH("LEFT")
    cb.Time = cb:CreateFontString(nil, "OVERLAY")
    cb.Time:SetPoint("RIGHT", -4, 0)
    cb.Time:SetJustifyH("RIGHT")
    ns.SetFont(cb.Text, 11)
    ns.SetFont(cb.Time, 11)
    cb.Text:SetPoint("RIGHT", cb.Time, "LEFT", -4, 0)
    cb.Spark = cb:CreateTexture(nil, "OVERLAY")
    cb.Spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    cb.Spark:SetBlendMode("ADD")
    cb.Spark:SetSize(12, 24)
    cb.Spark:SetPoint("CENTER", cb:GetStatusBarTexture(), "RIGHT", 0, 0)
    cb.Icon = cb:CreateTexture(nil, "ARTWORK")
    cb.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    cb.IconBg = cb:CreateTexture(nil, "BACKGROUND", nil, -1)
    cb.IconBg:SetTexture(WHITE)
    cb.IconBg:SetVertexColor(0, 0, 0, 1)
    cb.timeToHold = 0.4
    cb.PostCastStart = CastColor
    cb.PostCastInterruptible = CastColor
    cb.PostChannelStart = CastColor
    frame.Castbar = cb
end

local function ApplyCastbar(frame, c, cfg)
    local cb = frame.Castbar
    if not c.enable then SetElement(frame, "Castbar", false); cb:Hide(); return end
    local g = ns.Global()
    local h = c.height
    local w = (c.width and c.width > 0) and c.width or cfg.width
    local bShown, _, bSz = ResolveBorder(c.border, g.border)
    local bs = bShown and bSz or 0
    local iconGap = 2 * bs + 1          -- the icon border and the bar border just touch
    local iconW = c.icon and (h + iconGap) or 0
    cb:ClearAllPoints()
    if c.onScreen and Floats(frame) then
        PlaceOnScreen(cb, c.screen or { "CENTER", 0, -240 }, frame.fufKey)
    else
        cb:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", c.x + iconW, c.y - bs)
    end
    cb:SetSize(math.max(1, w - iconW), h)
    cb:SetStatusBarTexture(ns.Texture())
    cb.bg:SetTexture(ns.Texture(g.bgTexture))
    cb.bg:SetVertexColor(c.color[1] * 0.2, c.color[2] * 0.2, c.color[3] * 0.2, 0.9)
    local bsize = ApplyBorder(cb, c.border, g.border)
    local _, bcol = ResolveBorder(c.border, g.border)
    cb.IconBg:SetVertexColor(bcol[1], bcol[2], bcol[3], bsize > 0 and (bcol[4] or 1) or 0)
    cb.fufColor = c.color
    cb.fufClassColor = c.colorClass or nil
    -- colour right away too (test mode, and the first cast)
    do
        local col = c.color
        if c.colorClass then
            if frame.fufIsPreview then col = ns.SimClassColor(frame) or col
            else col = ns.UnitClassColor(frame.unit, frame.fufKey) or col end
        end
        if col then cb:SetStatusBarColor(col[1], col[2], col[3]) end
    end
    cb.fufShieldColor = c.shieldColor
    cb.Spark:SetHeight(h * 2)
    ns.SetFont(cb.Text, math.max(9, math.min(14, math.floor(h * 0.62))))
    ns.SetFont(cb.Time, math.max(9, math.min(14, math.floor(h * 0.62))))
    cb.Text:SetShown(c.showName)
    cb.Time:SetShown(c.showTime)
    cb.Icon:ClearAllPoints()
    cb.Icon:SetPoint("TOPRIGHT", cb, "TOPLEFT", -iconGap, 0)
    cb.Icon:SetSize(h, h)
    cb.Icon:SetShown(c.icon)
    cb.IconBg:ClearAllPoints()
    local o = math.max(bsize, 0)
    cb.IconBg:SetPoint("TOPLEFT", cb.Icon, -o, o)
    cb.IconBg:SetPoint("BOTTOMRIGHT", cb.Icon, o, -o)
    cb.IconBg:SetShown(c.icon)
    if Samples(frame) then
        -- sample cast, so the castbar can be seen and placed
        SetElement(frame, "Castbar", false)
        cb.fufSample = true
        cb:SetMinMaxValues(0, 1); cb:SetValue(0.62)
        cb.Text:SetText("Frostbolt"); cb.Time:SetText("1.2")
        cb.Icon:SetTexture("Interface\\Icons\\Spell_Frost_FrostBolt02")
        cb:SetAlpha(1)
        cb:Show()
        return
    end
    if cb.fufSample then cb.fufSample = nil; cb:Hide() end
    SetElement(frame, "Castbar", true)
end

-- ------------------------------------------------------------ bar backgrounds
-- "dark": fixed colour. "tint": the bar colour darkened (like ElvUI's backdrop
-- multiplier). Bar colours can be secret on Forever: fall back to the fixed colour then.
function ns.BarBackground(element, _, color, r, g, b)
    local bg = element.bg
    if not bg then return end
    local fixed = element.fufBgColor or { 0.12, 0.12, 0.13 }
    if element.fufBgMode == "tint" then
        if color and color.GetRGB then r, g, b = color:GetRGB() end
        if not r and element.fufCustom then r, g, b = unpack(element.fufCustom) end
        if not r then r, g, b = element:GetStatusBarColor() end
        if r and oUF:NotSecretValue(r) and oUF:NotSecretValue(g) and oUF:NotSecretValue(b) then
            local m = element.fufBgMult or 0.3
            bg:SetVertexColor(r * m, g * m, b * m, 1)
            return
        end
    end
    bg:SetVertexColor(fixed[1], fixed[2], fixed[3], fixed[4] or 1)
end

-- ------------------------------------------------------------ class power (combo points)
-- Drawing, styles and animations live in Combo.lua; here the holder is placed and sized.
local function BuildClassPower(frame)
    ns.ComboBuild(frame)
end

local function ApplyClassPower(frame, c, cfg)
    local cp = frame.ClassPower
    if not cp then return end
    if not c.enable then
        if cp.fufDriver then UnregisterStateDriver(cp.fufHolder, "visibility"); cp.fufDriver = nil end   -- else it would show it again
        SetElement(frame, "ClassPower", false); cp.fufHolder:Hide(); return
    end
    cp.fufHolder:ClearAllPoints()
    local w = cfg.width
    if c.onScreen and Floats(frame) then
        PlaceOnScreen(cp.fufHolder, c.screen or { "CENTER", 0, -170 }, frame.fufKey)
    else
        -- above / below the player frame, or on the target frame (combo points belong to the target)
        local where = c.where or "TARGET_TOP"
        local anchor = frame
        if where:find("TARGET") and not frame.fufIsPreview then
            local tf = ns.Object and ns.Object("target")
            if tf and tf.GetObjectType then
                anchor = tf
                local tc = ns.Unit("target")
                w = tc and tc.width or w
                -- the target frame may be scaled differently: follow it
                local s = (ns.UnitScale and ns.UnitScale("target") or 1) / (ns.UnitScale and ns.UnitScale(frame.fufKey) or 1)
                w = w * s
            end
        end
        if where:find("BOTTOM") then
            cp.fufHolder:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -(c.gap + 1))
        else
            cp.fufHolder:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, c.gap + 1)
        end
    end
    -- bars use "Height"; every other look uses "Size" (height of one point)
    local style = c.style or "BARS"
    local h = (style == "BARS") and c.height or (c.size or 16)
    cp.fufHolder:SetSize((c.width and c.width > 0) and c.width or w, h)
    -- when to show: always, with an attackable target, or in combat with one (default)
    local preview = Samples(frame)
    local cond = ({ ALWAYS = nil, HOSTILE = "[@target,exists,harm,nodead] show; hide",
                    COMBAT_HOSTILE = "[combat,@target,exists,harm,nodead] show; hide" })[c.visibility or "COMBAT_HOSTILE"]
    if cp.fufDriver then UnregisterStateDriver(cp.fufHolder, "visibility"); cp.fufDriver = nil end
    if cond and not preview then
        RegisterStateDriver(cp.fufHolder, "visibility", cond)
        cp.fufDriver = true
    else
        cp.fufHolder:Show()
    end
    if frame.fufIsPreview then return end      -- the preview draws its sample (ApplyPreviewSim)
    if preview then
        -- test / unlock mode: 3 sample points so the bar can be seen and placed
        SetElement(frame, "ClassPower", false)
        ns.ComboSample(cp, c, false)
        return
    end
    ns.ComboLive(cp)
    SetElement(frame, "ClassPower", true)
    ns.ComboApply(cp, c)
end

-- ------------------------------------------------------------ simulated state (options preview)
-- The options preview never shows a real unit: it draws a made-up one (health 65 %, power 40 %, a sample name,
-- level, class, unit type) so every setting can be tried, whatever you are targeting. Tag texts are evaluated
-- against the sample values. The real frames are not touched.
local SIM_HEALTH, SIM_POWER = 0.65, 0.40
local SIM_CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID", "DEATHKNIGHT" }
ns.SIM_TYPES = {
    { key = "AUTO", label = "Automatic (by frame)" }, { key = "PLAYER", label = "Player (class colour)" },
    { key = "FRIENDLY", label = "Friendly NPC" }, { key = "NEUTRAL", label = "Neutral NPC" },
    { key = "HOSTILE", label = "Hostile NPC" }, { key = "TAPPED", label = "Tapped NPC" },
}
local SIM_AUTO = { target = "HOSTILE", targettarget = "HOSTILE", focus = "HOSTILE", focustarget = "HOSTILE", boss = "HOSTILE", pet = "FRIENDLY" }
local SIM_NAMES = { PLAYER = "Decard", FRIENDLY = "Stormwind Guard", NEUTRAL = "Wild Boar", HOSTILE = "Training Dummy", TAPPED = "Mottled Boar" }
local SIM_POWER_TOKEN = { WARRIOR = "RAGE", ROGUE = "ENERGY", DEATHKNIGHT = "RUNIC_POWER" }
local FALLBACK_REACTION = { FRIENDLY = { 0.29, 0.69, 0.30 }, NEUTRAL = { 0.85, 0.77, 0.36 }, HOSTILE = { 0.78, 0.25, 0.25 } }
local REACTION_INDEX = { FRIENDLY = 5, NEUTRAL = 4, HOSTILE = 2 }
local FALLBACK_POWER = { MANA = { 0, 0, 1 }, RAGE = { 1, 0, 0 }, ENERGY = { 1, 1, 0 }, RUNIC_POWER = { 0, 0.82, 1 }, COMBO_POINTS = { 1, 0.85, 0.2 } }

local function RGBOf(c)
    if type(c) ~= "table" then return nil end
    if c.GetRGB then return c:GetRGB() end
    return c.r or c[1], c.g or c[2], c.b or c[3]
end
local function ClassRGB(class)
    if not class then return nil end
    local c = (oUF.colors and oUF.colors.class and oUF.colors.class[class]) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
    return RGBOf(c)
end
local function PowerRGB(token)
    local c = (oUF.colors and oUF.colors.power and oUF.colors.power[token]) or (PowerBarColor and PowerBarColor[token]) or FALLBACK_POWER[token]
    return RGBOf(c)
end
ns.PowerRGB = PowerRGB
local function ReactionRGB(typ)
    if typ == "TAPPED" then typ = "HOSTILE" end
    local idx = REACTION_INDEX[typ or "FRIENDLY"] or 5
    local c = oUF.colors and oUF.colors.reaction and oUF.colors.reaction[idx]
    local r, g, b = RGBOf(c)
    if r then return r, g, b end
    c = FALLBACK_REACTION[typ] or FALLBACK_REACTION.FRIENDLY
    return c[1], c[2], c[3]
end
local function Hex(r, g, b)
    local function byte(v) return math.max(0, math.min(255, math.floor((v or 1) * 255 + 0.5))) end
    return format("|cff%02x%02x%02x", byte(r), byte(g), byte(b))
end

local function PlayerClass()
    local ok, _, token = pcall(UnitClass, "player")
    return (ok and type(token) == "string") and token or "WARRIOR"
end
-- classes offered by the preview selector
function ns.SimClassList()
    local out, seen = {}, {}
    local function add(token)
        if seen[token] then return end
        seen[token] = true
        local label = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token]) or (token:sub(1, 1) .. token:sub(2):lower())
        out[#out + 1] = { key = token, label = label }
    end
    for _, t in ipairs(SIM_CLASSES) do
        if not RAID_CLASS_COLORS or RAID_CLASS_COLORS[t] then add(t) end
    end
    add(PlayerClass())
    return out
end
-- the simulated class / unit type (account-wide, kept in FreeUnitFramesDB.preview)
function ns.GetSim()
    local db = ns.GetDB()
    local st = db and db.preview or {}
    return { class = st.class or PlayerClass(), type = st.type or "AUTO", classIsDefault = st.class == nil }
end
function ns.SetSim(field, value)
    local db = ns.GetDB()
    if not db then return end
    db.preview = db.preview or {}
    if field == "type" and value == "AUTO" then value = nil end
    db.preview[field] = value
end

local function SimData(frame)
    local st = ns.GetSim()
    local key = frame.fufKey
    local typ = st.type
    if typ == "AUTO" then typ = SIM_AUTO[key] or "PLAYER" end
    local isPlayer = (typ == "PLAYER")
    local class = st.class
    local token = SIM_POWER_TOKEN[class] or "MANA"
    local ppMax = (token == "MANA") and 54200 or 100
    local hpMax = 187400
    local lvl = isPlayer and 60 or 62
    local ok, plvl = pcall(UnitLevel, "player")
    if ok and type(plvl) == "number" and plvl > 0 then lvl = isPlayer and plvl or plvl + 2 end
    local name = SIM_NAMES[typ]
    if key == "boss" then name = "Hogger" elseif key == "pet" then name = "Whiskers" end
    return {
        type = typ, isPlayer = isPlayer, class = isPlayer and class or nil, userClass = class,
        name = name, level = lvl, elite = (typ == "HOSTILE" and key == "boss"),
        hp = math.floor(hpMax * SIM_HEALTH), hpMax = hpMax, pp = math.floor(ppMax * SIM_POWER), ppMax = ppMax, powerToken = token,
    }
end
ns.SimData = SimData

-- number shortened like the game does (1.2K, 3.4M)
local function Abbr(n)
    if n >= 1e6 then return format("%.1fM", n / 1e6) elseif n >= 1e3 then return format("%.1fK", n / 1e3) end
    return tostring(math.floor(n))
end
local function Level(d)
    local c = GetQuestDifficultyColor and GetQuestDifficultyColor(d.level)
    local r, g, b = RGBOf(c)
    return Hex(r or 1, g or 0.82, b or 0), tostring(d.level)
end
local function SimTags()
    local T = {}
    local function pct(d, dec) return format(dec and "%.1f%%" or "%d%%", d.hp / d.hpMax * 100) end
    T["name"] = function(d) return d.name end
    T["raidcolor"] = function(d) if d.class then local r, g, b = ClassRGB(d.class); if r then return Hex(r, g, b) end end end
    T["powercolor"] = function(d) local r, g, b = PowerRGB(d.powerToken); if r then return Hex(r, g, b) end end
    T["difficulty"] = function(d) return (Level(d)) end
    T["smartlevel"] = function(d) return tostring(d.level) end
    T["level"] = T["smartlevel"]
    T["classification"] = function(d) return d.elite and "Elite" or "" end
    T["shortclassification"] = function(d) return d.elite and "+" or "" end
    T["smartclass"] = function(d) return d.class and ((LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[d.class]) or d.class:sub(1, 1) .. d.class:sub(2):lower()) or "" end
    T["class"] = T["smartclass"]
    T["race"] = function(d) return d.isPlayer and "Human" or "" end
    T["creature"] = function(d) return d.isPlayer and "" or "Humanoid" end
    T["sex"] = function() return "Male" end
    T["faction"] = function(d) return d.type == "HOSTILE" and "Horde" or "Alliance" end
    T["group"] = function(d) return d.isPlayer and "1" or "" end
    for _, k in ipairs({ "status", "dead", "offline", "leader", "resting", "pvp", "threat", "threatcolor", "affix" }) do T[k] = function() return "" end end
    T["curhp"] = function(d) return tostring(d.hp) end
    T["maxhp"] = function(d) return tostring(d.hpMax) end
    T["perhp"] = function(d) return format("%d", d.hp / d.hpMax * 100) end
    T["missinghp"] = function(d) return tostring(d.hpMax - d.hp) end
    T["curpp"] = function(d) return tostring(d.pp) end
    T["maxpp"] = function(d) return tostring(d.ppMax) end
    T["perpp"] = function(d) return format("%d", d.pp / d.ppMax * 100) end
    T["missingpp"] = function(d) return tostring(d.ppMax - d.pp) end
    -- our own tags
    T["fuf:hp"] = function(d) return Abbr(d.hp) end
    T["fuf:maxhp"] = function(d) return Abbr(d.hpMax) end
    T["fuf:perhp"] = function(d) return pct(d, true) end
    T["fuf:perhp0"] = function(d) return pct(d, false) end
    T["fuf:hpfull"] = function(d) return format("%s / %s", Abbr(d.hp), Abbr(d.hpMax)) end
    T["fuf:hpstatus"] = function(d) return format("%s | %s", Abbr(d.hp), pct(d, true)) end
    T["fuf:status"] = function(d) return pct(d, false) end
    T["fuf:targetname"] = function(d)
        local r, g, b = ClassRGB("WARRIOR")
        return r and format("%s%s|r", Hex(r, g, b), "Thrall") or "Thrall"
    end
    T["fuf:level"] = function(d) local col, txt = Level(d); return format("%s%s|r", col, txt) end
    T["fuf:pp"] = function(d) return Abbr(d.pp) end
    T["fuf:perpp"] = function(d) return format("%d%%", d.pp / d.ppMax * 100) end
    T["fuf:ppfull"] = function(d) return format("%s / %s", Abbr(d.pp), Abbr(d.ppMax)) end
    return T
end
local SIM_TAGS = SimTags()

-- Evaluate an oUF tag string ("[raidcolor][name] [fuf:hpstatus]", with [prefix$>tag<$suffix]) against sample data.
-- Tags we have no sample for fall back to the real oUF tag on your own character.
function ns.EvalTagString(fmt, d)
    return (tostring(fmt or ""):gsub("%[([^%[%]]-)%]", function(inner)
        local prefix, rest = inner:match("^(.-)%$>(.*)$")
        rest = rest or inner
        local name, suffix = rest:match("^(.-)<%$(.*)$")
        name = (name or rest):gsub("%b()", "")
        local val
        local fn = SIM_TAGS[name]
        if fn then
            local ok, r = pcall(fn, d)
            if ok then val = r end
        else
            local real = oUF.Tags and oUF.Tags.Methods and oUF.Tags.Methods[name]
            if type(real) == "function" then
                local ok, r = pcall(function() return format("%s", real("player", "player")) end)
                if ok then val = r end
            end
        end
        if val == nil or val == "" then return "" end
        return (prefix or "") .. val .. (suffix or "")
    end))
end

-- class colour of the simulated unit, or nil (NPC)
function ns.SimClassColor(frame)
    local d = frame.fufSim or SimData(frame)
    if not d.class then return nil end
    local r, g, b = ClassRGB(d.class)
    return r and { r, g, b } or nil
end

-- ------------------------------------------------------------ build (style function)
local function Style(frame, unit)
    frame:RegisterForClicks("AnyUp")
    if ns.IsSpawningPreview and ns.IsSpawningPreview() then frame.fufIsPreview = true end
    -- HookScript: group frames use the secure enter/leave handlers of their header
    -- unit tooltip on mouse-over (own handler: the Blizzard one is not there on every client)
    frame:HookScript("OnEnter", function(self)
        local unit = self.unit or self:GetAttribute("unit")
        if not unit or (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) then return end
        if GameTooltip_SetDefaultAnchor then GameTooltip_SetDefaultAnchor(GameTooltip, self) else GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT") end
        pcall(GameTooltip.SetUnit, GameTooltip, unit)
        GameTooltip:Show()
        self.fufTooltip = true
    end)
    frame:HookScript("OnLeave", function(self)
        if self.fufTooltip then self.fufTooltip = nil; GameTooltip:Hide() end
    end)

    local key = frame.fufKey or (unit and unit:gsub("%d+$", ""):gsub("^party.*", "party"):gsub("^raid.*", "raid"):gsub("^boss.*", "boss"))
    if frame:GetParent() and frame:GetParent().fufKey then key = frame:GetParent().fufKey end
    frame.fufKey = key

    frame.colors = setmetatable({ health = oUF:CreateColor(0.2, 0.2, 0.2) }, { __index = oUF.colors })

    frame.fufBg = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    frame.fufBg:SetAllPoints()
    frame.fufBg:SetTexture(WHITE)
    Edges(frame, "BORDER", 1)

    -- threat: a 2px coloured outline around the frame (only the outline, the inside stays untouched)
    local threat = CreateFrame("Frame", nil, frame)
    threat:SetPoint("TOPLEFT", -1, 1)
    threat:SetPoint("BOTTOMRIGHT", 1, -1)
    threat:SetFrameLevel(math.max(0, frame:GetFrameLevel() - 1))
    Edges(threat, "BACKGROUND", 2)
    threat.SetVertexColor = function(self, r, g, b) EdgeColor(self, r, g, b, 1) end
    threat:Hide()
    frame.ThreatIndicator = threat

    local health = Bar(frame)
    health.colorDisconnected = true
    health.colorHealth = true
    frame.Health = health

    local power = Bar(frame)
    power.frequentUpdates = true
    -- the game only sends power events on server ticks; reading it ~20 times a second shows regen as it happens
    power:SetScript("OnUpdate", function(self, elapsed)
        if not self.fufLive then return end
        self.fufT = (self.fufT or 0) + elapsed
        if self.fufT < 0.05 then return end
        self.fufT = 0
        local owner = self.__owner
        if self.ForceUpdate and owner and owner.unit then
            self:ForceUpdate()
            for _, fs in ipairs(owner.fufPowerTexts or {}) do
                if fs:IsShown() and fs.UpdateTag then fs:UpdateTag() end
            end
        end
    end)
    frame.Power = power

    local ph = CreateFrame("Frame", nil, frame)
    ph:SetFrameLevel(frame:GetFrameLevel() + 1)
    ph.bg = ph:CreateTexture(nil, "BACKGROUND", nil, -7)
    ph.bg:SetAllPoints()
    ph.bg:SetTexture(WHITE)
    Edges(ph, "BORDER", 1)
    ph:Hide()
    local model = CreateFrame("PlayerModel", nil, ph)
    model:SetAllPoints()
    model:Hide()
    local tex = ph:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:Hide()
    -- 3D: oUF resets zoom and camera on every unit change, so our settings are re-applied after it
    model.PostUpdate = function(el) ns.ApplyModel(el) end
    -- 2D portraits: crop the round frame; class icons come from an atlas and keep their own coords
    tex.PostUpdate = function(el) if not el.useClassBase then el:SetTexCoord(0.15, 0.85, 0.15, 0.85) end end
    frame.fufPortraitHolder, frame.fufPortraitModel, frame.fufPortraitTex = ph, model, tex
    frame.Portrait = model

    local overlay = CreateFrame("Frame", nil, frame)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(frame:GetFrameLevel() + 6)
    frame.fufOverlay = overlay

    frame.fufTexts = {}
    for _, k in ipairs({ "name", "health", "power", "level" }) do ns.TextString(frame, k) end

    BuildAuras(frame, "Buffs")
    BuildAuras(frame, "Debuffs")
    BuildCastbar(frame)
    if key == "player" then BuildClassPower(frame) end

    frame.RaidTargetIndicator = Indicator(frame)
    frame.LeaderIndicator = Indicator(frame)
    frame.ReadyCheckIndicator = Indicator(frame)
    if key == "player" then
        frame.CombatIndicator = Indicator(frame)
        frame.RestingIndicator = Indicator(frame)
    end
    frame.Range = { insideAlpha = 1, outsideAlpha = 0.45 }

    ns.RegisterFrame(frame)
    -- settings are applied once oUF has finished setting the frame up (see below)
end

-- ------------------------------------------------------------ texts
function ns.TextString(frame, key)
    local fs = frame.fufTexts[key]
    if not fs then
        fs = frame.fufOverlay:CreateFontString(nil, "OVERLAY")
        ns.SetFont(fs) -- a FontString needs a font before any SetText
        fs:SetWordWrap(false)
        frame.fufTexts[key] = fs
    end
    return fs
end

local function ApplyText(frame, fs, t)
    if t and t.enable and t.format and t.format ~= "" then
        ns.SetFont(fs, t.size, t.outline, t.font)
        local target = (t.attach == "POWER" and frame.Power:IsShown() and frame.Power) or (t.attach == "FRAME" and frame) or frame.Health
        fs:ClearAllPoints()
        t.point = t.point or "CENTER"
        fs:SetPoint(t.point, target, t.point, t.x or 0, t.y or 0)
        local j = t.point:find("LEFT") and "LEFT" or (t.point:find("RIGHT") and "RIGHT" or "CENTER")
        fs:SetJustifyH(j)
        fs:SetWidth((t.width and t.width > 0) and t.width or 0)
        local mode = t.colorMode or (t.useColor and "CUSTOM" or "TAGS")
        local c = (mode == "CUSTOM" and t.color) or { 1, 1, 1 }
        fs:SetTextColor(c[1], c[2], c[3])
        local fmt = t.format
        if mode == "CLASS" then fmt = "[raidcolor]" .. fmt .. "|r"
        elseif mode == "POWER" then fmt = "[powercolor]" .. fmt .. "|r" end
        if frame.fufIsPreview then
            -- the options preview shows sample values: no tag, the text is computed from the sample data
            if fs.fufFormat then frame:Untag(fs); fs.fufFormat = nil end
            fs:SetText(ns.EvalTagString(fmt, SimData(frame)))
            fs:Show()
            return
        end
        if fs.fufFormat ~= fmt then frame:Tag(fs, fmt); fs.fufFormat = fmt end
        if fmt:find("pp") or fmt:find("mana") or fmt:find("power") then
            frame.fufPowerTexts = frame.fufPowerTexts or {}
            local found
            for _, x in ipairs(frame.fufPowerTexts) do if x == fs then found = true end end
            if not found then table.insert(frame.fufPowerTexts, fs) end
        end
        fs:Show()
        if fs.UpdateTag then fs:UpdateTag() end
    else
        if fs.fufFormat then frame:Untag(fs); fs.fufFormat = nil end
        fs:Hide()
    end
end

local function ApplyTexts(frame, cfg)
    local used = {}
    for _, k in ipairs({ "name", "health", "power", "level" }) do
        ApplyText(frame, ns.TextString(frame, k), cfg.texts[k]); used[k] = true
    end
    for _, t in ipairs(cfg.texts.custom or {}) do
        local key = "c:" .. tostring(t.id)
        ApplyText(frame, ns.TextString(frame, key), t); used[key] = true
    end
    for key, fs in pairs(frame.fufTexts) do
        if not used[key] then ApplyText(frame, fs, nil) end -- deleted custom text
    end
end

-- ------------------------------------------------------------ 3D portrait camera
-- zoom: 0 = whole body, 1 = face. distance: camera distance (1 = default).
-- modelX/modelY move the camera view, rotation turns the model (degrees).
function ns.ApplyModel(model)
    local frame = model.__owner or model:GetParent():GetParent()
    local cfg = frame and frame.fufKey and ns.Unit(frame.fufKey)
    if not cfg then return end
    local p = cfg.portrait
    if model.state == false then return end -- question mark model: leave it alone
    model:SetPortraitZoom(p.zoom or 1)
    model:SetCamDistanceScale(p.distance or 1)
    if model.SetViewTranslation then model:SetViewTranslation((p.modelX or 0) * 100, (p.modelY or 0) * 100) end
    model:SetRotation(math.rad(p.rotation or 0))
    if model.SetDesaturation then model:SetDesaturation(p.desaturate or 0) end
    if model.SetPaused then model:SetPaused(p.paused and true or false) end
    if model.SetModelAlpha then model:SetModelAlpha(p.side == "OVERLAY" and (p.alpha or 0.35) or 1) end
end

-- ------------------------------------------------------------ apply settings to one frame
-- sample icons shown in test mode / unlock mode, so indicators can be placed without a group
local PREVIEW = {
    RaidTargetIndicator = { "Interface\\TargetingFrame\\UI-RaidTargetingIcons", 0.75, 1, 0.25, 0.5 },   -- skull
    LeaderIndicator     = { "Interface\\GroupFrame\\UI-Group-LeaderIcon", 0, 1, 0, 1 },
    ReadyCheckIndicator = { "Interface\\RaidFrame\\ReadyCheck-Ready", 0, 1, 0, 1 },
    CombatIndicator     = { "Interface\\CharacterFrame\\UI-StateIcon", 0.5, 1, 0, 0.49 },
    RestingIndicator    = { "Interface\\CharacterFrame\\UI-StateIcon", 0, 0.5, 0, 0.421875 },
}
local function PlaceIndicator(frame, el, name, c, enabledFor)
    if not el then return end
    local on = c and c.enable and (enabledFor == nil or enabledFor)
    if on then
        el:ClearAllPoints()
        el:SetSize(c.size, c.size)
        el:SetPoint("CENTER", frame, c.point, c.x, c.y)
    end
    local preview = on and Samples(frame)
    if preview and PREVIEW[name] then
        -- the element would hide the icon (no group, no ready check...): turn it off and show a sample
        SetElement(frame, name, false)
        local t = PREVIEW[name]
        el:SetTexture(t[1])
        el:SetTexCoord(t[2], t[3], t[4], t[5])
        el.fufPreview = true
        el:Show()
        return
    end
    if el.fufPreview then
        -- back to the real element: give it back its default look
        el.fufPreview = nil
        local t = PREVIEW[name]
        if t then el:SetTexture(t[1]); el:SetTexCoord(t[2], t[3], t[4], t[5]) end
        el:Hide()
    end
    SetElement(frame, name, on and true or false)
    if not on then el:Hide() end
end

-- ------------------------------------------------------------ options preview: draw the sample state
-- Every live oUF element is switched off on the preview frame (they would show the real player and overwrite
-- the sample values), then bars, portrait, combo points and threat are drawn by hand.
local LIVE_ELEMENTS = { "Health", "Power", "Portrait", "ClassPower", "Castbar", "ThreatIndicator", "Range", "FUFAuraContainers",
    "RaidTargetIndicator", "LeaderIndicator", "ReadyCheckIndicator", "CombatIndicator", "RestingIndicator" }
local CLASS_ICONS = "Interface\\TargetingFrame\\UI-Classes-Circles"

local function ApplyPreviewSim(frame, cfg)
    local d = SimData(frame)
    frame.fufSim = d
    for _, name in ipairs(LIVE_ELEMENTS) do
        if frame:IsElementEnabled(name) then frame:DisableElement(name) end
    end
    local hc, pc = cfg.health, cfg.power

    -- health: 65 %, coloured like oUF would (tapped, class, reaction, then the custom colour)
    local health = frame.Health
    local r, g, b
    if d.type == "TAPPED" and hc.colorTapped then r, g, b = 0.6, 0.6, 0.6
    elseif d.isPlayer and hc.colorClass then r, g, b = ClassRGB(d.class)
    elseif hc.colorReaction then r, g, b = ReactionRGB(d.type) end
    if not r then r, g, b = hc.color[1], hc.color[2], hc.color[3] end
    health:SetMinMaxValues(0, d.hpMax)
    health:SetValue(d.hp)
    health:SetStatusBarColor(r, g, b)
    ns.BarBackground(health, "player", nil, r, g, b)
    health:Show()

    -- power: 40 %
    local power = frame.Power
    if pc.enable and (pc.height or 0) > 0 then
        local pr, pg, pb
        if pc.colorPower then pr, pg, pb = PowerRGB(d.powerToken)
        elseif pc.colorClass and d.class then pr, pg, pb = ClassRGB(d.class) end
        if not pr then pr, pg, pb = pc.color[1], pc.color[2], pc.color[3] end
        power:SetMinMaxValues(0, d.ppMax)
        power:SetValue(d.pp)
        power:SetStatusBarColor(pr, pg, pb)
        ns.BarBackground(power, "player", nil, pr, pg, pb)
        power:Show()
    else
        power:Hide()
    end

    -- portrait: the 3D model of your character, or the class icon / your portrait for the flat styles
    local p = cfg.portrait
    if p.enable then
        local want = frame.Portrait
        want:Show()
        if want == frame.fufPortraitModel then
            pcall(want.SetUnit, want, "player")
            ns.ApplyModel(want)
        else
            local done = false
            if p.style ~= "class" and SetPortraitTexture then done = pcall(SetPortraitTexture, want, "player") end
            if p.style == "class" or not done then
                local tc = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[d.userClass]
                want:SetTexture(CLASS_ICONS)
                if tc then want:SetTexCoord(tc[1], tc[2], tc[3], tc[4]) else want:SetTexCoord(0, 1, 0, 1) end
            end
        end
    end

    -- combo points: 3 of 5, written again when their look changes
    local cp = frame.ClassPower
    if cp then
        local c = ns.Unit("player").classPower
        local key = frame.fufKey
        local wanted = key == "player" or (key == "target" and not c.onScreen and (c.where or "TARGET_TOP"):find("TARGET"))
        if c and c.enable and wanted then
            cp.fufHolder:Show()
            local sig = table.concat({ tostring(c.style), tostring(c.animate), tostring(c.animSpeed), tostring(c.size), tostring(c.thickness),
                tostring(c.line), tostring(c.irregular), tostring(c.tallyGap), tostring(c.newShapes) }, "|")
            ns.ComboSample(cp, c, cp.fufPreviewSig ~= sig and c.animate)
            cp.fufPreviewSig = sig
        else
            cp.fufHolder:Hide()
        end
    end

    -- pet happiness: a sample icon (pet card)
    if ns.HappinessPreview then ns.HappinessPreview(frame, cfg) end

    -- threat: a sample outline
    local threat = frame.ThreatIndicator
    if cfg.threat.enable then
        EdgeColor(threat, 1, 0.55, 0, 1)
        EdgesShown(threat, true)
        threat:Show()
    else
        threat:Hide()
    end
    frame:SetAlpha(1)
end

function ns.ApplyFrame(frame)
    local key = frame.fufKey
    local cfg = ns.Unit(key)
    local g = ns.Global()
    if not cfg then return end

    if not InCombatLockdown() then frame:SetSize(cfg.width, cfg.height) end

    -- background / border
    frame.fufBg:SetVertexColor(unpack(g.bgColor))
    local fb = ApplyBorder(frame, cfg.border, g.border)
    -- threat outline sits just outside the frame border
    frame.ThreatIndicator:ClearAllPoints()
    frame.ThreatIndicator:SetPoint("TOPLEFT", -fb, fb)
    frame.ThreatIndicator:SetPoint("BOTTOMRIGHT", fb, -fb)

    -- geometry ----------------------------------------------------------
    -- The frame is a box: portrait (left/right) and power bar (any side) take
    -- room inside it, the health bar fills the rest. Nothing overlaps.
    local W, H = cfg.width, cfg.height
    local p = cfg.portrait
    local pc = cfg.power
    local inside = p.enable and (p.side == "LEFT" or p.side == "RIGHT")
    local pw = inside and ((p.width and p.width > 0) and p.width or H) or 0
    local L = (inside and p.side == "LEFT") and (pw + 1) or 0
    local R = (inside and p.side == "RIGHT") and (pw + 1) or 0
    local T, B = 0, 0
    local det = pc.enable and (pc.detach or "NONE") or "NONE"
    if det == "SCREEN" and not Floats(frame) then det = "FRAME" end
    local thick = (pc.enable and det == "NONE") and pc.height or 0   -- room taken inside the frame
    local pos = pc.position or "BOTTOM"

    local power = frame.Power
    power.fufLive = (SINGLE[key] and pc.enable and not frame.fufIsPreview) and true or nil
    power:ClearAllPoints()
    if pc.enable and det ~= "NONE" then
        -- detached: own box, own size, own border
        local pwW = (pc.detW and pc.detW > 0) and pc.detW or W
        local pwH = (pc.detH and pc.detH > 0) and pc.detH or (pc.height or 8)
        power:SetSize(pwW, pwH)
        if det == "SCREEN" then
            PlaceOnScreen(power, pc.screen or { "CENTER", 0, -200 }, key)
        else
            local a = pc.detAnchor or "BOTTOM"
            local opposite = ({ LEFT = "RIGHT", RIGHT = "LEFT", TOP = "BOTTOM", BOTTOM = "TOP" })[a] or "TOP"
            power:SetPoint(opposite, frame, a, pc.detX or 0, pc.detY or 0)
        end
        power:SetOrientation(pwH > pwW and "VERTICAL" or "HORIZONTAL")
        ApplyBorder(power, pc.border, g.border)
    elseif power.fufEdges then
        EdgesShown(power, false)
    end
    if thick > 0 then
        local gap = pc.gap or 0
        if pos == "BOTTOM" then
            power:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", L, 0)
            power:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -R, 0)
            power:SetHeight(thick)
            B = thick + gap
        elseif pos == "TOP" then
            power:SetPoint("TOPLEFT", frame, "TOPLEFT", L, 0)
            power:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -R, 0)
            power:SetHeight(thick)
            T = thick + gap
        elseif pos == "LEFT" then
            power:SetPoint("TOPLEFT", frame, "TOPLEFT", L, 0)
            power:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", L, 0)
            power:SetWidth(thick)
            L = L + thick + gap
        else -- RIGHT
            power:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -R, 0)
            power:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -R, 0)
            power:SetWidth(thick)
            R = R + thick + gap
        end
        power:SetOrientation((pos == "LEFT" or pos == "RIGHT") and "VERTICAL" or "HORIZONTAL")
    end

    local health = frame.Health
    health:ClearAllPoints()
    health:SetPoint("TOPLEFT", frame, "TOPLEFT", L, -T)
    health:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -R, B)
    health:SetStatusBarTexture(ns.Texture())
    health.bg:SetTexture(ns.Texture(g.bgTexture))
    health:SetOrientation(cfg.health.vertical and "VERTICAL" or "HORIZONTAL")
    health:SetReverseFill(cfg.health.reverse and true or false)
    local hc = cfg.health
    health.colorClass = hc.colorClass
    health.colorClassPet = false
    health.colorReaction = hc.colorReaction
    health.colorTapping = hc.colorTapped
    frame.colors.health = oUF:CreateColor(hc.color[1], hc.color[2], hc.color[3])
    health.fufBgMode, health.fufBgColor, health.fufBgMult = hc.bgMode, hc.bgColor, hc.bgMult
    health.PostUpdateColor = ns.BarBackground
    ns.BarBackground(health)
    health:SetAlpha(cfg.barAlpha or 1)
    power:SetAlpha(cfg.barAlpha or 1)

    if pc.enable and (pc.height or 0) > 0 then
        power:SetStatusBarTexture(ns.Texture())
        power.__texture = power:GetStatusBarTexture() and power:GetStatusBarTexture():GetTexture() or power.__texture
        power.bg:SetTexture(ns.Texture(g.bgTexture))
        power.colorPower = pc.colorPower
        power.colorClass = pc.colorClass
        power.colorDisconnected = true
        local custom = not pc.colorPower and not pc.colorClass
        power.fufCustom = custom and pc.color or nil
        if custom then power:SetStatusBarColor(pc.color[1], pc.color[2], pc.color[3]) end
        power.fufBgMode, power.fufBgColor, power.fufBgMult = pc.bgMode, pc.bgColor, pc.bgMult
        power.PostUpdateColor = ns.BarBackground
        ns.BarBackground(power)
        power:Show()
        SetElement(frame, "Power", true)
    else
        SetElement(frame, "Power", false)
        power:Hide()
    end

    -- portrait --------------------------------------------------------------
    local holder, model, tex = frame.fufPortraitHolder, frame.fufPortraitModel, frame.fufPortraitTex
    local want = (p.style == "3D") and model or tex
    if frame.Portrait ~= want or not p.enable then
        SetElement(frame, "Portrait", false)
        model:Hide(); tex:Hide()
        frame.Portrait = want
    end
    if p.enable then
        holder:ClearAllPoints()
        local overlay = (p.side == "OVERLAY")
        if p.side == "LEFT" then
            holder:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
            holder:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
            holder:SetWidth(pw)
        elseif p.side == "RIGHT" then
            holder:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
            holder:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
            holder:SetWidth(pw)
        elseif overlay then
            holder:SetAllPoints(health)
        else -- DETACHED: own square next to the frame
            local size = (p.size and p.size > 0) and p.size or H
            local a = p.anchor or "LEFT"
            local opposite = ({ LEFT = "RIGHT", RIGHT = "LEFT", TOP = "BOTTOM", BOTTOM = "TOP" })[a] or "RIGHT"
            holder:SetSize(size, (p.detHeight and p.detHeight > 0) and p.detHeight or size)
            holder:SetPoint(opposite, frame, a, p.x or 0, p.y or 0)
        end
        holder:SetFrameLevel(health:GetFrameLevel() + (overlay and 1 or 0))
        holder:SetAlpha(overlay and (p.alpha or 0.35) or 1)
        local showBg = (not overlay) and p.background ~= false
        holder.bg:SetShown(showBg)
        local bc = p.bgColor or g.bgColor
        holder.bg:SetVertexColor(bc[1], bc[2], bc[3], bc[4] or 1)
        -- General: a detached portrait gets a border like the frame; inside the frame it shares the frame border
        if overlay then EdgesShown(holder, false)
        else ApplyBorder(holder, p.border, p.side == "DETACHED" and g.border) end
        holder:Show()
        -- style switches must force a refresh (the element only redraws when the unit changes)
        tex.useClassBase = (p.style == "class") or nil
        want.guid, want.state = nil, nil
        SetElement(frame, "Portrait", true)
        want:Show()
        if want == model then ns.ApplyModel(model) end
    else
        holder:Hide()
    end

    -- texts
    ApplyTexts(frame, cfg)

    -- auras / castbar / class power
    ApplyAuras(frame, "Buffs", cfg.buffs)
    ApplyAuras(frame, "Debuffs", cfg.debuffs, frame.Buffs)
    ApplyCastbar(frame, cfg.castbar, cfg)
    if frame.ClassPower then
        -- the options preview of the target card shows your combo points when they sit on the target frame
        local cpc = cfg.classPower
        if frame.fufIsPreview and key ~= "player" then cpc = ns.Unit("player").classPower end
        ApplyClassPower(frame, cpc, cfg)
    end

    -- indicators
    PlaceIndicator(frame, frame.RaidTargetIndicator, "RaidTargetIndicator", cfg.raidIcon)
    PlaceIndicator(frame, frame.LeaderIndicator, "LeaderIndicator", cfg.leader)
    PlaceIndicator(frame, frame.ReadyCheckIndicator, "ReadyCheckIndicator", cfg.readyCheck)
    PlaceIndicator(frame, frame.CombatIndicator, "CombatIndicator", cfg.combat)
    PlaceIndicator(frame, frame.RestingIndicator, "RestingIndicator", cfg.resting)
    if key == "pet" and not frame.fufIsPreview and ns.ApplyHappiness then ns.ApplyHappiness(frame) end

    SetElement(frame, "ThreatIndicator", cfg.threat.enable)
    if not cfg.threat.enable then frame.ThreatIndicator:Hide() end

    frame.Range.outsideAlpha = cfg.range.alpha
    -- The game only reports range for party/raid members (UnitInRange); for a target,
    -- focus or boss it always answers "out of range", which faded those frames.
    local groupFrame = (key == "party" or key == "raid") and not frame.fufIsPreview
    SetElement(frame, "Range", cfg.range.enable and groupFrame)
    if not (cfg.range.enable and groupFrame) then frame:SetAlpha(1) end

    -- test mode: show sample auras
    local test = ns.IsTestMode and ns.IsTestMode()
    if not USE_CONTAINERS then
        frame.Buffs.forceShow = test or nil
        frame.Debuffs.forceShow = test or nil
    end

    if frame.fufIsPreview then
        ApplyPreviewSim(frame, cfg)     -- sample state, no live unit
        return
    end
    if frame.unit or frame:GetAttribute("unit") then
        frame:UpdateAllElements("ElvUI_UpdateAllElements")
    end
end

-- oUF enables every element after the style function; apply our settings
-- (sizes, enabled/disabled elements, tags) right after that.
oUF:RegisterInitCallback(function(frame)
    if frame.fufKey and ns.GetDB() then ns.Safe("apply " .. frame.fufKey, ns.ApplyFrame, frame) end
end)

oUF:RegisterStyle("FreeUnitFrames", Style)
oUF:SetActiveStyle("FreeUnitFrames")
