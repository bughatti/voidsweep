----------------------------------------------------------------------
-- VoidSweep — World-map filter button
--
-- A single button on the Blizzard world map opens a checkbox menu to toggle
-- every category (plus Completed / Minimap / Crowd sync). This is the
-- anti-"busy as hell": the map shows only what you tick, and collectibles
-- are off by default. Uses the modern MenuUtil API (Dragonflight+).
----------------------------------------------------------------------
local ADDON, VS = ...
VS.MapButton = {}

-- Order shown in the menu (matches the pin kinds).
-- Only what the in-game classifier can tell from a vignette (Scanner.lua).
local CATS = {
    { key = "rare",       label = "Rares" },
    { key = "worldboss",  label = "World Bosses" },
    { key = "chest",      label = "Treasures" },
    { key = "lore",       label = "Lore" },
}

local function refresh()
    return MenuResponse and MenuResponse.Refresh   -- keep the menu open on toggle
end

-- Per-kind (needed, total) for the map being viewed, so the menu reads
-- "Mounts (0/1)" = 1 here, already done. Tells apart "not in this zone"
-- from "done" from "broken".
local function countsForViewedMap()
    local need, total = {}, {}
    local mapID = WorldMapFrame and WorldMapFrame:GetMapID()
    if not mapID then return need, total end
    local knownVid = {}
    for key, rec in pairs(VS.Learned:GetKnownForMap(mapID)) do
        if rec.name and rec.name ~= "" then
            if rec.vignetteID then knownVid[rec.vignetteID] = true end
            total[rec.kind] = (total[rec.kind] or 0) + 1
            if not VS:IsDone(rec) and not VS.Learned:IsCleared(mapID, key) then
                need[rec.kind] = (need[rec.kind] or 0) + 1
            end
        end
    end
    -- live ones only if they're on the viewed map and not already counted above
    for _, e in ipairs(VS.Scanner:GetLive()) do
        if not (e.vignetteID and knownVid[e.vignetteID])
           and e.guid and C_VignetteInfo.GetVignettePosition(e.guid, mapID) then
            total[e.kind] = (total[e.kind] or 0) + 1
            need[e.kind] = (need[e.kind] or 0) + 1
        end
    end
    return need, total
end

local function generator(_, root)
    local cfg = VS:Config()
    local need, total = countsForViewedMap()

    root:CreateTitle("VoidSweep — Show on map")
    for _, c in ipairs(CATS) do
        -- collected / total, like the game's collection UIs (1/1 = you own it)
        local tot = total[c.key] or 0
        local got = tot - (need[c.key] or 0)
        -- color swatch matching the map dot for this category. A tinted
        -- texture, not a "●" character: WoW's menu font has no bullet glyph
        -- (it rendered as an empty box).
        local col = VS.CategoryColor[c.key] or VS.CategoryColor.default
        local swatch = ("|TInterface\\Buttons\\WHITE8X8:10:10:0:0:8:8:0:8:0:8:%d:%d:%d|t"):format(
            math.floor(col[1] * 255), math.floor(col[2] * 255), math.floor(col[3] * 255))
        local label = ("%s  %s (%d/%d)"):format(swatch, c.label, got, tot)
        root:CreateCheckbox(label,
            function() return cfg.show[c.key] ~= false end,
            function()
                cfg.show[c.key] = (cfg.show[c.key] == false)  -- flip shown/hidden
                VS.Pins:Refresh()
                return refresh()
            end)
    end

    -- legend: the one non-category color on the map
    local function sw(g)
        return ("|TInterface\\Buttons\\WHITE8X8:10:10:0:0:8:8:0:8:0:8:%d:%d:%d|t"):format(
            math.floor(g[1] * 255), math.floor(g[2] * 255), math.floor(g[3] * 255))
    end
    root:CreateTitle(sw(VS.SpawnSpotColor) .. "  Light blue = delve treasure seen here once or twice")
    root:CreateTitle(sw(VS.ConfirmedSpawnColor) .. "  Dark green = confirmed delve treasure spot (3+ visits)")

    root:CreateDivider()
    root:CreateCheckbox("Show completed",
        function() return cfg.showCompleted end,
        function() cfg.showCompleted = not cfg.showCompleted; VS.Pins:Refresh(); return refresh() end)
    root:CreateCheckbox("Minimap pins",
        function() return cfg.showMinimap end,
        function() cfg.showMinimap = not cfg.showMinimap; return refresh() end)
    root:CreateCheckbox("Crowd sync",
        function() return cfg.sync end,
        function() cfg.sync = not cfg.sync; VS.Pins:Refresh(); VS.Sync:CountNow(); return refresh() end)
    root:CreateCheckbox("Players-here box",
        function() return VoidPresence:IsShown() end,
        function() VoidPresence:SetShown(not VoidPresence:IsShown()); return refresh() end)
    -- WoW Forever: the Layers window (LayerUI.lua)
    if VS.LayerUI and RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled() then
        root:CreateDivider()
        root:CreateButton("Layers... (your layer, hop to another)", function() VS.LayerUI:Show() end)
    end
end

function VS.MapButton:Init()
    if self.btn then return end
    -- Anchor to the map CANVAS (where the tracking + pin buttons live), not the
    -- outer frame — otherwise it's clipped by the border. Sits just under the
    -- Blizzard tracking/pin buttons at the map's top-right.
    local canvas = WorldMapFrame and WorldMapFrame.GetCanvasContainer
        and WorldMapFrame:GetCanvasContainer()
    if not canvas then return end

    local btn = CreateFrame("Button", "VoidSweepMapButton", canvas)
    btn:SetSize(31, 31)
    btn:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", -4, -72)  -- under the pin button
    btn:SetFrameStrata("HIGH")
    btn:SetFrameLevel(canvas:GetFrameLevel() + 500)

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(24, 24)
    bg:SetPoint("CENTER")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("CENTER")
    icon:SetSize(20, 20)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
    icon:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask")

    -- The ring sits in the top-left of MiniMap-TrackingBorder's 64x64 file, so
    -- anchor it TOPLEFT at 53x53 (LibDBIcon geometry) to center it on 31x31.
    local ring = btn:CreateTexture(nil, "OVERLAY")
    ring:SetSize(53, 53)
    ring:SetPoint("TOPLEFT")
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    btn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
        GameTooltip:SetText("VoidSweep — filters")
        GameTooltip:AddLine("Toggle what shows on the map.", 0.8, 0.8, 0.8)
        -- WoW Forever: your layer (Layer.lua)
        if VS.Layer and RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled() then
            local pair, zone = VS.Layer:Here()
            GameTooltip:AddLine(pair and ("Your layer: |cffffd200" .. pair .. "|r") or "Your layer: not known yet (point at any NPC)", 0.8, 0.8, 0.8)
            local s = VS.LayerNet and zone and VS.LayerNet:Summary(zone)
            if s then GameTooltip:AddLine("Layers here: " .. s, 0.8, 0.8, 0.8, true) end
            GameTooltip:AddLine("/vsw layers asks other VoidSweep players", 0.5, 0.5, 0.5)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    btn:SetScript("OnClick", function()
        if MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(btn, generator)
        end
    end)
    self.btn = btn
end
