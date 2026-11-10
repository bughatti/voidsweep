----------------------------------------------------------------------
-- VoidSweep — VoidSync (crowd rare-up channel)
--
-- Addon messages (prefix + SendAddonMessage + CHAT_MSG_ADDON) over a hidden
-- custom channel every VoidSweep client joins (VoidSweepNet, realm-cluster
-- wide), so sightings reach strangers with no group/guild. The stock
-- General/LookingForGroup channels reject addon messages in 12.x.
--
-- SECURITY MODEL: the channel is public and the prefix ships in our code,
-- so EVERY inbound message is treated as hostile.
--   * additive + ephemeral only: a message can add a temporary "reported"
--     pin and nothing else -- never writes the learned DB, never marks
--     completion, never triggers an action, never loadstring's a payload.
--   * validated against our own seed (ground truth of real vignetteIDs +
--     spawn coords); coords far from the known spawn = forged, dropped.
--   * world-boss claims cross-checked against the game (AreaPOI).
--   * rate-limited per sender, quorum for unknown IDs, short TTL, and it
--     self-corrects the moment your own scan reaches the spot.
-- No HMAC/signing: any secret would ship in the client, so crypto is
-- theater. Validation + quorum + self-correction is the real defense.
--
-- WoW FOREVER (live 2026-11-05) refuses addon messages in custom channels,
-- so there VoidSweepNet is only a member list (WhisperNet.lua) and the same
-- messages go by addon whisper to the bare "First Surname" name: UP and N
-- to up to FANOUT random members, Q to up to ASK_PEERS, and each of them
-- whispers its B straight back to the asker (one answer per player per
-- REPLY_GAP). "Who's here" can't be counted by zone there: the box shows how
-- many VoidSweep players are online (the channel's member count) and no P/H/L
-- goes out. /vsw synctest whispers a PING to yourself.
----------------------------------------------------------------------
local ADDON, VS = ...
VS.Sync = {}
local Sync = VS.Sync

local PREFIX         = "VSWEEP"
local PROTO          = "1"
local REPORT_TTL     = 180    -- seconds a report stays live (rares are short)
local REBROADCAST_CD = 45     -- don't resend the same vignette within this
local SENDER_WINDOW  = 60     -- rate-limit window (s)
local SENDER_MAX     = 15     -- max accepted msgs per sender per window
local COORD_TOL      = 0.06   -- allowed drift from seed coords (roaming rares)
local CHANNEL_NAME   = "VoidSweepNet"  -- General/LFG reject addon msgs; a custom channel doesn't
-- WoW Forever: a new channel every day, joined with a password, both worked out from the
-- server's date (WhisperNet.lua "Daily channel"). Nobody can /join it by hand, own it and
-- /ban players (that happened to VoidQuestNet, 2026-11-08), and if someone works it out
-- anyway, it only lasts until 00:00 UTC. Set in Sync:Init once the game says it's Forever.
-- Retail keeps VoidSweepNet.
local OLD_CHANNELS   = { "VoidSweepNet", "VoidSweepLink" }   -- left on Forever
local DAILY_TAG, DAILY_SALT = "Vs", 69621
local CHANNEL_PW
local daily = false      -- Forever: CHANNEL_NAME is the day's channel
-- Forever (whispers)
local FANOUT         = 8      -- members each rare-up / new spot is whispered to
local ASK_PEERS      = 4      -- members asked on entering a zone
local REPLY_MAX_W    = 60     -- spots per whispered answer
local ANSWER_EVERY   = 30     -- at most one whispered answer (to anyone) per this
local lastAnyReply
local REPLY_GAP      = 60     -- one answer per player per this, any map
local SEND_EVERY_W   = 1.5

Sync.reports = {}   -- [vid] = {mapID,x,y,hp,kind,senders={[name]=t},received,trusted}
Sync.pending = {}   -- self-test: [nonce] = {channel, got}
local lastSent = {} -- [vid] = GetTime()
local bucket   = {} -- [sender] = {n, start}
local nonceSeq = 0
local net           -- WhisperNet object on Forever, nil on retail (= channel)

local function now() return GetTime() end

local function enabled()
    return VS:Config().sync ~= false
end

-- Index of our shared custom channel (0/nil if not joined yet).
local function netIndex()
    local id = GetChannelName(CHANNEL_NAME)
    if id and id > 0 then return id end
    return nil
end

-- Join the shared VoidSweep channel and keep it out of the visible chat tabs.
-- Every client joins the SAME channel, so a broadcast reaches all of them
-- (realm-cluster-wide). Reports are filtered to your current zone on display.
-- Joining is blocked in combat and during the chat lockdown (encounters): ADDON_ACTION_BLOCKED
-- x6 on 2026-11-06, and it was called again even when already in the channel. Join only
-- when not in it, and when it's blocked try again once combat / the lockdown is over.
local function chatLocked()
    if InCombatLockdown() then return true end
    local f = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
    if not f then return false end
    local ok, v = pcall(f)
    if not ok then return true end
    if issecretvalue and issecretvalue(v) then return true end
    return v == true
end
local joinRetry = CreateFrame("Frame")
joinRetry:SetScript("OnEvent", function(self)
    if chatLocked() then return end
    self:UnregisterAllEvents()
    Sync:JoinNet()
end)

function Sync:JoinNet()
    -- Forever: out of the old channels first, so their slots are free for the new one (Codex
    -- review). A banned one can't be left; it goes at logout.
    if daily and not chatLocked() then
        for _, old in ipairs(OLD_CHANNELS) do
            if (GetChannelName(old) or 0) > 0 then LeaveChannelByName(old) end
        end
    end
    if not netIndex() then
        if chatLocked() then
            joinRetry:RegisterEvent("PLAYER_REGEN_ENABLED")
            joinRetry:RegisterEvent("ZONE_CHANGED_NEW_AREA")
            joinRetry:RegisterEvent("ENCOUNTER_END")
            -- fires when a chat / addon restriction lifts (PvP match end, ...): Codex review
            pcall(joinRetry.RegisterEvent, joinRetry, "ADDON_RESTRICTION_STATE_CHANGED")
            return
        end
        JoinTemporaryChannel(CHANNEL_NAME, CHANNEL_PW)
        C_Timer.After(5, function() if Sync.Publish then Sync.Publish() end end)   -- refused -> "blocked"
    end
    if netIndex() then
        for i = 1, (NUM_CHAT_WINDOWS or 10) do
            local cf = _G["ChatFrame" .. i]
            if cf then ChatFrame_RemoveChannel(cf, CHANNEL_NAME) end
        end
    end
end

----------------------------------------------------------------------
-- Broadcast — called by the scanner when a rare/boss is freshly seen UP.
----------------------------------------------------------------------
function Sync:Broadcast(entry, x, y, hp)
    if not (enabled() and entry and entry.vignetteID and x and y) then return end
    if entry.kind ~= "rare" and entry.kind ~= "worldboss" then return end

    local vid = entry.vignetteID
    if lastSent[vid] and (now() - lastSent[vid]) < REBROADCAST_CD then return end
    lastSent[vid] = now()

    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return end

    local payload = ("UP:%s:%d,%d,%d,%d,%d,%s"):format(
        PROTO, vid, mapID,
        math.floor(x * 1000), math.floor(y * 1000),
        math.floor((hp or 0) * 100),
        entry.kind == "worldboss" and "b" or "r")

    if net then   -- Forever: whispered to a few members (through the paced queue, ahead of answers)
        Sync.SendTo(payload, Sync.Targets(FANOUT), true)
        return
    end
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    local ci = netIndex()
    if ci then C_ChatInfo.SendAddonMessage(PREFIX, payload, "CHANNEL", ci) end
end

-- A rare seen on a nameplate / target (Sightings.lua): same transport as Broadcast.
function Sync:SendSighting(payload)
    if not (enabled() and payload) or #payload > 250 then return end
    if net then
        Sync.SendTo(payload, Sync.Targets(FANOUT), true)
        return
    end
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) or chatLocked() then return end
    local ci = netIndex()
    if ci then C_ChatInfo.SendAddonMessage(PREFIX, payload, "CHANNEL", ci) end
