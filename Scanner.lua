----------------------------------------------------------------------
-- VoidSweep — Scanner
--
-- Reads the game's LIVE vignette set (C_VignetteInfo) — the same system
-- that draws rare skulls / treasure chests on the minimap. Anything the
-- client currently knows is UP shows here, with name + atlas + kind.
-- Position is NOT cached here: it's map-relative, so Pins.lua asks
-- C_VignetteInfo.GetVignettePosition() against whichever map is open.
--
-- All C_VignetteInfo reads are SecretArguments = "AllowedWhenUntainted"
-- (verified in wow-ui-source) — no secret-value taint, safe to touch.
----------------------------------------------------------------------
local ADDON, VS = ...

VS.Scanner = { live = {} }
local Scanner = VS.Scanner

local VT_TREASURE  = (Enum.VignetteType and Enum.VignetteType.Treasure) or 3
local OT_DEFEAT    = (Enum.VignetteObjectiveType and Enum.VignetteObjectiveType.Defeat) or 1
local OT_DEFEAT_HP = (Enum.VignetteObjectiveType and Enum.VignetteObjectiveType.DefeatShowRemainingHealth) or 2

-- Classify a vignette into our kinds, or nil to skip it.
--
-- The atlas is the reliable signal (confirmed from live data): real content
-- uses VignetteLoot* (treasure) and VignetteKill* (rare). Everything else —
-- "Quartermaster", "housing-decor-vendor", "poi-abundance", "embercourt",
-- "loreobject" — is a friendly NPC / harvest / event / clutter, and gets
-- skipped. Type/objectiveType are backups for oddly-atlased content.
local function classify(guid, info)
    local la = (info.atlasName or ""):lower()

    -- Chests: a loot/storage/cache/coffer/treasure atlas or the explicit
    -- Treasure type. (Midnight uses atlases like "pocket-storage" that don't
    -- contain "loot" — those were being dropped.)
    if la:find("loot") or la:find("storage") or la:find("cache")
       or la:find("coffer") or la:find("chest") or la:find("treasure")
       or info.type == VT_TREASURE then
        return "chest"
    end

    -- Rares / bosses: a skull-kill atlas, or a "defeat" objective.
    local ot = info.objectiveType
    if la:find("kill") or ot == OT_DEFEAT or ot == OT_DEFEAT_HP then
        local grp = C_VignetteInfo.GetRecommendedGroupSize
            and C_VignetteInfo.GetRecommendedGroupSize(guid)
        if (grp and grp >= 5) or la:find("worldboss") then return "worldboss" end
        return "rare"
    end

    -- Lore objects: one-time readable collectibles (exploration/lore achieves).
    if la:find("loreobject") then return "lore" end

    -- Friendly NPCs (vendors), harvests, events → not ours.
    return nil
end

function Scanner:Rescan()
    wipe(self.live)
    if not C_VignetteInfo or not C_VignetteInfo.GetVignettes then return end

    -- map we're standing on — used to resolve each vignette's position so
    -- we can remember it (Data.lua) for a persistent, dimmed pin later.
    local playerMap = C_Map.GetBestMapForUnit("player")

    local guids = C_VignetteInfo.GetVignettes()
    for _, guid in ipairs(guids) do
        local info = C_VignetteInfo.GetVignetteInfo(guid)
        -- a killed rare's vignette lingers with isDead=true — it's not "up"
        -- anymore, so drop it (its known/seed dot still shows, dim).
        local kind = info and info.name and not info.isDead and classify(guid, info)
        if kind then
            local questID = info.rewardQuestID
            if questID == 0 then questID = nil end   -- 0 = no completion quest

            local entry = {
                guid       = guid,
                name       = info.name,
                atlasName  = info.atlasName,
                isDead     = info.isDead,
                vignetteID = info.vignetteID,
                objectGUID = info.objectGUID,
                questID    = questID,
                kind       = kind,
            }
            self.live[#self.live + 1] = entry

            if playerMap then
                local pos = C_VignetteInfo.GetVignettePosition(guid, playerMap)
                if pos then
                    VS.Learned:Record(entry, playerMap, pos.x, pos.y)
                    -- delves: also count WHERE random treasure spawns, per visit
                    if VS.Spawns then VS.Spawns:Seen(entry, playerMap, pos.x, pos.y) end
                    -- crowd-broadcast a live rare/boss sighting (throttled)
                    if entry.kind == "rare" or entry.kind == "worldboss" then
                        local hp = C_VignetteInfo.GetHealthPercent
                            and C_VignetteInfo.GetHealthPercent(guid)
                        VS.Sync:Broadcast(entry, pos.x, pos.y, hp)
                    end
                end
            end
        end
    end
end

function Scanner:GetLive()
    return self.live
end

-- After a rescan, if we're standing on a known chest/lore that has no live
-- vignette, we looted it → mark it cleared (handles items with no completion).
function Scanner:ProximityClear()
    local mapID = C_Map.GetBestMapForUnit("player")
    local ppos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    if not ppos then return 0 end
    local liveVIDs = {}
    for _, e in ipairs(self.live) do
        if e.vignetteID then liveVIDs[e.vignetteID] = true end
    end
    local px, py = ppos:GetXY()
    return VS.Learned:ClearNearby(mapID, px, py, liveVIDs)
end

