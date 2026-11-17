----------------------------------------------------------------------
-- VoidSweep — Treasure chests on WoW Forever (2026-11-17)
--
-- The user: "i see a lot of chest running around in forever, some are locked some are unlocked,
-- they never pop up in sweep". VoidSweep found treasures through vignettes (the game's map markers)
-- and WoW Forever has none (measured: 0 on 38 maps), so no Forever chest ever showed. Here a chest
-- is seen the way a player sees it:
--   hover     its tooltip: the name, "Locked", "Requires ..." (measured: Forever object tooltips
--             carry the name and lock lines, no object ID; VoidDev CampProbe, 2026-11-17)
--   walk-up   the game's soft-interact target hands addons the object's GUID (its object ID)
--   open it   the loot window names the object it came from (GetLootSourceInfo)
-- and snapped to the nearest spot that chest can spawn at (ChestData.lua, from VoidDB). A walk-up or
-- an opened chest far from every listed spot becomes a new spot of your own.
--   seen      bright with a white ring for 15 minutes ("Seen here 3 min ago"), lock line if locked
--   opened    dim for 30 minutes ("Opened 4 min ago": someone took it)
--   learned   a spot you found yourself stays as a dim pin
--   possible  every listed spawn spot, small and faint: OFF by default (Ashenvale alone has 76;
--             the user doesn't want dot clouds), "Possible chest spots" in the map menu / /vsw chests
-- Shared with other Void players like rare sightings: CH:1:mapID,x,y,u|o,locked,layer,name. Only
-- listed spots of that chest are accepted, so nobody can paint fake pins.
-- Nothing inside dungeons or raids (every group has its own copy).
----------------------------------------------------------------------
local ADDON, VS = ...
if (select(4, GetBuildInfo()) or 0) >= 100000 then return end   -- WoW Forever only
local CD = VS.ChestData
if not CD then return end

VS.Chests = {}
local C = VS.Chests

local SEEN_TTL   = 900     -- a seen chest is "up" this long
local OPEN_KEEP  = 1800    -- an opened chest shows as taken this long
local SNAP_HOVER = 70      -- yards: a hovered chest can be this far from you
local SNAP_NEAR  = 25      -- yards: walk-up and loot are right next to it
local LEARN_CAP  = 200     -- learned spots per map
local TOL        = 0.02    -- a shared report must be this close to a listed spot (map units)
local RESEND     = 120     -- the same chest and state is shared at most this often

local LOCKED_TXT = (type(LOCKED) == "string" and LOCKED) or "Locked"

local nameSet = {}
for _, n in ipairs(CD.names) do nameSet[n] = true end
-- supply containers (Food Crate, Water Barrel, Weapon Crate ...): the same rules, their own map category
-- (the user, 2026-11-17, "Own category")
local supplySet = {}
for i in pairs(CD.supply or {}) do if CD.names[i] then supplySet[CD.names[i]] = true end end
local function kindOf(name) return supplySet[name] and "supply" or "chest" end
C.KindOf = kindOf

local function secret(v) return issecretvalue and issecretvalue(v) end
local function readable(v) if canaccessvalue then return canaccessvalue(v) end return not secret(v) end
local function inInstance() local i = IsInInstance(); return i and true or false end

local function DB()
    VoidSweepDB = VoidSweepDB or {}
    local c = VoidSweepDB.chests or {}
    VoidSweepDB.chests = c
    c.seen, c.spots = c.seen or {}, c.spots or {}
    return c
end

-- a stable key for a spot, the same on every client: name@x,y in thousandths
local function keyOf(name, x, y)
    return ("%s@%d,%d"):format(name, math.floor(x * 1000 + 0.5), math.floor(y * 1000 + 0.5))
end
C.KeyOf = keyOf

-- listed spots on a map: { { name, x, y, key, listed = true }, ... } (built once per map)
local listedCache = {}
local function listed(mapID)
    local l = listedCache[mapID]
    if l then return l end
    l = {}
    local flat = CD.spots[mapID]
    if flat then
        for i = 1, #flat, 3 do
            local name = CD.names[flat[i]]
            local x, y = flat[i + 1], flat[i + 2]
            if name and x and y then l[#l + 1] = { name = name, x = x, y = y, key = keyOf(name, x, y), listed = true } end
        end
    end
    listedCache[mapID] = l
    return l
end
C.Listed = listed

-- every spot on a map: listed + your own learned ones
local function allSpots(mapID)
    local out = {}
    for _, s in ipairs(listed(mapID)) do out[#out + 1] = s end
    local own = DB().spots[mapID]
    if own then
        for key, s in pairs(own) do
            if type(s) == "table" and s.name and s.x and s.y then
                out[#out + 1] = { name = s.name, x = s.x, y = s.y, key = key, learned = true }
            end
        end
    end
    return out
end

-- distance in yards between two points on a map (map units when the size is unknown, x 1000)
local function yards(mapID, x1, y1, x2, y2)
    local w, h = C_Map.GetMapWorldSize(mapID)
    if w and h and w > 0 and h > 0 then
        local dx, dy = (x1 - x2) * w, (y1 - y2) * h
        return math.sqrt(dx * dx + dy * dy)
    end
    local dx, dy = x1 - x2, y1 - y2
    return math.sqrt(dx * dx + dy * dy) * 1000
end

-- where you stand, on the map that lists chests: the zone, also from a town / cave map inside it
local function here()
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return nil end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if not ok or not pos then return nil end
    local x, y = pos:GetXY()
    if secret(x) or secret(y) or not x or (x == 0 and y == 0) then return nil end
    local guard = 0
    while not CD.spots[mapID] and guard < 4 do
        guard = guard + 1
        local info = C_Map.GetMapInfo(mapID)
        local parent = info and info.parentMapID
        if not parent or parent == 0 then break end
        local cont, wp = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
        if not (cont and wp) then break end
        local _, p = C_Map.GetMapPosFromWorldPos(cont, wp, parent)
        if not p then break end
        mapID = parent
        x, y = p:GetXY()
    end
    return mapID, x, y
end

-- the spot of this chest nearest to (x, y) within max yards
local function nearest(mapID, name, x, y, max)
    local best, bestD
    for _, s in ipairs(allSpots(mapID)) do
        if s.name == name then
            local d = yards(mapID, x, y, s.x, s.y)
            if d <= max and (not bestD or d < bestD) then best, bestD = s, d end
        end
    end
    return best
end

local function myLayer(mapID)
    local L = VS.Layer
    return L and L.Current and L:Current(L:Zone(mapID)) or nil
end

local lastSent = {}
local function share(mapID, spot, st, locked, layer)
    if VS.Config and VS:Config().sync == false then return end
    local k = spot.key .. st
    if lastSent[k] and GetTime() - lastSent[k] < RESEND then return end
    lastSent[k] = GetTime()
    if not (VS.Sync and VS.Sync.SendSighting) then return end
    VS.Sync:SendSighting(("CH:1:%d,%d,%d,%s,%d,%s,%s"):format(mapID, math.floor(spot.x * 1000 + 0.5),
        math.floor(spot.y * 1000 + 0.5), st, locked and 1 or 0, layer or "-", spot.name))
end

local function refresh()
    if VS.Pins and VS.Pins.Refresh then VS.Pins:Refresh() end
end

-- You saw a chest. how = "hover" | "near" | "opened"
local lastNote = {}
function C:Note(name, how, locked, lock)
    if not (name and nameSet[name]) or inInstance() then return end
    -- a tooltip fires many times while you point at it
    local nk = name .. how
    if how ~= "opened" and lastNote[nk] and GetTime() - lastNote[nk] < 5 then return end
    lastNote[nk] = GetTime()
    local mapID, x, y = here()
    if not mapID then return end
    local spot = nearest(mapID, name, x, y, how == "hover" and SNAP_HOVER or SNAP_NEAR)
    if not spot then
        -- a spot nobody listed, learned only when you OPEN it (you're within loot range). A hovered chest
        -- can be far off, and the walk-up highlight can pick one several yards away: live 2026-11-17 it
        -- put a footlocker on the Food Crate the user stood at. Those only light up known spots.
        if how ~= "opened" then return end
        local own = DB().spots
        own[mapID] = own[mapID] or {}
        local n = 0
        for _ in pairs(own[mapID]) do n = n + 1 end
        if n >= LEARN_CAP then return end
        local key = keyOf(name, x, y)
        own[mapID][key] = { name = name, x = x, y = y, t = time(), o = 1 }   -- o: learned by opening it
        spot = { name = name, x = x, y = y, key = key, learned = true }
    end
    local seen = DB().seen
    seen[mapID] = seen[mapID] or {}
    local prev = seen[mapID][spot.key]
    local now = time()
    -- a hover reads the lock fresh (an unlocked chest clears it, Sol); walk-up and loot can't see it
    local fresh = how == "hover"
    local rec = {
        t = now, name = spot.name, x = spot.x, y = spot.y,
        -- not a hover: only a positive "locked" (you picked it) adds to what was known
        locked = (fresh and (locked or nil)) or (not fresh and (locked or (prev and prev.locked))) or nil,
        lock = (fresh and lock) or (not fresh and prev and prev.lock) or nil,
        opened = (how == "opened") and now or nil,
        layer = myLayer(mapID),
    }
    -- seen again right after you opened it (its tooltip as it fades): still opened
    if how ~= "opened" and prev and prev.opened and now - prev.opened < 60 then rec.opened = prev.opened end
    seen[mapID][spot.key] = rec
    share(mapID, spot, rec.opened and "o" or "u", rec.locked, rec.layer)
    refresh()
    if not rec.opened then C_Timer.After(SEEN_TTL + 1, refresh) end
end

-- Another Void player saw a chest (VoidSync). Untrusted: a listed spot of that chest only.
function C:OnShared(body, sender)
    if type(body) ~= "string" or #body > 200 then return end
    local mapID, x1k, y1k, st, lk, layer, name = body:match("^(%d+),(%d+),(%d+),([uo]),([01]),([%d%-]+),(.+)$")
    mapID, x1k, y1k = tonumber(mapID), tonumber(x1k), tonumber(y1k)
    if not (mapID and x1k and y1k and name and nameSet[name]) then return end
    if layer == "-" then layer = nil elseif #layer > 20 then return end
    if layer and VS.Layer and VS.Layer.Canon then layer = VS.Layer.Canon(layer) end
    local x, y = x1k / 1000, y1k / 1000
    local spot, bestD
    for _, s in ipairs(listed(mapID)) do
        if s.name == name then
            local d = math.max(math.abs(s.x - x), math.abs(s.y - y))
            if d <= TOL and (not bestD or d < bestD) then spot, bestD = s, d end
        end
    end
    if not spot then return end
    local seen = DB().seen
    seen[mapID] = seen[mapID] or {}
    local prev = seen[mapID][spot.key]
    local now = time()
    -- your own fresh look wins, except "someone opened it" (it's gone now, Sol); a chest you just saw
    -- opened isn't lit up again by a report; the same news again changes nothing (no replaying)
    if prev and not prev.by and now - prev.t < 60 and not (st == "o" and not prev.opened) then return end
    if st == "u" and prev and prev.opened and now - prev.opened < 60 then return end
    if prev and prev.by and ((st == "o") == (prev.opened ~= nil)) and now - prev.t < RESEND then return end
    local locked = lk == "1"
    seen[mapID][spot.key] = {
        t = now, name = spot.name, x = spot.x, y = spot.y, by = sender or "another Void player",
        locked = locked or nil, lock = locked and prev and prev.lock or nil,
        opened = (st == "o") and now or nil, layer = layer,
    }
    refresh()
    if st == "u" then C_Timer.After(SEEN_TTL + 1, refresh) end
end

-- the state of a spot right now: "up" | "opened" | nil, and its record
local function state(mapID, key)
    local m = DB().seen[mapID]
    local s = m and m[key]
    if not s then return nil end
    local age = time() - (s.t or 0)
    if s.opened then
        if time() - s.opened <= OPEN_KEEP then return "opened", s end
        return nil
    end
    if age <= SEEN_TTL then return "up", s end
    return nil
end

-- pins for VS.Pins:Build (world map + minimap): { { entry, x, y }, ... }
function C:Candidates(mapID)
    local out = {}
    if not mapID then return out end
    local cfg = VS:Config()
    for _, s in ipairs(allSpots(mapID)) do
        local st, rec = state(mapID, s.key)
        local show = st or s.learned or cfg.chestSpots
        if show then
            local e = {
                name = s.name, kind = kindOf(s.name), spawnKey = "fc:" .. s.key, chestSpot = true,
                chestState = st or (s.learned and "known") or "possible",
                mapID = mapID,
            }
            if rec then
                e.age, e.by, e.locked, e.lock, e.layer = time() - (rec.opened or rec.t), rec.by, rec.locked, rec.lock, rec.layer
            end
            e.mmHide = (e.chestState == "possible")   -- possible spots stay off the minimap
            out[#out + 1] = { entry = e, x = s.x, y = s.y }
        end
    end
    return out
end

-- tooltip lines for a chest pin (Pins.lua)
function C:TooltipLines(e, add)
    local ago = SecondsToTime(math.max(60, e.age or 0), true)
    local by = e.by and (" by " .. e.by) or ""
    if e.chestState == "up" then
        add(("Seen here %s ago%s"):format(ago, by), 0.3, 1, 0.3)
    elseif e.chestState == "opened" then
        add(("Opened %s ago%s: taken for now"):format(ago, by), 1, 0.45, 0.45)
    elseif e.chestState == "known" then
        add("You opened one here before: it comes back after a while", 0.85, 0.8, 0.4)
    else
        add("A spot it can appear at (from VoidDB)", 0.85, 0.8, 0.4)
    end
    if e.lock then
        add(e.lock, 1, 0.6, 0.2)
    elseif e.locked then
        add("Locked: needs Lockpicking (rogues) or a key", 1, 0.6, 0.2)
    end
    local lt = VS.Sightings and VS.Sightings.LayerText and e.layer and VS.Sightings:LayerText(e.mapID, e.layer) or ""
    if lt ~= "" then add(lt) end
end

function C:ToggleSpots()
    local cfg = VS:Config()
    cfg.chestSpots = not cfg.chestSpots
    refresh()
    return cfg.chestSpots
end

-- how many seen / opened lately and how many possible spots on a map (the menu and /vsw chests)
function C:Count(mapID, kind)
    local up, possible = 0, 0
    for _, s in ipairs(listed(mapID)) do
        if not kind or kindOf(s.name) == kind then possible = possible + 1 end
    end
    for _, s in ipairs(allSpots(mapID)) do
        if (not kind or kindOf(s.name) == kind) and state(mapID, s.key) == "up" then up = up + 1 end
    end
    return up, possible
end

----------------------------------------------------------------------
-- Seeing chests
----------------------------------------------------------------------
local OBJECT_TYPE = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Object

local function onTooltip(tt, data)
    if tt ~= GameTooltip or type(data) ~= "table" or not OBJECT_TYPE then return end
    if not (readable(data.type) and data.type == OBJECT_TYPE) then return end
    local lines = data.lines
    local first = lines and lines[1] and lines[1].leftText
    if not (first and readable(first) and nameSet[first]) then return end
    local locked, lock = false, nil
    for i = 2, #lines do
        local t = lines[i] and lines[i].leftText
        if type(t) == "string" and readable(t) then
            if t == LOCKED_TXT then locked = true end
            if not lock and t:find("^Requires ") and #t <= 60 then lock, locked = t, true end
        end
    end
    pcall(C.Note, C, first, "hover", locked, lock)
end

-- "GameObject-0-<server>-<zone>-<spawn>-<objectID>-<uid>" -> the chest's name
local function chestFromGUID(guid)
    if type(guid) ~= "string" or not readable(guid) then return nil end
    local m = guid:match("^GameObject%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    local id = m and tonumber(m)
    local i = id and CD.obj[id]
    return i and CD.names[i] or nil
end
C.FromGUID = chestFromGUID

-- The chest you walked up to last: a loot window that names no source right after counts as opening it.
local lastNear = nil   -- { name, t }

-- What the loot window came from: a chest's name, "other" when it names anything else (a mob, a Food
-- Crate, a herb), or nil when it names nothing at all.
local function lootSource()
    if not (GetLootSourceInfo and GetNumLootItems) then return nil end
    local other
    for slot = 1, math.min(GetNumLootItems() or 0, 8) do
        local ok, guid = pcall(GetLootSourceInfo, slot)
        if ok and type(guid) == "string" and readable(guid) and guid ~= "" then
            local name = chestFromGUID(guid)
            if name then return name end
            other = true
        end
    end
    return other and "other" or nil
end

-- One loot window = one session (Sol, 2026-11-17): LOOT_READY and LOOT_OPENED both fire for it, and with
-- auto-loot the window can be empty by the second. The first event that names a source decides ("chest"
-- name, or "other": a mob / Food Crate, which also blocks the fallback); a window that never named one
-- falls back to the chest you walked up to, at LOOT_CLOSED. LOOT_CLOSED ends the session.
local loot = nil     -- { decided = true } once a source was named this window
-- A rogue's Pick Lock right before a chest opens: that chest was locked, even when you never hovered it
-- (the user's Durnholde run, 2026-11-17: footlockers walked up to and opened showed no lock).
-- 1804 is Pick Lock's Classic ID; the name is the fallback in case Forever renumbered it.
local lastPick = nil   -- GetTime() of your last Pick Lock; nil = none this session (Sol: 0 counted early on)
local function isPickLock(id)
    if id == 1804 then return true end
    local ok, name = pcall(function()
        if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
        return GetSpellInfo and (GetSpellInfo(id))
    end)
    return ok and name == "Pick Lock"
end
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_SOFT_INTERACT_CHANGED")
-- LOOT_READY too (live 2026-11-17: an opened footlocker wasn't recorded): with auto-loot the window
-- can be empty by LOOT_OPENED; VoidQuest's Drops.lua listens to both for the same reason
ev:RegisterEvent("LOOT_READY")
ev:RegisterEvent("LOOT_OPENED")
ev:RegisterEvent("LOOT_CLOSED")
-- Pick Lock on WoW Forever logs only a START (and FAILED when it fails), never a success, even when the
-- lock opens (the user's combat log, 2026-11-17 12:52: START, FAILED, START, then the footlocker opened
-- and wasn't marked locked). So a started Pick Lock counts, and a failed / interrupted one is taken back.
ev:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
ev:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
ev:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
ev:SetScript("OnEvent", function(_, event, a1, a2, a3)
    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_SUCCEEDED" then
        if type(a3) == "number" and readable(a3) and isPickLock(a3) then lastPick = GetTime() end
    elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        if type(a3) == "number" and readable(a3) and isPickLock(a3) then lastPick = nil end
    elseif event == "PLAYER_LOGIN" then
        if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and TooltipDataProcessor.AllTypes then
            TooltipDataProcessor.AddTooltipPostCall(TooltipDataProcessor.AllTypes, onTooltip)
        end
        -- forget old news (a week) and spots past the cap are never added
        local seen, now = DB().seen, time()
        -- spots learned before 2026-11-17's fix by a walk-up (no o flag): kept only if you opened a chest
        -- there; the others could sit on whatever you stood at (a Food Crate)
        for mapID, m in pairs(DB().spots) do
            for k, s in pairs(m) do
                local sm = seen[mapID]
                if type(s) ~= "table" or (not s.o and not (sm and sm[k] and sm[k].opened)) then m[k] = nil
                elseif not s.o then s.o = 1 end
            end
        end
        for _, m in pairs(seen) do
            for k, s in pairs(m) do if type(s) ~= "table" or now - (s.t or 0) > 7 * 86400 then m[k] = nil end end
        end
    elseif event == "PLAYER_SOFT_INTERACT_CHANGED" then
        local name = chestFromGUID(a2)
        if name then
            lastNear = { name = name, t = GetTime() }
            pcall(C.Note, C, name, "near")
        end
    elseif event == "LOOT_READY" or event == "LOOT_OPENED" or event == "LOOT_CLOSED" then
        local function opened(name)
            lastNear = nil
            local picked = lastPick and GetTime() - lastPick <= 30 or false   -- you picked its lock just before
            pcall(C.Note, C, name, "opened", picked or nil, nil)
        end
        if event == "LOOT_CLOSED" then
            -- the window never named a source: the chest you walked up to a moment ago (never when the
            -- loot named something else: a mob, or the Food Crate next to a footlocker)
            if loot and not loot.decided and lastNear and GetTime() - lastNear.t <= 15 then opened(lastNear.name) end
            loot = nil
            return
        end
        loot = loot or {}
        if loot.decided then return end
        local src = lootSource()
        if src then
            loot.decided = true
            if src ~= "other" then opened(src) end
        end
    end
end)
