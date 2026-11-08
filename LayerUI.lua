----------------------------------------------------------------------
-- VoidSweep — Layers window (WoW Forever, 2026-11-08)
--
-- One small window for everything layers: your layer, every layer other VoidSweep
-- players reported in this zone (how many, and whether one of them hosts hops), a Hop
-- button per layer, "Hop to any layer", Refresh (asks the network; 5-minute limit per
-- zone), what a hop is doing right now, the 5-minute hop timer, and the two options:
-- host hops for others, and stay grouped after a hop.
-- Open: /vsw layers, or "Layers..." in VoidSweep's world-map button menu. Drag to move.
----------------------------------------------------------------------
local ADDON, VS = ...
VS.LayerUI = {}
local UI = VS.LayerUI

local A = { 0, 0.78, 1 }   -- Void cyan
local ROWS = 8
local W, ROW_H = 300, 20
local win

local function forever() return RegionalUniqueNamesEnabled ~= nil and RegionalUniqueNamesEnabled() == true end

local function db()
    VoidSweepDB = VoidSweepDB or {}
    return VoidSweepDB
end

local function button(parent, text, w)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 20)
    b:SetText(text)
    return b
end

local function check(parent, label, tip, get, set)
    local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    c:SetSize(22, 22)
    c.text = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    c.text:SetPoint("LEFT", c, "RIGHT", 2, 0)
    c.text:SetText(label)
    c:SetScript("OnClick", function(self) set(self:GetChecked()) end)
    c:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(label)
        GameTooltip:AddLine(tip, 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    c.get = get
    return c
end

local function build()
    local f = CreateFrame("Frame", "VoidSweepLayersFrame", UIParent, "BackdropTemplate")
    f:SetSize(W, 120)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    f:SetBackdropColor(0.04, 0.04, 0.07, 0.92)
    f:SetBackdropBorderColor(A[1], A[2], A[3], 0.6)
    local p = db().layerUIPos
    if p then f:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else f:SetPoint("CENTER", UIParent, "CENTER", 300, 80) end
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local pt, _, rel, x, y = self:GetPoint()
        db().layerUIPos = { pt, rel, x, y }
    end)
    table.insert(UISpecialFrames, "VoidSweepLayersFrame")   -- Esc closes it

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 10, -8)
    f.title:SetTextColor(A[1], A[2], A[3])
    f.title:SetJustifyH("LEFT")
    f.title:SetWidth(W - 40)
    f.title:SetWordWrap(false)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", 1, 1)

    -- your layer
    f.mine = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.mine:SetPoint("TOPLEFT", 10, -28)
    f.mine:SetJustifyH("LEFT")
    f.mine:SetWidth(W - 20)

    -- other layers
    f.rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Frame", nil, f)
        r:SetSize(W - 20, ROW_H)
        r:SetPoint("TOPLEFT", 10, -44 - (i - 1) * ROW_H)
        r.bg = r:CreateTexture(nil, "BACKGROUND")
        r.bg:SetAllPoints()
        r.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.04 or 0)
        r.pair = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.pair:SetPoint("LEFT", 4, 0)
        r.pair:SetWidth(80)
        r.pair:SetJustifyH("LEFT")
        r.who = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.who:SetPoint("LEFT", r.pair, "RIGHT", 4, 0)
        r.who:SetWidth(120)
        r.who:SetJustifyH("LEFT")
        r.hop = button(r, "Hop", 56)
        r.hop:SetPoint("RIGHT", 0, 0)
        r.hop:SetScript("OnClick", function(self) if self.pairID then VS.Hop:Start(self.pairID); UI:Update() end end)
        r:Hide()
        f.rows[i] = r
    end

    f.empty = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.empty:SetPoint("TOPLEFT", 14, -48)
    f.empty:SetWidth(W - 28)
    f.empty:SetJustifyH("LEFT")

    -- bottom: buttons, status, options
    f.any = button(f, "Hop to any layer", 130)
    f.any:SetScript("OnClick", function() VS.Hop:Start(nil); UI:Update() end)
    f.refresh = button(f, "Refresh", 130)
    f.refresh:SetScript("OnClick", function()
        local _, zone = VS.Layer:Here()
        if zone and VS.LayerNet:Ask(zone) then
            f.asking = GetTime()
        end
        UI:Update()
    end)
    f.refresh:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Ask other VoidSweep players in this zone which layer they're on.", 1, 1, 1, true)
        GameTooltip:AddLine("Once every 5 minutes per zone, to keep the chatter down.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    f.refresh:SetScript("OnLeave", function() GameTooltip:Hide() end)

    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.status:SetJustifyH("LEFT")
    f.status:SetWidth(W - 20)

    f.host = check(f, "Host hops for others",
        "Let VoidSweep players on your layer ask you for a quick group invite to join it. Only while you're solo, out of combat and outside dungeons; you leave the group on your own after 3 minutes.",
        function() return VS.Hop:HostingOn() end, function(on) VS.Hop:SetHosting(on) end)
    f.stay = check(f, "Stay grouped after a hop",
        "Stay in the host's group after hopping. Only needed if leaving sends you back to your old layer; VoidSweep turns this on by itself when it sees that happen.",
        function() return VS:Config().hopStay == true end, function(on) VS:Config().hopStay = on and true or false end)

    f:SetScript("OnShow", function() UI:Update() end)
    f.elapsed = 0
    f:SetScript("OnUpdate", function(self, dt)
        self.elapsed = self.elapsed + dt
        if self.elapsed >= 1 then self.elapsed = 0; UI:Update() end
    end)
    f:Hide()
    return f
end

-- Rows sorted: layers with a host first, then by how many Void players.
local function layers(zone, mine)
    local LN, out = VS.LayerNet, {}
    for pair, n in pairs(LN:Counts(zone)) do
        if pair ~= mine then out[#out + 1] = { pair = pair, n = n, hosts = #LN:Hosts(zone, pair) } end
    end
    table.sort(out, function(a, b)
        if (a.hosts > 0) ~= (b.hosts > 0) then return a.hosts > 0 end
        return a.n > b.n
    end)
    return out
end

function UI:Update()
    local f = win
    if not (f and f:IsShown()) then return end
    local mine, zone = VS.Layer:Here()
    local info = zone and C_Map.GetMapInfo(zone)
    f.title:SetText("VoidSweep Layers" .. (info and ("  ·  " .. info.name) or ""))

    if not forever() then
        f.mine:SetText("Layers are a WoW Forever thing.")
    elseif mine then
        local here = VS.LayerNet:Counts(zone)[mine] or 0
        f.mine:SetText(("Your layer: |cffffd200%s|r%s"):format(mine,
            here > 0 and ("  (+%d Void player%s)"):format(here, here == 1 and "" or "s") or ""))
    else
        f.mine:SetText("Your layer: |cff999999not known yet|r · point at or target any NPC")
    end

    local list = zone and layers(zone, mine) or {}
    local busy, cd = VS.Hop:Busy(), VS.Hop:CooldownLeft()
    local blocked = busy or cd > 0 or not mine or IsInGroup() or InCombatLockdown() or IsInInstance()
    for i, r in ipairs(f.rows) do
        local l = list[i]
        if l then
            r.pair:SetText(l.pair)
            r.who:SetText(("%d Void player%s"):format(l.n, l.n == 1 and "" or "s"))
            r.hop.pairID = l.pair
            r.hop:SetShown(l.hosts > 0)
            r.hop:SetEnabled(not blocked)
            r:Show()
        else
            r:Hide()
        end
    end
    local shown = math.min(#list, ROWS)
    if shown == 0 then
        f.empty:SetText(f.asking and GetTime() - f.asking < 6 and "Asking the VoidSweep players here..."
            or "No other layers known here yet. Refresh asks the VoidSweep players in this zone.")
        f.empty:Show()
    else
        f.empty:Hide()
    end

    -- layout below the rows
    local y = -48 - math.max(shown, 1) * ROW_H - 8
    f.any:ClearAllPoints();     f.any:SetPoint("TOPLEFT", 10, y)
    f.refresh:ClearAllPoints(); f.refresh:SetPoint("TOPRIGHT", -10, y)
    local anyHost = false
    for _, l in ipairs(list) do if l.hosts > 0 then anyHost = true break end end
    f.any:SetEnabled(anyHost and not blocked)
    local left = zone and VS.LayerNet:AskLeft(zone) or 0
    f.refresh:SetEnabled(forever() and zone ~= nil and left == 0)
    f.refresh:SetText(left > 0 and ("Refresh (%d:%02d)"):format(math.floor(left / 60), math.floor(left % 60)) or "Refresh")

    y = y - 26
    local status = VS.Hop:Status()
    if not status then
        if cd > 0 then status = ("Next hop in %d:%02d (one every 5 minutes)."):format(math.floor(cd / 60), math.floor(cd % 60))
        elseif IsInGroup() then status = "In a group: leave it to hop (moving a whole group comes later)."
        elseif InCombatLockdown() then status = "In combat."
        elseif not anyHost and shown > 0 then status = "Nobody on those layers hosts hops right now."
        end
    end
    f.status:ClearAllPoints()
    f.status:SetPoint("TOPLEFT", 10, y)
    f.status:SetText(status or "")
    if status then y = y - 16 end

    f.host:ClearAllPoints(); f.host:SetPoint("TOPLEFT", 6, y)
    f.stay:ClearAllPoints(); f.stay:SetPoint("TOPLEFT", 6, y - 22)
    f.host:SetChecked(f.host.get())
    f.stay:SetChecked(f.stay.get())
    f:SetHeight(-(y - 22) + 28)
end

function UI:Toggle()
    win = win or build()
    if win:IsShown() then win:Hide() else win:Show() end
end

function UI:Show()
    win = win or build()
    win:Show()
end

-- Opening it asks the network too (the 5-minute limit per zone still applies).
local function askOnOpen()
    local _, zone = VS.Layer:Here()
    if zone and forever() and VS.LayerNet:Ask(zone) and win then win.asking = GetTime() end
end
local origToggle, origShow = UI.Toggle, UI.Show
function UI:Toggle() origToggle(self); if win and win:IsShown() then askOnOpen() end end
function UI:Show() origShow(self); askOnOpen() end
