-- GroupInfo: Lightweight addon to display group composition and raid group
local addonName, addon = ...

-- Saved variables (account-wide)
GroupInfoDB = GroupInfoDB or {}

-- Initialize with defaults if not present
local defaults = {
    showComposition = true,
    showRaidGroup = true,
    testMode = false,
    position = nil,
    width = 250,
    height = 40,
    textColor = { r = 1, g = 1, b = 1 }  -- White by default
}

for key, value in pairs(defaults) do
    if GroupInfoDB[key] == nil then
        GroupInfoDB[key] = value
    end
end

-- Ensure textColor has all required fields (for existing users upgrading)
if not GroupInfoDB.textColor or type(GroupInfoDB.textColor) ~= "table" then
    GroupInfoDB.textColor = { r = 1, g = 1, b = 1 }
end
if not GroupInfoDB.textColor.r then GroupInfoDB.textColor.r = 1 end
if not GroupInfoDB.textColor.g then GroupInfoDB.textColor.g = 1 end
if not GroupInfoDB.textColor.b then GroupInfoDB.textColor.b = 1 end

-- Create main frame
local frame = CreateFrame("Frame", "GroupInfoFrame", UIParent)
frame:SetSize(GroupInfoDB.width, GroupInfoDB.height)
frame:SetMovable(true)
frame:SetResizable(true)
frame:SetUserPlaced(true)
frame:SetClampedToScreen(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetResizeBounds(150, 30, 600, 200)

-- Set saved position or default
if GroupInfoDB.position then
    frame:ClearAllPoints()
    frame:SetPoint(GroupInfoDB.position.point, UIParent, GroupInfoDB.position.relativePoint, 
                   GroupInfoDB.position.x, GroupInfoDB.position.y)
else
    frame:SetPoint("TOP", UIParent, "TOP", 0, -100)
end

-- Drag functionality
frame:SetScript("OnDragStart", function(self)
    self:StartMoving()
end)

frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    -- Save position
    local point, _, relativePoint, x, y = self:GetPoint()
    GroupInfoDB.position = {
        point = point,
        relativePoint = relativePoint,
        x = x,
        y = y
    }
end)

-- Background for visibility during movement
frame.bg = frame:CreateTexture(nil, "BACKGROUND")
frame.bg:SetAllPoints()
frame.bg:SetColorTexture(0, 0, 0, 0.5)
frame.bg:Hide()

-- Create resize grip (bottom-right corner)
local resizeGrip = CreateFrame("Frame", nil, frame)
resizeGrip:SetSize(16, 16)
resizeGrip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
resizeGrip:EnableMouse(true)
resizeGrip:SetFrameLevel(frame:GetFrameLevel() + 1)
resizeGrip:Hide()

-- Resize grip texture
resizeGrip.texture = resizeGrip:CreateTexture(nil, "OVERLAY")
resizeGrip.texture:SetAllPoints()
resizeGrip.texture:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")

-- Resize grip highlight
resizeGrip.highlight = resizeGrip:CreateTexture(nil, "HIGHLIGHT")
resizeGrip.highlight:SetAllPoints()
resizeGrip.highlight:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")

-- Resize functionality
resizeGrip:SetScript("OnMouseDown", function(self, button)
    if button == "LeftButton" then
        frame:StartSizing("BOTTOMRIGHT")
    end
end)

resizeGrip:SetScript("OnMouseUp", function(self, button)
    frame:StopMovingOrSizing()
    -- Save new size
    GroupInfoDB.width = frame:GetWidth()
    GroupInfoDB.height = frame:GetHeight()
end)

-- Show background and resize grip when dragging or unlocked
frame:HookScript("OnDragStart", function(self)
    self.bg:Show()
end)

frame:HookScript("OnDragStop", function(self)
    self.bg:Hide()
end)

-- Function to update resize grip visibility
local function UpdateResizeGripVisibility()
    if frame:IsMouseEnabled() then
        resizeGrip:Show()
        frame.bg:Show()
    else
        resizeGrip:Hide()
        frame.bg:Hide()
    end
end

