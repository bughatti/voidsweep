----------------------------------------------------------------------
-- VoidSwarmLink — the swarm's own connection, for when VoidQuest isn't installed (WoW Forever)
--
-- The swarm (VoidSwarm.lua) rides ONE channel for every Void addon: VoidQuest's daily channel
-- (tag "Vq", the same name and password VoidQuest works out) and VoidQuest's prefix "VQUEST", so
-- old and new clients sit in one member list (the user, 2026-11-15: one channel; old clients must
-- keep working; old paths go 30 days after nobody uses them). VoidQuest hosts it itself when
-- installed (ForeverShare.lua). Without VoidQuest, the first Void addon carrying this file hosts it:
-- it joins that channel, reads its member list (WhisperNet.lua), whispers swarm messages ("Z...")
-- and passes the swarm messages it gets to VoidSwarm. Never two hosts: VoidSwarm.net is the one.
--
-- Copied as-is into each addon that carries it (with VoidSwarm.lua and WhisperNet.lua); source of
-- truth: wow-addons/_shared/VoidSwarmLink.lua. The addon calls ns.SwarmLink.Start(db) once its
-- saved data is in (db keeps the salt for the sender hash, so a player counts once across reloads).
----------------------------------------------------------------------
local _, ns = ...
local L = {}
ns.SwarmLink = L

local PREFIX, TAG, SALT = "VQUEST", "Vq", 40692   -- VoidQuest's: one swarm network for every Void addon
L.PREFIX, L.TAG, L.SALT = PREFIX, TAG, SALT

-- a VoidQuest new enough to host the swarm itself sets VoidSwarm.questHost when it loads; an older
-- one doesn't speak the swarm (it drops "Z" messages), so then this link hosts it (stage 6: a new
-- VoidSweep next to an old VoidQuest must still get the swarm)
local function questHosts()
    return (VoidSwarm and VoidSwarm.questHost) and true or false
end

local function chatLocked()
    return (C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()) and true or false
end

function L.Start(db)
    if L.started then return end
    L.started = true
    local Net = ns.WhisperNet
    if not (VoidSwarm and VoidSwarm.Host and Net and Net.Active and Net.Active()) then return end
    -- VoidQuest hosts it (its Init runs at login): give it the first seconds
    C_Timer.After(8, function()
        if VoidSwarm.net or questHosts() then return end
        L.Host(db, Net)
    end)
end

function L.Host(db, Net)
    if VoidSwarm.net then return VoidSwarm.net end
    db = type(db) == "table" and db or {}
    db.swarmSalt = db.swarmSalt or tostring(math.random(100000, 999999)) .. tostring(math.random(100000, 999999))
    local name, pw = Net.DailyChannel(TAG, SALT)
    local link = Net.New(name, nil, {})
    L.link, L.channel = link, name

    local function join()
        if (GetChannelName(L.channel) or 0) > 0 or chatLocked() then return end
        JoinTemporaryChannel(L.channel, pw)
        if ChatFrame_RemoveChannel then
            C_Timer.After(2, function()
                for i = 1, (NUM_CHAT_WINDOWS or 10) do
                    local cf = _G["ChatFrame" .. i]
                    if cf then ChatFrame_RemoveChannel(cf, L.channel) end
                end
            end)
        end
    end
    join()

    local net = VoidSwarm.Host({
        send = function(to, msg)
            if chatLocked() or not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
            link:Noted(to)
            local r = C_ChatInfo.SendAddonMessage(PREFIX, msg, "WHISPER", to)
            link:Sent(to, r)
        end,
        members = function(k)
            link:RequestRoster()
            return link:Pick(k) or {}
        end,
        me = Net.Me,
        now = GetTime,
        hash = function(n) return tostring(VoidSwarm.Hash(db.swarmSalt .. ":" .. tostring(n))) end,
    })
    L.net = net

    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
    local f = CreateFrame("Frame")
    f:RegisterEvent("CHAT_MSG_ADDON")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", function(_, event, prefix, msg, kind, sender)
        if event == "PLAYER_REGEN_ENABLED" then join() return end
        if prefix ~= PREFIX or type(msg) ~= "string" or msg:byte(1) ~= 90 then return end   -- "Z": swarm only
        if issecretvalue and (issecretvalue(msg) or issecretvalue(sender)) then return end
        local who = Net.Canon(sender)
        if who then pcall(net.OnMessage, net, msg, who) end
    end)
    C_Timer.NewTicker(1, function() if not chatLocked() then pcall(net.Tick, net) end end)
    -- the channel changes at 00:00 UTC: follow it (leave yesterday's)
    C_Timer.NewTicker(60, function()
        local n2, p2 = Net.DailyChannel(TAG, SALT)
        if n2 == L.channel or chatLocked() then return end
        if (GetChannelName(L.channel) or 0) > 0 then LeaveChannelByName(L.channel) end
        L.channel, pw = n2, p2
        if link.SetChannel then link:SetChannel(n2) else link.channel = n2; link.roster, link.count = {}, nil end
        join()
    end)
    return net
end
