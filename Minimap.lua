----------------------------------------------------------------------
-- VoidSweep — Minimap pins
--
-- WoW ALREADY shows live rares/chests on the minimap via the vignette
-- system, so we deliberately do NOT redraw live pins (that would double the
-- icons). This layer adds only what Blizzard doesn't: KNOWN/seed spawn
-- locations that aren't up yet, plus crowd (VoidSync) reports — so you can
-- steer toward a spawn on the minimap before it's in vignette range.
--
-- Manual placement (the minimap isn't a MapCanvas): convert each pin's map
-- position to a yard offset from the player (C_Map.GetMapWorldSize), scale
-- by the minimap's view radius (C_Minimap.GetViewRadius), rotate if the
-- minimap rotates. Reuses VS.Pins:Build so it never drifts from the world map.
----------------------------------------------------------------------
local ADDON, VS = ...
VS.Minimap = {}
local MM = VS.Minimap

-- Reposition EVERY frame: the minimap scrolls every frame, so a 0.2s cadence made
-- pins lag behind then snap back -- visible jitter while flying (2026-10-21). The
-- per-frame work is only arithmetic + SetPoint on the cached pin list; the heavy
-- assembly (VS.Pins:Build) still runs at most every REBUILD seconds.
local REBUILD    = 1.5   -- how often to re-run the (heavier) pin assembly
local PIN_SIZE   = 13

local pool = {}          -- texture pool parented to Minimap
local nActive = 0

local function acquire()
    nActive = nActive + 1
    local p = pool[nActive]
    if not p then
        p = Minimap:CreateTexture(nil, "OVERLAY")
        p:SetSize(PIN_SIZE, PIN_SIZE)
        p:SetAtlas("WhiteCircle-RaidBlips")   -- colored dot, tinted per category
        pool[nActive] = p
    end
    p:Show()
    return p
end

local function hideRest()
    for i = nActive + 1, #pool do pool[i]:Hide() end
end

local buildCache, buildMap, buildTime
local function pins(mapID, t)
    if buildCache and buildMap == mapID and (t - buildTime) < REBUILD then
        return buildCache
    end
    buildCache, buildMap, buildTime = VS.Pins:Build(mapID), mapID, t
    return buildCache
end

function MM:Update()
    nActive = 0
    if VS:Config().showMinimap == false then hideRest(); return end

    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then hideRest(); return end
    local ppos = C_Map.GetPlayerMapPosition(mapID, "player")
    -- NOT `mapID and C_Map.GetMapWorldSize(mapID)`: `a and f()` keeps only f's FIRST
    -- return, so h was always nil and minimap pins never drew anywhere (found 2026-10-18).
    local w, h = C_Map.GetMapWorldSize(mapID)
    if not (ppos and w and h and w > 0 and h > 0) then hideRest(); return end

    local px, py = ppos:GetXY()
    local radius = (C_Minimap.GetViewRadius and C_Minimap.GetViewRadius()) or 133
    if radius <= 0 then radius = 133 end
    local half = Minimap:GetWidth() / 2
    local scale = half / radius

    local rotate = GetCVar("rotateMinimap") == "1"
    local facing = rotate and (GetPlayerFacing() or 0) or 0
    local sinF, cosF = math.sin(facing), math.cos(facing)

    local t = GetTime()
    for _, c in ipairs(pins(mapID, t)) do
        if not c.isLive then                       -- Blizzard minimaps live ones
            local sx = (c.x - px) * w * scale       -- east = +x on minimap
            local sy = -((c.y - py) * h) * scale    -- north = up (map y is south)
            if rotate then
                sx, sy = sx * cosF + sy * sinF, -sx * sinF + sy * cosF
            end
            if (sx * sx + sy * sy) <= (half * half) then   -- inside the minimap
                local p = acquire()
                local col = (c.entry.confirmed and VS.ConfirmedSpawnColor)
                    or (c.entry.heat and VS.SpawnSpotColor)
                    or VS.CategoryColor[c.entry.kind] or VS.CategoryColor.default
                p:SetVertexColor(col[1], col[2], col[3])
                local killed = VS.Respawns[c.entry.kind] and VS:IsDone(c.entry)
                if c.entry.confirmed then        -- confirmed delve spawn spot: solid dark green
                    p:SetAlpha(1.0); p:SetSize(PIN_SIZE + 1, PIN_SIZE + 1)
                elseif c.entry.heat then         -- unconfirmed: faded light blue
                    p:SetAlpha(0.45); p:SetSize(PIN_SIZE - 2, PIN_SIZE - 2)
                else
                    p:SetAlpha(c.entry.reported and 0.95 or (killed or c.entry.shared) and 0.4 or 0.8)
                    p:SetSize(PIN_SIZE, PIN_SIZE)
                end
                p:ClearAllPoints()
                p:SetPoint("CENTER", Minimap, "CENTER", sx, sy)
            end
        end
    end
    hideRest()
end

function MM:Init()
    local f = CreateFrame("Frame", nil, Minimap)   -- parented: stops when the minimap is hidden
    f:SetScript("OnUpdate", function() MM:Update() end)
end
