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

local function store(e, dead, who)
    local db = DB()
    db[e.mapID] = db[e.mapID] or {}
    db[e.mapID][e.key] = { t = time(), dead = dead or nil, by = who }
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
    return { t = s.t, dead = s.dead, by = s.by, age = age, up = not s.dead }
end

local function share(e, name, dead)
    local k = name .. (dead and "d" or "u")
    if lastSent[k] and GetTime() - lastSent[k] < RESEND then return end
    lastSent[k] = GetTime()
    if VS.Sync and VS.Sync.SendSighting then
        VS.Sync:SendSighting(("SN:1:%d,%d,%d,%s,%s"):format(e.mapID,
            math.floor(e.x * 1000), math.floor(e.y * 1000), dead and "d" or "u", name))
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
    store(e, dead, nil)
    share(e, name, dead)
end

-- From another player (VoidSync). Untrusted: a rare of ours, near its spot.
function S:OnShared(body, sender)
    local mapID, x1k, y1k, st, name = body:match("^(%d+),(%d+),(%d+),([ud]),(.+)$")
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
    if cur and cur.dead == (dead or nil) and cur.age < RESEND then return end
    store({ mapID = mapID, key = key }, dead, sender or "another player")
    if not dead then
        local zone = C_Map.GetMapInfo(mapID)
        DEFAULT_CHAT_FRAME:AddMessage(("|cff00c7ff[VoidSweep]|r |cff33ff33%s is up|r (seen by %s%s)."):format(
            name, sender or "another player", zone and (", " .. zone.name) or ""))
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
