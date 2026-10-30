----------------------------------------------------------------------
-- VoidSweep — Navigation
--
-- Click a pin -> drop a Blizzard user waypoint on the target and
-- super-track it, so the built-in arrow + distance kicks in. No TomTom
-- needed. C_Map.SetUserWaypoint is AllowedWhenUntainted and NOT a
-- hardware-event-protected call, so we can fire it straight from a click.
----------------------------------------------------------------------
local ADDON, VS = ...

VS.Nav = {}
local Nav = VS.Nav

local function toast(msg, r, g, b)
    UIErrorsFrame:AddMessage("|cff00c7ffVoidSweep|r  " .. msg, r or 0.3, g or 1, b or 0.3)
end

local ARRIVE = 30   -- yards: clear our waypoint once you're this close
                    -- (generous so it fires while hovering above on a mount)

-- While a waypoint WE set is active, poll the arrow distance and auto-clear
-- on arrival (Blizzard never removes a user waypoint on its own).
-- Is the current user waypoint still the one we placed?
local function ours()
    local t = Nav.target
    if not (t and C_Map.GetUserWaypoint()) then return false end
    local pos = C_Map.GetUserWaypointPositionForMap(t.mapID)
    if not pos then return false end
    local x, y = pos:GetXY()
    return math.abs(x - t.x) < 0.001 and math.abs(y - t.y) < 0.001
end

local function watch()
    if not Nav.tracking then return end
    if not ours() then
        Nav.tracking = false   -- user cleared/replaced it themselves: never clear theirs
        return
    end
    -- GetDistance() is to the SUPER-TRACKED target (could be a quest now)
    if C_SuperTrack.IsSuperTrackingUserWaypoint
       and not C_SuperTrack.IsSuperTrackingUserWaypoint() then return end
    local d = C_Navigation.GetDistance and C_Navigation.GetDistance()
    if d and d > 0 and d <= ARRIVE then
        C_Map.ClearUserWaypoint()
        Nav.tracking = false
        toast("arrived — waypoint cleared")
    end
end

function Nav:StartWatch()
    Nav.tracking = true
    if not Nav.ticker then
        Nav.ticker = C_Timer.NewTicker(0.5, watch)
    end
end

-- entry = a scanner live-record; mapID = the map the pin was clicked on.
function Nav:Goto(mapID, entry, name)
    if not (mapID and entry) then return end

    if not C_Map.CanSetUserWaypointOnMap(mapID) then
        toast("can't place a waypoint on this map", 1, 0.3, 0.3)
        return
    end

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

    local point = UiMapPoint.CreateFromCoordinates(mapID, x, y)
    C_Map.SetUserWaypoint(point)
    Nav.target = { mapID = mapID, x = x, y = y }
    C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    Nav:StartWatch()   -- auto-clear the waypoint when you reach it
    toast("navigating to " .. (name or "target"))
end
