-- VoidSweep: camp objects data, copied unchanged (below this header) from Campfire Tooltips: Forever
-- by GideonWhitlock, github.com/GideonWhitlock/wow-forever-addons commit 6e22c851f32a09bb8b1f9e349a55c73c5fd8dddf, GPL-3.0-or-later.
-- Only the namespace line differs: the data lives in VS.CampData. Refresh: copy the file again.
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Exact English names, used only for Object tooltips without a readable GUID.
-- Generic names require an ID. See SUPPORTED.md for recognition limits.
local _, VS = ...
VS.CampData = VS.CampData or {}
local ns = VS.CampData
local english = {
    ["Mana Well"] = 651948,
    ["Alchemy Laboratory"] = 612139,
    ["Fermenter"] = 612120,
    ["Sharpening Wheel"] = 651950,
    ["Master Forge"] = 612136,
    ["Enchanted Lute"] = 651952,
    ["Arcane Forge"] = 612143,
    ["Arcane Salvager"] = 612130,
    ["First Aid Kit"] = 651953,
    ["Plague Doctor's Laboratory"] = 612110,
    ["Toxin Study"] = 612091,
    ["Fish Bowl"] = 651954,
    ["Fishing Hut"] = 612092,
    ["Fishing Rack"] = 612090,
    ["Incense Candle"] = 651955,
    ["Lodestone"] = 651956,
    ["Molten Foundry"] = 612134,
    ["Rock Garden"] = 654285,
    ["Camp Chair"] = 612275,
    ["Trapper's Workbench"] = 612082,
    ["Camp Tent"] = 528996,
    ["Sewing Machine"] = 612140,
    ["Journeyman Campfire"] = 630660,
    ["Expert Campfire"] = 650137,
    ["Anarchist's Workbench"] = 612145,
    ["Iron Oven"] = 612132,
    ["Cookie's Feast"] = 612073,
    ["Chair"] = 612275,
}
local factional = {
    ["Faction Banner"] = { Alliance=612351, Horde=612350 },
}
ns.names = { enUS=english, enGB=english }
ns.factionNames = { enUS=factional, enGB=factional }
