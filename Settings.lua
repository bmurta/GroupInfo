-- Settings.lua
local addonName, ns = ...

-- Default per-layout position data
ns.defaultLayoutData = {
    point = "TOP",
    x     = 0,
    y     = -200,
}

-- Ensures GroupInfoDB[layoutName] exists with defaults applied
function ns.EnsureLayout(layoutName)
    GroupInfoDB             = GroupInfoDB             or {}
    GroupInfoDB.layouts     = GroupInfoDB.layouts     or {}
    GroupInfoDB.global      = GroupInfoDB.global      or {}

    if not GroupInfoDB.layouts[layoutName] then
        GroupInfoDB.layouts[layoutName] = CopyTable(ns.defaultLayoutData)
    end

    local g = GroupInfoDB.global
    if g.showComposition  == nil then g.showComposition  = true  end
    if g.showRaidGroup    == nil then g.showRaidGroup    = true  end
    if g.showPlayerCount  == nil then g.showPlayerCount  = true  end
    if g.testMode         == nil then g.testMode         = false end
    if g.textSpacing      == nil then g.textSpacing      = 6     end
    if g.scale            == nil then g.scale            = 1     end
    if g.playerCountAlign == nil then g.playerCountAlign = "CENTER" end
    if g.raidGroupAlign   == nil then g.raidGroupAlign   = "CENTER" end
    if type(g.textColor) ~= "table" then
        g.textColor = { r = 1, g = 1, b = 1 }
    end
    g.textColor.r = g.textColor.r or 1
    g.textColor.g = g.textColor.g or 1
    g.textColor.b = g.textColor.b or 1

    return GroupInfoDB.layouts[layoutName]
end