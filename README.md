# VoidSweep

**Works on:** WoW Midnight · WoW Forever

> **WoW Forever players: please update to the latest version.** Versions from before November 10, 2026 use the old sharing channels (both factions in one, where messages to the other faction never arrive), so they can't share with current players and aren't counted in the Players online box. The CurseForge app updates it for you; if you installed by hand, download the newest file.

**A live map radar: rares, world bosses, treasures and lore that are up right now, with one click to get there.**

VoidSweep reads the game's own live spawn markers, so its pins show what's actually up right now, with the rare's health. It remembers every spot it has seen, shares spots and rare sightings between players, and hides treasures you've already looted. Click any pin for directions. On WoW Forever it spots rares from nameplates, your target and your mouseover, and tells you which campfires are worth sitting at.

---

## Features

### Live, not static
- **Up right now** — rares, world bosses, treasures and lore objects near you get a bright pin with a white ring; hover a rare to see its health
- **World bosses zone-wide** — the zone's world boss and events show as soon as you open the map, wherever you're standing
- **Remembers what it has seen** — once VoidSweep spots something, its pin stays on your map (dimmed) even after you fly away
- **Starter map included** — a fresh install already knows over 350 Midnight rares, treasures, world bosses and lore spots captured in game, and over 300 WoW Forever rares

### Shared between players
- **Spots others find** — when another VoidSweep player on your realm finds a rare, treasure or lore spot, it's added to your map too, so you can find places you've never been
- **Zone catch-up** — entering a zone asks other players for the spots they know there
- **Easy to tell apart** — other players' spots are smaller and fainter until a second player confirms them, and become yours once you see them yourself
- **Rare sightings** — when another player sees a rare up, it lights up on your map for a few minutes
- **Hover a shared pin** to see who found it and when
- **Who's here** — entering a zone tells you how many other VoidSweep players are in it (`/vsw here` asks any time)
- **Players-here box** — a small box you can drag anywhere that keeps that count on screen, updated as people come and go (VoidGather players too, if you have it). Turn it on in the map menu or with `/vsw box`

### Clean map
- **One colored dot per category** — red rares, orange world bosses, yellow treasures, purple lore
- **Delve treasure that moves every run** (like the blue bags) — each spot you find it in gets a faded light-blue dot; once it's turned up in the same spot on **3 different visits** the dot turns **dark green**, meaning "it's usually here". Bags with no minimap icon count too — they're recorded when you open them
- **Looted treasures disappear** automatically
- **Rares never disappear** — they respawn, so a rare you've killed stays as a dim pin and brightens when it's back
- **Click a pin for directions** — sets Blizzard's waypoint and arrow, cleared when you arrive. On another continent it points you to the right portal first, then on to the spot
- **Minimap pins** for remembered spots near you. They also show on VoidGather's gathering HUD

### Map menu
- **A button on the world map** to show or hide each category (with collected/total counts for the zone), completed treasures, minimap pins, sharing and the players-here box

### WoW Forever
- **Every Classic rare on your map** — over 300 rares (Humar the Pridelord, Rocklance, Takk the Leaper and the rest) with a pin where they spawn, one pin per rare. Click for directions.
- **Rares light up when seen:** the Classic world has no live rare markers, so VoidSweep watches nameplates, your target and your mouseover. A rare you see gets the bright ring for 5 minutes ("UP · seen 1 min ago"), and a kill is remembered for 2 hours ("Killed 12 min ago") so you can guess when it's back. Sightings are shared with other VoidSweep players.
- **Is this campfire worth sitting at?** Walk up to a player's campfire and a small box tells you, for *you*: "Worth sitting: 3 new buffs", or "Nothing new for you here". Each camp item gets a line: **NEW** with what you'd gain at your level (+8% stats, +21 Stamina...), **have** (minutes left), **covered** (your class buff of that kind already gives it, and they don't stack), **no use** (Intellect on a rogue, the other faction's banner) or **wait** (the tent's rested XP is on cooldown). While you rest it counts down to your buffs. Hovering a camp item adds the same verdict to its tooltip.
- **Layers:** a rare a Void player sees on another layer of your zone asks "Hop there?", and one click brings you over with a Void player's help (`/vsw hop` hops to any other layer). Every VoidSweep player can bring others over: when one on your layer asks, you send a quick group invite that ends on its own (only while you're solo and out of combat, at most once every 2 minutes); **Help others change layer** in the Void hub's quick switches turns that off. For a layer window, your layer under the minimap and one-click hops, add **VoidLayer**: it shares VoidSweep's layer network.

