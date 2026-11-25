----------------------------------------------------------------------
-- VoidSweep — CampNet: campfires on everyone's map (WoW Forever, 2026-11-24)
--
-- The user: "put fire symbols on the map but they go away after 10 min, it detects from these
-- people around them and updates others via voidnet and shows on the map". A small popup with
-- Go / Hop when a fire in your zone has a buff that's NEW for you.
--
-- REPORT. A VoidSweep player at a campfire (the game's "Campfire Nearby" aura, Camp.lua) reports
-- it: the zone, the spot, their layer and the camp objects they've seen there. Again when they see
-- a new object, and every RESEND seconds while they stay, unless another player reported the same
-- fire lately (one report keeps it alive for everyone).
--   CF:1:<id>,<hops>,<zone>,<x>,<y>,<layer|->,<object ids joined by .>,<reporter>
--   x / y 0..9999 on the zone's map; id = random, the same while it's passed on
-- SPREAD. VoidNet carries addon whispers, not broadcasts: a report goes to FANOUT Void players and
-- each passes a report it hasn't seen before on to RELAY more, up to MAX_HOPS times, so it reaches
-- nearly every Void player online within seconds while each one sends only a few whispers.
-- SHOW. A fire icon on the world map and the minimap, gone TTL (10 min) after the last report.
-- Hover: its objects judged for you (Camp.lua: NEW / have / no use), its layer, who reported it.
-- Click: the way there. A fire on another layer gets a Hop (VoidLayer's network, the reporter
-- asked first: they're standing on that layer).
--
-- UNTRUSTED like every VoidNet message: the zone must exist, the spot be on its map, every object
-- a known camp object; a sender is rate-limited, one reporter holds at most a few fires, a hostile
-- sender's messages never get here (VoidSync drops them). Nothing a report says triggers an action:
-- the popup only offers buttons.
----------------------------------------------------------------------
local ADDON, VS = ...
local N = {}
VS.CampNet = N
local CD = VS.CampData

local TTL         = 600    -- a fire leaves the map this long after its last report (the user: 10 min)
local RESEND      = 240    -- while you're at a fire it goes out again this often...
local QUIET       = 180    -- ...unless another player reported it within this long
local MIN_GAP     = 20     -- at most one report of yours per this many seconds (objects show up one by one)
local TICK        = 15
local FANOUT      = 8      -- players a new report goes to
local RELAY       = 3      -- players each of them passes it on to (once per report)
local MAX_HOPS    = 4      -- 2 left ~1 player in 13 out (test 11-24); every player passes a report on once anyway
local RELAY_PER_MIN = 20   -- reports one player passes on per minute, all reporters together (caps the load)
local SAME        = 0.015  -- two reports this close (share of the map), same zone and layer = one fire
local MAX_OBJS    = 12
local MAX_FIRES   = 200
local PER_REPORTER = 3     -- fires one reporter can have on the map at once
local SENDER_WINDOW, SENDER_MAX = 60, 12
local RELAY_WINDOW, RELAY_MAX = 600, 8   -- reports passed on per reporter per window
local NEAR_YARDS  = 60     -- this close to a fire: you're at it (no popup)
local SEEN_KEEP   = 900

N.TTL = TTL
N.FIRE_ICON = "Interface\\Icons\\Spell_Fire_Fire"

local A = { 0, 0.78, 1 }
local function forever() return RegionalUniqueNamesEnabled ~= nil and RegionalUniqueNamesEnabled() == true end
local function readable(v)
    if canaccessvalue then return canaccessvalue(v) end
    return not (issecretvalue and issecretvalue(v))
end
local function cfg() return VS:Config() end
-- on: fires are taken, shown and passed on (crowd sync); sharing: your own fire goes out too
local function on() return forever() and cfg().sync ~= false end
local function sharing() return on() and cfg().campNet ~= false end
local function now() return GetServerTime() end
local function me() return VS.WhisperNet and VS.WhisperNet.Me and VS.WhisperNet.Me() or UnitName("player") end

local function VoidPX()
    local s = UIParent and UIParent:GetEffectiveScale()
    if s and s > 0 and PixelUtil and PixelUtil.GetPixelToUIUnitFactor then return PixelUtil.GetPixelToUIUnitFactor() / s end
    return 1
end

-- fires: { zone, x, y, pair, objs = { [id] = t }, by = { [reporter] = t }, t = last report, first }
-- (server time; kept in VoidSweepDB so a /reload keeps the map)
local function fires()
    VoidSweepDB = VoidSweepDB or {}
    VoidSweepDB.campFires = VoidSweepDB.campFires or {}
    return VoidSweepDB.campFires
end

local function objOf(id) return CD and (CD.objects[id] or CD.creatures[id]) end
-- a campfire itself (Basic / Journeyman / Expert Campfire: benefit "campfire"). Only a SEEN campfire makes a fire worth
-- a map icon: the game's "Campfire Nearby" aura also comes from town hearths, braziers and inn fireplaces (the user,
-- 2026-11-25, inside an Everlook building: "it can only be a campfire, we have to find a way to detect it")
local function isFire(id) local o = CD and CD.objects[id]; return o ~= nil and o.benefit == "campfire" end
local function hasFire(list) for _, id in ipairs(list or {}) do if isFire(id) then return true end end return false end
local function hasFireKeys(set) for id in pairs(set or {}) do if isFire(id) then return true end end return false end

local function cleanName(s)
    if type(s) ~= "string" then return nil end
    local t = s:gsub("[%c|;,:]", "")
    t = t:gsub("^%s+", "")
    t = t:gsub("%s+$", "")
    if #t == 0 or #t > 48 then return nil end
    return t
end

----------------------------------------------------------------------
-- The fires
----------------------------------------------------------------------
local expired = false   -- a fire left since the map was last redrawn (the ticker redraws it; Sol review)
local function prune()
    local list, t = fires(), now()
    for i = #list, 1, -1 do
        local f = list[i]
        if type(f) ~= "table" or not f.t or t - f.t > TTL or t - f.t < -60 then
            table.remove(list, i)
            expired = true
        else
            for id, ot in pairs(f.objs or {}) do if t - ot > TTL then f.objs[id] = nil end end
            for who, bt in pairs(f.by or {}) do if t - bt > TTL then f.by[who] = nil end end
        end
    end
end

local function sameLayer(a, b) return not a or not b or a == b end

-- the fire a report belongs to: same zone and layer (or one not known), the nearest within SAME
local function find(zone, x, y, pair)
    local best, bestD
    for _, f in ipairs(fires()) do
        if f.zone == zone and sameLayer(f.pair, pair) then
            local d = (f.x - x) ^ 2 + (f.y - y) ^ 2
            if d <= SAME * SAME and (not bestD or d < bestD) then best, bestD = f, d end
        end
    end
    return best
end

local function holds(reporter)
    local n = 0
    for _, f in ipairs(fires()) do if f.by and f.by[reporter] then n = n + 1 end end
    return n
end

-- -> fire, created, { new object ids }  (nil when refused)
local function merge(zone, x, y, pair, ids, reporter, t)
    prune()
    local f = find(zone, x, y, pair)
    local created = false
    -- a reporter keeps at most PER_REPORTER fires on the map, new ones or ones they join (Sol review)
    if not (f and f.by[reporter]) and holds(reporter) >= PER_REPORTER then return nil end
    if not f then
        if #fires() >= MAX_FIRES then return nil end
        f = { zone = zone, x = x, y = y, pair = pair, objs = {}, by = {}, t = t, first = t }
        table.insert(fires(), f)
        created = true
    end
    local added = {}
    for _, id in ipairs(ids) do
        if not f.objs[id] then added[#added + 1] = id end
        f.objs[id] = t
    end
    if t > f.t then f.t = t end
    f.by[reporter] = t
    if pair and not f.pair then f.pair = pair end
    return f, created, added
end
N.Merge = merge   -- (tests)

-- the newest report of this fire by someone other than you
local function othersLast(f, self)
    local last
    for who, t in pairs(f.by or {}) do
        if who ~= self and (not last or t > last) then last = t end
    end
    return last
end

-- the reporter seen last (a Void player standing at it: the Hop asks them first)
local function lastReporter(f, self)
    local who, last
    for name, t in pairs(f.by or {}) do
        if name ~= self and (not last or t > last) then who, last = name, t end
    end
    return who
end

local function count(t) local n = 0; for _ in pairs(t or {}) do n = n + 1 end; return n end

----------------------------------------------------------------------
-- Where you are
----------------------------------------------------------------------
local function zoneOf(mapID)
    if VS.Layer and VS.Layer.Zone then return VS.Layer:Zone(mapID) end
    return mapID
end

local function zonePos()
    local best = C_Map.GetBestMapForUnit("player")
    if not best then return nil end
    local zone = zoneOf(best)
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, zone, "player")
    if not ok or not pos then return nil end
    local x, y = pos:GetXY()
    if not (x and y and readable(x) and readable(y)) or (x == 0 and y == 0) then return nil end
    return zone, x, y
end
N.ZonePos = zonePos

-- yards and a compass word from you to a fire (nil when you're not in its zone)
local DIRS = { "E", "NE", "N", "NW", "W", "SW", "S", "SE" }
function N:Distance(f)
    local zone, x, y = zonePos()
    if not zone or zone ~= f.zone then return nil end
    local w, h = C_Map.GetMapWorldSize(zone)
    if not (w and h and w > 0 and h > 0) then return nil end
    local dx, dy = (f.x - x) * w, (y - f.y) * h   -- east +, north +
    local yd = math.sqrt(dx * dx + dy * dy)
    local a = math.atan2(dy, dx) / math.pi * 180
    local i = math.floor(((a + 22.5) % 360) / 45) + 1
    return yd, DIRS[i]
end

-- "same" / "other" / nil (not known) for a fire's layer, from where you stand
function N:Layer(f)
    local L = VS.Layer
    if not (L and f.pair) then return nil end
    return L:Compare(f.pair, f.zone)
end

----------------------------------------------------------------------
-- Sending
----------------------------------------------------------------------
local seenIds = {}   -- [id] = time: reports already taken (not passed on twice)
local relayed = {}   -- [reporter] = { n, start }
local mine = nil     -- { f, sig, at }: your report of the fire you're at

local function encode(id, hops, zone, x, y, pair, ids, reporter)
    return ("CF:1:%d,%d,%d,%d,%d,%s,%s,%s"):format(id, hops, zone,
        math.floor(x * 10000 + 0.5), math.floor(y * 10000 + 0.5), pair or "-", table.concat(ids, "."), reporter)
end
N.Encode = encode

local function send(msg, to)
    if VS.Sync and VS.Sync.SendTo and to then VS.Sync.SendTo(msg, to, false) end
end

local function targets(k, skip)
    local list = VS.Sync and VS.Sync.Targets and VS.Sync.Targets(k + #skip) or nil
    if not list then return nil end
    local out = {}
    for _, name in ipairs(list) do
        local bad = false
        for _, s in ipairs(skip) do if s and name == s then bad = true end end
        if not bad and #out < k then out[#out + 1] = name end
    end
    return out
end

local function report(zone, x, y, pair, ids)
    local self = me()
    local id = math.random(100000, 999999)
    seenIds[id .. ":" .. self] = now()   -- ids are random per reporter: the pair is the report (Sol review)
    local trimmed = {}
    for i = 1, math.min(#ids, MAX_OBJS) do trimmed[i] = ids[i] end
    send(encode(id, 0, zone, x, y, pair, trimmed, self), targets(FANOUT, { self }))
end

-- every TICK: your own fire
function N:Tick()
    if not sharing() then mine = nil; return end
    local at, ids = false, {}
    if VS.Camp and VS.Camp.AtCamp then at, ids = VS.Camp:AtCamp() end
    -- the aura alone isn't a camp: a town fire gives it too. A known camp object seen here (the campfire itself, a
    -- tent, a bedroll, a bot) is not enough: the campfire itself has to have been seen (2026-11-25, an inn fireplace in Everlook)
    if not at or not hasFire(ids) then mine = nil; return end
    local zone, x, y = zonePos()
    if not zone then return end
    local pair = VS.Layer and VS.Layer.Here and (VS.Layer:Here())
    local self, t = me(), now()
    local f = merge(zone, x, y, pair, ids, self, t)
    if not f then return end
    local sig = table.concat(ids, ".")
    if mine and mine.f == f then
        if t - mine.at < MIN_GAP then return end
        if mine.sig == sig then
            if t - mine.at < RESEND then return end
            local other = othersLast(f, self)
            -- another player keeps it on the map: wait (a little jitter, so two sitters don't take turns in step)
            if other and t - other < QUIET then mine.at = t - math.random(0, 30); return end
        end
    end
    mine = { f = f, sig = sig, at = t }
    report(zone, x, y, pair, ids)
    N:Changed()
end

----------------------------------------------------------------------
-- Receiving
----------------------------------------------------------------------
local bucket, newBy = {}, {}
local NEW_WINDOW, NEW_PER_SENDER = 600, 10
local function rateOK(t, key, window, max)
    local b = t[key]
    local n = GetTime()
    if not b or n - b.start > window then t[key] = { n = 1, start = n }; return true end
    b.n = b.n + 1
    return b.n <= max
end

-- body = everything after "CF:1:"; sender = who whispered it (the game's name)
function N:OnShared(body, sender)
    if not on() or type(body) ~= "string" or #body > 250 then return end
    local id, hops, zone, xs, ys, pair, objs, reporter =
        body:match("^(%d+),(%d),(%d+),(%d+),(%d+),([%d%-]+),([%d%.]*),(.+)$")
    id, hops, zone = tonumber(id), tonumber(hops), tonumber(zone)
    local x, y = tonumber(xs), tonumber(ys)
    reporter = cleanName(reporter)
    if not (id and hops and zone and x and y and reporter) then return end
    if hops > MAX_HOPS or x <= 0 or x >= 10000 or y <= 0 or y >= 10000 then return end
    -- first hand (hops 0) must come from the reporter themselves: the game names a whisper's sender
    if hops == 0 and sender ~= reporter then return end
    if not rateOK(bucket, sender, SENDER_WINDOW, SENDER_MAX) then return end
    local key = id .. ":" .. reporter
    if seenIds[key] then return end
    -- a zone's own map: not a continent (Zone() leaves those as they are), a cave or a city floor
    local mi = C_Map.GetMapInfo(zone)
    local ZONE = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
    if not (mi and mi.mapType == ZONE) or zoneOf(zone) ~= zone then return end
    if pair == "-" then pair = nil elseif not pair:match("^%d+%-%d+$") then return end
    local ids = {}
    for tok in objs:gmatch("[^%.]+") do
        local oid = tonumber(tok)
        if not (oid and objOf(oid)) or #ids >= MAX_OBJS then return end   -- one unknown object: the whole report goes
        ids[#ids + 1] = oid
    end
    -- no camp object at all: a town hearth, a brazier, an inn fireplace (the game's "Campfire Nearby" aura comes
    -- from those too; the user, 2026-11-25, inside an Everlook building: "it shows a campfire on the map, but im
    -- inside a building"). Only a player's camp is worth a map icon. Older VoidSweeps still send these.
    if not hasFire(ids) then return end
    seenIds[key] = now()
    if reporter == me() then return end   -- your own report, back by a relay
    local existing = find(zone, x / 10000, y / 10000, pair)
    -- the names in passed-on reports aren't proof (anyone can write one): each sender, whom the game does
    -- name, brings at most NEW_PER_SENDER fires we didn't have per window, whatever reporters they name (Sol review)
    if not existing and not rateOK(newBy, sender, NEW_WINDOW, NEW_PER_SENDER) then return end
    local f, created, added = merge(zone, x / 10000, y / 10000, pair, ids, reporter, now())
    if not f then return end
    -- pass it on (a report seen for the first time; a reporter can't make the network carry more than a few)
    if hops < MAX_HOPS and rateOK(relayed, reporter, RELAY_WINDOW, RELAY_MAX) and rateOK(relayed, "", 60, RELAY_PER_MIN) then
        send(encode(id, hops + 1, zone, x / 10000, y / 10000, pair, ids, reporter), targets(RELAY, { me(), sender, reporter }))
    end
    if created or #added > 0 then N:Changed() end
end

----------------------------------------------------------------------
-- For the map (Pins.lua / Minimap.lua) and the tooltip
----------------------------------------------------------------------
-- { { entry, x, y } } for this map: fires in this zone, still fresh
function N:Candidates(mapID)
    local out = {}
    if not on() or cfg().show.camp == false then return out end   -- crowd sync off: no shared fires at all
    prune()
    for _, f in ipairs(fires()) do
        -- a fire stored without a seen campfire (an inn fireplace, from before 2026-11-25) isn't shown
        if f.zone == mapID and hasFireKeys(f.objs) then
            out[#out + 1] = { x = f.x, y = f.y, entry = { name = "Campfire", kind = "camp", campfire = f,
                x = f.x, y = f.y, otherLayer = N:Layer(f) == "other" } }
        end
    end
    return out
end

function N:Count(mapID) return #N:Candidates(mapID) end

-- each object at the fire, judged for you, NEW first: { name, st, txt }
function N:Rows(f)
    local rows, byBenefit, fire = {}, {}, nil
    for id in pairs(f.objs or {}) do
        local o = objOf(id)
        if o and o.benefit == "campfire" then
            fire = o
        elseif o and not byBenefit[o.benefit or id] then
            byBenefit[o.benefit or id] = true
            local st, txt = "info", o.name
            if VS.Camp and VS.Camp.Judge then st, txt = VS.Camp:Judge(o) end
            rows[#rows + 1] = { name = o.name, st = st, txt = txt, id = id }
        end
    end
    local ORDER = VS.Camp and VS.Camp.ORDER or {}
    table.sort(rows, function(a, b)
        local oa, ob = ORDER[a.st] or 9, ORDER[b.st] or 9
        if oa ~= ob then return oa < ob end
        return a.name < b.name
    end)
    return rows, fire
end

local function ago(s)
    s = math.max(0, s)
    if s < 60 then return "just now" end
    return ("%d min ago"):format(math.floor(s / 60))
end

function N:LayerText(f)
    local m = N:Layer(f)
    if m == "same" then return "|cff33ff33On your layer|r" end
    if m == "other" then
        local label = VS.LayerNet and VS.LayerNet.Label and VS.LayerNet:Label(f.zone, f.pair) or f.pair
        return "|cffff9933On another layer (" .. tostring(label) .. "): Hop to get there|r"
    end
    if f.pair then return "|cff8c8c9eLayer not known yet (may be yours)|r" end
    return nil
end

function N:TooltipLines(f, add)
    local rows, fire = N:Rows(f)
    local COLORS, WORD = VS.Camp and VS.Camp.COLORS or {}, VS.Camp and VS.Camp.WORD or {}
    if fire then add(fire.name, 1, 0.6, 0.2) end
    for _, r in ipairs(rows) do
        add(("%s  %s%s|r  %s%s|r"):format(r.name, COLORS[r.st] or "", r.txt or "", COLORS[r.st] or "", WORD[r.st] or ""), 1, 1, 1)
    end
    if #rows == 0 then add("Objects not seen yet: only the fire is known", 0.6, 0.6, 0.6) end
    local lt = N:LayerText(f)
    if lt then add(lt) end
    local n, t = count(f.by), now()
    add(("Reported by %d Void player%s · %s"):format(n, n == 1 and "" or "s", ago(t - f.t)), 0.45, 0.75, 1)
    add(("Leaves the map %d min after the last report"):format(math.ceil((TTL - (t - f.t)) / 60)), 0.6, 0.6, 0.6)
end

----------------------------------------------------------------------
-- The popup: a fire in your zone with a buff that's NEW for you
----------------------------------------------------------------------
local pop       -- the box
local popFire   -- the fire it shows (fire.alerted = { [object id] = true }: NEW buffs already announced)

local function db() VoidSweepDB = VoidSweepDB or {}; return VoidSweepDB end

local function button(parent, label, onClick, tip)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(40, 16)
    b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = VoidPX() })
    b:SetBackdropColor(0.10, 0.12, 0.15, 1)
    b:SetBackdropBorderColor(A[1], A[2], A[3], 0.6)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("CENTER")
    b.text:SetText(label)
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(A[1], A[2], A[3], 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(tip[1])
        if tip[2] then GameTooltip:AddLine(tip[2], 0.8, 0.8, 0.8, true) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(A[1], A[2], A[3], 0.6)
        GameTooltip:Hide()
    end)
    return b
end

function N:Go(f)
    f = f or popFire
    if not f then return end
    if VS.Nav and VS.Nav.Goto then VS.Nav:Goto(f.zone, { x = f.x, y = f.y }, "Campfire") end
end

function N:Hop(f)
    f = f or popFire
    if not (f and f.pair and VS.Hop and VS.Hop.Start) then return end
    local who = lastReporter(f, me())
    -- ask the reporter first only if they're a Void player on the network now (a name in a report is not proof)
    if who and not (VS.Sync and VS.Sync.IsPeer and VS.Sync.IsPeer(who)) then who = nil end
    VS.Hop:Start(f.pair, f.zone, who)
end

local function buildPop()
    local f = CreateFrame("Frame", "VoidSweepFireAlert", UIParent, "BackdropTemplate")
    f:SetSize(240, 60)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = VoidPX() })
    f:SetBackdropColor(0.04, 0.04, 0.07, 0.9)
    f:SetBackdropBorderColor(1, 0.55, 0.1, 0.8)
    local p = db().firePopPos
    if p then f:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else f:SetPoint("TOP", UIParent, "TOP", 0, -190) end
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local pt, _, rel, x, y = self:GetPoint()
        db().firePopPos = { pt, rel, x, y }
    end)
    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("A campfire other Void players reported")
        GameTooltip:AddLine("It shows because it has a buff that's NEW for you. Every reported fire is on your map (fire icon) until 10 minutes after the last report.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Drag to move · the map's VoidSweep button turns these off", 0.4, 0.8, 1, true)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(16, 16)
    f.icon:SetPoint("TOPLEFT", 6, -5)
    f.icon:SetTexture(N.FIRE_ICON)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("LEFT", f.icon, "RIGHT", 4, 0)
    f.title:SetJustifyH("LEFT")
    local close = CreateFrame("Button", nil, f)
    close:SetSize(16, 16)
    close:SetPoint("TOPRIGHT", -4, -5)
    close.text = close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    close.text:SetPoint("CENTER", 0, 1)
    close.text:SetText("|cff8c8c9ex|r")
    close:SetScript("OnClick", function() f:Hide(); popFire = nil end)
    close:SetScript("OnEnter", function(self) self.text:SetText("|cffff5555x|r") end)
    close:SetScript("OnLeave", function(self) self.text:SetText("|cff8c8c9ex|r") end)
    f.close = close
    f.go = button(f, "Go", function() N:Go() end, { "The way there", "Puts the arrow on the fire." })
    f.go:SetPoint("TOPRIGHT", close, "TOPLEFT", -4, 0)
    f.hop = button(f, "Hop", function() N:Hop() end,
        { "Hop to its layer", "Joins a Void player on that layer for a moment (VoidLayer's network), the player who reported the fire first. If you turn out to be on that layer already, nothing changes." })
    f.hop:SetPoint("TOPRIGHT", f.go, "TOPLEFT", -4, 0)
    f.lines = {}
    f:Hide()
    f.elapsed = 0
    f:SetScript("OnUpdate", function(self, dt)
        self.elapsed = self.elapsed + dt
        if self.elapsed >= 1 then self.elapsed = 0; N:RenderPop() end
    end)
    return f
end

function N:RenderPop()
    if not (pop and pop:IsShown()) then return end
    local f = popFire
    local alive = false
    for _, g in ipairs(fires()) do if g == f then alive = true end end
    -- switched off since it showed (crowd sync or the popup): it goes (Sol review)
    if not (f and alive and now() - f.t <= TTL) or not on() or cfg().campAlert == false then pop:Hide(); popFire = nil; return end
    local yd, dir = N:Distance(f)
    if not yd then pop:Hide(); popFire = nil; return end      -- left its zone
    local m = N:Layer(f)
    -- you're there: Camp.lua's box takes over. Not for a fire on another layer: that one needs the Hop (Sol review)
    if yd <= NEAR_YARDS and m ~= "other" then pop:Hide(); popFire = nil; return end
    pop.title:SetText(("|cffff9933Campfire|r %d yd %s"):format(math.floor(yd + 0.5), dir))
    pop.hop:SetShown(f.pair ~= nil and m ~= "same" and VS.Hop ~= nil)
    local i, width = 0, pop.title:GetStringWidth() + 26 + 20 + 44 + (pop.hop:IsShown() and 44 or 0)
    local function line(text)
        i = i + 1
        local l = pop.lines[i]
        if not l then l = pop:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); pop.lines[i] = l end
        l:ClearAllPoints(); l:SetPoint("TOPLEFT", 8, -10 - i * 14)
        l:SetText(text); l:Show()
        width = math.max(width, l:GetStringWidth() + 20)
    end
    local rows = N:Rows(f)
    local COLORS, WORD = VS.Camp.COLORS, VS.Camp.WORD
    for _, r in ipairs(rows) do
        line(("%s  %s%s|r  %s%s|r"):format(r.name, COLORS[r.st] or "", r.txt or "", COLORS[r.st] or "", WORD[r.st] or ""))
    end
    local lt = N:LayerText(f)
    if lt then line(lt) end
    local n = count(f.by)
    line(("|cff8c8c9eReported by %d Void player%s · %s|r"):format(n, n == 1 and "" or "s", ago(now() - f.t)))
    for j = i + 1, #pop.lines do pop.lines[j]:Hide() end
    pop:SetSize(math.max(220, width), 16 + (i + 1) * 14)
end

-- the popup's rule (the user picked it): a fire in your zone, not the one you're at, with a buff
-- that's NEW for you that wasn't announced for it yet
function N:Check()
    if not on() or cfg().campAlert == false or InCombatLockdown() then return end
    local zone = zonePos()
    if not zone then return end
    for _, f in ipairs(fires()) do
        if f.zone == zone and not (mine and mine.f == f) then
            local yd = N:Distance(f)
            if yd and (yd > NEAR_YARDS or N:Layer(f) == "other") then
                local fresh = {}
                local done = f.alerted or {}   -- kept with the fire: a /reload doesn't announce it again
                for _, r in ipairs((N:Rows(f))) do
                    if r.st == "new" and not done[r.id] then fresh[#fresh + 1] = r.id end
                end
                if #fresh > 0 then
                    for _, id in ipairs(fresh) do done[id] = true end
                    f.alerted = done
                    popFire = f
                    pop = pop or buildPop()
                    pop:Show()
                    N:RenderPop()
                    if PlaySound and SOUNDKIT and SOUNDKIT.UI_MAP_WAYPOINT_SUPER_TRACK_ON then
                        pcall(PlaySound, SOUNDKIT.UI_MAP_WAYPOINT_SUPER_TRACK_ON)
                    end
                    return
                end
            end
        end
    end
end

-- something new on the map: redraw and maybe pop up
local changePending
function N:Changed()
    if changePending then return end
    changePending = true
    C_Timer.After(0.5, function()
        changePending = false
        if VS.Pins and VS.Pins.Refresh then VS.Pins:Refresh() end
        N:Check()
    end)
end

function N:IsPopShown() return pop ~= nil and pop:IsShown() end
function N:PopFire() return popFire end

----------------------------------------------------------------------
-- Start
----------------------------------------------------------------------
function N:Init()
    if not forever() then return end
    prune()
    local t = 0
    C_Timer.NewTicker(TICK, function()
        N:Tick()
        N:Check()
        -- each minute: fires past their 10 minutes leave the open map; old report ids are forgotten
        t = t + TICK
        if t >= 60 then
            t = 0
            local n = now()
            for id, s in pairs(seenIds) do if n - s > SEEN_KEEP then seenIds[id] = nil end end
            local g = GetTime()
            for k, b in pairs(relayed) do if g - b.start > RELAY_WINDOW then relayed[k] = nil end end
            for k, b in pairs(bucket) do if g - b.start > SENDER_WINDOW then bucket[k] = nil end end
            for k, b in pairs(newBy) do if g - b.start > NEW_WINDOW then newBy[k] = nil end end
            prune()
            -- anything that expired since the last redraw (here, or in a merge / the map's own read)
            if expired and VS.Pins and VS.Pins.Refresh then expired = false; VS.Pins:Refresh() end
        end
    end)
end
