-- GroupInfo.lua
local addonName, ns = ...

---------------------------------------------------------------------------
-- Icons
---------------------------------------------------------------------------

local TANK_ICON       = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:16:16:0:0:64:64:0:19:22:41|t"
local HEALER_ICON     = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:16:16:0:0:64:64:20:39:1:20|t"
local DPS_ICON        = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:16:16:0:0:64:64:20:39:22:41|t"
local UNASSIGNED_ICON = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:16:16:0:0:64:64:20:39:42:61|t"

---------------------------------------------------------------------------
-- Anchor frame  (what LibEditMode draws the selection box on)
--
-- The actual visible content (frame) is attached to anchorFrame so that
-- whatever LibEditMode does to move anchorFrame, the display follows.
---------------------------------------------------------------------------

local anchorFrame = CreateFrame("Frame", "GroupInfoAnchor", UIParent)
anchorFrame:SetSize(200, 55)
anchorFrame:SetPoint("TOP", UIParent, "TOP", 0, -200) -- default; overwritten by layout callback
anchorFrame.editModeName = "GroupInfo"
ns.anchorFrame = anchorFrame

---------------------------------------------------------------------------
-- Display frame (content, parented to anchorFrame)
---------------------------------------------------------------------------

local frame = CreateFrame("Frame", "GroupInfoFrame", anchorFrame)
frame:SetAllPoints(anchorFrame)

---------------------------------------------------------------------------
-- Text elements
---------------------------------------------------------------------------

local compositionText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
compositionText:SetPoint("CENTER", frame, "CENTER", 0, 0)
compositionText:SetText("")

local playerCountText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
playerCountText:SetText("")

local raidGroupText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
raidGroupText:SetText("")

local function UpdateTextPositions()
    local spacing = GroupInfoDB and GroupInfoDB.global and GroupInfoDB.global.textSpacing or 6
    playerCountText:ClearAllPoints()
    playerCountText:SetPoint("BOTTOMLEFT",  compositionText, "TOPLEFT",    0,  spacing)
    playerCountText:SetPoint("BOTTOMRIGHT", compositionText, "TOPRIGHT",   0,  spacing)
    raidGroupText:ClearAllPoints()
    raidGroupText:SetPoint("TOPLEFT",  compositionText, "BOTTOMLEFT",  0, -spacing)
    raidGroupText:SetPoint("TOPRIGHT", compositionText, "BOTTOMRIGHT", 0, -spacing)
end

UpdateTextPositions()

local function UpdateTextColors()
    local tc = (GroupInfoDB and GroupInfoDB.global and GroupInfoDB.global.textColor)
               or { r = 1, g = 1, b = 1 }
    playerCountText:SetTextColor(tc.r, tc.g, tc.b)
    compositionText:SetTextColor(tc.r, tc.g, tc.b)
    raidGroupText:SetTextColor(tc.r, tc.g, tc.b)
end

---------------------------------------------------------------------------
-- Data helpers
---------------------------------------------------------------------------

local function GetGroupComposition()
    local g = GroupInfoDB and GroupInfoDB.global or {}
    if g.testMode then return 2, 4, 14, 0 end

    local tanks, healers, dps, unassigned = 0, 0, 0, 0
    local n = GetNumGroupMembers()
    if n == 0 then return 0, 0, 0, 0 end

    if IsInRaid() then
        for i = 1, n do
            local unit = "raid"..i
            if UnitExists(unit) then
                local role = UnitGroupRolesAssigned(unit)
                if     role == "TANK"    then tanks      = tanks      + 1
                elseif role == "HEALER"  then healers    = healers    + 1
                elseif role == "DAMAGER" then dps        = dps        + 1
                else                          unassigned = unassigned + 1
                end
            end
        end
    else
        local role = UnitGroupRolesAssigned("player")
        if     role == "TANK"    then tanks      = tanks      + 1
        elseif role == "HEALER"  then healers    = healers    + 1
        elseif role == "DAMAGER" then dps        = dps        + 1
        else                          unassigned = unassigned + 1
        end
        for i = 1, n-1 do
            local unit = "party"..i
            if UnitExists(unit) then
                role = UnitGroupRolesAssigned(unit)
                if     role == "TANK"    then tanks      = tanks      + 1
                elseif role == "HEALER"  then healers    = healers    + 1
                elseif role == "DAMAGER" then dps        = dps        + 1
                else                          unassigned = unassigned + 1
                end
            end
        end
    end
    return tanks, healers, dps, unassigned
end

local function GetPlayerRaidGroup()
    local g = GroupInfoDB and GroupInfoDB.global or {}
    if g.testMode then return 3 end
    if not IsInRaid() then return nil end
    for i = 1, GetNumGroupMembers() do
        if UnitIsUnit("raid"..i, "player") then
            local _, _, subgroup = GetRaidRosterInfo(i)
            return subgroup
        end
    end
    return nil