---

## Slash Commands

| Command | What it does |
|---|---|
| `/vsw` | Open the map and say how many things are up and remembered |
| `/vsw rare` · `/vsw chest` · `/vsw worldboss` · `/vsw lore` | Show or hide that category |
| `/vsw completed` | Show or hide treasures you've already looted |
| `/vsw minimap` | Minimap pins on or off |
| `/vsw sync` | Sharing with other players on or off |
| `/vsw here` | How many other VoidSweep players are in your zone |
| `/vsw box` | Players-here box on or off |
| `/vsw net` | Check that sharing works on your realm, and see how many other VoidSweep players are online there |
| `/vsw camp` | WoW Forever: the campfire box on or off |
| `/vsw layers` | WoW Forever: the layers in your zone (VoidLayer's window if you have it) |
| `/vsw spawns` | List the treasure spots recorded for the delve you're in |
| `/vsw clear` | Forget every spot VoidSweep has learned or been sent |

---

## Getting Started

1. Install with the CurseForge app, or copy the `VoidSweep` folder into `World of Warcraft/_retail_/Interface/AddOns/` (WoW Forever: `_forever_/Interface/AddOns/`).
2. Restart WoW or `/reload`.
3. Open your map in any zone — the dots are VoidSweep. Click one to head there.

---

## Privacy & Data

- **What's shared:** spots VoidSweep finds (their name, kind, zone and map position), and when you see a rare or world boss up, which one and its health. Nothing about your character, bags or gold.
- Other players see the character name that shared a spot or sighting, the same as any addon message.
- Only spots players saw themselves are passed on — never second-hand — so one bad report can't spread.
- With sharing off (`/vsw sync`), VoidSweep sends and receives nothing.

---

## Good to Know

- **Settings are per character.** Each character keeps its own VoidSweep settings, and a new character starts with the settings of the one you played last, so nothing resets when you update. If you also run a Void addon with the hub icon by your minimap (VoidBags, VoidAH, VoidGather, ...), right-click it and pick **Copy settings from...** to take another character's settings. Your learned and shared spots stay shared.
- The game only shows a rare or treasure to addons when you're fairly close, so a spot appears once you or another VoidSweep player passes by.
- Sharing reaches players on your realm group who are online and running VoidSweep.
- Learned spots are saved per account; looted treasures are tracked per character.

---

## Compatibility

- **WoW Midnight** 12.1.5 (Season 2)
- **WoW Forever**
- Standalone — nothing else to install

---

## Credits

- **WoW Forever rares and their spawn spots** come from [NorgannonDB](https://github.com/zmarotrix/NorgannonDB) by Maro (GPL-3.0), which builds on [QuestieDB](https://github.com/Questie/Questie) (GPL-3.0) and pfQuest, and reads WoW Forever's own game tables. Thank you.
- **Camp items and their buffs** come from [Campfire Tooltips: Forever](https://www.curseforge.com/wow/addons/campfire-tooltips) by GideonWhitlock (GPL-3.0-or-later, [source](https://github.com/GideonWhitlock/wow-forever-addons)). Thank you.

---

*Part of the Void addon family by Vede · GPL-3.0 licensed · [Source & bug reports](https://github.com/bughatti/voidsweep) · [All Void addons](https://www.curseforge.com/members/bughatti/projects) · free M+ & raid player lookups at [voidscout.io](https://voidscout.io) · more at [tinkerline.io](https://tinkerline.io) · [Discord](https://discord.gg/7ZHmx7zMDh)*
