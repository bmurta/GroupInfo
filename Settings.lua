-- Settings.lua: Handles initialization and management of saved variables
local addonName, addon = ...

-- Initialize account-wide settings (shared across all characters)
GroupInfoDB = GroupInfoDB or {}

local defaults = {
    showComposition = true,
    showRaidGroup = true,
    testMode = false,
    position = nil,  -- Will be set to default on first use
    width = 250,
    height = 40,
    isLocked = true,  -- Frame starts locked by default
    textColor = { r = 1, g = 1, b = 1 }  -- White by default
}

-- Apply defaults for any missing keys
for key, value in pairs(defaults) do
    if GroupInfoDB[key] == nil then
        if type(value) == "table" then
            -- Deep copy for tables
            GroupInfoDB[key] = {}
            for k, v in pairs(value) do
                GroupInfoDB[key][k] = v
            end
        else
            GroupInfoDB[key] = value
        end
    end
end

-- Ensure textColor has all required fields (for existing users upgrading)
if not GroupInfoDB.textColor or type(GroupInfoDB.textColor) ~= "table" then
    GroupInfoDB.textColor = { r = 1, g = 1, b = 1 }
end
if not GroupInfoDB.textColor.r then GroupInfoDB.textColor.r = 1 end
if not GroupInfoDB.textColor.g then GroupInfoDB.textColor.g = 1 end
if not GroupInfoDB.textColor.b then GroupInfoDB.textColor.b = 1 end

-- Ensure isLocked exists (for existing users upgrading)
if GroupInfoDB.isLocked == nil then
    GroupInfoDB.isLocked = true
end

-- Export for use in main addon
addon.Settings = GroupInfoDB