end

----------------------------------------------------------------------
-- Receive — untrusted. Validate hard before it ever becomes a pin.
----------------------------------------------------------------------
local function rateOK(sender)
    local b = bucket[sender]
    if not b or (now() - b.start) > SENDER_WINDOW then
        bucket[sender] = { n = 1, start = now() }
        return true
    end
    b.n = b.n + 1
    return b.n <= SENDER_MAX
end

-- world-boss reports are cross-checked against the game's own POI data
local function bossLooksUp(mapID)
    if not (C_AreaPoiInfo and C_AreaPoiInfo.GetAreaPOIForMap) then return true end
    for _, id in ipairs(C_AreaPoiInfo.GetAreaPOIForMap(mapID) or {}) do
        local info = C_AreaPoiInfo.GetAreaPOIInfo(mapID, id)
        if info and (info.atlasName or ""):lower():find("worldboss") then return true end
    end
    return false
end

function Sync:OnMessage(payload, sender)
    if not enabled() or type(payload) ~= "string" then return end
    -- a sighting (Sightings.lua validates it); 2 = with the layer it was seen on
    local snv, sn = payload:match("^SN:([12]):(.+)$")
    if sn then
        if rateOK(sender) and VS.Sightings then VS.Sightings:OnShared(sn, sender, tonumber(snv)) end
        return
    end
    local proto, body = payload:match("^UP:(%d+):(.+)$")
    if proto ~= PROTO then return end

    local vid, mapID, x1k, y1k, hpP, kind =
        body:match("^(%d+),(%d+),(%d+),(%d+),(%d+),(%a)$")
    vid, mapID = tonumber(vid), tonumber(mapID)
    x1k, y1k, hpP = tonumber(x1k), tonumber(y1k), tonumber(hpP)
    if not (vid and mapID and x1k and y1k) then return end

    local x, y = x1k / 1000, y1k / 1000
    if x < 0 or x > 1 or y < 0 or y > 1 then return end
    if not rateOK(sender) then return end

    -- Validate against our seed (ground truth). Known vignette with sane
    -- coords = trusted; known vignette with wild coords = forged, dropped;
    -- unknown vignette = allowed but untrusted (must earn quorum).
    local seed = VS.Seed and VS.Seed[mapID] and VS.Seed[mapID]["v" .. vid]
    local trusted = false
    if seed then
        if math.abs(seed.x - x) <= COORD_TOL and math.abs(seed.y - y) <= COORD_TOL then
            trusted = true
        else
            return
        end
    end

    if kind == "b" and not bossLooksUp(mapID) then return end -- game says no boss

    local r = Sync.reports[vid]
    -- same ID on another map: never move a record across maps while it keeps
    -- the old map's trusted flag; an unvalidated claim can't replace a
    -- validated one, otherwise start over for the new map.
    if r and r.mapID ~= mapID then
        if r.trusted and not trusted then return end
        r = nil
    end
    if not r then
        r = { mapID = mapID, kind = (kind == "b" and "worldboss" or "rare"),
              senders = {}, trusted = false }
        Sync.reports[vid] = r
    end
    r.x, r.y, r.hp, r.received = x, y, hpP, now()
    r.senders[sender] = now()
    if trusted then r.trusted = true end
    -- nothing else redraws the world map when this report's TTL runs out
    C_Timer.After(REPORT_TTL + 1, function() VS.Pins:Refresh() end)
end

