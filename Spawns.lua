----------------------------------------------------------------------
-- VoidSweep — Spawn spots (random treasure heat map, delves only)
--
-- Some delve treasure moves every run (e.g. the blue "Mislaid Curiosity"
-- bags). The learned store keeps ONE spot per treasure, so a random bag
-- just jumped to wherever you saw it last. Here, inside delves, every
-- sighting is clustered into a spot and counted ONCE PER VISIT, next to
-- how many visits you've made to that map. Spots that come up often get a
-- pin sized/brightened by how often ("here 7 of 10 visits").
--
-- VoidSweepDB.spawns[mapID] = { visits = N, items = { [vignetteID] =
--   { name, kind, atlas, cells = { {x, y, n}, ... } } } }
-- A "visit" = one entry into the delve (not a /reload) that reached this map.
----------------------------------------------------------------------
local ADDON, VS = ...

VS.Spawns = {}
local S = VS.Spawns

local CELL_RADIUS = 0.025   -- sightings this close (map fraction) are the same spot
local CONFIRMED   = 3       -- seen on this many separate visits = a strong dot
-- (user choice 2026-10-18: show every spot from its FIRST sighting as a faint dot,
-- strong once it's been seen on 3 visits)

local function DB()
    VoidSweepDB = VoidSweepDB or {}
    VoidSweepDB.spawns = VoidSweepDB.spawns or {}
    return VoidSweepDB.spawns
end

local function inDelve()
    local _, t = IsInInstance()
    return t == "scenario"
end

-- Per-character run state (survives /reload): which maps this run already
-- counted as a visit, and which spot each item already counted this run.
local function Run()
    VoidSweepCharDB = VoidSweepCharDB or {}
    VoidSweepCharDB.spawnRun = VoidSweepCharDB.spawnRun or { maps = {}, hits = {} }
    return VoidSweepCharDB.spawnRun
end

-- New run whenever you zone in for real (PLAYER_ENTERING_WORLD, not a reload).
function S:NewRun()
    VoidSweepCharDB = VoidSweepCharDB or {}
    VoidSweepCharDB.spawnRun = { maps = {}, hits = {} }
end

local function mapRec(mapID)
    local db = DB()
    db[mapID] = db[mapID] or { visits = 0, items = {} }
    return db[mapID]
end

-- Count this map as visited once per run.
function S:Visit(mapID)
    if not (mapID and inDelve()) then return end
    local run = Run()
    if run.maps[mapID] then return end
    run.maps[mapID] = true
    local m = mapRec(mapID)
    m.visits = (m.visits or 0) + 1
end

-- A treasure seen at (x, y) on mapID while in a delve. Keyed by vignetteID, or
-- (for loot-time records of things with no minimap icon) entry.spawnID.
function S:Seen(entry, mapID, x, y)
    local vid = entry and (entry.vignetteID or entry.spawnID)
    if not (vid and mapID and x and y) then return end
    if entry.kind ~= "chest" or not inDelve() then return end
    self:Visit(mapID)
    local m = mapRec(mapID)
    local it = m.items[vid]
    if not it then
        it = { name = entry.name, kind = entry.kind, atlas = entry.atlasName, cells = {} }
        m.items[vid] = it
    end
    -- nearest existing spot within the radius
    local best, bestD
    for i, c in ipairs(it.cells) do
        local dx, dy = c.x - x, c.y - y
        local d = dx * dx + dy * dy
        if d <= CELL_RADIUS * CELL_RADIUS and (not bestD or d < bestD) then best, bestD = i, d end
    end
    local run = Run()
    if not best then
        it.cells[#it.cells + 1] = { x = x, y = y, n = 0 }
        best = #it.cells
    end
    local hitKey = mapID .. ":" .. vid .. ":" .. best
    if run.hits[hitKey] then return end   -- already counted this spot this visit
    run.hits[hitKey] = true
    local c = it.cells[best]
    c.n = c.n + 1
    -- running average keeps the pin centered on where it actually shows up
    c.x = c.x + (x - c.x) / c.n
    c.y = c.y + (y - c.y) / c.n
end

-- Has this treasure shown up in more than one spot here (= random spawn)?
function S:IsRandom(mapID, vid)
    local m = vid and DB()[mapID]
    local it = m and m.items[vid]
    return it and #it.cells > 1 or false
end

-- Pin candidates for a map: { entry, x, y } for spots worth showing.
function S:Candidates(mapID)
    local out = {}
    local m = DB()[mapID]
    if not m then return out end
    for vid, it in pairs(m.items) do
        -- vignette treasure seen in only one spot is a FIXED chest with its normal pin;
        -- loot-recorded objects (no minimap icon) have no other pin, so always show them
        local lootOnly = type(vid) == "string"
        if #it.cells > 1 or lootOnly then
            for i, c in ipairs(it.cells) do
                if c.n >= 1 then
                    local confirmed = c.n >= CONFIRMED
                    -- faint until confirmed; once confirmed, brightness follows how often
                    local rate = (m.visits or 0) > 0 and (c.n / m.visits) or 0
                    local heat = confirmed and (0.6 + 0.4 * math.min(1, rate)) or (0.12 + 0.1 * (c.n - 1))
                    out[#out + 1] = {
                        entry = { name = it.name, kind = it.kind or "chest", atlasName = it.atlas,
                                  heat = heat, hits = c.n, visits = m.visits or c.n, confirmed = confirmed,
                                  spawnKey = "s" .. tostring(vid) .. ":" .. i },
                        x = c.x, y = c.y,
                    }
                end
            end
        end
    end
    return out
end

-- Text summary for /vsw spawns.
function S:Report(mapID)
    local m = DB()[mapID]
    if not m then return { "No spawn data for this map yet (only delves are tracked)." } end
    local lines = { ("%d visit%s recorded here."):format(m.visits or 0, (m.visits or 0) == 1 and "" or "s") }
    for _, it in pairs(m.items) do
        local parts, sorted = {}, {}
        for _, c in ipairs(it.cells) do sorted[#sorted + 1] = c end   -- copy: cell indices are run keys
        table.sort(sorted, function(a, b) return a.n > b.n end)
        for _, c in ipairs(sorted) do
            parts[#parts + 1] = ("%.1f,%.1f %d/%d"):format(c.x * 100, c.y * 100, c.n, m.visits or 0)
        end
        lines[#lines + 1] = ("%s: %s"):format(it.name or "?", table.concat(parts, "  "))
    end
    return lines
end

----------------------------------------------------------------------
-- Loot-time capture: some bags have NO minimap icon (no vignette), so the
-- scanner never sees them. When you OPEN one you're standing on it, and the
-- click is a player cast whose SENT target is the object's name. So: remember
-- the last targeted cast, and if a loot window opens within a few seconds,
-- record that object at your position. Corpse loot isn't a cast -> ignored.
----------------------------------------------------------------------
local function secret(v) return issecretvalue and issecretvalue(v) end
local lastCast   -- { name, guid, t, ok }

local function objectID(guid)
    if type(guid) ~= "string" or secret(guid) then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind == "GameObject" then return tonumber(id) end
end

-- The object's NAME: hovering a world object shows a tooltip with no unit; its first
-- line is the object's name. Remember it briefly -- you hover a bag right before
-- clicking it. (The SENT target is often empty for objects, verified 2026-10-18.)
local lastHover   -- { name, t }
GameTooltip:HookScript("OnShow", function(tt)
    if not inDelve() then return end
    if tt:GetUnit() then return end
    local line = _G["GameTooltipTextLeft1"]
    local txt = line and line:GetText()
    if txt and not secret(txt) and txt ~= "" then lastHover = { name = txt, t = GetTime() } end
end)

local lf = CreateFrame("Frame")
lf:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
lf:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
lf:RegisterEvent("LOOT_OPENED")
-- Object-opening casts ("Opening", "Loot", ...). A damage spell on a mob that then
-- dies and gets looted must NOT count, so the cast itself has to be an opening.
local function isOpening(spellID)
    if not spellID or secret(spellID) then return false end
    local n = C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
    if not n or secret(n) then return false end
    n = n:lower()
    return n:find("open", 1, true) or n:find("loot", 1, true) or n:find("search", 1, true)
end

lf:SetScript("OnEvent", function(_, e, a1, a2, a3, a4)
    if not inDelve() then return end
    if e == "UNIT_SPELLCAST_SENT" then
        local target, castGUID = a2, a3
        if target and not secret(target) and target ~= "" and isOpening(a4) then
            lastCast = { name = target, guid = castGUID, t = GetTime() }
        else
            lastCast = nil
        end
    elseif e == "UNIT_SPELLCAST_SUCCEEDED" then
        if lastCast and lastCast.guid == a2 then lastCast.ok = true; lastCast.t = GetTime() end
    elseif e == "LOOT_OPENED" then
        local c = lastCast
        lastCast = nil
        -- prefer the loot source's own GUID when the client lets us read it
        local oid
        if GetLootSourceInfo then
            local ok, guid = pcall(GetLootSourceInfo, 1)
            if ok and type(guid) == "string" and not secret(guid) then
                if guid:find("^Creature") or guid:find("^Vehicle") then return end   -- a corpse
                oid = objectID(guid)
            end
        end
        if not (c and c.ok and (GetTime() - c.t) <= 4) and not oid then return end
        local mapID = C_Map.GetBestMapForUnit("player")
        local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
        if not pos then return end
        local x, y = pos:GetXY()
        if not x or (x == 0 and y == 0) then return end
        local hovered = lastHover and (GetTime() - lastHover.t) <= 8 and lastHover.name
        local name = (c and c.name) or hovered or ("Object " .. oid)
        local key = oid and ("o" .. oid) or ("n:" .. name)
        S:Seen({ kind = "chest", name = name, spawnID = key }, mapID, x, y)
        -- upgrade an earlier nameless record once we learn the real name
        local m = DB()[mapID]
        local it = m and m.items[key]
        if it and hovered and (it.name or ""):find("^Object ") then it.name = hovered end
        if VS.Pins then VS.Pins:Refresh() end
    end
end)

-- Zoning in for real starts a new visit.
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
ev:RegisterEvent("ZONE_CHANGED")
ev:SetScript("OnEvent", function(_, e, isLogin, isReload)
    if e == "PLAYER_ENTERING_WORLD" and not isReload and inDelve() then S:NewRun() end
    if inDelve() then S:Visit(C_Map.GetBestMapForUnit("player")) end
end)
