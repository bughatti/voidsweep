----------------------------------------------------------------------
-- VoidSweep — Learned location store
--
-- The fix for "chests only show when I fly close": vignettes are range-
-- limited, so the first time we DO see one we remember where it was
-- (SavedVariables). After that its pin persists on the map — dimmed —
-- even when we're far away or it's not currently up. Live sightings
-- (Scanner) override the remembered pin with a bright, HP-bearing one.
--
-- Seed.lua (the starter map, built from VoidSweep's own in-game captures)
-- merges with this store so a fresh user doesn't start with a blank map.
----------------------------------------------------------------------
local ADDON, VS = ...

VS.Learned = {}
local L = VS.Learned

-- Bump when the classifier changes so old, wrongly-tagged rows (e.g. vendors
-- saved as "rare" before the atlas-based classifier) get wiped and re-learned.
local LEARNED_VER = 2

local function DB()
    VoidSweepDB = VoidSweepDB or {}
    VoidSweepDB.learned = VoidSweepDB.learned or {}
    return VoidSweepDB.learned
end

-- Called once at login: purge the learned store if it predates the current
-- classifier version. Cheap to rebuild (just fly around), so a clean wipe
-- beats trying to re-validate rows we didn't store enough fields for.
local KINDS = { rare = true, worldboss = true, chest = true, lore = true }

function L:Migrate()
    VoidSweepDB = VoidSweepDB or {}
    if VoidSweepDB.learnedVer ~= LEARNED_VER then
        VoidSweepDB.learned = {}
        VoidSweepDB.learnedVer = LEARNED_VER
    end
    -- Older builds tagged some treasures mount/pet/decor/profession; the
    -- classifier only knows these four kinds now, so fold the rest into chest.
    for _, byKey in pairs(VoidSweepDB.learned) do
        for _, rec in pairs(byKey) do
            if not KINDS[rec.kind] then rec.kind = "chest" end
        end
    end
end

----------------------------------------------------------------------
-- Proximity-clear: many chests/lore carry NO quest/criteria, so the game
-- can't tell us they're done. But if you're standing on a known one-time
-- collectible and it has no live vignette, you looted it — mark it cleared.
----------------------------------------------------------------------
local CLEAR_YARDS = 22

-- PER-CHARACTER: whether YOU looted a completion-less chest is your own
-- business, not the whole account's. (Quest/criteria completion is already
-- per-char via the game; only these manual proximity-clears need scoping.)
local function ClearedDB()
    VoidSweepCharDB = VoidSweepCharDB or {}
    VoidSweepCharDB.cleared = VoidSweepCharDB.cleared or {}
    return VoidSweepCharDB.cleared
end

function L:IsCleared(mapID, key)
    local c = ClearedDB()[mapID]
    return c and c[key] or false
end

function L:MarkCleared(mapID, key)
    local c = ClearedDB()
    c[mapID] = c[mapID] or {}
    c[mapID][key] = true
end

-- liveVIDs = set of currently-live vignetteIDs, so we never clear something
-- that's actually up right now.
function L:ClearNearby(mapID, px, py, liveVIDs)
    local n = 0
    local w, h = C_Map.GetMapWorldSize(mapID)
    for key, rec in pairs(self:GetKnownForMap(mapID)) do
        -- Only records the game CAN'T track: anything with a completion quest or
        -- achievement criteria is handled by IsDone, and clearing those by
        -- proximity wiped chests you merely flew past before their vignette
        -- loaded (the "pins vanish while flying" bug).
        if (rec.kind == "chest" or rec.kind == "lore")
           and not rec.questID and not rec.criteria
           and rec.x and rec.y
           and not (rec.vignetteID and liveVIDs[rec.vignetteID])
           and not self:IsCleared(mapID, key) then
            local close
            if w and h and w > 0 and h > 0 then
                local dx, dy = (rec.x - px) * w, (rec.y - py) * h
                close = (dx * dx + dy * dy) <= (CLEAR_YARDS * CLEAR_YARDS)
            else
                local dx, dy = rec.x - px, rec.y - py
                close = (dx * dx + dy * dy) <= (0.012 * 0.012)
            end
            if close then self:MarkCleared(mapID, key); n = n + 1 end
        end
    end
    return n
end

-- Stable identity so re-sightings update in place rather than duplicate.
local function keyFor(entry)
    if entry.vignetteID then return "v" .. entry.vignetteID end
    return "n" .. (entry.name or "?")
end
L.keyFor = keyFor

