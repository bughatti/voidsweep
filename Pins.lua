----------------------------------------------------------------------
-- VoidSweep — Map pins
--
-- A MapCanvas data provider bolted onto WorldMapFrame. On every refresh
-- it clears its pins and re-draws one per live vignette that (a) the user
-- hasn't filtered out and (b) has a position on the currently-open map.
-- The pin reuses the vignette's OWN atlas, so it looks exactly like the
-- game's marker — zero custom art.
----------------------------------------------------------------------
local ADDON, VS = ...

local PIN_TEMPLATE = "VoidSweepPinTemplate"

-- Rares and world bosses respawn: even when flagged "done" (a daily kill
-- quest) they stay on the map — dimmed when not up, bright when up — instead
-- of vanishing like a looted treasure. (Defined before the pin mixin, which
-- uses it.)
local RESPAWNS = { rare = true, worldboss = true }
VS.Respawns = RESPAWNS

local KIND_LABEL = {
    rare       = "Rare",
    chest      = "Treasure",
    worldboss  = "World Boss",
    lore       = "Lore",
    mount      = "Mount",
    pet        = "Pet",
    toy        = "Toy",
    decor      = "Decor",
    junk       = "Fun / Junk",
    profession = "Profession",
}

-- Colored dot per category (WhiteCircle-RaidBlips tinted). One look for every
-- pin — color = category, brightness/alpha = state.
local function applyDot(tex, entry)
    local c = (entry.confirmed and VS.ConfirmedSpawnColor)
        or (entry.heat and VS.SpawnSpotColor)
        or VS.CategoryColor[entry.kind] or VS.CategoryColor.default
    tex:SetAtlas("WhiteCircle-RaidBlips")
    tex:SetVertexColor(c[1], c[2], c[3])
    tex:SetDesaturated(false)
end

----------------------------------------------------------------------
-- Pin
----------------------------------------------------------------------
VoidSweepPinMixin = CreateFromMixins(MapCanvasPinMixin)

function VoidSweepPinMixin:OnLoad()
    -- Framework calls this itself (MapCanvasMixin:AcquirePin). Mouse is
    -- enabled at the XML template level; don't touch it here or the
    -- first-acquire wiring pass in Blizzard_MapCanvas will assert.
    self:SetScalingLimits(1, 0.9, 1.15)          -- stay readable across zoom
    self:UseFrameLevelType("PIN_FRAME_LEVEL_VIGNETTE")
    self.ring:SetAtlas("WhiteCircle-RaidBlips")   -- white disc behind dot = border
    self.ring:SetVertexColor(1, 1, 1)
end

function VoidSweepPinMixin:OnAcquired(entry, x, y, isLive)
    self.entry = entry
    self.isLive = isLive
    self:SetPosition(x, y)
    applyDot(self.icon, entry)
    -- color = category (set above); alpha/size = state.
    local up = entry.reported or isLive   -- UP right now: seen live or reported
    if entry.reported then
        self:SetAlpha(0.95); self:SetSize(15, 15)   -- crowd-reported
    elseif isLive then
        self:SetAlpha(1.0);  self:SetSize(14, 14)   -- up, you're near it
    elseif entry.confirmed then                      -- confirmed delve spawn spot: solid dark green
        self:SetAlpha(1.0);  self:SetSize(14, 14)
    elseif entry.heat then                           -- unconfirmed spawn spot: faded light blue
        self:SetAlpha(0.45); self:SetSize(11, 11)
    elseif entry.shared then                         -- another player's spot
        self:SetAlpha((entry.c or 1) >= 2 and 0.45 or 0.3); self:SetSize(10, 10)
    elseif RESPAWNS[entry.kind] and VS:IsDone(entry) then
        self:SetAlpha(0.3);  self:SetSize(11, 11)   -- killed before, not up
    else
        self:SetAlpha(0.5);  self:SetSize(12, 12)   -- known / not up
    end
    -- white border = "it's up" (whether you saw it or VoidSync told you).
    -- +8 => ~4px of white shows around the dot; bump for a thicker border.
    if up then
        self.ring:SetSize(self:GetWidth() + 8, self:GetHeight() + 8)
        self.ring:Show()
    else
        self.ring:Hide()
    end
    self:Show()
end

function VoidSweepPinMixin:OnReleased()
    self.entry = nil
    self.isLive = nil
end