-- Create text displays
local compositionText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
compositionText:SetPoint("TOP", frame, "TOP", 0, 0)
compositionText:SetText("")
if GroupInfoDB.textColor then
    compositionText:SetTextColor(GroupInfoDB.textColor.r or 1, GroupInfoDB.textColor.g or 1, GroupInfoDB.textColor.b or 1)
else
    compositionText:SetTextColor(1, 1, 1)
end

local raidGroupText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
raidGroupText:SetPoint("TOP", compositionText, "BOTTOM", 0, -5)
raidGroupText:SetText("")
if GroupInfoDB.textColor then
    raidGroupText:SetTextColor(GroupInfoDB.textColor.r or 1, GroupInfoDB.textColor.g or 1, GroupInfoDB.textColor.b or 1)
else
    raidGroupText:SetTextColor(1, 1, 1)
end

-- Icon textures (using built-in WoW atlas textures)
local TANK_ICON = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:16:16:0:0:64:64:0:19:22:41|t"
local HEALER_ICON = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:16:16:0:0:64:64:20:39:1:20|t"
local DPS_ICON = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:16:16:0:0:64:64:20:39:22:41|t"
local UNASSIGNED_ICON = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:16:16:0:0:64:64:20:39:42:61|t"

-- Function to get role counts
local function GetGroupComposition()
    -- Test mode override
    if GroupInfoDB.testMode then
        return 2, 4, 14  -- 2 tanks, 4 healers, 14 dps
    end
    
    local tanks, healers, dps, unassigned = 0, 0, 0, 0
    local numGroupMembers = GetNumGroupMembers()
    
    if numGroupMembers == 0 then
        return tanks, healers, dps
    end
    
    local isRaid = IsInRaid()
    
    if isRaid then
        -- Raid: iterate through raid1 to raidN
        for i = 1, numGroupMembers do
            local unit = "raid"..i
            if UnitExists(unit) then
                local role = UnitGroupRolesAssigned(unit)
                
                if role == "TANK" then
                    tanks = tanks + 1
                elseif role == "HEALER" then
                    healers = healers + 1
                elseif role == "DAMAGER" then
                    dps = dps + 1
                else
                    unassigned = unassigned + 1
                end
            end
        end
    else
        -- Party: check player + party1 through party4
        -- First check player
        local role = UnitGroupRolesAssigned("player")
        if role == "TANK" then
            tanks = tanks + 1
        elseif role == "HEALER" then
            healers = healers + 1
        elseif role == "DAMAGER" then
            dps = dps + 1
        else
            unassigned = unassigned + 1
        end
        
        -- Then check party members (numGroupMembers includes player, so -1)
        for i = 1, numGroupMembers - 1 do
            local unit = "party"..i
            if UnitExists(unit) then
                role = UnitGroupRolesAssigned(unit)
                
                if role == "TANK" then
                    tanks = tanks + 1
                elseif role == "HEALER" then
                    healers = healers + 1
                elseif role == "DAMAGER" then
                    dps = dps + 1
                else
                    unassigned = unassigned + 1
                end
            end
        end
    end
    
    return tanks, healers, dps, unassigned
end

-- Function to get player's raid group
local function GetPlayerRaidGroup()
    -- Test mode override
    if GroupInfoDB.testMode then
        return 3  -- Simulate being in group 3
    end
    
    if not IsInRaid() then
        return nil
    end
    
    local numGroupMembers = GetNumGroupMembers()
    for i = 1, numGroupMembers do
        local unit = "raid"..i
        if UnitIsUnit(unit, "player") then
            local _, _, subgroup = GetRaidRosterInfo(i)
            return subgroup
        end
    end
    
    return nil
end

-- Function to update text colors
local function UpdateTextColors()
    if not GroupInfoDB.textColor then
        GroupInfoDB.textColor = { r = 1, g = 1, b = 1 }
    end
    local r = GroupInfoDB.textColor.r or 1
    local g = GroupInfoDB.textColor.g or 1
    local b = GroupInfoDB.textColor.b or 1
    compositionText:SetTextColor(r, g, b)
    raidGroupText:SetTextColor(r, g, b)
end

