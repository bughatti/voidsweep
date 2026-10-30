----------------------------------------------------------------------
-- VoidSweep — Area POI scanner (world bosses + events)
--
-- Unlike vignettes (range-limited), C_AreaPoiInfo.GetAreaPOIForMap returns
-- EVERY point of interest on a map regardless of where you're standing —
-- with a guaranteed position, name, atlas, and (for timed ones) a
-- countdown. So world bosses and zone events are readable ZONE-WIDE,
-- first-party, no datamining and no flying close. This is the clean answer
-- to "is the world boss up right now?" that vignettes couldn't give us.
--
-- We only surface world bosses + events here; flight masters, quest hubs
-- and vendors also come back from GetAreaPOIForMap but aren't our content,
-- so classify() drops them.
----------------------------------------------------------------------
local ADDON, VS = ...

VS.Poi = {}
local P = VS.Poi

local function classify(info)
    local atlas = (info.atlasName or ""):lower()
    if atlas:find("worldboss") then return "worldboss" end
    -- Events, harvests, delves, quest hubs, flight masters, vendors all
    -- already carry their own Blizzard map icons — not our content.
    return nil
end

-- Zone-wide world-boss POIs for a map. No proximity required.
function P:Scan(mapID)
    local out = {}
    if not (mapID and C_AreaPoiInfo and C_AreaPoiInfo.GetAreaPOIForMap) then
        return out
    end

    local ids = C_AreaPoiInfo.GetAreaPOIForMap(mapID) or {}

    local seen = {}
    for _, poiID in ipairs(ids) do
        if not seen[poiID] then
            seen[poiID] = true
            local info = C_AreaPoiInfo.GetAreaPOIInfo(mapID, poiID)
            if info and info.position then
                local kind = classify(info)
                if kind then
                    local x, y = info.position:GetXY()
                    local secs = C_AreaPoiInfo.GetAreaPOISecondsLeft
                        and C_AreaPoiInfo.GetAreaPOISecondsLeft(poiID)
                    out[#out + 1] = {
                        areaPoiID   = poiID,
                        name        = info.name,
                        atlasName   = info.atlasName,
                        kind        = kind,
                        x           = x,
                        y           = y,
                        secondsLeft = secs,
                        isPoi       = true,
                    }
                end
            end
        end
    end
    return out
end

