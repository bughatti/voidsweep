----------------------------------------------------------------------
-- Void WhisperNet: the WoW Forever addon-message transport
--
-- Live WoW Forever (measured 2026-11-05) refuses addon messages sent to custom
-- chat channels: SendAddonMessage(..., "CHANNEL", idx) returns 0, the server
-- answers CHAT_MSG_CHANNEL_NOTICE NOT_ALLOWED_IN_CHANNEL and nothing is
-- delivered. Addon WHISPERS work, to the bare character name: Forever names are
-- "First Surname", unique per region, with no realm (RegionalUniqueNamesEnabled()
-- is true; GetNormalizedRealmName() is a hidden backing realm that must never be
-- appended). Channel MEMBER LISTS still work.
--
-- So on Forever the addon's hidden channel is only a member list (who runs the
-- addon right now) and the messages go by addon whisper to a few of its members.
-- Retail keeps sending on the channel, where it works.
--
-- Copied as-is into each addon that uses it (VoidGather, VoidSweep; source of
-- truth: wow-addons/_shared/WhisperNet.lua). It uses the addon's private
-- namespace, so every addon has its own copy and nothing is shared between them.
-- VoidQuest's ForeverShare.lua is the same design written inline.
----------------------------------------------------------------------
local _, ns = ...
local Net = {}
ns.WhisperNet = Net

local ROSTER_EVERY = 300   -- re-read the member list at most this often
local ROSTER_MAX   = 300   -- members read from it
local HIDE_FOR     = 30    -- seconds a whispered name's "No player named" line is hidden

-- Whisper transport on? Only where names are unique per region (WoW Forever):
-- there the bare name reaches the player. Retail has no such API.
function Net.Active()
    return RegionalUniqueNamesEnabled ~= nil and RegionalUniqueNamesEnabled() == true
end

-- One name per player, as the game gives it in Forever ("First Surname").
function Net.Canon(name)
    if type(name) ~= "string" or name == "" then return nil end
    return name
end

function Net.Me()
    return Net.Canon(GetUnitName and GetUnitName("player") or UnitName("player"))
end

----------------------------------------------------------------------
-- net = Net.New(channelName, onRoster)
--   net:DisplayIndex()           the channel's row in the Channels list, or nil
--   net:RequestRoster(force)     ask the server for the member list (at most every 5 min)
--   net:OnRosterUpdate(i)        CHANNEL_ROSTER_UPDATE arg1; re-reads ours
--   net.roster / net.count       other members' names / member count incl. you (nil = unknown)
--   net:Others()                 other members online, or nil while unknown
--   net:Pick(k)                  up to k random other members
--   net:Noted(name)              call right before whispering name (hides the offline line)
----------------------------------------------------------------------
local Obj = {}
Obj.__index = Obj

function Obj:DisplayIndex()
    if not (GetNumDisplayChannels and GetChannelDisplayInfo) then return nil end
    local want = self.channel:lower()
    for i = 1, GetNumDisplayChannels() or 0 do
        local name, header = GetChannelDisplayInfo(i)
        if not header and type(name) == "string" and name:lower() == want then return i end
    end
end

