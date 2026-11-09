----------------------------------------------------------------------
-- VoidSweep: layers through the shared Void layer network (WoW Forever, 0.2.25)
--
-- The census, the hop and hosting used to live here (LayerNet.lua, Hop.lua, on VoidSweep's
-- own channel). Since 0.2.25 they're VoidLayerCore.lua, the same file VoidLayer carries: one
-- network for every Void player, with its own daily password channel, and only one copy runs
-- when both addons are installed. VS.Hop and VS.LayerNet stay as the names the rest of
-- VoidSweep uses (Layers window, sightings, /vsw); they pass every call on to the core, and
-- answer "nothing known" while it isn't running (retail, or before login).
----------------------------------------------------------------------
local ADDON, VS = ...

-- Settings: VoidSweep's own config, unless VoidLayer is installed (its settings win).
VS.LayerCoreSettings(1, "VoidSweep", function() return VS:Config() end)

local function forever() return RegionalUniqueNamesEnabled ~= nil and RegionalUniqueNamesEnabled() == true end
local function off() print("|cff00c7ffVoidSweep|r: layers are a WoW Forever thing.") end
local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded

local fallback = {
    Counts = function() return {} end,       Hosts = function() return {} end,
    Ask = function() return false end,       AskLeft = function() return 0 end,
    Summary = function() return nil end,     Report = off,
    Start = off,                             Status = function() return nil end,
    CooldownLeft = function() return 0 end,  Busy = function() return false end,
    HostingOn = function() return false end, SetHosting = off,
    StayOn = function() return false end,    SetStay = function() end,
    CanHost = function() return false end,   Offer = function() end,
    Rares = function() return {} end,        Label = function(_, _, pair) return pair end,
    Blocked = function() return "Layers are a WoW Forever thing." end,
}

local link = setmetatable({}, { __index = function(_, k)
    local c = _G.VoidLayerCore
    local v = c and c[k]
    if type(v) == "function" then return function(_, ...) return v(c, ...) end end
    if v ~= nil then return v end
    return fallback[k]
end })
VS.Hop, VS.LayerNet = link, link

-- The layer window is VoidLayer's (VoidSweep's own Layers window went in 0.2.25: two windows
-- showing the same thing once both are installed). Without VoidLayer: the layers in chat,
-- and where to get the window.
function VS.OpenLayers()
    if not forever() then off() return end
    local l = VoidHubLaunchers and VoidHubLaunchers.VoidLayer
    if l and l.onClick then l.onClick() return end
    VS.LayerNet:Report()
    print("|cff00c7ffVoidSweep|r: for a layer window, your layer under the minimap and one-click hops, get |cffffd200VoidLayer|r (CurseForge). It shares VoidSweep's layer network.")
end

-- The old Layers window kept itself up across logins (VoidSweepDB.layerUIOpen). It's gone, so
-- forget its flag and position; if it was up, VoidLayer's window stays up instead (one box,
-- not two). At VoidSweep's ADDON_LOADED: VoidLayer (loaded before it) hasn't opened its
-- window yet then, it does that at PLAYER_LOGIN.
local migrate = CreateFrame("Frame")
migrate:RegisterEvent("ADDON_LOADED")
migrate:SetScript("OnEvent", function(self, _, name)
    if name ~= ADDON then return end
    self:UnregisterAllEvents()
    local d = VoidSweepDB
    if type(d) ~= "table" or d.layerUIOpen == nil then return end
    local wasOpen = d.layerUIOpen
    d.layerUIOpen, d.layerUIPos = nil, nil
    if wasOpen and loaded and loaded("VoidLayer") then
        VoidLayerDB = VoidLayerDB or {}
        if VoidLayerDB.open == nil then VoidLayerDB.open = true end
    end
end)

-- Void hub quick box switch (only when VoidLayer isn't installed: it has the same one)
if not (loaded and loaded("VoidLayer")) then
    VoidHubToggles = VoidHubToggles or {}
    table.insert(VoidHubToggles, {
        id = "VoidSweep.host", group = "Sweep", label = "Help others change layer",
        tip = "WoW Forever: Void players on your layer can ask you for a quick group invite (only while you're solo and out of combat; the group ends on its own).",
        get = function() return forever() and VS.Hop:HostingOn() or false end,
        set = function(on) VS.Hop:SetHosting(on) end,
    })
end
