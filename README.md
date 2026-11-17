# VoidSweep - Rare & Treasure Radar

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
- **Spots others find** — when another VoidSweep player on your realm finds a rare, treasure or lore spot, it's added to your map too, so you can find places you've never been. On WoW Forever spots spread from player to player like a torrent, so you get the ones found while you were offline too
- **Zone catch-up** — entering a zone asks other players for the spots they know there
- **Easy to tell apart** — other players' spots are smaller and fainter until a second player confirms them, and become yours once you see them yourself
- **Rare sightings** — when another player sees a rare up, it lights up on your map for a few minutes
- **Hover a shared pin** to see when it was found and how many players confirmed it
- **Who's here** — entering a zone tells you how many other VoidSweep players are in it (`/vsw here` asks any time)
- **Players-here box** — a small box you can drag anywhere that keeps that count on screen, updated as people come and go (on WoW Forever its **VoidNet** line counts every Void addon player online, each once). Turn it on in the map menu or with `/vsw box`

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
- **Rares light up when seen:** the Classic world has no live rare markers, so VoidSweep watches nameplates, your target and your mouseover. A rare you see gets the bright ring for 5 minutes ("UP · seen 1 min ago"), and a kill is remembered for 2 hours ("Killed 12 min ago") so you can guess when it's back. Sightings are shared with other VoidSweep players, and a kill on your layer reaches players who log in later too (a kill on another layer doesn't mark it dead for you). Once two players have seen a rare come back after a kill, its tooltip says "Usually back after about 30 min".
- **Rares in dungeons and raids:** a rare (or rare elite) that shows up on a nameplate, your target or your mouseover plays a sound and says "Blind Hunter is here!", once per rare per run. Inside, there's no map pin and nothing is shared (every group has its own copy of the dungeon). With **VoidGPS**, its rare popup does this instead, so you never get two alerts.
- **Is this campfire worth sitting at?** Walk up to a player's campfire and a small box tells you, for *you*: "Worth sitting: 3 new buffs", or "Nothing new for you here". Each camp item gets a line: **NEW** with what you'd gain at your level (+8% stats, +21 Stamina...), **have** (minutes left), **covered** (your class buff of that kind already gives it, and they don't stack), **no use** (Intellect on a rogue, the other faction's banner) or **wait** (the tent's rested XP is on cooldown). While you rest it counts down to your buffs. Hovering a camp item adds the same verdict to its tooltip.
- **Sleeping bag invites:** unroll your Cozy Sleeping Bag and whispers with "bag" get a party invite for 15 minutes, with a whisper back saying where your bag is (never a plain "inv", one invite per player per bag). The camp box gets a **Bag** button: one click says it in /say and puts a star on you so they can find you; right-click takes the star off
- **Layers:** a rare a Void player sees on another layer of your zone asks "Hop there?", and one click brings you over with a Void player's help (`/vsw hop` hops to any other layer). Every VoidSweep player can bring others over: when one on your layer asks, you send a quick group invite that ends on its own (only while you're solo and out of combat, at most once every 2 minutes); **Help Void layer hopping** in the Void hub's quick switches turns that off (one switch for every Void addon). For a layer window, your layer under the minimap and one-click hops, add **VoidLayer**: it's on the same network.

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
| `/vsw bag` | WoW Forever: sleeping bag invites on or off |
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

- **What's shared:** spots VoidSweep finds (their name, kind, zone and map position), and when you see a rare or world boss up, which one and its health. On WoW Forever also when you saw a rare killed (and the layer number), and how many minutes a rare stayed down before you saw it again (rounded: 5, 10, 15, 20, 30 ... minutes). Nothing about your character, bags or gold.
- **How:** by hidden addon whisper, one player at a time. Like any whisper, the player who gets it can see which character sent it. "It's up" alerts go out live; that's what they're for.
- **Passed on (WoW Forever):** a spot two players agree on, and a kill time, is passed along by the players who have it; whoever gets it from them sees their name, not yours. One player's spot alone isn't passed on, so a single bad report can't spread. Votes are counted with a one-way code, not names; a spot keeps its finder's name only when an older VoidSweep reported it directly.
- **VoidNet, one network for the Void addons (WoW Forever):** VoidSweep, VoidLayer, VoidQuest, VoidGather, VoidBounty and VoidDungeon players of your faction meet in **one** hidden channel whose name and password change every hour, with backups. Spots, kill times and respawn times ride it.
- **Hard to break:** if someone takes the channel over, bans or kicks Void players or changes its password, everyone moves to a backup and that player is ignored for 24 hours. Nothing is shown as a list of names.
- **Kept on your computer:** the Void players you heard from in the last 2 hours (names and a time, deleted after 2 hours, never shown or shared) and players marked for attacking the channel (24 hours).
- **Older VoidSweep versions keep working.** Their old channel is kept while players on an older version are on it, and dropped 30 days after the last one. The old spot messages stop by themselves once no older version has been seen for 30 days (they start again if one shows up); `/vsw net` shows when one was last heard.
- With sharing off (`/vsw sync`), VoidSweep sends and takes nothing, and only your own sightings show.

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

- **WoW Forever rares and their spawn spots** come from VoidDB. **VoidDB**, the game data the Void addons ship, is built from Blizzard's game data, finds shared by Void players, and open data: NorgannonDB by Maro, QuestieDB, pfQuest by Shagu, DungeonJournal by Exehn and CMaNGOS classic-db (GPL-3.0; pfQuest MIT). Full credits and licences: NOTICE.txt in the addon folder. Thank you to all of them.
- **Camp items and their buffs** come from [Campfire Tooltips: Forever](https://www.curseforge.com/wow/addons/campfire-tooltips) by GideonWhitlock (GPL-3.0-or-later, [source](https://github.com/GideonWhitlock/wow-forever-addons)). Thank you.

---

*Part of the Void addon family by Vede · GPL-3.0 licensed · [Source & bug reports](https://github.com/bughatti/voidsweep) · [All Void addons](https://www.curseforge.com/members/bughatti/projects) · free M+ & raid player lookups at [voidscout.io](https://voidscout.io) · more at [tinkerline.io](https://tinkerline.io/addons/voidsweep/) · [Discord](https://discord.gg/7ZHmx7zMDh)*
