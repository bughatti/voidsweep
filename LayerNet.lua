----------------------------------------------------------------------
-- VoidSweep — LayerNet: which layers other VoidSweep players are on (WoW Forever)
--
-- On demand only, never a steady chatter:
--   LQ:1:zone        "which layer are you on in this zone?" -> up to ASK_PEERS members
--   LA:1:zone:pair   the answer, only from players standing in that zone with a known
--                    layer (everyone else stays silent)
-- A zone is asked about at most once every ASK_CD seconds: by /vsw layers, or when a
-- rare sighting from another layer comes in (so we know if a Void player is there).
-- Answers are counted per layer for LIVE seconds; the players' names stay in memory only
-- (step 4, the hop, needs a host) and are never shown or saved.
-- Only members of our sharing channel get an answer, and each player at most once a
-- minute; an answer is checked (real zone, a well-formed pair) before it counts.
-- Older VoidSweep versions don't know LQ / LA and ignore them.
----------------------------------------------------------------------
local ADDON, VS = ...
VS.LayerNet = {}
local LN = VS.LayerNet

local PROTO     = "1"
local ASK_PEERS = 10
local ASK_CD    = 300     -- ask about the same zone at most this often
local LIVE      = 600     -- an answer counts this long
local REPLY_GAP = 60      -- answer the same player at most this often
local WAIT      = 5       -- /vsw layers prints after this

local census = {}         -- [zone] = { [name] = { pair, t } }
local lastAsk = {}        -- [zone] = GetTime()
local lastReplyTo = {}    -- [name] = GetTime()
local asked = {}          -- [zone] = { [name] = GetTime() }: only these may answer (Codex)
local ANSWER_WINDOW = 60

local function forever() return RegionalUniqueNamesEnabled ~= nil and RegionalUniqueNamesEnabled() == true end
local function validPair(p) return type(p) == "string" and #p <= 20 and p:match("^%d+%-%d+$") ~= nil end

-- Ask the network about a zone: at most once every ASK_CD, /vsw layers included (Codex).
-- True if a question went out.
function LN:Ask(zone)
    if not (forever() and zone and VS.Sync and VS.Sync.Targets) then return false end
    if lastAsk[zone] and GetTime() - lastAsk[zone] < ASK_CD then return false end
    lastAsk[zone] = GetTime()
    local to = VS.Sync.Targets(ASK_PEERS)
    if not to or #to == 0 then return false end
    local a = {}
    for _, name in ipairs(to) do a[name] = GetTime() end
    asked[zone] = a
    VS.Sync.SendTo(("LQ:%s:%d"):format(PROTO, zone), to, true)
    return true
end

-- Seconds until this zone may be asked about again (0 = now). For the Layers window.
function LN:AskLeft(zone)
    local t = zone and lastAsk[zone]
    local l = t and (ASK_CD - (GetTime() - t)) or 0
    return l > 0 and l or 0
end

-- { [pair] = count } of other Void players in this zone (answers within LIVE).
function LN:Counts(zone)
    local out, now = {}, GetTime()
    for _, a in pairs(census[zone] or {}) do
        if now - a.t <= LIVE then out[a.pair] = (out[a.pair] or 0) + 1 end
    end
    return out
end