----------------------------------------------------------------------
-- Shared spots: locations OTHER players' VoidSweep learned, received over
-- VoidSweepNet (VoidSync.lua). Kept apart from your own learned store:
-- VoidSweepDB.shared[mapID][key] = {kind,name,x,y,vignetteID,questID,
-- c (distinct reporters, stops at 5), f (first reporter), by (set), t}.
-- Drawn faded until a second player confirms; replaced by your own record
-- the moment you see it yourself.
----------------------------------------------------------------------
local SHARED_CAP = 1500   -- per map
local CONFIRMED  = 5

local function SharedDB()
    VoidSweepDB = VoidSweepDB or {}
    VoidSweepDB.shared = VoidSweepDB.shared or {}
    return VoidSweepDB.shared
end

function L:GetSharedForMap(mapID) return SharedDB()[mapID] end

-- Returns true if anything changed.
function L:AddShared(mapID, rec, sender)
    local key = keyFor(rec)
    local mine = DB()[mapID]
    if mine and mine[key] then return false end                 -- you know it
    local seed = VS.Seed and VS.Seed[mapID]
    if seed and seed[key] then return false end                 -- everyone has it
    local db = SharedDB()
    db[mapID] = db[mapID] or {}
    local s = db[mapID][key]
    if s then
        if s.c >= CONFIRMED or s.by[sender] then return false end
        s.by[sender] = true
        s.c = s.c + 1
        s.t = time()
        return true
    end
    local n = 0
    for _ in pairs(db[mapID]) do n = n + 1 end
    if n >= SHARED_CAP then return false end
    rec.c, rec.f, rec.by, rec.t = 1, sender, { [sender] = true }, time()
    db[mapID][key] = rec
    return true
end

-- Record a sighting at map-relative (x, y) on mapID.
function L:Record(entry, mapID, x, y)
    if not (mapID and x and y and entry) then return end
    -- Events are transient zone happenings, not fixed spawns — don't
    -- persist them or the map fills with stale one-offs.
    if entry.kind == "event" then return end

    local db = DB()
    db[mapID] = db[mapID] or {}
    local key = keyFor(entry)
    local isNew = db[mapID][key] == nil
    local rec = {
        vignetteID = entry.vignetteID,
        name       = entry.name,
        atlasName  = entry.atlasName,
        kind       = entry.kind,
        questID    = entry.questID,
        x          = x,
        y          = y,
    }
    db[mapID][key] = rec
    -- seen it yourself now: the shared copy is redundant
    local shared = SharedDB()[mapID]
    if shared then shared[key] = nil end
    -- a spot nobody ships in the starter map -> tell other players
    if isNew and VS.Sync and not (VS.Seed and VS.Seed[mapID] and VS.Seed[mapID][key]) then
        VS.Sync:ShareSpot(mapID, rec)
    end
end

-- All remembered records for a map (keyed table), or nil.
function L:GetForMap(mapID)
    return DB()[mapID]
end

-- Seed (shipped starter map) + learned (SavedVars, observed) merged into one
-- keyed table. Learned wins on key collision — your own sighting is fresher.
function L:GetKnownForMap(mapID)
    local merged = {}
    local seed = VS.Seed and VS.Seed[mapID]
    if seed then
        for k, v in pairs(seed) do
            local c = {}
            for kk, vv in pairs(v) do c[kk] = vv end
            merged[k] = c
        end
    end
    local learned = DB()[mapID]
    if learned then
        for k, lv in pairs(learned) do
            local base = merged[k]
            if base then
                -- learned wins on live-captured fields, but KEEP the seed's
                -- completion refs (criteria/achievement/questID) so a pin can
                -- still be marked done after we've seen it live.
                base.x, base.y     = lv.x, lv.y
                base.name          = lv.name or base.name
                base.kind          = lv.kind or base.kind
                base.vignetteID    = lv.vignetteID or base.vignetteID
                base.atlasName     = lv.atlasName or base.atlasName
                base.questID       = lv.questID or base.questID
            else
                merged[k] = lv
            end
        end
    end
    -- other players' spots, only where we have nothing of our own
    local shared = SharedDB()[mapID]
    if shared then
        for k, sv in pairs(shared) do
            if not merged[k] then
                local c = {}
                for kk, vv in pairs(sv) do c[kk] = vv end
                c.shared = true
                merged[k] = c
            end
        end
    end
    return merged
end

function L:Count()
    local n = 0
    for _, byMap in pairs(DB()) do
        for _ in pairs(byMap) do n = n + 1 end
    end
    return n
end

function L:Clear()
    VoidSweepDB.learned = {}
    VoidSweepDB.shared = {}
    VoidSweepCharDB = VoidSweepCharDB or {}
    VoidSweepCharDB.cleared = {}   -- this character's proximity-clears only
end