-- Update display
local function UpdateDisplay()
    local tanks, healers, dps, unassigned = GetGroupComposition()
    
    -- Update composition text
    if GroupInfoDB.showComposition and (GetNumGroupMembers() > 0 or GroupInfoDB.testMode) then
        local text = string.format("%d %s  %d %s  %d %s", 
            tanks, TANK_ICON,
            healers, HEALER_ICON,
            dps, DPS_ICON)
        
        -- Add unassigned if any exist
        if unassigned and unassigned > 0 then
            text = text .. string.format("  %d %s", unassigned, UNASSIGNED_ICON)
        end
        
        compositionText:SetText(text)
        compositionText:Show()
    else
        compositionText:Hide()
    end
    
    -- Update raid group text
    local raidGroup = GetPlayerRaidGroup()
    if GroupInfoDB.showRaidGroup and raidGroup then
        raidGroupText:SetText(string.format("Group %d", raidGroup))
        raidGroupText:Show()
    else
        raidGroupText:Hide()
    end
end

-- Event handler
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_ROLES_ASSIGNED")
frame:RegisterEvent("ROLE_CHANGED_INFORM")

frame:SetScript("OnEvent", function(self, event, ...)
    UpdateDisplay()
end)

-- Initial update
UpdateDisplay()

-- Slash command handler
SLASH_GROUPINFO1 = "/groupinfo"
SLASH_GROUPINFO2 = "/gi"
SlashCmdList["GROUPINFO"] = function(msg)
    if msg == "" or msg == "help" then
        print("|cFF00FF00GroupInfo Commands:|r")
        print("/gi config - Open settings")
        print("/gi lock - Lock frame (disable dragging)")
        print("/gi unlock - Unlock frame (enable dragging)")
        print("/gi test - Toggle test mode")
    elseif msg == "config" then
        Settings.OpenToCategory("GroupInfo")
    elseif msg == "lock" then
        frame:EnableMouse(false)
        UpdateResizeGripVisibility()
        print("|cFF00FF00GroupInfo:|r Frame locked")
    elseif msg == "unlock" then
        frame:EnableMouse(true)
        UpdateResizeGripVisibility()
        print("|cFF00FF00GroupInfo:|r Frame unlocked - drag to reposition or resize from corner")
    elseif msg == "test" then
        GroupInfoDB.testMode = not GroupInfoDB.testMode
        UpdateDisplay()
        if GroupInfoDB.testMode then
            print("|cFF00FF00GroupInfo:|r Test mode enabled (2 tanks, 4 healers, 14 dps, group 3)")
        else
            print("|cFF00FF00GroupInfo:|r Test mode disabled")
        end
    end
end

