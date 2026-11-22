----------------------------------------------------------------------
-- VoidSweep — Sleeping bag invites (WoW Forever, 2026-11-13)
--
-- The user: "alot of people ask for invite for sleeping back, how can we add that or automate
-- that as part of the camping fire thing". Party members get the Cozy Sleeping Bag's bonus by
-- walking onto your unrolled bag: resting in it a minute gives an XP bonus that stacks up to 3
-- times (Blizzard item 211527, use spell "Unroll Bag" 429961, 1 hour cooldown, checked against
-- Blizzard's Forever item data and the Forever guides 2026-11-13).
--
-- While your bag is out, a whisper with a bag word ("bag", "sleeping bag", "sleep", "cozy") gets a
-- party invite and a whisper back saying where to walk. Never a plain "inv": the user's pick, so a
-- quest-group "inv" doesn't pull someone into your party. Never turns a party into a raid, one
-- invite per player per bag, only when you can invite (no group, or you lead / assist).
--
-- How long a bag stays on the ground isn't published anywhere: invites stay on BAG_WINDOW after you
-- unroll it, or until you change zones (an estimate, to be measured in game). /vsw bag toggles it.
----------------------------------------------------------------------
if (select(4, GetBuildInfo()) or 0) >= 100000 then return end   -- WoW Forever only

local ADDON, VS = ...
local B = {}
VS.Bag = B

local UNROLL = 429961          -- "Unroll Bag", the Cozy Sleeping Bag's use spell
local BAG_WINDOW = 15 * 60     -- seconds invites stay on after you unroll it (estimate)
local WORDS = { "sleeping bag", "sleepingbag", "bag", "bags", "sleep", "cozy" }

local active   -- { untilT, where, done = { [sender] = true } }

local function secret(v) return issecretvalue and issecretvalue(v) end
local function on() return VS:Config().bagInvite ~= false end
local function say(msg) print("|cff00c7ffVoidSweep|r: " .. msg) end

-- a bag word as a whole word ("bag?", "sleeping bag pls"), not inside another ("baggage")
function B.HasWord(msg)
    local m = " " .. msg:lower():gsub("[^%a]", " ") .. " "
    for _, w in ipairs(WORDS) do
        if m:find(" " .. w .. " ", 1, true) then return true end
    end
    return false
end

local PENDING = 60   -- seconds an invite counts as taking a spot (the game's invite times out)
local REASK = 90     -- seconds before someone not in the group yet can ask again (declined, timed out, failed)

local function inGroup(name)
    local short = Ambiguate(name, "none")
    return (UnitInParty(short) or UnitInRaid(short)) and true or false
end

-- invites still waiting for an answer: they hold a spot (Sol review: the member count alone missed them)
local function pending()
    local c, t = 0, GetTime()
    for name, at in pairs(active.done) do
        if t - at < PENDING and not inGroup(name) then c = c + 1 end
    end
    return c
end

-- can you invite right now? -> true, or false and why ("lead" / "full")
local function canInvite()
    if IsInGroup() and not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then return false, "lead" end
    local n = (IsInGroup() and GetNumGroupMembers() or 1) + pending()
    if (IsInRaid() and n >= 40) or (not IsInRaid() and n >= 5) then return false, "full" end
    return true
end

local function whisper(text, to)
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if send then pcall(send, text, "WHISPER", nil, to) end
end

function B:Active() return active and GetTime() < active.untilT and active or nil end

-- A star over your head while the bag is out, so the players you invite can find you in a crowded
-- camp (the user, 2026-11-13: "putting a marker on me so people can find me"). The game shows raid
-- markers only to your group, so strangers see it once they join.
-- SetRaidTarget is RESTRICTED (Forever API docs: HasRestrictions, AllowedWhenUntainted): addon
-- code can't call it at all, not even from a click (ADDON_ACTION_FORBIDDEN on the Bag click, live
-- 2026-11-14). Only Blizzard's secure button does it: Camp.lua lays one over the Bag button
-- (type "raidtarget": left click sets the star unless a marker is on you already, right click
-- clears it). This file only reads the marker, for the whisper.
local STAR = 1
local function marker()
    local i = GetRaidTargetIndex and GetRaidTargetIndex("player")
    if secret(i) then return false end
    return i
end

-- The bag is remembered across a /reload (the user, 2026-11-13: "reloading removed it"):
-- VoidSweepCharDB.bag = { at = server time unrolled, zone = zone name, gone = left the zone }.
local function saved() VoidSweepCharDB = VoidSweepCharDB or {}; return VoidSweepCharDB.bag end

-- Where you stand, as map coordinates ("52.1, 13.8"): a zone name alone was confusing (the user,
-- 2026-11-21: "saying i am in durotar when i am right outside org"). nil inside instances / no position.
local function coords()
    local m = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local p = m and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(m, "player")
    if not (p and p.GetXY) then return nil end
    local x, y = p:GetXY()
    if secret(x) or secret(y) or type(x) ~= "number" or type(y) ~= "number" or x <= 0 or y <= 0 then return nil end
    return ("%.1f, %.1f"):format(x * 100, y * 100)
end

-- "Razor Hill (52.1, 41.8)", "Durotar (45.3, 12.0)", or just the name without a position
local function placeText(where, xy)
    if xy then return (where ~= "" and (where .. " ") or "") .. "(" .. xy .. ")" end
    return where
end
B.PlaceText = placeText

-- left: seconds of the window still to go (a fresh bag: all of it); quiet: no chat line (a reload);
-- xy: the bag's coordinates (a reload: the ones saved when it was unrolled, not where you stand now)
local function start(left, quiet, xy, savedWhere)
    left = left or BAG_WINDOW
    local where = savedWhere or GetSubZoneText()   -- a reload: the place name saved with the bag (Codex)
    if not where or where == "" then where = GetZoneText() or "" end
    xy = xy or (left == BAG_WINDOW and coords()) or nil
    active = { untilT = GetTime() + left, where = where, xy = xy, place = placeText(where, xy),
        zone = GetZoneText() or "", done = {}, told = {} }
    if left == BAG_WINDOW then
        VoidSweepCharDB = VoidSweepCharDB or {}
        VoidSweepCharDB.bag = { at = GetServerTime(), zone = GetZoneText() or "", xy = xy, where = where }
    end
    if on() and not quiet then
        say(("sleeping bag out: a whisper with \"bag\" gets a party invite for the next %d minutes. Click Bag on the camp box to say so in /say and put a star on you so they can find you (right-click Bag takes the star off). /vsw bag turns this off.")
            :format(BAG_WINDOW / 60))
    end
    if VS.Camp and VS.Camp.BagOut then VS.Camp:BagOut() end   -- the camp box, with its Bag button
end

-- After a /reload or relog: the Cozy Sleeping Bag's 1 h cooldown says when it was unrolled. Still
-- inside the window and not seen leaving the zone -> pick the bag back up, star and Bag button too.
local BAG_ITEM = 211527
local function restore()
    if active then return end
    local getCD = (C_Container and C_Container.GetItemCooldown) or (C_Item and C_Item.GetItemCooldown)
    if not getCD then return end
    local ok, st, dur = pcall(getCD, BAG_ITEM)
    if not ok or secret(st) or secret(dur) or type(st) ~= "number" or type(dur) ~= "number" then return end
    if st <= 0 or dur < 600 then return end            -- not on its cooldown (or only a global cooldown)
    local ago = GetTime() - st
    if ago < 0 or ago >= BAG_WINDOW then return end
    local s, unrolled = saved(), GetServerTime() - ago
    if s and math.abs((s.at or 0) - unrolled) < 30 then   -- the bag we saw unrolled
        if s.gone or (s.zone and s.zone ~= "" and s.zone ~= GetZoneText()) then return end
    elseif s and s.gone and (s.at or 0) > unrolled then
        return   -- (clock odd) a newer bag already left behind
    end
    local same = s and math.abs((s.at or 0) - unrolled) < 30
    -- the bag's own spot when we saw it unrolled; else none (you may have walked off since)
    start(BAG_WINDOW - ago, true, same and s.xy or nil, same and s.where or nil)
    if not same then
        VoidSweepCharDB.bag = { at = unrolled, zone = GetZoneText() or "" }   -- unrolled before this was saved
    end
    if on() then say(("your sleeping bag is still out: invites back on for %d more minutes."):format(math.ceil((BAG_WINDOW - ago) / 60))) end
end

local function onWhisper(msg, sender)
    if not (on() and B:Active()) then return end
    if type(msg) ~= "string" or type(sender) ~= "string" or secret(msg) or secret(sender) then return end
    if not B.HasWord(msg) then return end
    local me = UnitName("player")
    if Ambiguate(sender, "none") == me or inGroup(sender) then return end
    if active.done[sender] and GetTime() - active.done[sender] < REASK then return end
    local ok, why = canInvite()
    if not ok then
        -- told once; asking again once a spot opens still gets an invite
        if not active.told[sender] then
            active.told[sender] = true
            whisper(why == "full" and "Sorry, my group is full right now. Whisper again in a bit."
                or "I'm not leading my group, so I can't invite you to my sleeping bag.", sender)
        end
        return
    end
    active.done[sender] = GetTime()
    active.told[sender] = nil
    C_PartyInfo.InviteUnit(sender)
    whisper(("Invited! My sleeping bag is at %s%s: walk onto it and rest a minute (it stacks up to 3 times).")
        :format(active.place ~= "" and active.place or "my camp", marker() == STAR and ", look for the star over me" or ""), sender)
    say(("invited %s to your sleeping bag."):format(Ambiguate(sender, "none")))
end

local f = CreateFrame("Frame")
f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
f:RegisterEvent("CHAT_MSG_WHISPER")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function(_, event, a1, a2, a3)
    if event == "PLAYER_ENTERING_WORLD" then
        -- a moment later: the camp box is set up at PLAYER_LOGIN, cooldowns can lag a fresh login
        if C_Timer and C_Timer.After then C_Timer.After(2, restore) else restore() end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if not secret(a3) and a3 == UNROLL then start() end   -- secret check FIRST: comparing a secret errors (Sol)
    elseif event == "CHAT_MSG_WHISPER" then
        onWhisper(a1, a2)
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        local s = VoidSweepCharDB and VoidSweepCharDB.bag
        if s and not s.gone and s.zone ~= GetZoneText() then s.gone = true end   -- a /reload won't bring it back
        if active and active.zone ~= GetZoneText() then   -- (it can fire on a reload in the same zone)
            active = nil                  -- you left the bag behind (a star stays: right-click Bag clears it)
            if VS.Camp and VS.Camp.Refresh then VS.Camp:Refresh() end
        end
    end
end)

-- /vsw bag
function B:Toggle()
    local cfg = VS:Config()
    cfg.bagInvite = cfg.bagInvite == false
    if VS.Camp and VS.Camp.Refresh then VS.Camp:Refresh() end   -- show / hide the Bag button
    return cfg.bagInvite
end