----------------------------------------------------------------------
-- Render feed — active, corroborated reports for a map (names from seed).
----------------------------------------------------------------------
function Sync:GetForMap(mapID)
    local out, t = {}, now()
    for vid, r in pairs(Sync.reports) do
        if (t - r.received) > REPORT_TTL then
            Sync.reports[vid] = nil
        elseif r.mapID == mapID then
            -- quorum = senders heard within the TTL (old ones expire, so one
            -- player can't keep a 2-player quorum alive alone)
            local count = 0
            for name, ts in pairs(r.senders) do
                if (t - ts) <= REPORT_TTL then count = count + 1 else r.senders[name] = nil end
            end
            -- trusted (seed-validated) shows at once; unknown needs 2+ senders
            if r.trusted or count >= 2 then
                local seed = VS.Seed and VS.Seed[mapID] and VS.Seed[mapID]["v" .. vid]
                out[#out + 1] = {
                    vignetteID = vid, kind = r.kind,
                    name = (seed and seed.name) or "Reported rare",
                    x = r.x, y = r.y, hp = r.hp,
                    reported = true, senders = count,
                    age = math.floor(t - r.received),
                }
            end
        end
    end
    return out
end

----------------------------------------------------------------------
-- Spot sharing (persistent locations, not "up right now")
--
-- When your VoidSweep learns a spot the starter map doesn't have, it tells
-- everyone (N:). Entering a zone asks "who knows spots here?" (Q:); one
-- player answers with their OWN learned spots (B:) — answerers wait 1-6 s
-- at random and stand down if someone else's B: for that map arrives first.
--   N:1:mapID:entries   B:1:mapID:entries   Q:1:mapID
--   entries = "k,x,y,vignetteID,questID,name;..."  k = r/b/c/l, x/y 0..9999
-- Untrusted like UP:. Received spots go to VoidSweepDB.shared (Data.lua),
-- drawn faded until a 2nd player confirms, dropped once you see it
-- yourself; only your own sightings are ever passed on.
----------------------------------------------------------------------
local SPOT_PROTO   = "1"
local MAX_LEN      = 250
local SEND_EVERY   = 1.1
local QUEUE_MAX    = 60
local REPLY_MAX    = 300
local REPLY_CD     = 120
local QUERY_CD     = 900
local SPOT_MAX     = 40     -- spot messages accepted per sender per window

local KIND_CODE = { rare = "r", worldboss = "b", chest = "c", lore = "l" }
local CODE_KIND = { r = "rare", b = "worldboss", c = "chest", l = "lore" }

local queue, sending = {}, nil
local spotBucket = {}
local replyTimer, lastReply, lastQuery = {}, {}, {}   -- Forever: lastReply[sender .. ":" .. mapID]
local lastReplyTo = {}   -- Forever: [sender] = GetTime() of our last answer to them
local me
local refreshPending

local function cleanName(s)
    if type(s) ~= "string" then return nil end
    s = (s:gsub("[%c|;,:]", ""))
    s = (s:gsub("^%s+", ""):gsub("%s+$", ""))
    if #s > 48 then
        s = (s:sub(1, 48):gsub("[\192-\255][\128-\191]*$", ""))
    end
    return s ~= "" and s or nil
end

-- Traffic counter (the user, 2026-11-08: nothing had ever arrived and nothing told us
-- why). By message type (UP/SN/Q/B/L/P/H/...): what went out, what the game refused
-- (offline), what came in, and what never went because nobody was online, since `since`,
-- in VoidSweepDB.netStats. /vsw net prints it.
-- Kept small on purpose (incoming messages are counted before they're checked): the type
-- is the message's short uppercase prefix, a short label we pass ourselves, else "other",
-- and each bucket holds at most TALLY_KEYS types (the rest count as "other").
local TALLY_KEYS = 16
local function tally(what, msg)
    if not VoidSweepDB then return end
    local s = VoidSweepDB.netStats
    if not s then s = { since = time() }; VoidSweepDB.netStats = s end
    local kind = type(msg) == "string" and (msg:match("^(%u%u?%u?%u?):") or (#msg <= 12 and not msg:find(":") and msg))
    kind = kind or "other"
    local b = s[what]
    if not b then b = {}; s[what] = b end
    if not b[kind] then
        local n = 0
        for _ in pairs(b) do n = n + 1 end
        if n >= TALLY_KEYS then kind = "other" end
    end
    b[kind] = (b[kind] or 0) + 1
    s["last_" .. what] = time()
end
-- SendAddonMessage's result: accepted (0; older clients nil/true), the player is offline
-- (12 = TargetOffline), or refused for another reason (throttle, lockdown, ...)
local function sendResult(result)
    if result == nil or result == true or result == 0 then return "sent" end
    return result == 12 and "offline" or "refused"
end
Sync.Tally = tally

-- An item with .to is an addon whisper (Forever), without one it goes on the
-- channel (retail).
local function pump()
    local item = table.remove(queue, 1)
    if not item then
        if sending then sending:Cancel(); sending = nil end
        return
    end
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    if not enabled() then wipe(queue); return end   -- sync turned off: nothing more goes out
    if item.to then
        if net then net:Noted(item.to) end
        local result = C_ChatInfo.SendAddonMessage(PREFIX, item.msg, "WHISPER", item.to)
        tally(sendResult(result), item.msg)
        if net then net:Sent(item.to, result) end
    else
        local ci = netIndex()
        if ci then tally(sendResult(C_ChatInfo.SendAddonMessage(PREFIX, item.msg, "CHANNEL", ci)), item.msg) end
    end
end

-- urgent = jump the queue (who's-here answers are only useful within seconds)
-- to = whisper target; Forever drops anything without one (its channel refuses them)
local function send(msg, urgent, to)
    if #queue >= QUEUE_MAX then return end
    if net and not to then return end
    local item = { msg = msg, to = to }
    if urgent then table.insert(queue, 1, item) else queue[#queue + 1] = item end
    if not sending then
        pump()
        -- always start the ticker: pump() just emptied the queue, so a
        -- "#queue > 0" check here never fired and bursts went out unpaced.
        -- The ticker cancels itself once the queue is empty.
        sending = C_Timer.NewTicker(net and SEND_EVERY_W or SEND_EVERY, pump)
    end
end

-- Who a message to "everyone" goes to: nil = the channel (retail); on Forever up
-- to k random members of VoidSweepNet (empty when nobody else is online).
function Sync.Targets(k)
    if not net then return nil end
    net:RequestRoster()
    return net:Pick(k)
end

-- Forever: is this player in our sharing channel right now? (LayerNet answers only them)
function Sync.IsPeer(name)
    if not (net and name) then return false end
    for _, n in ipairs(net.roster or {}) do if n == name then return true end end
    return false
end

-- One message to every target (to = nil: once, on the channel).
function Sync.SendTo(msg, to, urgent)
    if not to then send(msg, urgent); return end
    if #to == 0 then tally("nobody", msg); return end   -- Forever: nobody else online
    for _, name in ipairs(to) do send(msg, urgent, name) end
end

local function encode(rec)
    local name = cleanName(rec.name)
    if not (name and KIND_CODE[rec.kind] and rec.x and rec.y) then return nil end
    return ("%s,%d,%d,%d,%d,%s"):format(KIND_CODE[rec.kind],
        math.floor(rec.x * 10000 + 0.5), math.floor(rec.y * 10000 + 0.5),
        rec.vignetteID or 0, rec.questID or 0, name)
end

-- Pack spots into as few messages as fit under MAX_LEN; each to every target
-- (to = nil: once, on the channel).
local function sendSpots(tag, mapID, recs, to)
    local head = ("%s:%s:%d:"):format(tag, SPOT_PROTO, mapID)
    local msgs, parts, len = {}, {}, #head
    for _, rec in ipairs(recs) do
        local e = encode(rec)
        if e then
            if #parts > 0 and len + 1 + #e > MAX_LEN then
                msgs[#msgs + 1] = head .. table.concat(parts, ";")
                parts, len = {}, #head
            end
            parts[#parts + 1] = e
            len = len + #e + 1
        end
    end
    if #parts > 0 then msgs[#msgs + 1] = head .. table.concat(parts, ";") end
    if not to then
        for _, m in ipairs(msgs) do send(m) end
        return
    end
    if #to == 0 and #msgs > 0 then tally("nobody", msgs[1]) end   -- Forever: nobody else online
    for _, name in ipairs(to) do
        for _, m in ipairs(msgs) do send(m, false, name) end
    end
end

-- Data.lua calls this when you learn a spot the starter map doesn't have.
function Sync:ShareSpot(mapID, rec)
    if not (enabled() and mapID and rec) then return end
    sendSpots("N", mapID, { rec }, Sync.Targets(FANOUT))
end

local function askHere()
    if not enabled() or not netIndex() then return end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return end
    if lastQuery[mapID] and GetTime() - lastQuery[mapID] < QUERY_CD then return end
    if net then
        net:RequestRoster()
        -- nobody to ask yet (none online, or all known to be offline): try again on the next zone change
        local targets = net:Pick(ASK_PEERS)
        if #targets == 0 then tally("nobody", "Q"); return end
        lastQuery[mapID] = GetTime()
        for _, to in ipairs(targets) do send(("Q:%s:%d"):format(SPOT_PROTO, mapID), false, to) end
        return
    end
    lastQuery[mapID] = GetTime()
    send(("Q:%s:%d"):format(SPOT_PROTO, mapID))
end

local function ownSpots(mapID, cap)
    local out = {}
    for _, rec in pairs(VS.Learned:GetForMap(mapID) or {}) do
        if #out >= cap then break end
        out[#out + 1] = rec
    end
    return out
end

local function answer(mapID)
    replyTimer[mapID] = nil
    lastReply[mapID] = GetTime()
    sendSpots("B", mapID, ownSpots(mapID, REPLY_MAX))
end

-- Forever: whisper our own spots for a map back to the player who asked. Each
-- asker gets one answer per REPLY_GAP (any map) and one per map per REPLY_CD,
-- and only when there's something to say, so a stranger can't make us spam.
local function answerWhisper(mapID, sender, replyTo)
    if not replyTo then return end
    local key, t = sender .. ":" .. mapID, GetTime()
    if lastReply[key] and t - lastReply[key] < REPLY_CD then return end
    if lastReplyTo[sender] and t - lastReplyTo[sender] < REPLY_GAP then return end
    if not next(VS.Learned:GetForMap(mapID) or {}) then return end
    -- and one answer to anyone every ANSWER_EVERY seconds, so answers can't fill the
    -- queue and crowd out live rare alerts
    if lastAnyReply and t - lastAnyReply < ANSWER_EVERY then return end
    lastReply[key], lastReplyTo[sender], lastAnyReply = t, t, t
    C_Timer.After(1 + math.random() * 3, function()
        if enabled() then sendSpots("B", mapID, ownSpots(mapID, REPLY_MAX_W), { replyTo }) end
    end)
end

local lastSweep = 0
local function spotRateOK(sender)
    local t = GetTime()
    if t - lastSweep > SENDER_WINDOW then   -- forget senders whose window ran out
        lastSweep = t
        for k, b in pairs(spotBucket) do
            if t - b.start > SENDER_WINDOW then spotBucket[k] = nil end
        end
        for k, b in pairs(bucket) do
            if t - b.start > SENDER_WINDOW then bucket[k] = nil end
        end
        if net then
            for k, v in pairs(lastReply) do
                if t - v > REPLY_CD then lastReply[k] = nil end
            end
            for k, v in pairs(lastReplyTo) do
                if t - v > REPLY_GAP then lastReplyTo[k] = nil end
            end
        end
    end
    local b = spotBucket[sender]
    if not b or t - b.start > SENDER_WINDOW then
        spotBucket[sender] = { n = 1, start = t }
        return true
    end
    b.n = b.n + 1
    return b.n <= SPOT_MAX
end

local function scheduleRefresh()
    if refreshPending then return end
    refreshPending = true
    C_Timer.After(1, function()
        refreshPending = nil
        VS.Pins:Refresh()
        if VS.Minimap and VS.Minimap.Invalidate then VS.Minimap:Invalidate() end
    end)
end

local function takeSpots(mapID, body, sender)
    local changed, n = false, 0
    for entry in body:gmatch("[^;]+") do
        n = n + 1
        if n > 40 then break end
        local code, xs, ys, vs, qs, name = entry:match("^(%a),(%d+),(%d+),(%d+),(%d+),(.+)$")
        local kind = code and CODE_KIND[code]
        local x, y = tonumber(xs), tonumber(ys)
        name = cleanName(name)
        if kind and name and x and y and x > 0 and x < 10000 and y > 0 and y < 10000 then
            local vid, qid = tonumber(vs), tonumber(qs)
            local rec = { kind = kind, name = name, x = x / 10000, y = y / 10000,
                          vignetteID = (vid and vid > 0) and vid or nil,
                          questID = (qid and qid > 0) and qid or nil }
            if VS.Learned:AddShared(mapID, rec, sender) then changed = true end
        end
    end
    if changed then scheduleRefresh() end
end

-- returns true if msg was a spot message (handled here)
-- replyTo = the name to whisper an answer back to, as the game gave it (Forever)
function Sync:OnSpotMessage(msg, sender, replyTo)
    local tag, proto, mapS, body = msg:match("^([NQB]):(%d+):(%d+):?(.*)$")
    if not tag then return false end
    if proto ~= SPOT_PROTO or not enabled() or sender == me then return true end
    if not spotRateOK(sender) then return true end
    local mapID = tonumber(mapS)
    if not (mapID and mapID > 0 and C_Map.GetMapInfo(mapID)) then return true end

    if tag == "Q" and net then
        if body == "" then answerWhisper(mapID, sender, replyTo) end
    elseif tag == "Q" then
        if replyTimer[mapID] or (lastReply[mapID] and GetTime() - lastReply[mapID] < REPLY_CD) then return true end
        if not next(VS.Learned:GetForMap(mapID) or {}) then return true end
        replyTimer[mapID] = C_Timer.NewTimer(1 + math.random() * 5, function() answer(mapID) end)
    else
        if tag == "B" and replyTimer[mapID] then
            replyTimer[mapID]:Cancel()
            replyTimer[mapID] = nil
            lastReply[mapID] = GetTime()
        end
        takeSpots(mapID, body, sender)
    end
    return true
end

----------------------------------------------------------------------
-- Who's here: entering a zone tells you how many other VoidSweep players
-- are in it.
--   P:1:zoneID   "I just arrived" (sent when you enter a zone)
--   H:1:zoneID   "I'm here too" (answer from players already in that zone)
-- Answerers wait 0.5-4 s at random and stand down once HERE_CAP others have
-- answered, so a busy zone sends about HERE_CAP answers and shows "10+".
-- Subzones and caves count as their zone; instances are skipped. Only
-- players on a VoidSweep with this feature answer.
----------------------------------------------------------------------
local HERE_PROTO = "1"
local HERE_CAP   = 10
local HERE_WAIT  = 6      -- seconds the arrival listens before printing
local ARRIVE_CD  = 120    -- announce the same zone at most this often
local ASK_CD     = 15     -- /vsw here at most this often

local hereZone            -- zone you're in now (nil in instances)
local announced           -- zone you last announced
local lastArrive = {}     -- [zoneID] = GetTime()
local listen              -- { zone, from = {[name]=true}, n, always, recount }
local rounds = {}         -- [zoneID] = { n = answers heard, timer = our pending answer }

-- Who's in your zone now, for the "players here" box (PresenceBox.lua): filled
-- by arrivals (P), answers (H) and departures (L:1:zoneID, sent when you leave
-- a zone; older versions ignore it), and rebuilt by a quiet recount every 10
-- minutes while the box is shown (catches players who logged off).
local RECOUNT = 600
local rosters = {}        -- [zoneID] = { [name] = true }
local rosterZone          -- the zone we last counted
local capped = {}         -- [zoneID] = true: the last count hit HERE_CAP (busy zone)
local LEAVE_DELAY = 10    -- seconds out of a zone before "left" goes out (border flapping)
local leaveTimer = {}     -- [zoneID] = pending "left" timer

local function publish()
    if not _G.VoidPresence then return end
    local note = enabled() and VS.WhisperNet and VS.WhisperNet.BlockNote(CHANNEL_NAME) or nil
    if net then
        -- Forever: players online on the channel (no zone counts without channel messages)
        local others = net:Others()
        VoidPresence:Set("VoidSweep", "VoidSweep online", others or 0, false, enabled() and others ~= nil, note)
        return
    end
    local n = 0
    for _ in pairs(hereZone and rosters[hereZone] or {}) do n = n + 1 end
    VoidPresence:Set("VoidSweep", "VoidSweep", n, capped[hereZone or 0] or n >= HERE_CAP, enabled() and hereZone ~= nil, note)
end
Sync.Publish = publish

-- Roll a map up to its zone (city floors, caves and subzones count as the zone).
local function zoneOf(mapID)
    local ZONE = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
    local info = mapID and C_Map.GetMapInfo(mapID)
    local hops = 0
    while info and info.mapType and info.mapType > ZONE and (info.parentMapID or 0) > 0 and hops < 5 do
        info = C_Map.GetMapInfo(info.parentMapID)
        hops = hops + 1
    end
    if info and info.mapType == ZONE then return info.mapID, info.name end
end

local function currentZone()
    if IsInInstance() then return nil end
    return zoneOf(C_Map.GetBestMapForUnit("player"))
end

local function report(zone)
    local l = listen
    if not (l and l.zone == zone) then return end
    listen = nil
    local now, name = currentZone()
    if now ~= zone then return end
    if l.recount then rosters[zone] = l.from end
    -- a busy zone stays "10+" through departures, until a count says otherwise
    capped[zone] = l.n >= HERE_CAP
    publish()
    -- the box shows the count: chat only when asked by hand or the box is off
    if l.recount or (not l.always and _G.VoidPresence and VoidPresence:IsShown()) then return end
    if l.n == 0 then
        if l.always then
            print(("|cff00c7ffVoidSweep|r: no other VoidSweep players answered in %s."):format(name or "this zone"))
        end
        return
    end
    local count = l.n >= HERE_CAP and (HERE_CAP .. "+") or tostring(l.n)
    print(("|cff00c7ffVoidSweep|r: |cff33ff33%s|r other VoidSweep player%s in %s."):format(
        count, l.n == 1 and " is" or "s are", name or "this zone"))
end

-- always = asked by hand: skip the cooldowns and say so even when nobody answers
local function arrive(always)
    local zone = currentZone()
    if net then   -- Forever: no P/H/L (the channel refuses them); the box counts members
        hereZone = zone
        publish()
        return
    end
    if zone ~= rosterZone then
        -- left a zone: tell the players there, so their count drops
        -- left a zone: after a few seconds away tell the players there, so their count
        -- drops (coming back before then cancels it; flying along a border sends nothing)
        local left = rosterZone
        if left and enabled() and netIndex() and not leaveTimer[left] then
            leaveTimer[left] = C_Timer.NewTimer(LEAVE_DELAY, function()
                leaveTimer[left] = nil
                if hereZone ~= left and enabled() and netIndex() then
                    send(("L:%s:%d"):format(HERE_PROTO, left), true)
                    lastArrive[left] = nil   -- they dropped us: coming back announces again
                    if announced == left then announced = nil end
                end
            end)
        end
        if zone and leaveTimer[zone] then leaveTimer[zone]:Cancel(); leaveTimer[zone] = nil end
        rosterZone = zone
        if zone then rosters[zone] = rosters[zone] or {} end
    end
    hereZone = zone
    publish()
    if not zone then announced = nil end   -- back from an instance = arriving again
    if not zone or not enabled() or not netIndex() then return end
    local cd = always and ASK_CD or ARRIVE_CD
    if not always and zone == announced then return end
    if lastArrive[zone] and GetTime() - lastArrive[zone] < cd then
        if always then print("|cff00c7ffVoidSweep|r: asked a moment ago, try again in a few seconds.") end
        return
    end
    announced = zone
    lastArrive[zone] = GetTime()
    listen = { zone = zone, from = {}, n = 0, always = always }
    send(("P:%s:%d"):format(HERE_PROTO, zone), true)
    C_Timer.After(HERE_WAIT, function() report(zone) end)
end

-- Forever: "N other VoidSweep players online" from the channel's member list.
local function printOnline()
    local others = net:Others()
    local why = VS.WhisperNet.BlockReason(CHANNEL_NAME)
    if why then
        print("|cff00c7ffVoidSweep|r: |cffff5555" .. why .. "|r")
    elseif not others then
        print("|cff00c7ffVoidSweep|r: couldn't read " .. CHANNEL_NAME .. "'s member list yet, try again in a few seconds.")
    else
        print(("|cff00c7ffVoidSweep|r: %s%d|r other VoidSweep player%s of your faction online (WoW Forever can't count by zone).")
            :format(others > 0 and "|cff33ff33" or "|cffffd200", others, others == 1 and " is" or "s are"))
    end
    if net.bounces > 0 then
        print(("|cff00c7ffVoidSweep|r: %d whisper%s bounced this session (player not reachable)."):format(net.bounces, net.bounces == 1 and "" or "s"))
    end
end

function Sync:WhoHere()
    if not enabled() then
        print("|cff00c7ffVoidSweep|r: crowd sync is off (/vsw sync).")
    elseif net then
        Sync:JoinNet()
        net:RequestRoster(true)
        C_Timer.After(3.5, printOnline)
    elseif not currentZone() then
        print("|cff00c7ffVoidSweep|r: not counted inside instances.")
    else
        arrive(true)
    end
end

-- Quiet recount for the box: same as arriving, no chat, and the answers
-- replace the roster.
local function recount()
    local zone = currentZone()
    if not (_G.VoidPresence and VoidPresence:IsShown()) then return end
    if net then
        publish()   -- a blocked channel is never read, so say so now
        if enabled() then net:RequestRoster(true) end   -- publish() runs when it's read
        return
    end
    if not zone or zone ~= hereZone or listen or not enabled() or not netIndex() then return end
    lastArrive[zone] = GetTime()
    listen = { zone = zone, from = {}, n = 0, recount = true }
    send(("P:%s:%d"):format(HERE_PROTO, zone), true)
    C_Timer.After(HERE_WAIT, function() report(zone) end)
end

-- The box was just turned on: count now instead of waiting for the next recount.
function Sync:CountNow()
    publish()
    recount()
end

-- returns true if msg was a who's-here message (handled here)
function Sync:OnHereMessage(msg, sender)
    local tag, proto, zoneS = msg:match("^([PHL]):(%d+):(%d+)$")
    if not tag then return false end
    if net or proto ~= HERE_PROTO or not enabled() or sender == me then return true end
    if not spotRateOK(sender) then return true end
    local zone = tonumber(zoneS)

    if tag == "L" then   -- someone left this zone
        if rosters[zone] then rosters[zone][sender] = nil end
        -- and out of a count in progress, or the recount would add them back
        if listen and listen.zone == zone and listen.from[sender] then
            listen.from[sender] = nil
            listen.n = listen.n - 1
        end
        if zone == hereZone then publish() end
        return true
    end
    -- an arrival counts everyone who says they're in its zone
    if listen and listen.zone == zone and not listen.from[sender] then
        listen.from[sender] = true
        listen.n = listen.n + 1
    end
    if zone ~= hereZone then return true end
    rosters[zone] = rosters[zone] or {}
    if not rosters[zone][sender] then
        rosters[zone][sender] = true
        publish()
    end

    -- a round lasts until our answer goes out; a P after that starts a new one
    local r = rounds[zone]
    if tag == "P" then
        if r and r.timer then
            r.n = 0   -- answers heard so far came before this arrival; ours still covers both
        else
            r = { n = 0 }
            rounds[zone] = r
            r.timer = C_Timer.NewTimer(0.5 + math.random() * 3.5, function()
                r.timer = nil
                if hereZone == zone and r.n < HERE_CAP and enabled() then
                    send(("H:%s:%d"):format(HERE_PROTO, zone), true)
                end
            end)
        end
    elseif r and r.timer then
        r.n = r.n + 1
        if r.n >= HERE_CAP and r.timer then
            r.timer:Cancel()
            r.timer = nil
        end
    end
    return true
end

----------------------------------------------------------------------
-- Init
----------------------------------------------------------------------
local HEARD_MAX = 500   -- players remembered for /vsw synctest

function Sync:Init()
    local Net = VS.WhisperNet
    if Net and Net.Active() then
        daily = true
        local today
        -- one channel per faction since 2026-11-10 (WhisperNet.lua: whispers don't cross factions)
        CHANNEL_NAME, CHANNEL_PW, today = Net.DailyChannel(DAILY_TAG, DAILY_SALT)
        -- channels survive a /reload: yesterday's goes too (reload across 00:00 UTC, Codex),
        -- and the old both-factions ones
        for _, old in ipairs(Net.OldDailyChannels(DAILY_TAG, DAILY_SALT, today)) do
            table.insert(OLD_CHANNELS, old)
        end
        -- WoW Forever: the channel is a member list, messages go by addon whisper
        -- offline marks (players whose whisper bounced): this session only, never saved (the user,
        -- 2026-11-09: "get rid of the offline list"); the old saved list is deleted
        VoidSweepDB = VoidSweepDB or {}
        VoidSweepDB.netOffline = nil
        net = Net.New(CHANNEL_NAME, publish, {})
        -- a whisper that came back "No player named X" (2026-11-10: the other faction's were all
        -- that, and nothing counted them)
        net.onBounce = function() tally("offline", "whisper") end
        me = Net.Me()
    else
        me = UnitName("player")
    end
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    end
    -- Join the shared channel a few seconds after login (the chat/channel
    -- system needs to be up first), then ask about the zone we're in.
    -- Forever: read the member list first; staggered from VoidGather's, which
    -- selects its own channel at the same moment after login.
    C_Timer.After(net and 14 or 8, function()
        Sync:JoinNet()
        C_Timer.After(3, function()
            if net then net:RequestRoster(true) end
            C_Timer.After(net and 4 or 0, function() askHere(); arrive() end)
        end)
    end)
    C_Timer.NewTicker(RECOUNT, recount)
    VoidPresence:Listen(function() Sync:CountNow() end)
    -- Forever: at 00:00 UTC everyone moves to the new day's channel together
    if daily then
        C_Timer.NewTicker(60, function()
            local name, pw = Net.DailyChannel(DAILY_TAG, DAILY_SALT)
            if name == CHANNEL_NAME then return end
            local old = CHANNEL_NAME
            CHANNEL_NAME, CHANNEL_PW = name, pw
            net:SetChannel(name)
            table.insert(OLD_CHANNELS, old)   -- JoinNet leaves it (now, or once chat unlocks)
            publish()   -- "—" until the new list is read
            if not enabled() then
                if (GetChannelName(old) or 0) > 0 and not chatLocked() then LeaveChannelByName(old) end
                return
            end
            C_Timer.After(2 + math.random() * 3, function()   -- not all at the same second as VoidGather
                Sync:JoinNet()
                C_Timer.After(3, function() net:RequestRoster(true) end)
            end)
        end)
    end

    local f = CreateFrame("Frame")
    f:RegisterEvent("CHAT_MSG_ADDON")
    f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    f:RegisterEvent("ZONE_CHANGED")
    f:SetScript("OnEvent", function(_, event, prefix, msg, dist, sender)
        if event ~= "CHAT_MSG_ADDON" then askHere(); arrive(); return end
        if prefix ~= PREFIX or type(msg) ~= "string" then return end
        -- Forever: whispers only. A Q arriving by guild / raid would otherwise make every
        -- member who heard it whisper back at once.
        if net and dist ~= "WHISPER" then return end
        local who
        if net then
            who = VS.WhisperNet.Canon(sender)
        else
            who = Ambiguate and Ambiguate(sender or "", "none") or sender
        end
        if type(who) ~= "string" or who == "" then return end
        -- self-test echo? (Forever: only our own whisper counts; anyone can whisper a PING)
        local nonce = msg:match("^PING:(.+)$")
        if nonce then
            local p = Sync.pending[nonce]
            if p and (not net or who == me) then p.got = true end
            return
        end
        if who ~= me then
            tally("got", msg)
            if not net or Sync.heard[who] or Sync.heardPeople < HEARD_MAX then   -- cap: Forever only
                if not Sync.heard[who] then Sync.heardPeople = Sync.heardPeople + 1 end
                Sync.heard[who] = (Sync.heard[who] or 0) + 1
            end
            Sync.heardTotal = Sync.heardTotal + 1
        end
        if Sync:OnHereMessage(msg, who) then return end
        if Sync:OnSpotMessage(msg, who, sender) then return end
        Sync:OnMessage(msg, who)
        VS.Pins:Refresh()
    end)
end

-- Network health: other players heard from this session (any VSWEEP message),
-- and how many players are in VoidSweepNet right now (= VoidSweep users online
-- on your realm group, incl. you). The member count comes from the channel
-- roster; selecting the display channel asks the server to fill it in.
Sync.heard, Sync.heardTotal, Sync.heardPeople = {}, 0, 0

local function channelMembers()
    if not (GetNumDisplayChannels and GetChannelDisplayInfo) then return nil end
    for i = 1, GetNumDisplayChannels() do
        local name, header, _, _, count = GetChannelDisplayInfo(i)
        if not header and name and name:lower() == CHANNEL_NAME:lower() then
            return count, i
        end
    end
end

-- the traffic counter since it started (all sessions), on every /vsw net
local function printTraffic()
    local s = VoidSweepDB and VoidSweepDB.netStats
    if not s then
        print("|cff00c7ffVoidSweep|r: traffic -- nothing sent or received yet since the counter started.")
        return
    end
    local function list(t)
        local out = {}
        for k, v in pairs(t or {}) do out[#out + 1] = k .. " " .. v end
        table.sort(out)
        return #out > 0 and table.concat(out, ", ") or "none"
    end
    print(("|cff00c7ffVoidSweep|r: traffic since %s -- sent: %s | received: %s | not sent, nobody online: %s | offline: %s | refused: %s"):format(
        date("%b %d %H:%M", s.since), list(s.sent), list(s.got), list(s.nobody), list(s.offline), list(s.refused)))
end

function Sync:NetStats(done)
    printTraffic()
    if net then
        net:RequestRoster(true)
        C_Timer.After(3.5, function()
            printOnline()
            print(("|cff00c7ffVoidSweep|r: this session -- %d message%s from %d other player%s (rare sightings + shared spots).")
                :format(Sync.heardTotal, Sync.heardTotal == 1 and "" or "s", Sync.heardPeople, Sync.heardPeople == 1 and "" or "s"))
            if done then done() end
        end)
        return
    end
    local _, idx = channelMembers()
    if idx and SetSelectedDisplayChannel then pcall(SetSelectedDisplayChannel, idx) end
    C_Timer.After(2, function()
        local count = channelMembers()
        local people = 0
        for _ in pairs(Sync.heard) do people = people + 1 end
        if count and count > 0 then
            local others = count - 1
            print(("|cff00c7ffVoidSweep|r: %s|r other VoidSweep player%s online on your realm group right now.")
                :format((others > 0 and "|cff33ff33" or "|cffffd200") .. others, others == 1 and " is" or "s are"))
        else
            print("|cff00c7ffVoidSweep|r: couldn't read the channel's member count yet.")
        end
        print(("|cff00c7ffVoidSweep|r: this session -- %d message%s from %d other player%s (rare sightings + shared spots).")
            :format(Sync.heardTotal, Sync.heardTotal == 1 and "" or "s", people, people == 1 and "" or "s"))
        if done then done() end
    end)
end

-- Single-client self-test. You receive your own addon messages back over a
-- channel you're in, so we ping each channel and listen for the echo. A
-- private temp channel is the CONTROL: if that echoes, self-echo works and
-- the General/LFG results are meaningful; if even the control is silent,
-- this client can't self-test and you'd need a second person.
function Sync:SelfTest()
    Sync.pending = {}
    Sync:JoinNet()
    if net then
        -- Forever: an addon whisper to yourself comes back if whispers get through
        print("|cff00c7ffVoidSweep|r: testing crowd sync by addon whisper (~5s)...")
        nonceSeq = nonceSeq + 1
        local nonce = ("%d-%d-%d"):format(math.floor(GetTime() * 100), nonceSeq, math.random(1000, 9999))
        Sync.pending[nonce] = { channel = "WHISPER", got = false }
        if me then C_ChatInfo.SendAddonMessage(PREFIX, "PING:" .. nonce, "WHISPER", me) end
        C_Timer.After(4, function()
            local ok = Sync.pending[nonce] and Sync.pending[nonce].got
            if ok then
                print("|cff20ff20VoidSweep|r: addon whispers |cff33ff33work — crowd sync is live!|r")
                Sync:NetStats()
            else
                print("|cffff5555VoidSweep|r: addon whispers didn't come back — messages aren't getting through here.")
            end
            Sync.pending = {}
        end)
        return
    end
    print("|cff00c7ffVoidSweep|r: self-test running (~6s)...")

    C_Timer.After(2, function()
        local idx = netIndex()
        if not idx then
            print("|cffff5555VoidSweep|r: not joined to " .. CHANNEL_NAME .. " yet — try again in a few seconds.")
            return
        end
        nonceSeq = nonceSeq + 1
        local nonce = ("%d-%d"):format(math.floor(GetTime() * 100), nonceSeq)
        Sync.pending[nonce] = { channel = CHANNEL_NAME, got = false }
        C_ChatInfo.SendAddonMessage(PREFIX, "PING:" .. nonce, "CHANNEL", idx)

        C_Timer.After(4, function()
            local ok = false
            for _, p in pairs(Sync.pending) do ok = p.got end
            if ok then
                print("|cff20ff20VoidSweep|r: " .. CHANNEL_NAME .. " |cff33ff33ECHO OK — crowd sync is live!|r")
            else
                print("|cffff5555VoidSweep|r: " .. CHANNEL_NAME .. " no echo — channel join failed.")
            end
            Sync.pending = {}
            if ok then Sync:NetStats() end
        end)
    end)
end