-- Settings Panel
local function CreateSettingsPanel()
    local panel = CreateFrame("Frame", "GroupInfoSettingsPanel", UIParent)
    panel.name = "GroupInfo"
    
    -- Title
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("GroupInfo Settings")
    
    -- Lock/Unlock Button
    local lockButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    lockButton:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -20)
    lockButton:SetSize(150, 25)
    lockButton:SetText(frame:IsMouseEnabled() and "Lock Frame" or "Unlock Frame")
    lockButton:SetScript("OnClick", function(self)
        local isUnlocked = frame:IsMouseEnabled()
        frame:EnableMouse(not isUnlocked)
        UpdateResizeGripVisibility()
        self:SetText(isUnlocked and "Unlock Frame" or "Lock Frame")
        if isUnlocked then
            print("|cFF00FF00GroupInfo:|r Frame locked")
        else
            print("|cFF00FF00GroupInfo:|r Frame unlocked - drag to reposition or resize from corner")
        end
    end)
    
    -- Test Mode Button
    local testButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    testButton:SetPoint("LEFT", lockButton, "RIGHT", 10, 0)
    testButton:SetSize(150, 25)
    testButton:SetText(GroupInfoDB.testMode and "Disable Test Mode" or "Enable Test Mode")
    testButton:SetScript("OnClick", function(self)
        GroupInfoDB.testMode = not GroupInfoDB.testMode
        self:SetText(GroupInfoDB.testMode and "Disable Test Mode" or "Enable Test Mode")
        UpdateDisplay()
        if GroupInfoDB.testMode then
            print("|cFF00FF00GroupInfo:|r Test mode enabled")
        else
            print("|cFF00FF00GroupInfo:|r Test mode disabled")
        end
    end)
    
    -- Show Composition Checkbox
    local showCompCheckbox = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    showCompCheckbox:SetPoint("TOPLEFT", lockButton, "BOTTOMLEFT", 0, -20)
    showCompCheckbox.Text:SetText("Show Group Composition")
    showCompCheckbox:SetChecked(GroupInfoDB.showComposition)
    showCompCheckbox:SetScript("OnClick", function(self)
        GroupInfoDB.showComposition = self:GetChecked()
        UpdateDisplay()
    end)
    
    -- Show Raid Group Checkbox
    local showRaidCheckbox = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    showRaidCheckbox:SetPoint("TOPLEFT", showCompCheckbox, "BOTTOMLEFT", 0, -5)
    showRaidCheckbox.Text:SetText("Show Raid Group Number")
    showRaidCheckbox:SetChecked(GroupInfoDB.showRaidGroup)
    showRaidCheckbox:SetScript("OnClick", function(self)
        GroupInfoDB.showRaidGroup = self:GetChecked()
        UpdateDisplay()
    end)
    
    -- Text Color Button
    local colorButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    colorButton:SetPoint("TOPLEFT", showRaidCheckbox, "BOTTOMLEFT", 0, -20)
    colorButton:SetSize(120, 25)
    colorButton:SetText("Text Color")
    
    -- Open color picker on click
    colorButton:SetScript("OnClick", function(self)
        -- Ensure textColor exists
        if not GroupInfoDB.textColor then
            GroupInfoDB.textColor = { r = 1, g = 1, b = 1 }
        end
        
        local r, g, b = GroupInfoDB.textColor.r or 1, GroupInfoDB.textColor.g or 1, GroupInfoDB.textColor.b or 1
        
        local info = {
            r = r,
            g = g,
            b = b,
            hasOpacity = false,
            swatchFunc = function()
                local newR, newG, newB = ColorPickerFrame:GetColorRGB()
                if not GroupInfoDB.textColor then
                    GroupInfoDB.textColor = {}
                end
                GroupInfoDB.textColor.r = newR
                GroupInfoDB.textColor.g = newG
                GroupInfoDB.textColor.b = newB
                UpdateTextColors()
            end,
            cancelFunc = function(previousValues)
                if previousValues and previousValues.r then
                    if not GroupInfoDB.textColor then
                        GroupInfoDB.textColor = {}
                    end
                    GroupInfoDB.textColor.r = previousValues.r
                    GroupInfoDB.textColor.g = previousValues.g
                    GroupInfoDB.textColor.b = previousValues.b
                    UpdateTextColors()
                end
            end,
            extraInfo = {
                previousValues = {r = r, g = g, b = b}
            }
        }
        
        -- Add default button callback
        ColorPickerFrame.hasColorRestore = true
        ColorPickerFrame.previousValues = {r = r, g = g, b = b}
        
        -- Override the default button to restore to white
        if ColorPickerFrame.Footer and ColorPickerFrame.Footer.DefaultButton then
            ColorPickerFrame.Footer.DefaultButton:SetScript("OnClick", function()
                if not GroupInfoDB.textColor then
                    GroupInfoDB.textColor = {}
                end
                GroupInfoDB.textColor.r = 1
                GroupInfoDB.textColor.g = 1
                GroupInfoDB.textColor.b = 1
                UpdateTextColors()
                ColorPickerFrame:SetColorRGB(1, 1, 1)
            end)
        end
        
        ColorPickerFrame:SetupColorPickerAndShow(info)
    end)
    
    -- Info text
    local infoText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    infoText:SetPoint("TOPLEFT", colorButton, "BOTTOMLEFT", 0, -20)
    infoText:SetText("Unlock the frame to drag it to a new position or resize from the corner.\nTest mode simulates a 20-player raid composition:\n2 Tanks, 4 Healers, 14 DPS in Raid Group 3")
    infoText:SetJustifyH("LEFT")
    
    -- Register in new settings system
    local category = Settings.RegisterCanvasLayoutCategory(panel, "GroupInfo")
    Settings.RegisterAddOnCategory(category)
end

-- Create settings panel on load
CreateSettingsPanel()

-- Set initial resize grip visibility
UpdateResizeGripVisibility()

print("|cFF00FF00GroupInfo|r loaded successfully! Type /gi for commands")