end

local function GetPlayerCount()
    local g = GroupInfoDB and GroupInfoDB.global or {}
    if g.testMode then return 20 end
    local n = GetNumGroupMembers()
    -- Return nil when solo (not in a group)
    return n > 0 and n or nil
end

---------------------------------------------------------------------------
-- Display update
---------------------------------------------------------------------------

local LEM -- assigned in ADDON_LOADED

local function UpdateDisplay()
    if LEM and LEM:IsInEditMode() then
        -- Static preview in Edit Mode so the frame is visible while positioning
        playerCountText:SetText("20")  ; playerCountText:Show()
        compositionText:SetText(string.format("2 %s  4 %s  14 %s", TANK_ICON, HEALER_ICON, DPS_ICON)) ; compositionText:Show()
        raidGroupText:SetText("Group 3") ; raidGroupText:Show()
        UpdateTextColors()
        return
    end

    local g = GroupInfoDB and GroupInfoDB.global or {}
    local tanks, healers, dps, unassigned = GetGroupComposition()
    local playerCount = GetPlayerCount()

    if g.showPlayerCount and playerCount then
        playerCountText:SetText(tostring(playerCount))
        playerCountText:Show()
    else
        playerCountText:Hide()
    end

    if g.showComposition and (GetNumGroupMembers() > 0 or g.testMode) then
        local text = string.format("%d %s  %d %s  %d %s",
            tanks, TANK_ICON, healers, HEALER_ICON, dps, DPS_ICON)
        if unassigned and unassigned > 0 then
            text = text .. string.format("  %d %s", unassigned, UNASSIGNED_ICON)
        end
        compositionText:SetText(text)
        compositionText:Show()
    else
        compositionText:Hide()
    end

    local raidGroup = GetPlayerRaidGroup()
    if g.showRaidGroup and raidGroup then
        raidGroupText:SetText(string.format("Group %d", raidGroup))
        raidGroupText:Show()
    else
        raidGroupText:Hide()
    end

    playerCountText:SetJustifyH(g.playerCountAlign or "CENTER")
    raidGroupText:SetJustifyH(g.raidGroupAlign    or "CENTER")
    UpdateTextColors()
end

---------------------------------------------------------------------------
-- Group events
---------------------------------------------------------------------------

frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_ROLES_ASSIGNED")
frame:RegisterEvent("ROLE_CHANGED_INFORM")
frame:SetScript("OnEvent", function() UpdateDisplay() end)

