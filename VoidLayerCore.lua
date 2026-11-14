----------------------------------------------------------------------
-- VoidLayerCore: the WoW Forever layer network (2026-11-09)
--
-- Copied as-is into every addon that carries it (VoidLayer, VoidSweep; source of truth:
-- wow-addons/_shared/VoidLayerCore.lua). Needs WhisperNet.lua and Layer.lua loaded before it
-- in the same addon. Like VoidHubBundle / PresenceBox: every copy registers, and at
-- PLAYER_LOGIN ONE copy runs (the newest CORE_VERSION), so two addons never answer, host or
-- invite twice. Settings come from the addon with the highest priority (VoidLayer 2,
-- VoidSweep 1): each addon calls ns.LayerCoreSettings(prio, label, getSettingsTable).
-- The running core is _G.VoidLayerCore (nil on retail, or before PLAYER_LOGIN).
--
-- The game has no layer API and no "go to layer X". Your layer is read from nearby NPC GUIDs
-- (Layer.lua), and you move to another one by joining a group whose leader is on it
-- (measured 2026-11-08). So the network does three things, all by addon whisper (Forever
-- refuses addon messages in custom channels; the channel is only a member list):
--   1. Who's on which layer:  Q:1:ttl:zone:nonce:asker   relayed once (ttl 1) to a few more
--                             A:1:zone:pair:h            straight back to the asker; h=1 hosts
--   2. Rares:                 R:1:ttl:zone:pair:npc:hp:x:y:origin:name   relayed twice (ttl 2);
--                             hp 0 = dead. Shown in the window; a rare on ANOTHER layer of your
--                             zone pops up "Hop there?" (one click).
--   3. The hop:               HR:1:zone:pair:nonce   "please invite me"  (to a host)
--                             HA:1:nonce:ok|no:why   then the host invites you
--                             HS:1:nonce             "I'm staying grouped"
--   4. One layer, many zones:  L:1:0:zoneA:pairA:zoneB:pairB:age   never relayed; a solo zone
--                             crossing showed both ids are one layer, age s ago (section 4)
--     You accept only the invite from the host you asked, while asking; check your layer
--     changed; leave (or stay, if leaving sent you back once). One hop every 5 minutes.
-- Hosting is ON unless turned off (the user, 11-09: a hop only works when someone hosts).
-- A host only invites while solo, alive, out of combat, outside instances, on the asked
-- layer and zone, at most once every 2 minutes and 8 times an hour, and only channel members.
--
-- Channel: a new one every UTC day and per faction, with a password, both worked out from the date
-- (WhisperNet.DailyChannel), so nobody can /join it by hand, own it and /ban players, and a
-- takeover lasts a day at most. The password is in the addon's code, so it stops casual
-- griefing, not a determined one: EVERY message is treated as hostile. A message can only
-- add a short-lived census line or rare line, or ask for an invite the host checks itself.
-- Names stay in memory, never saved or shown (the host's name shows only in its invite).
----------------------------------------------------------------------
local ADDON, ns = ...
-- 2: a hop counts any move off your layer; the hop group is always left (2026-11-10)
-- 3: one channel per faction, so this core must win over an older copy's both-factions one (2026-11-10)
-- 4: layer names from the layer's own number, the same for every player (2026-11-14)
local CORE_VERSION = 4

local reg = _G.VoidLayerCoreReg or { list = {} }
_G.VoidLayerCoreReg = reg
local mine = { v = CORE_VERSION, addon = ADDON, ns = ns, prio = 0 }
table.insert(reg.list, mine)

-- The embedding addon says where the settings live (a table it saves) and what to call itself.
function ns.LayerCoreSettings(prio, label, get)
    mine.prio, mine.label, mine.settings = prio, label, get
end

local function forever() return RegionalUniqueNamesEnabled ~= nil and RegionalUniqueNamesEnabled() == true end

----------------------------------------------------------------------
-- The core (built once, by the elected copy)
----------------------------------------------------------------------
function ns.LayerCoreBuild(owner)
    local Net, Layer = ns.WhisperNet, ns.Layer
    local C = { version = CORE_VERSION, owner = owner.addon }
    local LABEL = owner.label or owner.addon

    local PREFIX        = "VLAYER"
    local DAILY_TAG, DAILY_SALT = "Vl", 58313
    local SEND_EVERY    = 0.6
    local QUEUE_MAX     = 60
    local SENDER_MAX    = 20      -- messages accepted per player per minute
    -- census
    local ASK_PEERS     = 10
    local RELAY_FANOUT  = 4
    local ASK_CD        = 120     -- one question per zone per this
    local ANSWER_WINDOW = 60      -- answers count this long after our question
    local LIVE          = 600     -- an answer counts this long
    local HOST_LIVE     = 300     -- ...and says "hosts" this long
    local REPLY_GAP     = 60      -- one answer per asker per this
    -- rares
    local RARE_FANOUT   = 8
    local RARE_RESEND   = 180     -- the finder re-sends the same rare at most this often
    local RARE_LIVE     = 600     -- a rare line stays this long (dead: DEAD_LIVE)
    local DEAD_LIVE     = 120
    local OFFER_GAP     = 600     -- "hop there?" once per rare per this
    local POPUP_GAP     = 60      -- ...and at most one "hop there?" per this, any rare
    local RARE_MAX      = 200     -- rare lines kept
    -- hop
    local ASK_WAIT      = 12
    local MOVE_WAIT     = 45
    local REVERT_WATCH  = 40
    local COOLDOWN      = 300
    local FIND_WAIT     = 6
    local HOST_GAP      = 120
    local HOUR_CAP      = 8
    local HOST_STAY     = 180
    local STAY_MAX      = 900
    local JOIN_WAIT     = 65      -- the game's invite lasts about a minute
    local LATE_JOIN     = 120     -- a guest who accepts after that is still looked after

    local function S() local t = owner.settings and owner.settings(); return type(t) == "table" and t or {} end
    local function say(msg) print(("|cff00c7ff%s|r: %s"):format(LABEL, msg)) end
    local function now() return GetTime() end
    local function secret(v) return issecretvalue and issecretvalue(v) end
    local function validPair(p) return type(p) == "string" and #p <= 20 and p:match("^%d+%-%d+$") ~= nil end
    local function validName(n) return type(n) == "string" and n ~= "" and #n <= 48 and not n:find("[|:]") end
    local function validZone(z) z = tonumber(z); return z and z > 0 and C_Map.GetMapInfo(z) and z or nil end

    local listeners = {}
    local function changed() for _, fn in ipairs(listeners) do pcall(fn) end end
    function C:OnChange(fn) listeners[#listeners + 1] = fn end

    ------------------------------------------------------------------
    -- Channel + whisper transport
    ------------------------------------------------------------------
    -- one channel per faction since 2026-11-10 (WhisperNet.lua): whispers don't cross factions
    -- and neither do hop groups. OLD = yesterday's and the old both-factions ones, to leave.
    local CHANNEL, PW, today = Net.DailyChannel(DAILY_TAG, DAILY_SALT)
    local OLD = Net.OldDailyChannels(DAILY_TAG, DAILY_SALT, today)
    -- offline marks (players whose whisper bounced): this session only, never saved (the user,
    -- 2026-11-09: "get rid of the offline list"; the README says no names are saved). After a
    -- reload the online count can include a player who just logged off until their whisper bounces.
    local offlineMarks = {}
    -- Members seen in any read of the list this session: a busy channel (over 300) is read a
    -- random window at a time, so one read isn't everyone (Sol review).
    local everPeer, everN = {}, 0
    local net
    -- "VoidLayer online" in the Void players box (PresenceBox.lua): members of the layer channel
    -- (VoidLayer players, and VoidSweep 0.2.25+ players, who share it). Only when VoidLayer runs
    -- the core: VoidSweep has its own line.
    local function publish()
        if owner.addon ~= "VoidLayer" or not _G.VoidPresence or not net then return end
        local others = net:Others()
        _G.VoidPresence:Set("VoidLayer", "VoidLayer online", others or 0, false, others ~= nil, Net.BlockNote(CHANNEL))
    end
    net = Net.New(CHANNEL, function()
        for _, n in ipairs(net and net.roster or {}) do
            if not everPeer[n] and everN < 3000 then everPeer[n] = true; everN = everN + 1 end
        end
        publish()
        changed()
    end, offlineMarks)
    if _G.VoidPresence and _G.VoidPresence.Listen then
        _G.VoidPresence:Listen(function() net:RequestRoster(true); publish() end)
    end
    -- the member list is re-read at most every 5 minutes (WhisperNet); ask now and then so the count stays current
    C_Timer.NewTicker(60, function() net:RequestRoster(); publish() end)
    local me = Net.Me()

    local function chatLocked()
        if InCombatLockdown() then return true end
        local f = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
        if not f then return false end
        local ok, v = pcall(f)
        if not ok or secret(v) then return true end
        return v == true
    end
    local function joined() local id = GetChannelName(CHANNEL); return id and id > 0 end
    local joinRetry = CreateFrame("Frame")
    local function join()
        if chatLocked() then
            for _, ev in ipairs({ "PLAYER_REGEN_ENABLED", "ZONE_CHANGED_NEW_AREA", "ENCOUNTER_END" }) do joinRetry:RegisterEvent(ev) end
            return
        end
        for _, old in ipairs(OLD) do
            if (GetChannelName(old) or 0) > 0 then LeaveChannelByName(old) end
        end
        if not joined() then JoinTemporaryChannel(CHANNEL, PW) end
        C_Timer.After(2, function()
            if joined() then
                for i = 1, (NUM_CHAT_WINDOWS or 10) do
                    local cf = _G["ChatFrame" .. i]
                    if cf and ChatFrame_RemoveChannel then ChatFrame_RemoveChannel(cf, CHANNEL) end
                end
            end
        end)
    end
    joinRetry:SetScript("OnEvent", function(self)
        if chatLocked() then return end
        self:UnregisterAllEvents()
        join()
    end)

    -- traffic this session, for /vl net: whispers the game took, refused as offline (result 12),
    -- or refused otherwise. Bounces ("No player named X") are net.bounces.
    local traffic = { sent = 0, offline = 0, refused = 0 }
    local queue, pumping = {}, nil
    local function pump()
        local item = table.remove(queue, 1)
        if not item then
            if pumping then pumping:Cancel(); pumping = nil end
            return
        end
        net:Noted(item.to)
        local result = C_ChatInfo.SendAddonMessage(PREFIX, item.msg, "WHISPER", item.to)
        local k = (result == nil or result == true or result == 0) and "sent" or result == 12 and "offline" or "refused"
        traffic[k] = traffic[k] + 1
        net:Sent(item.to, result)
    end
    local function send(msg, to, urgent)
        if not to or to == me or #queue >= QUEUE_MAX then return end
        local item = { msg = msg, to = to }
        if urgent then table.insert(queue, 1, item) else queue[#queue + 1] = item end
        if not pumping then
            pump()
            pumping = C_Timer.NewTicker(SEND_EVERY, pump)
        end
    end
    local function sendAll(msg, list, urgent) for _, n in ipairs(list) do send(msg, n, urgent) end end

    local function isPeer(name)
        if everPeer[name] then return true end
        for _, n in ipairs(net.roster or {}) do if n == name then return true end end
        return false
    end

    -- k targets: players we know are in this zone first, then random members.
    local census = {}   -- [zone] = { [name] = { pair, host, t } }
    local function targets(k, zone, skip)
        net:RequestRoster()
        local out, used = {}, { [me or ""] = true }
        if skip then for _, n in ipairs(skip) do used[n] = true end end
        if zone and census[zone] then
            for name, a in pairs(census[zone]) do
                if #out >= k then break end
                if not used[name] and now() - a.t <= LIVE and net:Reachable(name) then out[#out + 1] = name; used[name] = true end
            end
        end
        for _, name in ipairs(net:Pick(k + #out + 2)) do
            if #out >= k then break end
            if not used[name] then out[#out + 1] = name; used[name] = true end
        end
        return out
    end

    function C:Online() return net:Others() end
    function C:Channel() return CHANNEL end
    function C:BlockReason() return Net.BlockReason(CHANNEL) end

    -- /vl net: who's reachable and what our whispers did this session (bounces were invisible
    -- before 2026-11-10, when the channel still mixed factions)
    function C:NetReport()
        net:RequestRoster(true)
        C_Timer.After(3.5, function()
            local why, others = Net.BlockReason(CHANNEL), net:Others()
            if why then say("|cffff5555" .. why .. "|r")
            elseif not others then say("couldn't read the member list yet, try again in a few seconds.")
            else say(("%d other Void player%s of your faction online."):format(others, others == 1 and "" or "s")) end
            say(("this session: %d whisper%s sent, %d bounced (not reachable), %d refused as offline, %d refused otherwise.")
                :format(traffic.sent, traffic.sent == 1 and "" or "s", net.bounces, traffic.offline, traffic.refused))
        end)
    end

    ------------------------------------------------------------------
    -- Layer names, the same for every player: the layer's own number, the part after the dash
    -- ("6829-98" -> "Layer 98"). Until 2026-11-14 they were letters in the order YOU met them
    -- this session, so the same layer was "B" for the user and "G" for a guildie who had just
    -- swapped them (the user: "mine still said b"). Two layers in one zone with the same number
    -- (another server) both show the full id ("Layer 6829-98"). The full id shows in tooltips.
    ------------------------------------------------------------------
    local known = {}   -- [zone] = { [pair] = true }: the pairs met in that zone, to spot a shared number
    function C:Label(zone, pair)
        if not validPair(pair) then return pair or "?" end
        local slot = pair:match("%-(%d+)$")
        if zone then
            local z = known[zone]
            if not z then z = {}; known[zone] = z end
            z[pair] = true
            for other in pairs(z) do
                if other ~= pair and other:match("%-(%d+)$") == slot then return "Layer " .. pair end
            end
        end
        return "Layer " .. slot
    end
    function C:Here() return Layer:Here() end
    function C:Current(zone) return Layer:Current(zone) end
    function C:Zone(mapID) return Layer:Zone(mapID) end

    -- Section 4 (one layer, many zones) fills these in; the census, rares and messages call them.
    local noteSeen = function() end   -- (zone, pair): a Void player saw this layer in this zone
    local onLink, shareLinks          -- a link from a message; links to hand an asker
    local linkSharedTo = {}           -- [asker] = GetTime() we last handed them links

    ------------------------------------------------------------------
    -- 1. Who's on which layer
    ------------------------------------------------------------------
    local lastAsk, asked, seenQ, lastReplyTo = {}, {}, {}, {}

    function C:Ask(zone)
        if not zone or not forever() then return false end
        if lastAsk[zone] and now() - lastAsk[zone] < ASK_CD then return false end
        local to = targets(ASK_PEERS, zone)
        if #to == 0 then return false end
        lastAsk[zone], asked[zone] = now(), now()
        local nonce = tostring(math.random(100000, 999999))
        seenQ[nonce .. me] = now()
        sendAll(("Q:1:1:%d:%s:%s"):format(zone, nonce, me), to, true)
        return true
    end

    function C:AskLeft(zone)
        local t = zone and lastAsk[zone]
        local l = t and (ASK_CD - (now() - t)) or 0
        return l > 0 and l or 0
    end

    function C:Counts(zone)
        local out = {}
        for _, a in pairs(census[zone] or {}) do
            if now() - a.t <= LIVE then out[a.pair] = (out[a.pair] or 0) + 1 end
        end
        return out
    end

    function C:Hosts(zone, pair)
        local out = {}
        for name, a in pairs(census[zone] or {}) do
            if a.pair == pair and a.host and now() - a.t <= HOST_LIVE then out[#out + 1] = name end
        end
        return out
    end

    ------------------------------------------------------------------
    -- 2. Rares
    ------------------------------------------------------------------
    local rares = {}     -- [origin..":"..npc] = { zone, pair, npc, name, hp, x, y, origin, t }
    local sentRare = {}  -- [npc] = { t, dead }
    local offered = {}   -- [name] = GetTime()
    local RARE_CLASS = { rare = true, rareelite = true, worldboss = true }

    local rareCount = 0
    local function pruneRares()
        local n, count, oldestK, oldestT = now(), 0, nil, nil
        for k, r in pairs(rares) do
            if n - r.t > ((r.hp == 0) and DEAD_LIVE or RARE_LIVE) then
                rares[k] = nil
            else
                count = count + 1
                if not oldestT or r.t < oldestT then oldestK, oldestT = k, r.t end
            end
        end
        if count > RARE_MAX and oldestK then rares[oldestK] = nil; count = count - 1 end
        rareCount = count
    end

    -- Rares known, newest first: { npc, name, zone, pair, hp, x, y, age, origin, mineLayer }
    function C:Rares(zone)
        pruneRares()
        local out = {}
        for _, r in pairs(rares) do
            if not zone or r.zone == zone then
                local cur = Layer:Current(r.zone)
                out[#out + 1] = { npc = r.npc, name = r.name, zone = r.zone, pair = r.pair, hp = r.hp, x = r.x, y = r.y,
                                  age = now() - r.t, origin = not r.test and r.origin or nil, same = cur ~= nil and cur == r.pair }
            end
        end
        table.sort(out, function(a, b) return a.age < b.age end)
        return out
    end

    local offerRare   -- defined with the hop

    local function storeRare(zone, pair, npc, hp, x, y, origin, name, test)
        noteSeen(zone, pair)
        local key = origin .. ":" .. npc
        local old = rares[key]
        -- dead stays dead: a late "alive" (relayed slower) doesn't bring it back (Sol review)
        if old and old.hp == 0 and hp > 0 and now() - old.t < DEAD_LIVE then return false end
        if not old and rareCount >= RARE_MAX then pruneRares() end
        local fresh = not old or (old.hp == 0) ~= (hp == 0) or now() - old.t > 60
        if not old then rareCount = rareCount + 1 end
        rares[key] = { zone = zone, pair = pair, npc = npc, name = name, hp = hp, x = x, y = y, origin = origin, t = now(), test = test }
        -- a newer report of the same rare from someone else replaces nothing: both lines age out
        if fresh then changed() end
        return fresh
    end

    local function myPos(zone)
        local pos = C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(zone, "player")
        if not pos then return 0, 0 end
        local x, y = pos:GetXY()
        if not x or secret(x) then return 0, 0 end
        return math.floor(x * 1000 + 0.5), math.floor(y * 1000 + 0.5)
    end

    local function seeUnit(unit)
        if not UnitExists(unit) or UnitPlayerControlled(unit) or IsInInstance() then return end
        local cls = UnitClassification(unit)
        if secret(cls) or not RARE_CLASS[cls] then return end
        local g = UnitGUID(unit)
        if not g or secret(g) then return end
        local kind, _, server, _, shard, npc = strsplit("-", g)
        if kind ~= "Creature" then return end
        npc = tonumber(npc)
        local name = UnitName(unit)
        if not npc or secret(name) or not validName(name) then return end
        local zone = Layer:Zone(C_Map.GetBestMapForUnit("player"))
        if not zone then return end
        local pair = Layer:Current(zone) or (server and shard and server .. "-" .. shard)
        if not validPair(pair) then return end
        local dead = UnitIsDead(unit) and true or false
        local hp = 0
        if not dead then
            local h, m = UnitHealth(unit), UnitHealthMax(unit)
            hp = (not secret(h) and not secret(m) and m and m > 0) and math.max(1, math.floor(h / m * 100)) or 100
        end
        -- per rare AND layer: the same rare seen again after a hop is a new report (Sol review)
        local sk = npc .. "@" .. pair
        local s = sentRare[sk]
        if s and s.dead == dead and now() - s.t < RARE_RESEND then return end
        sentRare[sk] = { t = now(), dead = dead }
        local x, y = myPos(zone)
        storeRare(zone, pair, npc, hp, x, y, me, name)
        sendAll(("R:1:2:%d:%s:%d:%d:%d:%d:%s:%s"):format(zone, pair, npc, hp, x, y, me, name), targets(RARE_FANOUT, zone), true)
    end

    ------------------------------------------------------------------
    -- 3. The hop
    ------------------------------------------------------------------
    local state, lastHop, lastHosted, hosting, finding
    local hostedTimes = {}

    local function inGroupWith(name)
        if not (name and IsInGroup()) then return false end
        local raid = IsInRaid()
        local n = GetNumGroupMembers() or 0
        for i = 1, raid and n or n - 1 do
            local un = UnitName((raid and "raid" or "party") .. i)
            if type(un) == "string" and not secret(un) and Net.Canon(un) == name then return true end
        end
        return false
    end
    -- hopGroupUntil: a group you accepted for a hop (you were solo: the hop requires it) is yours to
    -- leave for a few minutes, even when the host's name doesn't match the party member's (first real
    -- hop, 2026-11-10: the user stayed grouped after VoidLayer gave up, most likely a name-format mismatch)
    local hopGroupUntil, hopGroupSeen = 0, false
    local function leaveHopGroup(other)
        local two = (GetNumGroupMembers() or 0) <= 2 and not IsInRaid()
        if two and (inGroupWith(other) or now() < hopGroupUntil) and C_PartyInfo and C_PartyInfo.LeaveParty then
            hopGroupUntil = 0
            C_PartyInfo.LeaveParty()
            return true
        end
        return false
    end

    function C:HostingOn() return S().hostHops ~= false end
    function C:SetHosting(on)
        S().hostHops = on and true or false
        say(("helping others change layer %s."):format(on and "|cff33ff33on|r: Void players on your layer can ask you for a quick group invite (only while you're solo and out of combat; the group ends on its own)" or "|cffff5555off|r"))
        changed()
    end
    function C:StayOn() return S().hopStay == true end
    function C:SetStay(on) S().hopStay = on and true or false; changed() end
    function C:PopupsOn() return S().rarePopups ~= false end
    function C:SetPopups(on) S().rarePopups = on and true or false; changed() end

    local function hostedLastHour()
        local n = 0
        for i = #hostedTimes, 1, -1 do
            if now() - hostedTimes[i] > 3600 then table.remove(hostedTimes, i) else n = n + 1 end
        end
        return n
    end
    function C:CanHost()
        -- never while your own hop is under way: two invites at once (Sol review)
        return self:HostingOn() and not hosting and not state and not finding
            and not IsInGroup() and not InCombatLockdown() and not IsInInstance()
            and not UnitIsDeadOrGhost("player")
            and not (lastHosted and now() - lastHosted < HOST_GAP)
            and hostedLastHour() < HOUR_CAP
    end
    function C:CooldownLeft()
        local l = lastHop and (COOLDOWN - (now() - lastHop)) or 0
        return l > 0 and l or 0
    end
    function C:Busy() return state ~= nil or finding == true end
    -- Why you can't hop right now (nil = you can).
    function C:Blocked()
        if not forever() then return "Layers are a WoW Forever thing." end
        if state or finding then return "A hop is under way." end
        if hosting then return "Bringing another Void player over right now; a moment." end
        if InCombatLockdown() then return "In combat." end
        if IsInInstance() then return "Not inside a dungeon or raid." end
        if IsInGroup() then return "In a group: leave it to hop (moving a whole group comes later)." end
        local cd = self:CooldownLeft()
        if cd > 0 then return ("Next hop in %d:%02d (one every 5 minutes)."):format(math.floor(cd / 60), math.floor(cd % 60)) end
    end

    function C:Status()
        if finding then return "Looking for a Void player on that layer..." end
        if not state then return nil end
        local p = self:Label(state.zone, state.pair)
        if state.phase == "asking" then return ("Asking a Void player on %s to invite you..."):format(p) end
        if state.phase == "joined" then return ("In their group: checking you moved to %s..."):format(p) end
        if state.phase == "retrying" then return "That didn't move you: trying another player..." end
        if state.phase == "left" then return ("On %s. Left the group; making sure you stay."):format(p) end
        return "Hopping..."
    end

    local function stop(msg)
        if msg then say(msg) end
        if state and state.timer then state.timer:Cancel() end
        state = nil
        changed()
    end
    local function setTimer(sec, fn)
        if state.timer then state.timer:Cancel() end
        state.timer = C_Timer.NewTimer(sec, fn)
    end

    local nextHost
    local function moved()
        lastHop = now()
        -- the host is on the layer you landed on, whatever they reported before (2026-11-10: host said
        -- B, you landed on C, and the window kept listing them on B)
        local c = census[state.zone] and census[state.zone][state.host]
        if c then c.pair = state.pair end
        say(("you're on |cffffd200%s|r now."):format(C:Label(state.zone, state.pair)))
        if C:StayOn() and not state.test then   -- a test always leaves (Sol review)
            send(("HS:1:%s"):format(state.nonce), state.host, true)
            stop("staying in the group so you keep this layer (it lasts up to 15 minutes); leave it when you're done.")
            return
        end
        state.phase = "left"
        local host = state.host
        C_Timer.After(3, function() leaveHopGroup(host) end)
        setTimer(REVERT_WATCH, function() stop() end)
        changed()
    end

    Layer:OnChange(function(pair, zone)
        C:Label(zone, pair)
        if state and zone == state.zone then
            -- In the host's group, ANY move off the layer you came from is the hop: joining puts you on
            -- the group's layer, and the layer the host reported can be stale. First real hop (the user,
            -- 2026-11-10, The Barrens): A 7054-28 -> joined -> 7054-29 at once, but the host had reported
            -- another id ("Layer B"), so the check waited for B, never finished and never left the group.
            if state.phase == "joined" and pair ~= state.from then
                state.pair = pair
                moved()
            elseif state.phase == "left" and pair ~= state.pair then
                S().hopStay = true
                stop("leaving the group sent you back, so from now on a hop keeps you in the group (Stay grouped, in the window).")
            end
        end
        changed()
    end)

    local function checkMove()
        if not (state and state.phase == "joined") then return end
        local cur = Layer:Current(state.zone)
        if cur and cur ~= state.from then
            state.pair = cur   -- moved off your layer: that's the hop, whatever id the host reported
            moved()
        elseif state.anyPair and cur then
            local host = state.host
            stop(("test: you joined but stayed on %s, so %s was on your layer already. Leaving the group."):format(C:Label(state.zone, cur), host))
            leaveHopGroup(host)
        elseif cur then
            say(("joined, but you're still on %s. Trying another player."):format(C:Label(state.zone, cur)))
            state.phase = "retrying"
            leaveHopGroup(state.host)
            C_Timer.After(2, function() if state and state.phase == "retrying" then nextHost() end end)
        elseif not state.extended then
            state.extended = true
            say("point at or target any NPC so your new layer can be read.")
            setTimer(MOVE_WAIT, checkMove)
        else
            local host = state.host
            stop("couldn't confirm the move (no NPC seen), so you're leaving the group.")
            leaveHopGroup(host)
        end
    end

    nextHost = function()
        if not state then return end
        state.idx = state.idx + 1
        local h = state.hosts[state.idx]
        if not h then
            stop("nobody on that layer could bring you over right now. Try again in a bit.")
            return
        end
        state.host, state.pair, state.phase, state.extended, state.seenHost = h.name, h.pair, "asking", nil, nil
        state.nonce = tostring(math.random(100000, 999999))
        send(("HR:1:%d:%s:%s"):format(state.zone, state.pair, state.nonce), h.name, true)
        local asked1 = h.name
        setTimer(ASK_WAIT, function()
            if state and state.phase == "asking" and state.host == asked1 then nextHost() end
        end)
        changed()
    end

    -- Hop to a layer in your zone. pair nil = any other layer. prefer = a player to ask first
    -- (the one who saw the rare). isRetry: internal (after asking around).
    function C:Start(pair, expectZone, prefer, isRetry)
        if finding and not isRetry then say("still looking for a Void player there; one moment.") return end
        local why = self:Blocked()
        if why then
            if not isRetry then say(why) end   -- a retry that can't go ahead (combat since) stays quiet
            changed()
            return
        end
        local cur, zone = Layer:Here()
        if not zone then say("no zone here.") return end
        if expectZone and zone ~= expectZone then say("you've left that zone, so that hop no longer applies.") return end
        if not cur then say("your layer isn't known yet: point at or target any NPC, then try again.") return end
        if pair == cur then say("you're already on that layer.") return end
        local hosts, used = {}, {}
        local function add(name, p)
            if name and name ~= me and not used[name] and p ~= cur and (not pair or p == pair) then
                used[name] = true
                hosts[#hosts + 1] = { name = name, pair = p }
            end
        end
        -- the rare's finder first, then players who said they host, then other rare finders there
        if prefer and pair then add(prefer, pair) end
        local known = {}
        for p in pairs(self:Counts(zone)) do
            for _, n in ipairs(self:Hosts(zone, p)) do known[#known + 1] = { n, p } end
        end
        for i = #known, 2, -1 do local j = math.random(i); known[i], known[j] = known[j], known[i] end
        for _, k in ipairs(known) do add(k[1], k[2]) end
        pruneRares()
        for _, r in pairs(rares) do if r.zone == zone and r.hp > 0 and not r.test then add(r.origin, r.pair) end end
        if #hosts == 0 then
            if not isRetry and self:Ask(zone) then
                finding = true
                changed()
                C_Timer.After(FIND_WAIT, function()
                    finding = nil
                    C:Start(pair, zone, prefer, true)
                end)
                return
            end
            -- Known players there who answered "can't host" (in a group, in combat, dead, just hosted, or Help
            -- others off): say so, else "Hop" looks broken (the user, 2026-11-10, Orgrimmar: Refresh showed
            -- 1 player on another layer, Hop said nobody was there).
            local busy = 0
            for p, n in pairs(self:Counts(zone)) do
                if p ~= cur and (not pair or p == pair) then busy = busy + n end
            end
            if busy > 0 then
                say(("the Void player%s on %s can't bring anyone over right now (in a group, in combat, or Help others is off). Refresh in a few minutes and try again.")
                    :format(busy == 1 and "" or "s", pair and "that layer" or "the other layer"))
            else
                say(("no Void player who can bring you over is on %s in this zone right now. Try again in a few minutes.")
                    :format(pair and "that layer" or "another layer"))
            end
            changed()
            return
        end
        state = { zone = zone, from = cur, hosts = hosts, idx = 0 }
        say(("asking a Void player on %s to bring you over..."):format(pair and self:Label(zone, pair) or "another layer"))
        nextHost()
    end

    local lateGuest   -- { name, nonce, t }: invited but didn't come in time (the invite may still be open)
    local function endHosting(leave)
        if not hosting then return end
        local guest = hosting.guest
        if not hosting.joined then lateGuest = { name = guest, nonce = hosting.nonce, t = now() } end
        hosting = nil
        if leave and leaveHopGroup(guest) then say("left the layer-hop group.") end
    end

    ------------------------------------------------------------------
    -- Incoming messages
    ------------------------------------------------------------------
    local bucket = {}
    local function rateOK(who)
        local b = bucket[who]
        if not b or now() - b.start > 60 then b = { n = 0, start = now() }; bucket[who] = b end
        b.n = b.n + 1
        return b.n <= SENDER_MAX
    end

    local function relay(msg, ttl, who, extraSkip, k)
        if ttl < 1 then return end
        sendAll(msg, targets(k or RELAY_FANOUT, nil, { who, extraSkip }), false)
    end

    local function onMessage(msg, who)
        local tag = msg:match("^(%u%u?):1:")
        if tag == "Q" then
            local ttl, zoneS, nonce, asker = msg:match("^Q:1:(%d):(%d+):(%d+):(.+)$")
            local zone = validZone(zoneS)
            ttl = tonumber(ttl)
            if not (zone and ttl and ttl <= 1 and validName(asker)) or asker == me then return end
            if not isPeer(who) then return end
            -- a first-hand question is from the asker itself; a relayed one names a channel member
            -- (Sol review: else anyone could make us whisper any name)
            if ttl == 1 and asker ~= who then return end
            if ttl == 0 and not isPeer(asker) then return end
            local key = nonce .. asker
            if seenQ[key] then return end
            seenQ[key] = now()
            if ttl > 0 then relay(("Q:1:%d:%d:%s:%s"):format(ttl - 1, zone, nonce, asker), ttl, who, asker) end
            -- the layer links we know for that zone, wherever we stand (section 4), once per asker per ASK_CD
            if shareLinks and not (linkSharedTo[asker] and now() - linkSharedTo[asker] < ASK_CD) then
                linkSharedTo[asker] = now()
                shareLinks(asker, zone)
            end
            if IsInInstance() then return end
            local cur, here = Layer:Here()
            if not cur or here ~= zone then return end
            if lastReplyTo[asker] and now() - lastReplyTo[asker] < REPLY_GAP then return end
            lastReplyTo[asker] = now()
            send(("A:1:%d:%s:%d"):format(zone, cur, C:CanHost() and 1 or 0), asker, true)
        elseif tag == "A" then
            local zoneS, pair, h = msg:match("^A:1:(%d+):(%d+%-%d+):([01])$")
            local zone = validZone(zoneS)
            if not (zone and validPair(pair)) then return end
            if not (asked[zone] and now() - asked[zone] <= ANSWER_WINDOW) or not isPeer(who) then return end
            census[zone] = census[zone] or {}
            census[zone][who] = { pair = pair, host = h == "1", t = now() }
            C:Label(zone, pair)
            noteSeen(zone, pair)
            changed()
        elseif tag == "R" then
            local ttl, zoneS, pair, npc, hp, x, y, origin, name =
                msg:match("^R:1:(%d):(%d+):(%d+%-%d+):(%d+):(%d+):(%d+):(%d+):([^:]+):(.+)$")
            local zone = validZone(zoneS)
            ttl, npc, hp, x, y = tonumber(ttl), tonumber(npc), tonumber(hp), tonumber(x), tonumber(y)
            if not (zone and ttl and ttl <= 2 and validPair(pair) and npc and npc < 10000000 and hp and hp <= 100
                    and x and x <= 1000 and y and y <= 1000 and validName(origin) and validName(name)) then return end
            if origin == me or not isPeer(who) then return end
            if storeRare(zone, pair, npc, hp, x, y, origin, name) then
                if ttl > 0 then
                    relay(("R:1:%d:%d:%s:%d:%d:%d:%d:%s:%s"):format(ttl - 1, zone, pair, npc, hp, x, y, origin, name), ttl, who, origin)
                end
                C:Label(zone, pair)
                if hp > 0 then offerRare(name, zone, pair, origin, x, y, npc) end
            end
        elseif tag == "L" then
            -- one layer's ids in two zones (section 4): the sender vouches for it, seen `age` s ago;
            -- never relayed (a griefer's word reaches only who they whisper)
            local za, pa, zb, pb, age = msg:match("^L:1:0:(%d+):(%d+%-%d+):(%d+):(%d+%-%d+):(%d+)$")
            za, zb, age = validZone(za), validZone(zb), tonumber(age)
            if not (za and zb and za ~= zb and validPair(pa) and validPair(pb) and age and age <= 3 * 3600) then return end
            if not isPeer(who) or not onLink then return end
            onLink(za, pa, zb, pb, who, now() - age)
        elseif tag == "HR" then
            local zoneS, pair, nonce = msg:match("^HR:1:(%d+):(%d+%-%d+):(%d+)$")
            if not (nonce and validPair(pair)) or not isPeer(who) then return end
            local function reply(txt) send(("HA:1:%s:%s"):format(nonce, txt), who, true) end
            if not C:HostingOn() then reply("no:off") return end
            if not C:CanHost() then reply("no:busy") return end
            local cur, zone = Layer:Here()
            if zone ~= tonumber(zoneS) or cur ~= pair then reply("no:layer") return end
            lastHosted = now()
            hostedTimes[#hostedTimes + 1] = lastHosted
            hosting = { guest = who, nonce = nonce, invited = now(), deadline = now() + HOST_STAY }
            C_PartyInfo.InviteUnit(who)
            reply("ok")
            say(("inviting %s to bring them to your layer (a layer hop; the group ends on its own)."):format(who))
        elseif tag == "HS" then
            local nonce = msg:match("^HS:1:(%d+)$")
            if hosting and hosting.guest == who and nonce == hosting.nonce and inGroupWith(who) then
                hosting.deadline = hosting.invited + STAY_MAX
                say(("%s stays in the group to keep your layer (up to 15 minutes); leave any time."):format(who))
            end
        elseif tag == "HA" then
            local nonce, answer = msg:match("^HA:1:(%d+):(.+)$")
            if not (state and state.phase == "asking" and who == state.host and nonce == state.nonce) then return end
            if answer ~= "ok" then nextHost() end
        end
    end

    ------------------------------------------------------------------
    -- "Hop there?" for a rare on another layer of your zone; a line in chat for one on yours
    -- (only when VoidLayer itself runs the core: VoidSweep shows its own rare alerts).
    ------------------------------------------------------------------
    StaticPopupDialogs.VOIDLAYER_HOP = {
        text = "%s",
        button1 = "Hop there", button2 = CANCEL,
        OnAccept = function(_, d) if d then C:Start(d.pair, d.zone, d.prefer) end end,
        timeout = 60, whileDead = false, hideOnEscape = true, preferredIndex = 3,
    }
    local function canOffer()
        return C:PopupsOn() and not C:Blocked()
    end
    local lastPopup
    offerRare = function(name, zone, pair, origin, x, y, npc)
        local cur, here = Layer:Here()
        if not cur then return end
        -- once per rare (by NPC id when known: a name is whatever the message says, Sol review)
        local okey = tostring(npc or name) .. "@" .. zone
        if offered[okey] and now() - offered[okey] < OFFER_GAP then return end
        if here ~= zone then
            -- another zone, but YOUR layer there (section 4's links): walk over, no hop
            if owner.addon == "VoidLayer" and C:PopupsOn() and C.OnMyLayer and C:OnMyLayer(zone, pair) == true then
                offered[okey] = now()
                local info = C_Map.GetMapInfo(zone)
                local at = (x > 0 or y > 0) and (" near %.0f, %.0f"):format(x / 10, y / 10) or ""
                say(("|cffffd200%s|r is up in %s%s, on your layer: walk over, no hop needed."):format(name, info and info.name or "the next zone", at))
            end
            return
        end
        if cur == pair then
            if owner.addon == "VoidLayer" and C:PopupsOn() then
                offered[okey] = now()
                local at = (x > 0 or y > 0) and (" near %.0f, %.0f"):format(x / 10, y / 10) or ""
                say(("|cffffd200%s|r is up on your layer%s."):format(name, at))
            end
            return
        end
        if not canOffer() then return end
        if lastPopup and now() - lastPopup < POPUP_GAP then return end
        lastPopup = now()
        offered[okey] = now()
        StaticPopup_Show("VOIDLAYER_HOP",
            ("%s: |cffffd200%s|r is up on %s.\nA Void player there can bring you over. Hop there?"):format(LABEL, name, C:Label(zone, pair)),
            nil, { pair = pair, zone = zone, prefer = origin })
    end
    -- Other addons (VoidSweep sightings): offer the hop if anyone there can host.
    function C:Offer(name, zone, pair)
        if not (name and zone and validPair(pair)) then return end
        if #self:Hosts(zone, pair) == 0 then
            local found
            for _, r in pairs(rares) do if r.zone == zone and r.pair == pair and r.hp > 0 then found = true break end end
            if not found then return end
        end
        offerRare(name, zone, pair, nil, 0, 0)
    end

    ------------------------------------------------------------------
    -- 4. Your layer, zone to zone (2026-11-14). Each zone gives you its own id: five solo crossings
    -- Barrens <-> Ashenvale were ALWAYS Barrens 6831-88 / Ashenvale 6829-98 (VoidDev's log), and
    -- a world refresh changes only the zone you're in (Ashenvale 98 -> 100, the Barrens stayed 88).
    -- So the game keeps YOUR id per zone: a SOLO crossing with no refresh, no loading screen and no
    -- hop links your two ids:
    --   L:1:0:zoneA:pairA:zoneB:pairB:age    age = seconds since the crossing that showed it
    -- Sent to a few Void players, never relayed. Every message is hostile (Sol review, 11-14), so:
    --   * only your own crossings are sure ("your layer, walk over"); another player's link is true
    --     for THEM, so it's a hint, however many send it; only your own links are passed on (to a
    --     census asker, with their age)
    --   * a link keeps the time it was SEEN, not received, so passing it around doesn't renew it;
    --     it ages out after LINK_LIVE (ids get reused)
    --   * a layer has one id per zone: your own crossing replaces a different id in that zone, and
    --     a zone the links give two ids for is left out (contradiction = say nothing)
    -- What you get: your layer's ids in other zones, a rare next door on YOUR layer ("walk over"),
    -- and the layers Void players have seen in a zone lately (readings, answers, rares, links).
    ------------------------------------------------------------------
    local LINK_LIVE    = 3 * 3600   -- a link counts this long after the crossing that showed it
    local LINK_FANOUT  = 6
    local LINK_SHARE   = 4          -- links handed to an asker
    local LINK_MAX     = 400        -- ids kept
    local BY_MAX       = 8          -- reporters kept per link
    local CROSS_GAP    = 90         -- the old zone's layer was read at most this long before the new one
    local LINK_CONFIRM = 10         -- the new zone's id has to hold this long (a border NPC can be read first)
    local SEEN_WINDOW  = 1800       -- "layers seen in this zone": the last 30 minutes

    -- [node][node] = { own = t, by = { [player] = t } }, both ways; node = "zone:pair"; t = when seen
    local links = {}
    local seenIds = {}   -- [zone][pair] = t
    local function node(zone, pair) return zone .. ":" .. pair end
    local function unnode(k) local z, p = k:match("^(%d+):(%d+%-%d+)$"); return tonumber(z), p end

    local function edgeTime(e)
        -- not 0: GetTime() is seconds since the game started, so a link seen before that is negative
        local t = e.own or -math.huge
        for _, bt in pairs(e.by) do if bt > t then t = bt end end
        return t
    end
    local function alive(e) return now() - edgeTime(e) <= LINK_LIVE end
    -- the time of your own crossing: what gets passed on (only your own links are), so passing a
    -- link around never renews it (Sol review)
    local function sureTime(e) return e.own or -math.huge end
    -- Sure = YOUR OWN crossing only (live 11-14: a refresh moved Ashenvale 98 -> 100 while the
    -- Barrens stayed 88, so the game keeps each player's id per zone; another player's crossing is
    -- true for them, not necessarily for you, however many agree). Others' links are hints.
    local function sure(e)
        return e.own ~= nil and now() - e.own <= LINK_LIVE
    end

    -- t = when it was seen (a link's crossing time, not when the message came; Sol review)
    noteSeen = function(zone, pair, t)
        if not (zone and validPair(pair)) then return end
        t = math.min(t or now(), now())
        if now() - t > SEEN_WINDOW then return end
        local z = seenIds[zone]
        if not z then z = {}; seenIds[zone] = z end
        z[pair] = math.max(z[pair] or -math.huge, t)
    end

    local function dropNode(k)
        for b in pairs(links[k] or {}) do if links[b] then links[b][k] = nil end end
        links[k] = nil
    end
    local function pruneLinks()
        local n = 0
        for a, t in pairs(links) do
            for b, e in pairs(t) do
                for who, bt in pairs(e.by) do if now() - bt > LINK_LIVE then e.by[who] = nil end end
                if e.own and now() - e.own > LINK_LIVE then e.own = nil end
                if not e.own and not next(e.by) then t[b] = nil end
            end
            if next(t) then n = n + 1 else links[a] = nil end
        end
        -- too many ids (a flood): drop the stalest
        while n > LINK_MAX do
            local oldK, oldT
            for a, t in pairs(links) do
                for _, e in pairs(t) do local et = edgeTime(e); if not oldT or et < oldT then oldK, oldT = a, et end end
            end
            if not oldK then break end
            dropNode(oldK)
            n = n - 1
        end
        for zone, z in pairs(seenIds) do
            for p, t in pairs(z) do if now() - t > SEEN_WINDOW then z[p] = nil end end
            if not next(z) then seenIds[zone] = nil end
        end
    end

    -- A link between a's id in its zone and b's. who = nil: your own crossing (sure, and it replaces
    -- any other id for that zone); else the player who sent it, seen at time t. True when it's new.
    local function addLink(za, pa, zb, pb, who, t)
        if za == zb or not (validPair(pa) and validPair(pb)) then return false end
        t = math.min(t or now(), now())
        local a, b = node(za, pa), node(zb, pb)
        local function put(x, y, zy)
            local tx = links[x]
            if not tx then tx = {}; links[x] = tx end
            if not who then
                -- what you saw yourself wins: another id for that zone is stale or wrong
                for k in pairs(tx) do
                    if k ~= y and unnode(k) == zy then
                        tx[k] = nil
                        if links[k] then links[k][x] = nil end
                    end
                end
            end
            local e = tx[y]
            local was = e ~= nil
            if not e then e = { by = {} }; tx[y] = e end
            if who then
                e.by[who] = math.max(e.by[who] or -math.huge, t)   -- not 0: times can be negative (edgeTime)
                local n, oldW, oldT = 0, nil, nil
                for w, bt in pairs(e.by) do n = n + 1; if not oldT or bt < oldT then oldW, oldT = w, bt end end
                if n > BY_MAX and oldW then e.by[oldW] = nil end
            else
                e.own = t
            end
            return not was
        end
        local fresh = put(a, b, zb)
        put(b, a, za)
        noteSeen(za, pa, t); noteSeen(zb, pb, t)
        if fresh then changed() end
        return fresh
    end
    onLink = function(za, pa, zb, pb, who, t) return addLink(za, pa, zb, pb, who, t) end

    -- ids reachable from start over live links (sure ones only, or all), never through a bad id
    -- (the whole store fits: LINK_MAX ids; cut short = second return true, then nothing is sure)
    local function reach(start, sureOnly, bad)
        local seen, queue, n = { [start] = true }, { start }, 0
        while #queue > 0 and n < LINK_MAX * 2 do
            local k = table.remove(queue, 1)
            for o, e in pairs(links[k] or {}) do
                if not seen[o] and not (bad and bad[o]) and alive(e) and (not sureOnly or sure(e)) then
                    seen[o] = true
                    queue[#queue + 1] = o
                    n = n + 1
                end
            end
        end
        return seen, #queue > 0
    end

    -- This layer's ids in other zones: { { zone, pair, sure }, ... }. sure = every link on the way
    -- is your own crossing (others' links: hints); a zone with two ids is left out.
    function C:SameLayer(zone, pair)
        local out = {}
        if not (zone and validPair(pair)) then return out end
        local start = node(zone, pair)
        -- a zone the links give two ids for (one of them may be your own zone) is a contradiction:
        -- those ids are bad, and nothing is followed THROUGH them either (Sol review: a stale branch
        -- could still certify a zone further on). Repeat until no new contradiction shows up.
        -- One SURE id against unsure ones: the unsure ones go (one griefer can't silence a zone).
        local bad, cut, settled = {}, false, false
        for _ = 1, 5 do
            local allSet, c1 = reach(start, false, bad)
            local sureSet, c2 = reach(start, true, bad)
            cut = cut or c1 or c2
            local perZone, grew = {}, false
            for k in pairs(allSet) do
                local z = unnode(k)
                if z then perZone[z] = perZone[z] or {}; perZone[z][#perZone[z] + 1] = k end
            end
            for z, ks in pairs(perZone) do
                if #ks > 1 or (z == zone and ks[1] ~= start) then
                    local sures = {}
                    for _, k in ipairs(ks) do if sureSet[k] and k ~= start then sures[#sures + 1] = k end end
                    local keep = (z ~= zone and #sures == 1) and sures[1] or nil
                    for _, k in ipairs(ks) do
                        if k ~= start and k ~= keep and not bad[k] then bad[k] = true; grew = true end
                    end
                end
            end
            if not grew then settled = true break end
        end
        local sureSet, c1 = reach(start, true, bad)
        local allSet, c2 = reach(start, false, bad)
        -- cut short (a flood) or still contradicting after 5 rounds: show what's there, none of it sure
        local trust = settled and not (cut or c1 or c2)
        for k in pairs(allSet) do
            local z, p = unnode(k)
            if z and z ~= zone then out[#out + 1] = { zone = z, pair = p, sure = trust and sureSet[k] and true or false } end
        end
        return out
    end

    -- Is that zone's id your layer? true (your own crossing), "maybe" (another player's link), or false
    function C:OnMyLayer(zone, pair)
        local cur, here = Layer:Here()
        if not (cur and here) then return false end
        if here == zone then return cur == pair end
        for _, x in ipairs(self:SameLayer(here, cur)) do
            if x.zone == zone and x.pair == pair then return x.sure and true or "maybe" end
        end
        return false
    end

    -- Rares up in OTHER zones on your layer (your own crossings only), newest first (C:Rares fields + nextDoor)
    function C:RaresNextDoor()
        local cur, here = Layer:Here()
        if not (cur and here) then return {} end
        local mine = {}
        for _, x in ipairs(self:SameLayer(here, cur)) do mine[node(x.zone, x.pair)] = x.sure end
        local out = {}
        if not next(mine) then return out end
        for _, r in ipairs(self:Rares()) do
            local s = mine[node(r.zone, r.pair)]
            if r.zone ~= here and r.hp > 0 and s == true then
                r.nextDoor, r.sure = true, s
                out[#out + 1] = r
            end
        end
        return out
    end

    -- Layers Void players have seen in a zone in the last 30 minutes: count, { pair = t }
    function C:LayersSeen(zone)
        local list, n = {}, 0
        for p, t in pairs(seenIds[zone] or {}) do
            if now() - t <= SEEN_WINDOW then list[p] = t; n = n + 1 end
        end
        return n, list
    end

    -- links to hand an asker in a zone: the freshest SURE ones with an end there, with their age
    shareLinks = function(asker, zone)
        local picks = {}
        for a, t in pairs(links) do
            local za, pa = unnode(a)
            if za == zone then
                for b, e in pairs(t) do
                    local zb, pb = unnode(b)
                    if zb and alive(e) and sure(e) then picks[#picks + 1] = { za, pa, zb, pb, sureTime(e) } end
                end
            end
        end
        table.sort(picks, function(x, y) return x[5] > y[5] end)
        for i = 1, math.min(LINK_SHARE, #picks) do
            local p = picks[i]
            send(("L:1:0:%d:%s:%d:%s:%d"):format(p[1], p[2], p[3], p[4], math.floor(now() - p[5])), asker, false)
        end
    end

    -- Your own crossings. trail = where your layer was last confirmed (every 5 s, solo only); a new
    -- zone's first id within CROSS_GAP of it, with nothing in between that moves you, is the same layer.
    local trail
    local lastGroupT, lastTaintT, lastZoneT, cancelT = 0, 0, 0, 0
    -- A world refresh may move you until refreshUntil (its countdown + a minute): no links before then.
    -- Set from the game's own countdown, so a /reload or a zone change during it keeps it (Sol review).
    local refreshUntil = 0
    -- only ever moves it later: no countdown (or none given) keeps what we had (Sol review);
    -- a cancel ends it, and an expired one simply passes
    local function readCountdown()
        local left = GetEvictionTimeRemaining and GetEvictionTimeRemaining()
        if type(left) == "number" and left > 0 then refreshUntil = math.max(refreshUntil, now() + left + 60) end
    end
    readCountdown()
    C_Timer.NewTicker(5, function()
        pruneLinks()
        if IsInInstance() or IsInGroup() then trail = nil return end
        local cur, zone = Layer:Here()
        if cur and zone then
            trail = { zone = zone, pair = cur, t = now() }
            noteSeen(zone, cur)
        end
    end)
    -- solo only: in a group, a leader change can move you without the group's size changing (Sol review)
    local function clean(since)
        return lastGroupT < since and lastTaintT < since and not state and now() >= refreshUntil and not IsInGroup()
    end
    -- Your id in a zone is `pair` now: your own links to any OTHER id of that zone are stale (a refresh
    -- moved you there: Ashenvale 98 -> 100). They stop being sure; what others sent stays a hint (Sol review).
    local function forgetOwn(zone, pair)
        local keep = node(zone, pair)
        for k, t in pairs(links) do
            if k ~= keep and unnode(k) == zone then
                for o, e in pairs(t) do
                    if e.own then
                        e.own = nil
                        local back = links[o] and links[o][k]
                        if back then back.own = nil end
                        if not next(e.by) then
                            t[o] = nil
                            if links[o] then links[o][k] = nil end
                        end
                    end
                end
            end
        end
    end

    Layer:OnChange(function(pair, zone)
        noteSeen(zone, pair)
        if zone and validPair(pair) and not IsInInstance() then forgetOwn(zone, pair) end
        local tr = trail
        if not (tr and zone and validPair(pair)) or zone == tr.zone or IsInInstance() then return end
        trail = { zone = zone, pair = pair, t = now() }
        local since = tr.t - 1
        if now() - tr.t > CROSS_GAP or not clean(since) then return end
        C_Timer.After(LINK_CONFIRM, function()
            if Layer:Current(zone) ~= pair or not clean(since) then return end
            if addLink(tr.zone, tr.pair, zone, pair) then
                sendAll(("L:1:0:%d:%s:%d:%s:0"):format(tr.zone, tr.pair, zone, pair), targets(LINK_FANOUT, zone), false)
            end
        end)
    end)
    local lf = CreateFrame("Frame")
    for _, ev in ipairs({ "SHARD_TRANSFER_IMMINENT", "SHARD_TRANSFER_CANCELLED", "SHARD_TRANSFER",
                          "ZONE_CHANGED_NEW_AREA", "GROUP_ROSTER_UPDATE", "PARTY_LEADER_CHANGED", "PLAYER_ENTERING_WORLD" }) do
        pcall(lf.RegisterEvent, lf, ev)
    end
    lf:SetScript("OnEvent", function(_, ev)
        if ev == "SHARD_TRANSFER_IMMINENT" then
            readCountdown()
            if refreshUntil < now() then refreshUntil = now() + 660 end   -- no countdown given: the usual 10 min
        elseif ev == "SHARD_TRANSFER_CANCELLED" then
            refreshUntil, cancelT = 0, now()   -- "Refresh Now" cancels the countdown, then moves you
        elseif ev == "SHARD_TRANSFER" then
            -- every zone change fires it too and keeps your layer (live 11-14); a world refresh moves
            -- you: one announced, one just cancelled by Refresh Now, or one far from a zone change
            if now() < refreshUntil or now() - cancelT < 5 or now() - lastZoneT > 15 then lastTaintT = now() end
            if now() - lastZoneT > 15 then
                refreshUntil = 0   -- not a zone change: that WAS the refresh (the move itself is tainted above)
            else
                readCountdown()    -- a zone change during the countdown leaves it running
            end
        elseif ev == "ZONE_CHANGED_NEW_AREA" then
            lastZoneT = now()
        elseif ev == "PLAYER_ENTERING_WORLD" then
            lastTaintT = now()   -- a login, /reload or loading screen (boat, zeppelin, portal)
        else
            lastGroupT = now()   -- any roster or leader change
        end
    end)

    ------------------------------------------------------------------
    -- Tests (/vl test ...): each half of a hop with a player who doesn't run VoidLayer and
    -- sends or accepts the invite by hand (the user, 11-09: "no one will install a zip").
    ------------------------------------------------------------------
    -- You: wait for that player's invite, accept only it, see whether your layer changed, leave.
    function C:TestJoin(name)
        if not validName(name) then say("test join: whose invite? /vl test join First Surname (or target them).") return end
        local why = self:Blocked()
        if why then say(why) return end
        local cur, zone = Layer:Here()
        if not (zone and cur) then say("your layer isn't known yet: point at or target any NPC, then try again.") return end
        state = { zone = zone, from = cur, hosts = {}, idx = 0, host = name, phase = "asking", nonce = "0",
                  anyPair = true, test = true }
        setTimer(120, function()
            if state and state.test and state.phase == "asking" then stop(("test: no invite from %s within 2 minutes."):format(name)) end
        end)
        say(("test: you're on %s. Ask %s to invite you now (within 2 minutes): VoidLayer accepts only that invite, checks your layer and leaves the group."):format(self:Label(zone, cur), name))
        changed()
    end

    -- Host: invite that player as a hop host would; leave the group 60 s after they join.
    function C:TestHost(name)
        if not validName(name) then say("test host: invite whom? /vl test host First Surname (or target them).") return end
        if hosting or state or IsInGroup() or InCombatLockdown() or IsInInstance() then
            say("test host: be solo, out of combat and outside instances, with no hop under way.") return
        end
        lastHosted = now()
        hostedTimes[#hostedTimes + 1] = lastHosted
        hosting = { guest = name, nonce = "0", invited = now(), deadline = now() + JOIN_WAIT + 60, testStay = 60 }
        C_PartyInfo.InviteUnit(name)
        say(("test: invited %s the way a hop host does. Once they accept, you leave the group by yourself within about a minute."):format(name))
    end

    -- A made-up rare on a made-up layer of your zone: the pop-up and the window's rare list.
    function C:TestRare()
        local cur, zone = Layer:Here()
        if not (zone and cur) then say("your layer isn't known yet: point at or target any NPC, then try again.") return end
        local fake = "9999-" .. math.random(10, 99)
        storeRare(zone, fake, 999999, 80, 500, 500, "VoidLayerTest", "Test Rare", true)
        offered["999999@" .. zone], lastPopup = nil, nil
        offerRare("Test Rare", zone, fake, nil, 500, 500, 999999)
        say(("test: a made-up \"Test Rare\" is up on %s. Its Hop finds nobody (that layer doesn't exist)."):format(self:Label(zone, fake)))
    end

    ------------------------------------------------------------------
    -- Chat / summary
    ------------------------------------------------------------------
    function C:Summary(zone)
        local cur = Layer:Current(zone)
        local counts = self:Counts(zone)
        local parts = {}
        if cur then
            local n = counts[cur] or 0
            parts[#parts + 1] = ("|cffffd200%s|r (you%s)"):format(self:Label(zone, cur), n > 0 and (" + " .. n .. " Void") or "")
        end
        for pair, n in pairs(counts) do
            if pair ~= cur then
                parts[#parts + 1] = ("%s: %d Void%s"):format(self:Label(zone, pair), n, #self:Hosts(zone, pair) > 0 and " |cff33ff33(hop)|r" or "")
            end
        end
        return #parts > 0 and table.concat(parts, " · ") or nil
    end

    function C:Report()
        local cur, zone = Layer:Here()
        if not zone then say("no zone here (instances have no layers to compare).") return end
        local info = C_Map.GetMapInfo(zone)
        local zname = info and info.name or "this zone"
        local sent = self:Ask(zone)
        local function show()
            local s = self:Summary(zone)
            say(s and ("layers in %s: %s"):format(zname, s) or ("no layers known in %s yet."):format(zname))
            if not cur then say("your own layer isn't known yet: point at or target any NPC.") end
        end
        if sent then say(("asking the Void players in %s..."):format(zname)); C_Timer.After(FIND_WAIT, show) else show() end
    end

    ------------------------------------------------------------------
    -- Events
    ------------------------------------------------------------------
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
    local f = CreateFrame("Frame")
    for _, ev in ipairs({ "CHAT_MSG_ADDON", "PARTY_INVITE_REQUEST", "PLAYER_REGEN_DISABLED", "GROUP_ROSTER_UPDATE",
                          "NAME_PLATE_UNIT_ADDED", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "ZONE_CHANGED_NEW_AREA" }) do
        pcall(f.RegisterEvent, f, ev)
    end
    f:SetScript("OnEvent", function(_, event, a1, a2, a3, a4)
        if event == "CHAT_MSG_ADDON" then
            if a1 ~= PREFIX or a3 ~= "WHISPER" or type(a2) ~= "string" or secret(a2) or #a2 > 255 then return end
            local who = Net.Canon(a4)
            if not who or secret(who) or who == me or not rateOK(who) then return end
            pcall(onMessage, a2, who)
        elseif event == "NAME_PLATE_UNIT_ADDED" then pcall(seeUnit, a1)
        elseif event == "PLAYER_TARGET_CHANGED" then pcall(seeUnit, "target")
        elseif event == "UPDATE_MOUSEOVER_UNIT" then pcall(seeUnit, "mouseover")
        elseif event == "ZONE_CHANGED_NEW_AREA" then changed()
        elseif event == "PLAYER_REGEN_DISABLED" then
            if state and state.phase == "asking" then stop("hop cancelled: you're in combat.") end
        elseif event == "GROUP_ROSTER_UPDATE" then
            -- the leave-without-name-match window lasts only as long as the hop's own group: once we've
            -- been in it and it's gone, a later two-person group (a friend's) is never left (Sol review)
            if hopGroupUntil > 0 then
                if IsInGroup() then hopGroupSeen = true
                elseif hopGroupSeen then hopGroupUntil, hopGroupSeen = 0, false end
            end
            if state and state.phase == "joined" then
                if inGroupWith(state.host) then state.seenHost = true
                elseif state.seenHost then stop("the group ended before the move was confirmed.") end
            end
            if hosting then
                if inGroupWith(hosting.guest) then
                    -- test host: the minute counts from the join (Sol review)
                    if not hosting.joined and hosting.testStay then hosting.deadline = now() + hosting.testStay end
                    hosting.joined = true
                elseif hosting.joined then endHosting(false) end
            elseif lateGuest and now() - lateGuest.t < LATE_JOIN and inGroupWith(lateGuest.name)
                    and (GetNumGroupMembers() or 0) <= 2 then
                -- they accepted after we stopped waiting: look after the group anyway (Sol review)
                hosting = { guest = lateGuest.name, nonce = lateGuest.nonce, invited = now(), joined = true,
                            deadline = now() + HOST_STAY }
                lateGuest = nil
            end
            changed()
        elseif event == "PARTY_INVITE_REQUEST" then
            -- accept only the invite from the player we asked, while asking
            if not (state and state.phase == "asking") then return end
            if type(a1) ~= "string" or secret(a1) or Net.Canon(a1) ~= state.host then return end
            -- still the hop you asked for: same zone, solo, no combat, no instance (Sol review)
            local _, zone = Layer:Here()
            if zone ~= state.zone or IsInGroup() or InCombatLockdown() or IsInInstance() then
                stop("hop cancelled: you've moved on since asking.")
                return
            end
            AcceptGroup()
            hopGroupUntil, hopGroupSeen = now() + MOVE_WAIT * 2 + REVERT_WATCH + 30, false   -- this group is the hop's
            C_Timer.After(0, function()
                local d = StaticPopup_FindVisible and StaticPopup_FindVisible("PARTY_INVITE")
                if d then d.inviteAccepted = 1 end
                StaticPopup_Hide("PARTY_INVITE")
            end)
            state.phase = "joined"
            setTimer(MOVE_WAIT, checkMove)
            changed()
        end
    end)

    C_Timer.NewTicker(5, function()
        if hosting then
            local n = now()
            if not hosting.joined and n - hosting.invited > JOIN_WAIT then endHosting(false)
            elseif hosting.joined and n >= hosting.deadline then endHosting(true) end
        end
        -- forget old question ids, old rares and old offers (Sol review: unbounded otherwise)
        for k, t in pairs(seenQ) do if now() - t > 300 then seenQ[k] = nil end end
        pruneRares()
        for k, t in pairs(offered) do if now() - t > OFFER_GAP then offered[k] = nil end end
        for k, s in pairs(sentRare) do if now() - s.t > RARE_RESEND then sentRare[k] = nil end end
        for k, b in pairs(bucket) do if now() - b.start > 60 then bucket[k] = nil end end
        for k, t in pairs(linkSharedTo) do if now() - t > ASK_CD then linkSharedTo[k] = nil end end
    end)

    -- join a little after login (VoidSweep 14 s, VoidGather earlier), then read the members
    C_Timer.After(18, function()
        join()
        C_Timer.After(4, function() net:RequestRoster(true) end)
    end)
    -- a new channel at 00:00 UTC
    C_Timer.NewTicker(60, function()
        local name, pw = Net.DailyChannel(DAILY_TAG, DAILY_SALT)
        if name == CHANNEL then return end
        OLD[#OLD + 1] = CHANNEL
        CHANNEL, PW = name, pw
        net:SetChannel(name)
        publish()   -- "—" until the new day's list is read
        C_Timer.After(5 + math.random() * 5, function()
            join()
            C_Timer.After(4, function() net:RequestRoster(true) end)
        end)
    end)

    -- once per character: hosting is on, and how to turn it off
    local s = S()
    if s.hostHops == nil and not s.hostNoticeShown then
        s.hostNoticeShown = true
        C_Timer.After(25, function()
            local where = owner.addon == "VoidLayer" and "the VoidLayer window (click your layer under the minimap)"
                or "the Void hub's quick switches (Help others change layer)"
            say(("you help other Void players change layer: if one on your layer asks, you send a quick group invite (only while you're solo and out of combat; the group ends on its own). Turn it off in %s."):format(where))
        end)
    end

    return C
end

----------------------------------------------------------------------
-- Election at PLAYER_LOGIN: the newest core runs, with the settings of the highest priority
----------------------------------------------------------------------
local elect = CreateFrame("Frame")
elect:RegisterEvent("PLAYER_LOGIN")
elect:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    if reg.done then return end
    reg.done = true
    if not forever() then return end
    local best, owner
    for _, c in ipairs(reg.list) do
        if not best or c.v > best.v then best = c end
        if c.settings and (not owner or c.prio > owner.prio) then owner = c end
    end
    if not (best and owner and best.ns.LayerCoreBuild) then return end
    local ok, core = pcall(best.ns.LayerCoreBuild, owner)
    if ok then
        _G.VoidLayerCore = core
        for _, fn in ipairs(reg.ready or {}) do pcall(fn, core) end
    else
        print("|cff00c7ffVoid layers|r: couldn't start: " .. tostring(core))
    end
end)

-- Run fn(core) once the core is up (right away if it already is).
function ns.OnLayerCore(fn)
    if _G.VoidLayerCore then pcall(fn, _G.VoidLayerCore) return end
    reg.ready = reg.ready or {}
    table.insert(reg.ready, fn)
end
