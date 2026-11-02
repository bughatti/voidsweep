----------------------------------------------------------------------
-- VoidSweep — Navigation
--
-- Click a pin -> drop a Blizzard user waypoint on the target and
-- super-track it, so the built-in arrow + distance kicks in. No TomTom
-- needed. C_Map.SetUserWaypoint is AllowedWhenUntainted and NOT a
-- hardware-event-protected call, so we can fire it straight from a click.
-- The pin itself goes through Route.lua (cross-continent routing + arrival clear).
----------------------------------------------------------------------
local ADDON, VS = ...

VS.Nav = {}
local Nav = VS.Nav

local function toast(msg, r, g, b)
    UIErrorsFrame:AddMessage("|cff00c7ffVoidSweep|r  " .. msg, r or 0.3, g or 1, b or 0.3)
end

local ARRIVE = 30   -- yards: clear our waypoint once you're this close
                    -- (generous so it fires while hovering above on a mount)

-- entry = a scanner live-record; mapID = the map the pin was clicked on.
function Nav:Goto(mapID, entry, name)
    if not (mapID and entry) then return end

    -- Live vignette: pull a fresh map-relative position. Remembered pin:
    -- use its stored coords (recorded against this same mapID).
    local x, y
    if entry.guid then
        local pos = C_VignetteInfo.GetVignettePosition(entry.guid, mapID)
        if pos then x, y = pos.x, pos.y end
    end
    if not x and entry.x and entry.y then
        x, y = entry.x, entry.y
    end
    if not x then
        toast("lost track of that target", 1, 0.3, 0.3)
        return
    end

    -- This addon's Route.lua: portal first across continents, clears on arrival.
    local ok = VS.Route:Go({ map = mapID, x = x, y = y, name = name or "target" },
        { arrive = ARRIVE, say = function(msg) toast(msg) end })
    if not ok then toast("can't place a waypoint on this map", 1, 0.3, 0.3) end
end
