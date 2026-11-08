----------------------------------------------------------------------
-- VoidSweep — Sightings: rares seen on nameplates, your target, your mouseover.
--
-- WoW Forever's Classic world has no rare markers (vignettes), so the Forever
-- rare pins could never light up. Here a rare is seen the way a player sees it:
-- its nameplate appears, you target it or point at it. UnitClassification says
-- rare / rare elite; the name is matched to the starter map's rares.
--   up      -> its pin gets the white "up" ring for 5 minutes: "Up · seen 1 min ago"
--   dead    -> "Killed 12 min ago" (kept for 2 hours, so you can guess when it's back)
-- Each sighting goes to other VoidSweep players (the same paced whispers / channel
-- as rare alerts): SN:1:mapID,x,y,u|d,name. Only rares from the starter map are
-- accepted, near their spot, so nobody can paint fake pins.
-- WoW Forever layers (Layer.lua, 2026-11-08): a sighting carries the layer it was seen
-- on, SN:2:mapID,x,y,u|d,<server-shard>,name, and says whether that's YOUR layer: a
-- rare up on another layer isn't there for you. SN:1 (no layer) is still read, and
-- still sent while your layer isn't known yet.
-- Works on retail too (vignettes already light those pins; this only adds kills).
----------------------------------------------------------------------
local ADDON, VS = ...
VS.Sightings = {}
local S = VS.Sightings

local UP_TTL    = 300     -- an "up" sighting shows for this long
local KEEP      = 7200    -- a kill is remembered this long
local RESEND    = 60      -- don't resend the same rare (same state) within this
local TOL       = 0.08    -- a shared sighting must be this close to the rare's spot

local byName                -- name -> { { mapID, key, x, y }, ... } from the seed
local lastSent = {}         -- name .. state -> GetTime()

local function DB()
    VoidSweepDB = VoidSweepDB or {}
    VoidSweepDB.sightings = VoidSweepDB.sightings or {}
    return VoidSweepDB.sightings
end

local function index()
    if byName then return byName end
    byName = {}
    for mapID, recs in pairs(VS.Seed or {}) do
        for key, r in pairs(recs) do
            if r.kind == "rare" and r.name then
                local t = byName[r.name] or {}
                t[#t + 1] = { mapID = mapID, key = key, x = r.x, y = r.y }
                byName[r.name] = t
            end
        end
    end
    return byName
end

local function playerPos()
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return nil end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if not ok or not pos then return nil end
    local x, y = pos:GetXY()
    if issecretvalue and (issecretvalue(x) or issecretvalue(y)) then return nil end
    if not x or (x == 0 and y == 0) then return nil end
    return mapID, x, y
end

-- The seed rare with this name nearest to (mapID, x, y): this map or a map it sits in.
local function match(name, mapID, x, y)
    local list = index()[name]
    if not list then return nil end
    local best, bestD
    for _, e in ipairs(list) do
        local ex, ey = x, y
        if e.mapID ~= mapID and mapID then
            -- the player stands on a child map (a cave, a town): put the point on the rare's map
            local cont, wp = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
            local p
            if cont and wp then p = select(2, C_Map.GetMapPosFromWorldPos(cont, wp, e.mapID)) end   -- (not "cont and f()": that keeps one return)
            if p then ex, ey = p:GetXY() else ex, ey = nil, nil end
        end
        if ex then
            local d = (ex - e.x) ^ 2 + (ey - e.y) ^ 2
            if not bestD or d < bestD then best, bestD = e, d end
        end
    end
    return best, bestD and math.sqrt(bestD)
end

-- The layer a rare's zone is on for you right now (nil = not known).
local function myLayer(mapID)
    local L = VS.Layer
    return L and L:Current(L:Zone(mapID)) or nil
end

-- "same" / "other" / nil: was this sighting on your layer?
function S:LayerMatch(mapID, layer)
    local L = VS.Layer
    if not (L and layer) then return nil end
    return L:Compare(layer, L:Zone(mapID))
end

-- A few words for chat lines and tooltips ("" while unknown).
function S:LayerText(mapID, layer)
    local m = self:LayerMatch(mapID, layer)
    if m == "same" then return "|cff33ff33your layer|r" end
    if m == "other" then return "|cffff9933another layer (" .. layer .. "), not up for you|r" end
    return ""
end

local function store(e, dead, who, layer)
    local db = DB()
    db[e.mapID] = db[e.mapID] or {}
    db[e.mapID][e.key] = { t = time(), dead = dead or nil, by = who, layer = layer }
    if VS.Pins and VS.Pins.Refresh then
        VS.Pins:Refresh()
        if not dead then C_Timer.After(UP_TTL + 1, function() VS.Pins:Refresh() end) end   -- the ring goes away
    end
end

-- { t, dead, by, age } for a seed key on a map, or nil when stale.
function S:Get(mapID, key)
    local m = DB()[mapID]
    local s = m and m[key]
    if not s then return nil end
    local age = time() - (s.t or 0)
    if age > KEEP or (not s.dead and age > UP_TTL) then return nil end
    return { t = s.t, dead = s.dead, by = s.by, age = age, up = not s.dead, layer = s.layer, mapID = mapID }
end

local function share(e, name, dead, layer)
    local k = name .. (dead and "d" or "u")
    if lastSent[k] and GetTime() - lastSent[k] < RESEND then return end
    lastSent[k] = GetTime()
    if not (VS.Sync and VS.Sync.SendSighting) then return end
    local x, y, st = math.floor(e.x * 1000), math.floor(e.y * 1000), dead and "d" or "u"
    if layer then
        VS.Sync:SendSighting(("SN:2:%d,%d,%d,%s,%s,%s"):format(e.mapID, x, y, st, layer, name))
    else
        VS.Sync:SendSighting(("SN:1:%d,%d,%d,%s,%s"):format(e.mapID, x, y, st, name))
    end
end

local function check(unit)
    if not UnitExists(unit) then return end
    local cls = UnitClassification(unit)
    if cls ~= "rare" and cls ~= "rareelite" then return end
    if not UnitCanAttack("player", unit) then return end
    local name = UnitName(unit)
    if not name or (issecretvalue and issecretvalue(name)) then return end
    local mapID, x, y = playerPos()
    if not mapID then return end
    local e, d = match(name, mapID, x, y)
    if not e or d > 0.25 then return end    -- not one of ours, or far from its spot
    local dead = UnitIsDead(unit) and true or false
    local cur = S:Get(e.mapID, e.key)
    if cur and cur.dead == (dead or nil) and cur.by == nil and cur.age < 30 then return end
    local layer = myLayer(e.mapID)   -- you see it, so it's on your layer
    store(e, dead, nil, layer)
    share(e, name, dead, layer)
end

-- From another player (VoidSync). Untrusted: a rare of ours, near its spot.
-- version 1 = no layer, 2 = with the layer it was seen on.
function S:OnShared(body, sender, version)
    local mapID, x1k, y1k, st, layer, name
    if version == 2 then
        mapID, x1k, y1k, st, layer, name = body:match("^(%d+),(%d+),(%d+),([ud]),(%d+%-%d+),(.+)$")
    else
        mapID, x1k, y1k, st, name = body:match("^(%d+),(%d+),(%d+),([ud]),(.+)$")
    end
    if layer and #layer > 20 then return end
    mapID, x1k, y1k = tonumber(mapID), tonumber(x1k), tonumber(y1k)
    if not (mapID and x1k and y1k and name) or #name > 40 then return end
    local key = "n" .. name
    local seed = VS.Seed and VS.Seed[mapID] and VS.Seed[mapID][key]
    if not (seed and seed.kind == "rare") then return end
    if math.abs(seed.x - x1k / 1000) > TOL or math.abs(seed.y - y1k / 1000) > TOL then return end
    local dead = st == "d"
    local cur = S:Get(mapID, key)
    if cur and cur.by == nil and cur.age < UP_TTL then return end   -- your own sighting is fresher
    -- the same news again (repeats, or several players at once): no new chat line, no
    -- refresh of the timer, so nobody can keep a pin lit by replaying one report
    -- (same layer only: news from your layer always gets through after another layer's, Codex)
    if cur and cur.dead == (dead or nil) and cur.layer == layer and cur.age < RESEND then return end
    -- news from another layer never replaces fresh news from yours (a kill over there
    -- doesn't mean it's dead here)
    if cur and S:LayerMatch(mapID, cur.layer) == "same" and S:LayerMatch(mapID, layer) == "other" then return end
    store({ mapID = mapID, key = key }, dead, sender or "another player", layer)
    if not dead then
        local zone = C_Map.GetMapInfo(mapID)
        local lt = S:LayerText(mapID, layer)
        DEFAULT_CHAT_FRAME:AddMessage(("|cff00c7ff[VoidSweep]|r |cff33ff33%s is up|r (seen by %s%s)%s."):format(
            name, sender or "another player", zone and (", " .. zone.name) or "", lt ~= "" and (" · " .. lt) or ""))
        -- up on another layer: find out which Void players are on it (LayerNet, rate-limited)
        if S:LayerMatch(mapID, layer) == "other" and VS.LayerNet and VS.Layer then
            VS.LayerNet:Ask(VS.Layer:Zone(mapID))
        end
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
f:RegisterEvent("PLAYER_TARGET_CHANGED")
f:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
f:RegisterEvent("UNIT_HEALTH")
f:SetScript("OnEvent", function(_, event, unit)
    if event == "NAME_PLATE_UNIT_ADDED" then check(unit)
    elseif event == "PLAYER_TARGET_CHANGED" then check("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then check("mouseover")
    elseif event == "UNIT_HEALTH" and unit == "target" and UnitIsDead("target") then
        check("target")   -- you (or someone) just killed your target
    end
end)
