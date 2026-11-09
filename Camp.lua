----------------------------------------------------------------------
-- VoidSweep — Camp: is this campfire worth sitting at, for me? (WoW Forever, 2026-11-08)
--
-- Players put a campfire down and add profession objects to it (Fish Bowl, Camp Tent,
-- Incense Candle ...). Resting there 1 minute gives each object's buff for 1 hour. Walking up
-- you can't tell what a camp gives (the user: "some are worth sitting at, some are not, I don't
-- know what's what when I walk up").
--
-- Every camp object you hover, or the game soft-targets as you walk up (the interact
-- highlight), is identified by its object ID (CampData.lua, from Campfire Tooltips: Forever,
-- GPL-3.0-or-later). The objects seen near you in the last few minutes are "this camp", and a
-- small box judges each buff FOR YOU:
--   NEW      you'd gain it: the amount at your level
--   have     you already have it (minutes left)
--   covered  your class buff of that kind already covers it (they don't stack)
--   no use   not for your class (Intellect on a rogue), or the other faction's banner
--   wait     the tent's rested XP is on its 1-hour cooldown, or you're already rested
-- Title line: "Worth sitting: 3 new" or "Nothing new for you". The same verdict goes into
-- the object's tooltip. The box goes away 20 s after you walk off. /vsw camp toggles it.
----------------------------------------------------------------------
-- Borders are one screen pixel (tools/cmd/pixelfix, 2026-11-09). WoW snaps each border
-- piece to the pixel grid, and a thin line on a fractional position can snap to 0 px: a side
-- of a box vanishes. VoidPX() asks for one real pixel, and the hook below (installed once, by
-- the first Void addon loaded) turns snapping off on the edges of flat WHITE8X8 borders, like
-- Blizzard's NineSliceUtil.DisableSharpening, so a 1 px line always covers a pixel.
local function VoidPX()
    local s = UIParent and UIParent:GetEffectiveScale()
    if s and s > 0 and PixelUtil and PixelUtil.GetPixelToUIUnitFactor then return PixelUtil.GetPixelToUIUnitFactor() / s end
    return 1
end
if not _G.__VoidBorderHook and hooksecurefunc and NineSliceUtil and NineSliceUtil.ApplyLayout then
    _G.__VoidBorderHook = true
    local EDGES = { "TopEdge", "BottomEdge", "LeftEdge", "RightEdge",
                    "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner" }
    hooksecurefunc(NineSliceUtil, "ApplyLayout", function(c)
        local i = type(c) == "table" and c.backdropInfo
        local e = i and i.edgeFile
        if type(e) ~= "string" or not e:lower():find("white8x8", 1, true) or (tonumber(i.edgeSize) or 0) > 3 then return end
        for _, k in ipairs(EDGES) do
            local t = c[k]
            if t and t.SetSnapToPixelGrid then
                t:SetSnapToPixelGrid(false)
                t:SetTexelSnappingBias(0)
            end
        end
    end)
end
local ADDON, VS = ...
local C = {}
VS.Camp = C
local CD = VS.CampData

local A = { 0, 0.78, 1 }
local NEAR_YARDS = 45      -- objects this close to you belong to the camp you're at
local KEEP = 300           -- forget an object not seen for this long
local LINGER = 20          -- the box stays this long after you walk off

local function forever() return RegionalUniqueNamesEnabled ~= nil and RegionalUniqueNamesEnabled() == true end
local function readable(v)
    if canaccessvalue then return canaccessvalue(v) end
    return not (issecretvalue and issecretvalue(v))
end
local function on() return VS:Config().campBox ~= false end

----------------------------------------------------------------------
-- What an object is
----------------------------------------------------------------------
-- From a GUID (object or creature) or, failing that, an English object name.
local function identify(guid, name)
    if type(guid) == "string" and readable(guid) then
        local e = guid:match("^GameObject%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
        e = e and tonumber(e)
        if e and CD.objects[e] then return CD.objects[e], e end
        local c = guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
        c = c and tonumber(c)
        if c and CD.creatures[c] then return CD.creatures[c], c end
    end
    if type(name) == "string" and readable(name) then
        local loc = GetLocale()
        local id = CD.names[loc] and CD.names[loc][name]
        if id and CD.objects[id] then return CD.objects[id], id end
        local f = CD.factionNames[loc] and CD.factionNames[loc][name]
        if f then
            -- a banner seen by name only (Forever's object tooltips carry no GUID): whose it is
            -- can't be told, so it's judged as "only if it's your faction's" (Codex review)
            local fid = f[UnitFactionGroup("player") or "Horde"]
            if fid and CD.objects[fid] then
                return setmetatable({ unsureFaction = true }, { __index = CD.objects[fid] }), fid
            end
        end
    end
end

----------------------------------------------------------------------
-- What a buff is worth to you
----------------------------------------------------------------------
local MANA = { MAGE = true, PRIEST = true, WARLOCK = true, DRUID = true, SHAMAN = true, PALADIN = true, HUNTER = true }
local USE = {   -- benefit -> classes it does something for (nil = everyone)
    mana = MANA, intellect = MANA, spirit = MANA,
    strength = { WARRIOR = true, PALADIN = true, ROGUE = true, SHAMAN = true, DRUID = true },
    attack = { WARRIOR = true, PALADIN = true, ROGUE = true, SHAMAN = true, DRUID = true, HUNTER = true },
}

local function atLevel(list, level)
    for _, l in ipairs(list or {}) do
        if level <= l[1] then return l[2] end
    end
    local last = list and list[#list]
    return last and last[2]
end

-- The gain at your level, as text ("+21 Stamina").
local function amount(key, b, level)
    if key == "lute" then
        local ar, at, re = atLevel(b.armor, level), atLevel(b.attributes, level), atLevel(b.resistances, level)
        local parts = { ("+%d armor"):format(ar or 0) }
        if at and at > 0 then parts[#parts + 1] = ("+%d stats"):format(at) end
        if re and re > 0 then parts[#parts + 1] = ("+%d resist"):format(re) end
        return table.concat(parts, ", ")
    end
    local v = atLevel(b.levels, level)
    if v and b.prediction and b.prediction ~= "" then return b.prediction:format(v):gsub("%.$", "") end
    return b.effect
end

----------------------------------------------------------------------
-- What you already have: Forever gives NO per-object buff (measured 2026-11-08, none of the
-- data's aura IDs ever showed up). Resting puts ONE aura on you, "Camp Benefits" (1229741, 1 hour),
-- and its tooltip lists the objects:
--   "Gained the following camp benefits:\r\n\r\nLodestone: Melee Attack Power increased by 32.\r\n\r\n"
-- So "have" = that list, read from the tooltip once per aura instance.
----------------------------------------------------------------------
local BENEFITS_AURA = 1229741
-- the object's name first (CampNames), then words in the effect text
local KEYWORDS = {
    { "critical", "chair" }, { "attack power", "attack" }, { "armor", "lute" },
    { "all attributes", "fish" }, { "all stats", "fish" }, { "strength", "strength" },
    { "stamina", "stamina" }, { "intellect", "intellect" }, { "spirit", "spirit" }, { "mana", "mana" },
}

local function benefitKey(item, effect)
    local loc = GetLocale()
    local id = CD.names[loc] and CD.names[loc][item]
    local o = id and CD.objects[id]
    if o and o.benefit then return o.benefit end
    local e = effect:lower()
    for _, k in ipairs(KEYWORDS) do
        if e:find(k[1], 1, true) then return k[2] end
    end
    return "raw:" .. item     -- a camp object we don't know yet: still listed as "have"
end

local cache = { iid = nil, map = nil, exp = nil, at = 0 }
local REREAD = 30     -- seconds: the same aura can be refreshed in place with another camp's list

-- { [benefit] = { name = "Lodestone", text = "Melee Attack Power increased by 32." } }, expirationTime
function C:Benefits()
    local ok, a = pcall(C_UnitAuras.GetPlayerAuraBySpellID, BENEFITS_AURA)
    if not (ok and a) then
        -- in combat the lookup can come back empty while the aura is still on you (Codex review)
        -- ...but not past its known end time (Astra review)
        if InCombatLockdown() and not (cache.exp and cache.exp <= GetTime()) then return cache.map, cache.exp end
        cache.iid, cache.map, cache.exp = nil, nil, nil
        return nil
    end
    local iid = readable(a.auraInstanceID) and a.auraInstanceID or nil
    local exp = readable(a.expirationTime) and a.expirationTime or nil
    if not iid then return cache.map, exp or cache.exp end   -- hidden in combat: keep what we read
    -- re-read on a new aura, a refreshed timer (rested at another camp) or every 30 s (Codex review)
    if cache.iid ~= iid or not cache.map or (exp and exp ~= cache.exp) or GetTime() - cache.at > REREAD then
        local okT, d = pcall(C_TooltipInfo.GetUnitBuffByAuraInstanceID, "player", iid)
        local text = okT and d and d.lines and d.lines[2] and d.lines[2].leftText
        if type(text) ~= "string" or not readable(text) then return cache.map, exp end
        local map = {}
        -- "Item: effect" lines; the "...camp benefits:" header has nothing after its colon
        for item, effect in text:gmatch("([^\r\n:]+): ?([^\r\n]+)") do
            item = strtrim(item)
            map[benefitKey(item, effect)] = { name = item, text = strtrim(effect) }
        end
        cache.iid, cache.map, cache.exp, cache.at = iid, map, exp, GetTime()
    end
    return cache.map, exp
end

local function haveText(exp)
    local left = exp and exp > 0 and (exp - GetTime())
    return left and left > 0 and ("have it (%dm left)"):format(math.floor(left / 60)) or "have it"
end

local function classBuff(b)
    local name = b.exclusive and b.exclusive:match("Does not stack: (.-)%.?$")
    if not name then return nil end
    local a = C_UnitAuras.GetAuraDataBySpellName and C_UnitAuras.GetAuraDataBySpellName("player", name, "HELPFUL")
    if a then return name end
    if AuraUtil and AuraUtil.FindAuraByName and AuraUtil.FindAuraByName(name, "player", "HELPFUL") then return name end
end

-- status, text for one object: status = "new" | "have" | "covered" | "nouse" | "wait" | "info"
function C:Judge(obj)
    local key = obj.benefit
    local b = CD.benefits[key]
    if not b then return "info", obj.name end
    if not b.aura then return "info", b.effect or obj.name end      -- campfire, oven, bots ...
    local have, haveExp = C:Benefits()
    if have and have[key] and key ~= "tent" then return "have", haveText(haveExp) end
    if obj.unsureFaction then
        local okB, mineB = pcall(C_UnitAuras.GetPlayerAuraBySpellID, b.aura)
        if okB and mineB then return "have", "have it" end
        return "info", "Spirit, if it's your faction's banner"
    end
    local level = UnitLevel("player") or 1
    local class = select(2, UnitClass("player"))
    if obj.requirement and obj.requirement:find(UnitFactionGroup("player") == "Horde" and "Alliance" or "Horde") then
        return "nouse", "the other faction's banner"
    end
    if key == "tent" then
        local okT, t = pcall(C_UnitAuras.GetPlayerAuraBySpellID, b.aura)
        if okT and t then return "wait", "rested XP on cooldown" end
        local max = UnitXPMax("player") or 0
        if level >= (GetMaxPlayerLevel and GetMaxPlayerLevel() or 60) then return "nouse", "max level: no XP" end
        if max > 0 and (GetXPExhaustion() or 0) >= max * 0.05 then return "wait", "you're already rested" end
        return "new", "rested XP (5% of a level)"
    end
    local ok, mine = pcall(C_UnitAuras.GetPlayerAuraBySpellID, b.aura)
    mine = ok and mine or nil
    if mine then
        return "have", haveText(readable(mine.expirationTime) and mine.expirationTime or nil)
    end
    if USE[key] and not USE[key][class] then return "nouse", amount(key, b, level) .. " (no use to you)" end
    local cb = classBuff(b)
    if cb then return "covered", cb .. " covers it" end
    return "new", amount(key, b, level)
end

local COLORS = {
    new = "|cff33ff33", have = "|cff8c8c9e", covered = "|cff8c8c9e", nouse = "|cff8c8c9e", wait = "|cffffb84d", info = "|cffb0b0b8",
}
local WORD = { new = "NEW", have = "have", covered = "covered", nouse = "no use", wait = "wait", info = "" }

----------------------------------------------------------------------
-- The camp you're at: objects seen near you lately
----------------------------------------------------------------------
local seen = {}   -- [guid or name] = { obj, id, t, y, x, inst }

-- The game's own signal (measured 2026-11-08): "Campfire Nearby" (1283391) is on you while
-- you're near a campfire, "Welcoming Campfire" (1229739, 60 s) while you rest there.
-- UnitPosition gave nothing there, so the aura decides what "this camp" is.
local CAMP_AURA, REST_AURA = 1283391, 1229739
local campSince, campLeft = nil, nil

local function aura(id)
    local ok, a = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
    if ok and a then return a end
end

local function pos()
    local y, x, _, inst = UnitPosition("player")
    if y and readable(y) and readable(x) then return y, x, inst end
end

-- Closed by the box's x: { since = the camp visit it was closed on (campSince; nil while
-- lingering) }. A new camp visit or a camp item not seen before opens it again.
local closed = nil

local function note(key, obj, id)
    if closed and not seen[key] then closed = nil end
    local y, x, inst = pos()
    seen[key] = { obj = obj, id = id, t = GetTime(), y = y, x = x, inst = inst }
    -- kept through a /reload or relog (5 minutes): VoidSweepDB.campSeen[key] = { id, serverTime }
    VoidSweepDB = VoidSweepDB or {}
    VoidSweepDB.campSeen = VoidSweepDB.campSeen or {}
    VoidSweepDB.campSeen[key] = { id, GetServerTime(), UnitGUID("player") }
    C:Refresh()
end

local function restoreSeen()
    local saved = VoidSweepDB and VoidSweepDB.campSeen
    if not saved then return end
    local nowS, nowT = GetServerTime(), GetTime()
    for key, v in pairs(saved) do
        local age = nowS - (v[2] or 0)
        local obj = CD.objects[v[1]] or CD.creatures[v[1]]
        -- only this character's (an alt logged in within 5 minutes isn't at that camp; Codex review)
        if obj and age >= 0 and age < KEEP and v[3] == UnitGUID("player") then
            seen[key] = { obj = obj, id = v[1], t = nowT - age, restored = true }
        else
            saved[key] = nil
        end
    end
end

-- Track the camp aura coming and going.
local function campTick()
    local at = aura(CAMP_AURA) ~= nil
    if at and not campSince then campSince, campLeft = GetTime(), nil
    elseif at and campLeft then campLeft = nil      -- came back before the box let go (Codex review)
    elseif not at and campSince and not campLeft then campLeft = GetTime() end
    if campLeft and GetTime() - campLeft > LINGER then campSince, campLeft = nil, nil end
    return at
end

local function here()
    local at = campTick()
    local y, x, inst = pos()
    local out, now = {}, GetTime()
    for k, s in pairs(seen) do
        if now - s.t > KEEP and not (campSince and s.t >= campSince - 60) then
            seen[k] = nil
        elseif campSince and (s.t >= campSince - 60 or s.restored) then
            out[#out + 1] = s                       -- seen since you came to this campfire (or before a reload)
        elseif s.y and y and s.inst == inst and ((s.y - y) ^ 2 + (s.x - x) ^ 2) <= NEAR_YARDS ^ 2 then
            out[#out + 1] = s
        elseif not s.y and now - s.t < 30 then      -- no position, no camp aura: recent only
            out[#out + 1] = s
        end
    end
    return out, at
end

----------------------------------------------------------------------
-- The box
----------------------------------------------------------------------
local box, lastNear = nil, 0

local function db()
    VoidSweepDB = VoidSweepDB or {}
    return VoidSweepDB
end

local function build()
    local f = CreateFrame("Frame", "VoidSweepCampBox", UIParent, "BackdropTemplate")
    f:SetSize(250, 60)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = VoidPX() })
    f:SetBackdropColor(0.04, 0.04, 0.07, 0.9)
    f:SetBackdropBorderColor(A[1], A[2], A[3], 0.6)
    local p = db().campPos
    if p then f:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else f:SetPoint("TOP", UIParent, "TOP", 0, -260) end
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local pt, _, rel, x, y = self:GetPoint()
        db().campPos = { pt, rel, x, y }
    end)
    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Camp buffs, for you")
        GameTooltip:AddLine("Rest by the campfire for 1 minute (sit, use a chair, lie down or kneel) to get its buffs. They last 1 hour, also after you leave.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Objects show up here when you hover them or walk up to them.", 0.6, 0.6, 0.6, true)
        GameTooltip:AddLine("Drag to move · /vsw camp turns the box off", 0.4, 0.8, 1)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 8, -6)
    f.title:SetJustifyH("LEFT")
    -- Sit (the user, 2026-11-09): resting by the fire for a minute is what gives the buffs.
    -- A plain button calling the SIT emote, not a secure /sit macro button: a secure child
    -- would make this box protected, and it hides itself on a timer, also in combat.
    -- Close (the user, 2026-11-09: "so it doesn't stay longer than it needs to"): hides it
    -- for this visit to this fire; the next camp (or a new camp item) brings it back.
    local close = CreateFrame("Button", nil, f)
    close:SetSize(16, 16)
    close:SetPoint("TOPRIGHT", -4, -5)
    close.text = close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    close.text:SetPoint("CENTER", 0, 1)
    close.text:SetText("|cff8c8c9ex|r")
    close:SetScript("OnClick", function() C:Close() end)
    close:SetScript("OnEnter", function(self)
        self.text:SetText("|cffff5555x|r")
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Close")
        GameTooltip:AddLine("Back at the next campfire you walk up to.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    close:SetScript("OnLeave", function(self)
        self.text:SetText("|cff8c8c9ex|r")
        GameTooltip:Hide()
    end)
    f.close = close
    local sit = CreateFrame("Button", nil, f, "BackdropTemplate")
    sit:SetSize(44, 16)
    sit:SetPoint("TOPRIGHT", close, "TOPLEFT", -4, 0)
    sit:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = VoidPX() })
    sit:SetBackdropColor(0.10, 0.12, 0.15, 1)
    sit:SetBackdropBorderColor(A[1], A[2], A[3], 0.6)
    sit.text = sit:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sit.text:SetPoint("CENTER")
    sit.text:SetText("Sit")
    sit:SetScript("OnClick", function() C:Sit() end)
    sit:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(A[1], A[2], A[3], 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Sit down by the fire")
        GameTooltip:AddLine("Rest here for 1 minute to get the camp's buffs.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    sit:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(A[1], A[2], A[3], 0.6)
        GameTooltip:Hide()
    end)
    sit:Hide()
    f.sit = sit
    f.lines = {}
    f:Hide()
    f.elapsed = 0
    f:SetScript("OnUpdate", function(self, dt)
        self.elapsed = self.elapsed + dt
        if self.elapsed >= 1 then self.elapsed = 0; C:Refresh() end
    end)
    return f
end

local ORDER = { new = 1, wait = 2, have = 3, covered = 4, nouse = 5, info = 6 }

function C:Close()
    closed = { since = campSince }
    if box then box:Hide() end
end

-- On a mount, in the air or on a flight path: you're leaving, not standing at the fire's edge.
local function movingOn()
    return (UnitOnTaxi and UnitOnTaxi("player")) or (IsFlying and IsFlying()) or (IsMounted and IsMounted())
end

function C:Refresh()
    if not (on() and forever()) then if box then box:Hide() end return end
    local list, atCamp = here()
    -- Left the fire on a mount / flight: done with this camp right away (the user, 2026-11-09:
    -- "im flying and had to close it far away"). Forget its items so they don't hold the box up;
    -- the next fire's aura (or walking back) brings them back.
    if not atCamp and campLeft and movingOn() then
        campSince, campLeft, lastNear = nil, nil, 0
        wipe(seen)
        if VoidSweepDB then VoidSweepDB.campSeen = nil end
        if box then box:Hide() end
        return
    end
    if closed then
        if not atCamp then closed.away = true end         -- walked away from that fire
        if (campSince and campSince ~= closed.since) or (atCamp and closed.away) then
            closed = nil                                  -- a new camp visit: show it again
        else
            if box then box:Hide() end
            return
        end
    end
    -- the 20 s count from the moment you left the fire's range, once: the camp's items (kept
    -- while campLeft counts down) don't restart it (two 20 s waits back to back = ~40 s)
    if atCamp or (#list > 0 and not campLeft) then lastNear = GetTime() end
    if #list == 0 and not atCamp and GetTime() - lastNear > LINGER then
        if box then box:Hide() end
        return
    end
    if #list == 0 and not atCamp then return end   -- lingering: keep what's shown
    box = box or build()
    -- one line per buff kind (a Fish Bowl and a Fishing Hut give the same buff)
    local rows, byBenefit, campfire = {}, {}, nil
    for _, s in ipairs(list) do
        local o = s.obj
        if o.benefit == "campfire" then
            campfire = o
        elseif not byBenefit[o.benefit] then
            local st, txt = C:Judge(o)
            byBenefit[o.benefit] = true
            rows[#rows + 1] = { st = st, txt = txt, name = o.name }
        end
    end
    -- at a campfire: camp buffs you're wearing count as seen ("have"), even if their object wasn't
    if atCamp then
        for key, b in pairs(CD.benefits) do
            if b.aura and not byBenefit[key] and aura(b.aura) then
                local name
                for _, o in pairs(CD.objects) do
                    if o.benefit == key and o.nameFallback and (not name or #o.name < #name) then name = o.name end
                end
                local st, txt = C:Judge({ benefit = key, name = name or key })
                byBenefit[key] = true
                rows[#rows + 1] = { st = st, txt = txt, name = name or key }
            end
        end
        -- and what your Camp Benefits lists (the real source on Forever)
        local have, haveExp = C:Benefits()
        for key, v in pairs(have or {}) do
            if not byBenefit[key] then
                byBenefit[key] = true
                rows[#rows + 1] = { st = "have", txt = haveText(haveExp), name = v.name }
            end
        end
    end
    table.sort(rows, function(a, b)
        if ORDER[a.st] ~= ORDER[b.st] then return ORDER[a.st] < ORDER[b.st] end
        return a.name < b.name
    end)
    local new = 0
    for _, r in ipairs(rows) do if r.st == "new" then new = new + 1 end end
    if new > 0 then
        box.title:SetText(("|cff33ff33Worth sitting:|r %d new buff%s"):format(new, new == 1 and "" or "s"))
    elseif #rows > 0 then
        box.title:SetText("|cff8c8c9eNothing new for you here|r")
    else
        box.title:SetText("|cff00c7ffCampfire|r")
    end
    -- the Sit button: at a fire and not already resting (then the countdown line takes over)
    local restA = aura(REST_AURA)
    local restExp = restA and readable(restA.expirationTime) and restA.expirationTime
    local showSit = atCamp and not (restExp and restExp > GetTime())
    box.sit:SetShown(showSit and true or false)
    local i = 0
    local width = box.title:GetStringWidth() + 20 + 20 + (showSit and 52 or 0)   -- + the x, + Sit
    local function line(left, right)
        i = i + 1
        local l = box.lines[i]
        if not l then
            l = { left = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"),
                  right = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") }
            box.lines[i] = l
        end
        l.left:ClearAllPoints(); l.left:SetPoint("TOPLEFT", 8, -10 - i * 14)
        l.right:ClearAllPoints(); l.right:SetPoint("TOPRIGHT", -8, -10 - i * 14)
        l.left:SetText(left); l.right:SetText(right or "")
        l.left:Show(); l.right:Show()
        width = math.max(width, l.left:GetStringWidth() + l.right:GetStringWidth() + 30)
    end
    for _, r in ipairs(rows) do
        line(r.name .. "  " .. COLORS[r.st] .. r.txt .. "|r", COLORS[r.st] .. WORD[r.st] .. "|r")
    end
    if campfire then
        line("|cffb0b0b8" .. campfire.name .. ": " .. (campfire.utility or ""):gsub("additional camp features", "items") .. "|r")
    end
    if #rows == 0 then line("|cff8c8c9eWalk up to or hover its objects to see what they give.|r") end
    -- resting: the game's 1-minute timer before the buffs land
    local rest = aura(REST_AURA)
    local exp = rest and readable(rest.expirationTime) and rest.expirationTime
    if exp and exp > GetTime() then
        line(("|cffffd200Resting: buffs in %ds|r"):format(math.ceil(exp - GetTime())))
    elseif new > 0 and atCamp then
        line("|cff8c8c9eSit 1 minute by the fire to get them.|r")
    end
    for j = i + 1, #box.lines do box.lines[j].left:Hide(); box.lines[j].right:Hide() end
    box:SetSize(math.max(220, width), 16 + (i + 1) * 14)
    box:Show()
end

----------------------------------------------------------------------
-- Seeing objects: tooltips (hover) and the soft-interact target (walking up)
----------------------------------------------------------------------
-- Only world objects and NPCs (camp bots): a Camp Tent ITEM in your bags has the same name as the
-- placed tent and must not count as one standing here (Codex review).
local WORLD_TYPES = {}
if Enum and Enum.TooltipDataType then
    if Enum.TooltipDataType.Object then WORLD_TYPES[Enum.TooltipDataType.Object] = true end
    if Enum.TooltipDataType.Unit then WORLD_TYPES[Enum.TooltipDataType.Unit] = true end
end

local function onTooltip(tt, data)
    if not (forever() and on()) or tt ~= GameTooltip or type(data) ~= "table" then return end
    if not (readable(data.type) and WORLD_TYPES[data.type]) then return end
    local guid = readable(data.guid) and data.guid or nil
    local first = data.lines and data.lines[1] and data.lines[1].leftText
    local name = readable(first) and first or nil
    local obj, id = identify(guid, name)
    if not obj then return end
    note(guid or name, obj, id)
    local st, txt = C:Judge(obj)
    if st ~= "info" then
        tt:AddLine(("|cff00c7ffVoidSweep:|r %s%s|r"):format(COLORS[st], (st == "new" and "NEW for you: " or "") .. txt))
        tt:Show()
    end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_SOFT_INTERACT_CHANGED")
ev:RegisterUnitEvent("UNIT_AURA", "player")
ev:SetScript("OnEvent", function(_, event, _, newGuid)
    if event == "PLAYER_LOGIN" then
        restoreSeen()
        if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and TooltipDataProcessor.AllTypes then
            TooltipDataProcessor.AddTooltipPostCall(TooltipDataProcessor.AllTypes, onTooltip)
        end
    elseif event == "PLAYER_SOFT_INTERACT_CHANGED" then
        if not (forever() and on()) then return end
        local obj, id = identify(newGuid)
        if obj then note(newGuid, obj, id) end
    elseif event == "UNIT_AURA" then
        -- arriving at a campfire (its aura) opens the box; a buff came: "NEW" turns into "have"
        -- while closed too: it has to see you leave the fire to come back at the next one
        if forever() and on() and ((box and box:IsShown()) or closed or aura(CAMP_AURA)) then C:Refresh() end
    end
end)

-- Sit down (the box's Sit button). The emote API is marked restricted; if the game says no,
-- say what to do instead.
function C:Sit()
    if InCombatLockdown() then
        print("|cff00c7ffVoidSweep|r: you can't sit down in combat.")
        return
    end
    -- Only a real error counts: the return value's meaning is unclear (the API docs call it
    -- "success", Blizzard's own chat code reads it as "restricted"; Sol review), and sitting
    -- worked in game.
    local ok
    if C_ChatInfo and C_ChatInfo.PerformEmote then
        ok = pcall(C_ChatInfo.PerformEmote, "SIT")
    elseif DoEmote then
        ok = pcall(DoEmote, "SIT")
    end
    if not ok then
        print("|cff00c7ffVoidSweep|r: the game won't let an addon sit you down right now. Type |cffffd200/sit|r instead.")
    end
end

function C:Toggle()
    local cfg = VS:Config()
    cfg.campBox = cfg.campBox == false
    if not on() and box then box:Hide() end
    if on() then C:Refresh() end   -- show it right away when you're at a camp (Codex review)
    return on()
end
