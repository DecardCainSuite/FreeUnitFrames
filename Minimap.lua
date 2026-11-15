-- FreeUnitFrames - minimap button (LibDataBroker + LibDBIcon).
-- Standard LibDBIcon button, so minimap button collectors pick it up.

local ADDON, ns = ...
local ICON_NAME = "FreeUnitFrames"
local Icon

local function Tooltip(tt)
    tt:AddLine("Free Unit Frames")
    tt:AddLine("|cffffffffLeft-click|r  options", 0.8, 0.8, 0.8)
    tt:AddLine("|cffffffffRight-click|r  lock / unlock the frames", 0.8, 0.8, 0.8)
    tt:AddLine("|cffffffffShift + right-click|r  test frames", 0.8, 0.8, 0.8)
end

function ns.InitMinimap()
    local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
    Icon = LibStub and LibStub("LibDBIcon-1.0", true)
    local db = ns.GetDB()
    if not (LDB and Icon and db) then return end
    local obj = LDB:NewDataObject(ICON_NAME, {
        type = "launcher",
        text = "Free Unit Frames",
        icon = "Interface\\AddOns\\" .. ADDON .. "\\Media\\icon",
        OnClick = function(_, button)
            if button == "RightButton" then
                if IsShiftKeyDown() then ns.SetTestMode(not ns.IsTestMode()) else ns.SetUnlocked(not ns.IsUnlocked()) end
            else
                ns.ToggleConfig()
            end
        end,
        OnTooltipShow = Tooltip,
    })
    if obj then Icon:Register(ICON_NAME, obj, db.minimap) end
    -- Free Hub shows one button for all the Free addons
    if FreeHub and FreeHub.ManagesMinimap and FreeHub:ManagesMinimap() then Icon:Hide(ICON_NAME) end
end

ns.SetMinimapShown = function(show)
    local db = ns.GetDB()
    if not (db and Icon) then return end
    db.minimap.hide = not show
    if show then Icon:Show(ICON_NAME) else Icon:Hide(ICON_NAME) end
    if ns.OnChanged then ns.OnChanged() end
end

-- called by Free Hub: show/hide our button without changing the saved choice
ns.ApplyMinimapVisibility = function(show)
    local db = ns.GetDB()
    if not (db and Icon) then return end
    if show and not (db.minimap and db.minimap.hide) then Icon:Show(ICON_NAME) else Icon:Hide(ICON_NAME) end
end
