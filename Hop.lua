----------------------------------------------------------------------
-- VoidSweep — Hop: move to another layer through a Void host (WoW Forever)
--
-- The game has no "go to layer X": you get there by joining a group whose leader is on
-- it (measured 2026-11-08: a guild invite moved 7075-4 -> 7054-6). So:
--   you  -> host  HR:1:zone:pair:nonce        "please invite me" (a host LayerNet found on
--                                             that layer, in your zone)
--   host -> you   HA:1:nonce:ok | no:reason   then the host invites you
--   you: accept that one invite (only from the host you asked, only while asking), watch
--        your layer (Layer.lua); moved -> leave the group (or stay, below); not moved
--        within MOVE_WAIT -> leave and try the next host.
--   you  -> host  HS:1:nonce                  "I'm staying grouped" (hopStay): the host keeps
--                                             the group up to STAY_MAX instead of HOST_STAY
-- After leaving, it keeps watching: if leaving sent you back, it says so and keeps you
-- grouped on later hops (VoidSweepDB.config.hopStay; /vsw hopstay).
-- Hosting is OPT-IN (/vsw host, the Layers window or the Void hub quick box): only while
-- solo, out of combat, outside instances, on the asked layer and zone, at most once every
-- HOST_GAP, and only for members of the sharing channel. The host leaves the 2-player group
-- after HOST_STAY (STAY_MAX if the guest stays).
-- Every "leave" checks it's still THE hop group (the other player in it, 2 players): it
-- never leaves a group you've joined since (Codex Astra review 2026-11-08).
-- One hop every COOLDOWN (the game's own limit is said to be 5 minutes). Solo only for
-- now: moving a whole group (promote the host to leader) comes once that's been tested.
----------------------------------------------------------------------
local ADDON, VS = ...
VS.Hop = {}
local H = VS.Hop

local PROTO        = "1"
local ASK_WAIT     = 12     -- the host has this long to invite
local MOVE_WAIT    = 45     -- after joining, the layer must change within this (twice if unknown)
local REVERT_WATCH = 40     -- after leaving the group, watch for a move back this long
local COOLDOWN     = 300
local HOST_GAP     = 120    -- a host invites at most once per this
local HOST_STAY    = 180    -- the host leaves the hop group after this...
local STAY_MAX     = 900    -- ...or after this when the guest stays grouped
local JOIN_WAIT    = 30     -- host: the guest must join within this

local state           -- your hop: { zone, from, hosts = { {name, pair} }, idx, host, pair, nonce, phase, timer, extended }
local lastHop         -- GetTime() of your last hop
local lastHosted      -- host side: GetTime() of the last invite
local hosting         -- host side: { guest, nonce, invited, joined, deadline }

local function forever() return RegionalUniqueNamesEnabled ~= nil and RegionalUniqueNamesEnabled() == true end
local function say(msg) print("|cff00c7ffVoidSweep|r: " .. msg) end
local function cfg() return VS:Config() end
local function canon(n) return VS.WhisperNet and VS.WhisperNet.Canon(n) or n end

-- Is this player in my group? (names only: Forever names are unique, no realm)
local function inGroupWith(name)
    if not (name and IsInGroup()) then return false end
    local raid = IsInRaid()
    local n = GetNumGroupMembers() or 0
    for i = 1, raid and n or n - 1 do
        local un = UnitName((raid and "raid" or "party") .. i)
        if type(un) == "string" and not (issecretvalue and issecretvalue(un)) and canon(un) == name then return true end
    end
    return false
end

-- Leave only THE hop group: the two of us, nobody else.
local function leaveHopGroup(other)
    if inGroupWith(other) and (GetNumGroupMembers() or 0) <= 2 and C_PartyInfo and C_PartyInfo.LeaveParty then
        C_PartyInfo.LeaveParty()
        return true
    end
    return false
end

function H:HostingOn() return cfg().hostHops == true end
function H:SetHosting(on)
    cfg().hostHops = on and true or false
    say(("hosting layer hops %s."):format(on and "|cff33ff33on|r: Void players on your layer can ask you for a quick group invite to join it (only while you're solo and out of combat)" or "|cffff5555off|r"))
end
-- Can I host right now? (LayerNet's answers say so)
function H:CanHost()
    return self:HostingOn() and not hosting and not IsInGroup() and not InCombatLockdown() and not IsInInstance()
        and not (lastHosted and GetTime() - lastHosted < HOST_GAP)
end

function H:CooldownLeft()
    local l = lastHop and (COOLDOWN - (GetTime() - lastHop)) or 0
    return l > 0 and l or 0
end

function H:Busy() return state ~= nil end

-- One line for the Layers window (LayerUI.lua): what the hop is doing, or nil.
function H:Status()
    if not state then return nil end
    local p = state.pair or "another layer"
    if state.phase == "asking" then return ("Asking a Void player on %s to invite you..."):format(p) end
    if state.phase == "joined" then return ("In the host's group: checking you moved to %s..."):format(p) end
    if state.phase == "retrying" then return "That host didn't move you: trying another..." end
    if state.phase == "left" then return ("On %s. Left the group; making sure you stay."):format(p) end
    return "Hopping..."
end

local function stop(msg)
    if msg then say(msg) end
    if state and state.timer then state.timer:Cancel() end
    state = nil
end

local function setTimer(sec, fn)
    if state.timer then state.timer:Cancel() end
    state.timer = C_Timer.NewTimer(sec, fn)
end

local nextHost

local function moved()
    lastHop = GetTime()
    say(("you're on layer |cffffd200%s|r now."):format(state.pair))
    if cfg().hopStay then
        -- tell the host, so it keeps the group (up to STAY_MAX) instead of leaving at HOST_STAY
        VS.Sync.SendTo(("HS:%s:%s"):format(PROTO, state.nonce), { state.host }, true)
        stop("staying in the host's group so you keep this layer (it lasts up to 15 minutes); leave it when you're done.")
        return
    end
    state.phase = "left"
    local host = state.host
    C_Timer.After(3, function() leaveHopGroup(host) end)
    setTimer(REVERT_WATCH, function() stop() end)
end

-- Your layer changed (Layer.lua).
local function onLayer(pair, zone)
    if not state or zone ~= state.zone then return end
    if state.phase == "joined" and pair == state.pair then
        moved()
    elseif state.phase == "left" and pair ~= state.pair then
        cfg().hopStay = true
        stop(("leaving the group sent you back (%s). From now on a hop keeps you in the host's group; /vsw hopstay to change."):format(pair))
    end
end

local function checkMove()
    if not (state and state.phase == "joined") then return end
    local cur = VS.Layer:Current(state.zone)
    if cur == state.pair then
        moved()
    elseif cur then
        -- not moved: leave THAT group, then the next host (unless a late success beat us)
        say(("joined, but you're still on %s. Trying another host."):format(cur))
        state.phase = "retrying"
        leaveHopGroup(state.host)
        C_Timer.After(2, function() if state and state.phase == "retrying" then nextHost() end end)
    elseif not state.extended then
        state.extended = true
        say("point at or target any NPC so VoidSweep can see your new layer.")
        setTimer(MOVE_WAIT, checkMove)
    else
        local host = state.host
        stop("couldn't confirm the move (no NPC seen), so you're leaving the host's group.")
        leaveHopGroup(host)
    end
end

nextHost = function()
    if not state then return end
    state.idx = state.idx + 1
    local h = state.hosts[state.idx]
    if not h then
        stop("no Void host could bring you over right now. Try again in a bit.")
        return
    end
    state.host, state.pair, state.phase, state.extended, state.seenHost = h.name, h.pair, "asking", nil, nil
    state.nonce = tostring(math.random(100000, 999999))
    VS.Sync.SendTo(("HR:%s:%d:%s:%s"):format(PROTO, state.zone, state.pair, state.nonce), { h.name }, true)
    local asked = h.name
    setTimer(ASK_WAIT, function()
        if state and state.phase == "asking" and state.host == asked then nextHost() end
    end)
end

-- Hop to a layer in your zone (pair nil = any other layer with a host). expectZone: the
-- zone an offer was made for (you may have moved on since).
function H:Start(pair, expectZone)
    if not forever() then say("layers are a WoW Forever thing.") return end
    if state then say("a hop is already under way.") return end
    if InCombatLockdown() then say("not in combat.") return end
    if IsInInstance() then say("not inside a dungeon or raid.") return end
    if IsInGroup() then say("leave your group first (moving a whole group comes next).") return end
    local cd = self:CooldownLeft()
    if cd > 0 then say(("one hop every 5 minutes: %s to go."):format(SecondsToTime(cd))) return end
    local mine, zone = VS.Layer:Here()
    if not zone then say("no zone here.") return end
    if expectZone and zone ~= expectZone then say("you've left that zone, so that hop no longer applies.") return end
    if not mine then say("your own layer isn't known yet: point at or target any NPC, then try again.") return end
    if pair == mine then say("you're already on that layer.") return end
    local hosts = {}
    local LN = VS.LayerNet
    for p in pairs(LN:Counts(zone)) do
        if p ~= mine and (not pair or p == pair) then
            for _, name in ipairs(LN:Hosts(zone, p)) do hosts[#hosts + 1] = { name = name, pair = p } end
        end
    end
    if #hosts == 0 then
        local sent = LN:Ask(zone)
        say(sent and "no Void host known on that layer yet; asking around. Try again in a few seconds."
            or "no Void host known on that layer right now (only Void players who turned hosting on can bring you over).")
        return
    end
    for i = #hosts, 2, -1 do   -- spread the asks over hosts
        local j = math.random(i)
        hosts[i], hosts[j] = hosts[j], hosts[i]
    end
    state = { zone = zone, from = mine, hosts = hosts, idx = 0 }
    say(("asking a Void player on layer %s to bring you over..."):format(pair or "another"))
    nextHost()
end

-- Host side: done hosting (the guest left, never came, or time's up).
local function endHosting(leave)
    if not hosting then return end
    local guest = hosting.guest
    hosting = nil
    if leave and leaveHopGroup(guest) then say("left the layer-hop group.") end
end

-- Messages (VoidSync's handler). Returns true if it was one of ours.
function H:OnMessage(msg, who, replyTo)
    local tag, proto, rest = msg:match("^(H[RAS]):(%d+):(.+)$")
    if not tag then return false end
    if proto ~= PROTO or not forever() then return true end
    if tag == "HR" then   -- someone asks me to host
        local zoneS, pair, nonce = rest:match("^(%d+):(%d+%-%d+):(%d+)$")
        if not nonce or #pair > 20 then return true end
        if not (VS.Sync.IsPeer and VS.Sync.IsPeer(who)) then return true end   -- members only
        local function reply(txt) VS.Sync.SendTo(("HA:%s:%s:%s"):format(PROTO, nonce, txt), { replyTo or who }, true) end
        if not self:HostingOn() then reply("no:off"); return true end
        if not self:CanHost() then reply("no:busy"); return true end
        local mine, zone = VS.Layer:Here()
        if zone ~= tonumber(zoneS) or mine ~= pair then reply("no:layer"); return true end
        lastHosted = GetTime()
        hosting = { guest = who, nonce = nonce, invited = GetTime(), deadline = GetTime() + HOST_STAY }
        C_PartyInfo.InviteUnit(replyTo or who)
        reply("ok")
        say(("inviting %s to bring them to your layer (a VoidSweep layer hop; the group ends on its own)."):format(who))
    elseif tag == "HS" then   -- my guest stays grouped to keep the layer
        if hosting and hosting.guest == who and rest == hosting.nonce and inGroupWith(who) then
            hosting.deadline = hosting.invited + STAY_MAX
            say(("%s stays in the group to keep your layer (up to 15 minutes); leave any time."):format(who))
        end
    else                  -- HA: the host I asked answers
        local nonce, answer = rest:match("^(%d+):(.+)$")
        if not (state and state.phase == "asking" and who == state.host and nonce == state.nonce) then return true end
        if answer ~= "ok" then nextHost() end   -- "no:..." -> the next host; "ok" -> wait for the invite
    end
    return true
end

local f = CreateFrame("Frame")
f:RegisterEvent("PARTY_INVITE_REQUEST")
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:SetScript("OnEvent", function(_, event, name)
    if event == "PLAYER_REGEN_DISABLED" then
        if state and state.phase == "asking" then stop("hop cancelled: you're in combat.") end
        return
    end
    if event == "GROUP_ROSTER_UPDATE" then
        -- your hop: the host's group ended (kicked, you left) before the move was confirmed
        -- (only once the host was seen in it: the first update can come before they show)
        if state and state.phase == "joined" then
            if inGroupWith(state.host) then
                state.seenHost = true
            elseif state.seenHost then
                stop("the host's group ended before the move was confirmed.")
            end
        end
        -- hosting: note the guest joining; forget them once they're gone
        if hosting then
            if inGroupWith(hosting.guest) then hosting.joined = true
            elseif hosting.joined then endHosting(false) end
        end
        return
    end
    -- PARTY_INVITE_REQUEST: accept only the invite from the host I asked, while asking
    if not (state and state.phase == "asking") then return end
    if type(name) ~= "string" or (issecretvalue and issecretvalue(name)) then return end
    if canon(name) ~= state.host then return end
    AcceptGroup()
    C_Timer.After(0, function()
        local d = StaticPopup_FindVisible and StaticPopup_FindVisible("PARTY_INVITE")
        if d then d.inviteAccepted = 1 end   -- so hiding it doesn't decline
        StaticPopup_Hide("PARTY_INVITE")
    end)
    state.phase = "joined"
    setTimer(MOVE_WAIT, checkMove)
end)

-- Hosting clock: the guest must join within JOIN_WAIT; the group ends at the deadline.
C_Timer.NewTicker(5, function()
    if not hosting then return end
    local now = GetTime()
    if not hosting.joined and now - hosting.invited > JOIN_WAIT then endHosting(false) return end
    if hosting.joined and now >= hosting.deadline then endHosting(true) end
end)

if VS.Layer then VS.Layer:OnChange(onLayer) end

-- A rare up on another layer with a Void host there: offer the hop (Sightings.lua).
StaticPopupDialogs.VOIDSWEEP_HOP = {
    text = "%s is up on another layer (%s).\nA Void player there can bring you over. Hop?",
    button1 = "Hop", button2 = CANCEL,
    OnAccept = function(_, data) if data and data.pair then H:Start(data.pair, data.zone) end end,
    timeout = 60, whileDead = false, hideOnEscape = true,
}
local offered = {}   -- [rare name] = GetTime()
function H:Offer(name, zone, pair)
    if not (forever() and name and pair and zone) or state or InCombatLockdown() or IsInGroup() or IsInInstance() then return end
    if self:CooldownLeft() > 0 then return end
    local _, here = VS.Layer:Here()
    if here ~= zone then return end   -- you've moved on since the sighting
    if offered[name] and GetTime() - offered[name] < 600 then return end
    if #VS.LayerNet:Hosts(zone, pair) == 0 then return end
    offered[name] = GetTime()
    StaticPopup_Show("VOIDSWEEP_HOP", name, pair, { pair = pair, zone = zone })
end

-- Void hub quick box switch (VoidHubBundle.lua of any Void addon that has one)
VoidHubToggles = VoidHubToggles or {}
table.insert(VoidHubToggles, {
    id = "VoidSweep.host", group = "Sweep", label = "Host layer hops",
    tip = "WoW Forever: let VoidSweep players on your layer ask you for a quick group invite to join it (only while you're solo and out of combat; /vsw host).",
    get = function() return H:HostingOn() end,
    set = function(on) H:SetHosting(on) end,
})