function VoidSweepPinMixin:OnMouseEnter()
    local e = self.entry
    if not e then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(e.name or "Unknown", 1, 1, 1)
    GameTooltip:AddLine(KIND_LABEL[e.kind] or "Point of Interest", 0.6, 0.8, 1)

    if e.reported then
        local s = e.senders or 1
        GameTooltip:AddLine(("|cff77ccffReported UP|r by %d player%s · %ds ago"):format(
            s, s == 1 and "" or "s", e.age or 0), 0.45, 0.75, 1)
    elseif e.isPoi then
        if e.secondsLeft and e.secondsLeft > 0 then
            GameTooltip:AddLine("Available · " .. SecondsToTime(e.secondsLeft) .. " left", 0.3, 1, 0.3)
        else
            GameTooltip:AddLine("Available", 0.3, 1, 0.3)
        end
    elseif e.heat then
        GameTooltip:AddLine(("Spawn spot · seen here on %d of %d visits"):format(e.hits or 0, e.visits or 0), 0.85, 0.8, 0.4)
        if e.confirmed then
            GameTooltip:AddLine("Confirmed spot (dark green) -- seen here on 3+ visits", 0.2, 0.85, 0.35)
        else
            GameTooltip:AddLine("Seen once or twice (light blue) -- turns dark green after 3 visits", 0.6, 0.6, 0.6)
        end
    elseif self.isLive then
        local hp = e.guid and C_VignetteInfo.GetHealthPercent and C_VignetteInfo.GetHealthPercent(e.guid)
        if hp then
            GameTooltip:AddLine(("UP  ·  %d%% HP"):format(math.floor(hp * 100 + 0.5)), 0.3, 1, 0.3)
        else
            GameTooltip:AddLine("UP", 0.3, 1, 0.3)
        end
    elseif e.shared then
        local who = (e.c or 1) >= 2 and ("%d players"):format(e.c) or (e.f or "another player")
        local ago = SecondsToTime(math.max(60, time() - (e.t or time())), true)
        GameTooltip:AddLine(("Found by %s · %s ago"):format(who, ago), 0.45, 0.75, 1)
        if (e.c or 1) < 2 then
            GameTooltip:AddLine("Unconfirmed until a second player finds it", 0.6, 0.6, 0.6)
        end
    elseif VS:IsDone(e) and RESPAWNS[e.kind] then
        GameTooltip:AddLine("Killed before · not up right now", 0.6, 0.6, 0.6)
    elseif VS:IsDone(e) then
        GameTooltip:AddLine("Completed", 0.6, 0.6, 0.6)
    elseif e.seed then
        -- shipped with VoidSweep (Seed.lua), nobody's sighting of yours
        GameTooltip:AddLine("Known spawn spot · not up right now", 0.85, 0.8, 0.4)
    else
        GameTooltip:AddLine("Seen here before · not up right now", 0.85, 0.8, 0.4)
    end
    GameTooltip:AddLine("Click to travel", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

function VoidSweepPinMixin:OnMouseLeave()
    GameTooltip:Hide()
end

-- Base MapCanvasPinMixin:OnClick dispatches here (it checks self.OnMouseClickAction).
function VoidSweepPinMixin:OnMouseClickAction(button)
    if button == "LeftButton" and self.entry then
        local mapID = self:GetMap():GetMapID()
        VS.Nav:Goto(mapID, self.entry, self.entry.name)
    end
end

----------------------------------------------------------------------
-- Data provider
----------------------------------------------------------------------
VoidSweepDataProviderMixin = CreateFromMixins(MapCanvasDataProviderMixin)

function VoidSweepDataProviderMixin:RemoveAllData()
    if self:GetMap() then
        self:GetMap():RemoveAllPinsByTemplate(PIN_TEMPLATE)
    end
end

-- More specific kinds win a same-name collision (a thing that appears as
-- both a rare vignette and an event POI should show once, as the rare).
local KIND_RANK = {
    worldboss = 10, rare = 9, mount = 8, pet = 7, toy = 6,
    decor = 5, profession = 4, chest = 3, lore = 2, junk = 1,
}

function VoidSweepDataProviderMixin:RefreshAllData()
    -- Acquiring pins makes the map framework call protected mouse funcs
    -- (SetPassThroughButtons / SetPropagateMouseClicks), which are BLOCKED in
    -- combat and taint. So in combat, LEAVE the existing pins exactly as they
    -- are (map pins are positioned by world coords, so they stay correct) and
    -- do nothing; Core rebuilds on PLAYER_REGEN_ENABLED when combat ends.
    -- Exception: if the viewed map changed, HIDE the old map's pins so they
    -- don't sit on the new map at the old map's coords. Only hide: releasing
    -- them (RemoveAllPinsByTemplate) marks Blizzard's canvas dirty, writing its
    -- shared scale/scroll fields from addon code -- the same combat taint.
    local map = self:GetMap()
    local mapID = map and map:GetMapID()
    if InCombatLockdown() then
        if mapID ~= self.drawnMapID and map then
            for pin in map:EnumeratePinsByTemplate(PIN_TEMPLATE) do pin:Hide() end
            self.drawnMapID = nil
        end
        return
    end
    self:RemoveAllData()
    self.drawnMapID = mapID
    if not mapID then return end

    for _, c in ipairs(VS.Pins:Build(mapID)) do
        map:AcquirePin(PIN_TEMPLATE, c.entry, c.x, c.y, c.isLive)
    end
end

----------------------------------------------------------------------
-- Wiring
----------------------------------------------------------------------
VS.Pins = {}

-- Assemble the final deduped pin set for a map from every source (seed +
-- learned, live vignettes, POIs, crowd reports). Shared by the world-map
-- provider AND the minimap so the two never drift. Returns an array of
-- { entry, x, y, isLive }.
function VS.Pins:Build(mapID)
    local cfg = VS:Config()
    local candidates = {}

    -- Dedup key = shared identity across seed / learned / live, so the same
    -- thing collapses to one pin even when coords or name differ. questID and
    -- vignetteID are the stable identities; fall back to name + rounded pos.
    local function dedupKey(e, x, y)
        if e.spawnKey then return e.spawnKey end   -- each spawn spot is its own pin
        if e.questID and e.questID ~= 0 then return "q" .. e.questID end
        if e.vignetteID then return "v" .. e.vignetteID end
        return ("nc:%s@%d,%d"):format(e.name or "?",
            math.floor((x or 0) * 1000), math.floor((y or 0) * 1000))
    end

    -- vignetteID -> the dedup key its pin got (crowd reports carry no questID,
    -- so they'd otherwise key as "vV" while their twin keys as "qQ")
    local vidKey = {}

    local function consider(entry, x, y, isLive)
        if not (x and y) then return end
        if not entry.name or entry.name == "" then return end  -- skip seed artifacts
        if cfg.show[entry.kind] == false then return end
        local done = VS:IsDone(entry) and not RESPAWNS[entry.kind]
        if done and not cfg.showCompleted then return end
        if done then isLive = false end   -- completed treasure always renders dim

        local key = dedupKey(entry, x, y)
        if entry.vignetteID then vidKey[entry.vignetteID] = key end
        local prio = (isLive and 100 or 0) + (KIND_RANK[entry.kind] or 0)
        local ex = candidates[key]
        if not ex or prio > ex.prio then
            candidates[key] = { entry = entry, x = x, y = y, isLive = isLive, prio = prio }
        end
    end

    -- Known (seed + learned), dim. Record DONE/cleared identities — only these
    -- rows carry the completion refs + proximity-cleared flag, so the live/POI
    -- layers below rely on this to stay hidden too.
    local doneKeys = {}
    for key, rec in pairs(VS.Learned:GetKnownForMap(mapID)) do
        if VS.Spawns and VS.Spawns:IsRandom(mapID, rec.vignetteID) then
            -- random-spawn treasure: its single "last seen" pin is misleading;
            -- the spawn-spot pins below replace it
        elseif (VS:IsDone(rec) and not RESPAWNS[rec.kind]) or VS.Learned:IsCleared(mapID, key) then
            local dk = dedupKey(rec, rec.x, rec.y)
            doneKeys[dk] = true
            if rec.vignetteID then vidKey[rec.vignetteID] = dk end
            if cfg.showCompleted then
                consider(rec, rec.x, rec.y, false)   -- reveal completed when asked
            end
        else
            consider(rec, rec.x, rec.y, false)
        end
    end
    -- Delve spawn spots for random treasure (sized/brightened by how often).
    if VS.Spawns then
        for _, c in ipairs(VS.Spawns:Candidates(mapID)) do
            consider(c.entry, c.x, c.y, false)
        end
    end
    -- Live vignettes, bright. Skip any whose known twin is completed.
    for _, entry in ipairs(VS.Scanner:GetLive()) do
        local pos = C_VignetteInfo.GetVignettePosition(entry.guid, mapID)
        if pos then
            local x, y = pos:GetXY()
            if not doneKeys[dedupKey(entry, x, y)] then
                consider(entry, x, y, true)
            end
        end
    end
    -- Zone-wide Area POIs (world bosses + events), bright.
    for _, poi in ipairs(VS.Poi:Scan(mapID)) do
        if not doneKeys[dedupKey(poi, poi.x, poi.y)] then
            consider(poi, poi.x, poi.y, true)
        end
    end
    -- Crowd reports (VoidSync): "UP right now", so they replace a remembered
    -- (dim) pin of the same thing; only your own live sighting beats them.
    -- Same category filter as everything else.
    if VS.Sync and cfg.sync ~= false then
        for _, rep in ipairs(VS.Sync:GetForMap(mapID)) do
            if cfg.show[rep.kind] ~= false then
                local key = vidKey[rep.vignetteID] or dedupKey(rep, rep.x, rep.y)
                local ex = candidates[key]
                if not doneKeys[key] and not (ex and ex.isLive) then
                    candidates[key] = { entry = rep, x = rep.x, y = rep.y, isLive = false, prio = -1 }
                end
            end
        end
    end

    local out = {}
    for _, c in pairs(candidates) do out[#out + 1] = c end
    return out
end

function VS.Pins:Init()
    if self.provider then return end
    self.provider = CreateFromMixins(VoidSweepDataProviderMixin)
    WorldMapFrame:AddDataProvider(self.provider)
end

-- Live refresh (vignette set changed while the map is open).
function VS.Pins:Refresh()
    if self.provider and WorldMapFrame:IsShown() then
        self.provider:RefreshAllData()
    end
end