function Obj:ReadRoster()
    local i = self:DisplayIndex()
    if not i then return end
    local _, _, _, _, count = GetChannelDisplayInfo(i)
    count = tonumber(count)
    if count and count > 0 then self.count = count end
    if C_ChatInfo and C_ChatInfo.GetChannelRosterInfo then
        local me, list = Net.Me(), {}
        -- a busy channel: read a random window of ROSTER_MAX members, a new one each time,
        -- so everyone can be picked (not just the first ROSTER_MAX)
        local total = count or 0
        local start = total > ROSTER_MAX and math.random(0, total - ROSTER_MAX) or 0
        for r = start + 1, start + math.min(total, ROSTER_MAX) do
            local ok, name = pcall(C_ChatInfo.GetChannelRosterInfo, i, r)
            name = ok and Net.Canon(name)
            if name and name ~= me then list[#list + 1] = name end
        end
        -- an empty read while others are in the channel = not arrived yet: keep the old list
        if #list > 0 or (count or 0) <= 1 then self.roster = list end
    end
    if self.onRoster then self.onRoster() end
end

-- The server sends the member list after the channel is selected (CHANNEL_ROSTER_UPDATE,
-- ~3 s on live 11-05). Left alone while the Channels window is open, so we never change
-- what the player is looking at.
function Obj:RequestRoster(force)
    if not force and GetTime() - self.rosterAt < ROSTER_EVERY then return end
    local i = self:DisplayIndex()
    if not i then return end   -- not in the channel yet: try again next time
    -- the wait only starts once the list was really asked for (not while the window is open)
    if not (ChannelFrame and ChannelFrame:IsShown()) and SetSelectedDisplayChannel then
        self.rosterAt = GetTime()
        pcall(SetSelectedDisplayChannel, i)
    end
    self:ReadRoster()   -- may already be there
    C_Timer.After(3, function() self:ReadRoster() end)
end

function Obj:OnRosterUpdate(displayIndex)
    if displayIndex ~= nil and displayIndex == self:DisplayIndex() then self:ReadRoster() end
end

-- The member list also holds players who can't be whispered right now: logged off (the
-- server keeps them on the list for a while) or out of reach. The game's connected check
-- answers "unknown" for everyone but you (live 11-05), so learn it the honest way: a
-- whisper that comes back "No player named X is currently playing" marks X unreachable for
-- UNREACH_FOR seconds (not picked, not counted).
local UNREACH_FOR = 1800
function Obj:Reachable(name)
    local t = self.unreach[name:lower()]
    if t and GetTime() - t < UNREACH_FOR then return false end
    self.unreach[name:lower()] = nil
    return true
end

-- Other members online (nil = unknown), less the ones just found unreachable.
function Obj:Others()
    if not self.count then return nil end
    local gone = 0
    if self.count > ROSTER_MAX then
        -- only a window of the list is read: count every name still marked unreachable
        for name in pairs(self.unreach) do
            if not self:Reachable(name) then gone = gone + 1 end
        end
    else
        for _, name in ipairs(self.roster) do
            if not self:Reachable(name) then gone = gone + 1 end
        end
    end
    return math.max(0, self.count - 1 - gone)
end

function Obj:Pick(k)
    local live = {}
    for _, name in ipairs(self.roster) do
        if self:Reachable(name) then live[#live + 1] = name end
    end
    local n, out, used = #live, {}, {}
    while #out < math.min(k, n) do
        local j = math.random(n)
        if not used[j] then used[j] = true; out[#out + 1] = live[j] end
    end
    return out
end

function Obj:Noted(name)
    if type(name) == "string" then self.whispered[name:lower()] = GetTime() end
end

-- "No player named X is currently playing." for a name we whispered in the last HIDE_FOR
-- seconds: returns that name (lowercased), else nil.
function Obj:NoticeName(text)
    if type(text) ~= "string" or not ERR_CHAT_PLAYER_NOT_FOUND_S then return nil end
    local now, lower = GetTime(), text:lower()
    for name, t in pairs(self.whispered) do
        if now - t > HIDE_FOR then
            self.whispered[name] = nil
        elseif lower == ERR_CHAT_PLAYER_NOT_FOUND_S:format(name):lower() then
            return name
        end
    end
end

-- Hide that line in chat (it's our hidden whisper, not something the player sent).
function Obj:HidesNotice(text) return self:NoticeName(text) ~= nil end

function Net.New(channel, onRoster)
    local o = setmetatable({ channel = channel, onRoster = onRoster, roster = {}, count = nil,
                             rosterAt = -ROSTER_EVERY, whispered = {}, unreach = {} }, Obj)
    local addFilter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
    if addFilter then
        addFilter("CHAT_MSG_SYSTEM", function(_, _, text) return o:HidesNotice(text) end)
    end
    local f = CreateFrame("Frame")
    f:RegisterEvent("CHANNEL_ROSTER_UPDATE")
    f:RegisterEvent("CHAT_MSG_SYSTEM")
    f:SetScript("OnEvent", function(_, event, a1)
        if event == "CHANNEL_ROSTER_UPDATE" then
            o:OnRosterUpdate(a1)
        else
            local name = o:NoticeName(a1)   -- our whisper bounced: unreachable for a while
            if name then
                o.unreach[name] = GetTime()
                if o.onRoster then o.onRoster() end   -- the count drops
            end
        end
    end)
    return o
end