---------------------------------------------------------------------------
-- ADDON_LOADED: wire up LEM now that SVs are available
---------------------------------------------------------------------------

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(self, event, name)
    if name ~= addonName then return end
    self:UnregisterEvent("ADDON_LOADED")

    -- Safe to call LibStub now — library file already loaded by TOC
    LEM = LibStub("LibEditMode")
    ns.LEM = LEM

    -- Position save callback
    local function OnPositionChanged(_, layoutName, point, x, y)
        if GroupInfoDB and GroupInfoDB.layouts and GroupInfoDB.layouts[layoutName] then
            GroupInfoDB.layouts[layoutName].point = point
            GroupInfoDB.layouts[layoutName].x     = x
            GroupInfoDB.layouts[layoutName].y     = y
        end
    end

    -- Register anchor frame
    LEM:AddFrame(anchorFrame, OnPositionChanged, ns.defaultLayoutData)

    -- Frame settings shown in the Edit Mode right-click dialog
    LEM:AddFrameSettings(anchorFrame, {
        {
            name    = "Scale",
            kind    = LEM.SettingType.Slider,
            default = 1,
            get = function() return GroupInfoDB.global.scale or 1 end,
            set = function(_, value)
                GroupInfoDB.global.scale = value
                frame:SetScale(value)
            end,
            minValue = 0.5, maxValue = 2.0, valueStep = 0.05,
            formatter = function(v) return FormatPercentage(v, true) end,
        },
        {
            name    = "Text Color",
            kind    = LEM.SettingType.ColorPicker,
            default = CreateColor(1, 1, 1, 1),
            get = function()
                local c = GroupInfoDB.global.textColor
                return CreateColor(c.r, c.g, c.b, 1)
            end,
            set = function(_, colorObj)
                local r, g, b = colorObj:GetRGB()
                GroupInfoDB.global.textColor = { r = r, g = g, b = b }
                UpdateTextColors()
            end,
        },
        {
            name    = "Show Player Count",
            kind    = LEM.SettingType.Checkbox,
            default = true,
            get = function() return GroupInfoDB.global.showPlayerCount end,
            set = function(_, value) GroupInfoDB.global.showPlayerCount = value ; UpdateDisplay() end,
        },
        {
            name    = "Show Group Composition",
            kind    = LEM.SettingType.Checkbox,
            default = true,
            get = function() return GroupInfoDB.global.showComposition end,
            set = function(_, value) GroupInfoDB.global.showComposition = value ; UpdateDisplay() end,
        },
        {
            name    = "Show Raid Group Number",
            kind    = LEM.SettingType.Checkbox,
            default = true,
            get = function() return GroupInfoDB.global.showRaidGroup end,
            set = function(_, value) GroupInfoDB.global.showRaidGroup = value ; UpdateDisplay() end,
        },
        {
            name    = "Player Count Alignment",
            kind    = LEM.SettingType.Dropdown,
            default = "CENTER",
            get = function() return GroupInfoDB.global.playerCountAlign or "CENTER" end,
            set = function(_, value)
                GroupInfoDB.global.playerCountAlign = value
                UpdateDisplay()
            end,
            values = {
                { text = "Left",   value = "LEFT" },
                { text = "Center", value = "CENTER" },
                { text = "Right",  value = "RIGHT" },
            },
        },
        {
            name    = "Raid Group Alignment",
            kind    = LEM.SettingType.Dropdown,
            default = "CENTER",
            get = function() return GroupInfoDB.global.raidGroupAlign or "CENTER" end,
            set = function(_, value)
                GroupInfoDB.global.raidGroupAlign = value
                UpdateDisplay()
            end,
            values = {
                { text = "Left",   value = "LEFT" },
                { text = "Center", value = "CENTER" },
                { text = "Right",  value = "RIGHT" },
            },
        },
        {
            name    = "Text Spacing",
            kind    = LEM.SettingType.Slider,
            default = 6,
            get = function() return GroupInfoDB.global.textSpacing or 6 end,
            set = function(_, value) GroupInfoDB.global.textSpacing = value ; UpdateTextPositions() end,
            minValue = 0, maxValue = 30, valueStep = 1,
        },
        {
            name    = "Test Mode",
            kind    = LEM.SettingType.Checkbox,
            default = false,
            get = function() return GroupInfoDB.global.testMode end,
            set = function(_, value) GroupInfoDB.global.testMode = value ; UpdateDisplay() end,
        },
    })

    -- LEM callbacks
    LEM:RegisterCallback("enter", function()
        frame:Show()
        anchorFrame:Show()
        UpdateDisplay()
    end)

    LEM:RegisterCallback("exit", function()
        UpdateDisplay()
    end)

    LEM:RegisterCallback("layout", function(layoutName)
        -- Ensure the layout entry exists in DB, then apply saved position
        local layout = ns.EnsureLayout(layoutName)
        anchorFrame:ClearAllPoints()
        anchorFrame:SetPoint(layout.point, UIParent, layout.point, layout.x, layout.y)
        frame:SetScale(GroupInfoDB.global.scale or 1)
        UpdateDisplay()
        UpdateTextPositions()
    end)

    LEM:RegisterCallback("create", function(layoutName, _, sourceLayoutName)
        if sourceLayoutName and GroupInfoDB.layouts[sourceLayoutName] then
            GroupInfoDB.layouts[layoutName] = CopyTable(GroupInfoDB.layouts[sourceLayoutName])
        end
    end)

    LEM:RegisterCallback("rename", function(layoutName, newLayoutName)
        GroupInfoDB.layouts[newLayoutName] = CopyTable(GroupInfoDB.layouts[layoutName])
        GroupInfoDB.layouts[layoutName]    = nil
    end)

    LEM:RegisterCallback("delete", function(layoutName)
        GroupInfoDB.layouts[layoutName] = nil
    end)

    UpdateDisplay()
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

SLASH_GROUPINFO1 = "/groupinfo"
SLASH_GROUPINFO2 = "/gi"
SlashCmdList["GROUPINFO"] = function(msg)
    msg = msg:lower():gsub("^%s*(.-)%s*$", "%1")
    if msg == "" or msg == "help" then
        print("|cFF00FF00GroupInfo:|r /gi test  |  configure in Edit Mode (Escape -> Edit Mode)")
    elseif msg == "test" then
        if GroupInfoDB and GroupInfoDB.global then
            GroupInfoDB.global.testMode = not GroupInfoDB.global.testMode
            UpdateDisplay()
            print("|cFF00FF00GroupInfo:|r Test mode " .. (GroupInfoDB.global.testMode and "enabled" or "disabled"))
        end
    else
        print("|cFF00FF00GroupInfo:|r Unknown command. /gi for help.")
    end
end

print("|cFF00FF00GroupInfo|r loaded. Configure via Edit Mode (Escape -> Edit Mode).")