-- Names of Void players on a layer in a zone who host hops (Hop.lua). Never shown.
-- Fresher than LIVE: a host's answer is only good for HOST_LIVE (they may have moved on).
local HOST_LIVE = 300
function LN:Hosts(zone, pair)
    local out, now = {}, GetTime()
    for name, a in pairs(census[zone] or {}) do
        if a.pair == pair and a.host and now - a.t <= HOST_LIVE then out[#out + 1] = name end
    end
    return out
end

-- Messages. Returns true if it was one of ours.
function LN:OnMessage(msg, who, replyTo)
    local tag, proto, zoneS, pair = msg:match("^(L[QAH]):(%d+):(%d+):?(.*)$")
    if not tag then return false end
    if proto ~= PROTO or not forever() then return true end
    local zone = tonumber(zoneS)
    if not (zone and zone > 0 and C_Map.GetMapInfo(zone)) then return true end
    local L = VS.Layer
    if tag == "LQ" then
        if pair ~= "" or not L then return true end
        if VS.Sync.IsPeer and not VS.Sync.IsPeer(who) then return true end   -- members only
        if lastReplyTo[who] and GetTime() - lastReplyTo[who] < REPLY_GAP then return true end
        if IsInInstance() then return true end
        local mine, here = L:Here()
        if not mine or here ~= zone then return true end                      -- not there: stay silent
        lastReplyTo[who] = GetTime()
        VS.Sync.SendTo(("LA:%s:%d:%s"):format(PROTO, zone, mine), { replyTo or who }, true)
        -- I host layer hops right now (Hop.lua): a separate LH after the LA (not urgent, so it
        -- queues behind it). A ":h" on the LA itself made 0.2.20 drop the whole answer (Codex).
        if VS.Hop and VS.Hop:CanHost() then
            VS.Sync.SendTo(("LH:%s:%d:%s"):format(PROTO, zone, mine), { replyTo or who }, false)
        end
    elseif tag == "LH" then   -- "and I host": only right after that player's LA, same layer
        local a = census[zone] and census[zone][who]
        if a and a.pair == pair and GetTime() - a.t <= ANSWER_WINDOW then a.host = true end
    else   -- LA: only from a player we just asked about this zone (Codex: anyone could
           -- whisper made-up answers and keep them fresh)
        local t = asked[zone] and asked[zone][who]
        if not t or GetTime() - t > ANSWER_WINDOW then return true end
        asked[zone][who] = nil   -- one answer per question
        if not validPair(pair) then return true end
        local z = census[zone] or {}
        census[zone] = z
        z[who] = { pair = pair, t = GetTime() }
    end
    return true
end

-- One line for chat / tooltips: "6833-20 (you) · 6833-21: 2 Void players".
function LN:Summary(zone)
    local mine = VS.Layer and VS.Layer:Current(zone)
    local counts = self:Counts(zone)
    local parts = {}
    if mine then
        local n = counts[mine] or 0
        parts[#parts + 1] = ("|cffffd200%s|r (you%s)"):format(mine, n > 0 and (" + " .. n .. " Void player" .. (n == 1 and "" or "s")) or "")
    end
    local others = {}
    for pair, n in pairs(counts) do if pair ~= mine then others[#others + 1] = { pair, n } end end
    table.sort(others, function(a, b) return a[2] > b[2] end)
    for _, o in ipairs(others) do
        local hop = #self:Hosts(zone, o[1]) > 0 and (" |cff33ff33(/vsw hop " .. o[1] .. ")|r") or ""
        parts[#parts + 1] = ("%s: %d Void player%s%s"):format(o[1], o[2], o[2] == 1 and "" or "s", hop)
    end
    return #parts > 0 and table.concat(parts, " · ") or nil
end

-- /vsw layers
function LN:Report()
    if not forever() then
        print("|cff00c7ffVoidSweep|r: layers are a WoW Forever thing; nothing to show here.")
        return
    end
    local L = VS.Layer
    local mine, zone = L:Here()
    local info = zone and C_Map.GetMapInfo(zone)
    local zname = info and info.name or "this zone"
    if not zone then print("|cff00c7ffVoidSweep|r: no zone here (instances have no layers to compare).") return end
    local sent = self:Ask(zone)
    local function show()
        local s = self:Summary(zone)
        if s then
            print(("|cff00c7ffVoidSweep|r: layers in %s: %s"):format(zname, s))
        else
            print(("|cff00c7ffVoidSweep|r: no layers known in %s yet. Point at any NPC for yours; other Void players' layers show once they answer."):format(zname))
        end
        if not mine then print("|cff00c7ffVoidSweep|r: your own layer isn't known yet: point at or target any NPC.") end
    end
    if sent then
        print(("|cff00c7ffVoidSweep|r: asking other VoidSweep players in %s..."):format(zname))
        C_Timer.After(WAIT, show)
    else
        show()
    end
end
