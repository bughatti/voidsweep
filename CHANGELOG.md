# VoidSweep Changelog

## 0.2.10

- **Settings are per character.** Each character keeps its own VoidSweep settings, and a new character starts with the settings of the one you played last, so nothing resets when you update. If you also run a Void addon with the hub icon by your minimap (VoidBags, VoidAH, VoidGather, ...), right-click it and pick **Copy settings from...** to take another character's settings. Your learned and shared spots stay shared.

## 0.2.9

- **Works with VoidGather's gathering HUD.** VoidSweep's minimap pins stay on the minimap and stay visible when VoidGather turns it into a see-through HUD in front of you.

## 0.2.8

- **Bigger starter map.** A fresh install now knows 358 spots (was 154), including far more of The Coiled Isle and Harandar.
- **Players-here box.** A small box you can drag anywhere showing how many other VoidSweep (and VoidGather) players are in your zone. Turn it on in the map menu or with `/vsw box`.

## 0.2.7

- **Directions across continents.** Clicking a pin in another zone or continent now sends you to the right portal first (Silvermoon, Orgrimmar, Stormwind, Voidstorm, Harandar), then on to the spot once you arrive. The waypoint still clears itself when you get there, and VoidSweep never touches a waypoint you set yourself.

## 0.2.6

- **Who's here.** When you enter a zone, VoidSweep tells you how many other VoidSweep players are in it ("3 other VoidSweep players are in Zul'Aman."). It stays quiet when nobody else is there; `/vsw here` asks anytime. Caves and city floors count as their zone, instances aren't counted, players with crowd sync off aren't counted, and players on an older VoidSweep don't answer yet.

## 0.2.5

- **Map pins:** changing maps in combat no longer leaves the old map's pins on the new one; a rare someone else reports as up now replaces your dim "remembered" pin instead of hiding behind it, and reports follow your category filters.
- **Map button counts** no longer count the same rare twice or count rares from other maps.
- **Sharing:** a report fades when it expires instead of waiting for a map redraw; one player can't keep a "2 players saw it" report alive alone; messages are paced properly.
- **Waypoints:** VoidSweep never clears a waypoint you set yourself, and only auto-clears its own when you're actually following it.
- World boss / event changes refresh the map.

## 0.2.4

- **`/vsw net` shows who else is out there.** Besides checking that sharing works, it now tells you how many other VoidSweep players are online on your realm group right now, and how many rare sightings and spots you've received from other players this session.

## 0.2.3

- **Smooth minimap pins.** Pins no longer jitter while you fly or ride; they now move with the minimap every frame instead of catching up a few times a second.

## 0.2.2

- **Minimap pins now actually show.** A bug kept every VoidSweep pin off the minimap (the world map was fine).
- **Random treasure spots in delves.** Treasure that moves every run (like the blue Mislaid Curiosity bags) is now counted spot-by-spot across your visits. Every spot shows as a faded light-blue dot from its first sighting and turns **dark green** once it's been seen there on 3 visits (also explained in the world-map button menu) — on the minimap and world map, with "seen here on 7 of 10 visits" on hover. `/vsw spawns` lists the spots for the delve you're in. Bags with no minimap icon are counted too - recorded the moment you open them.

## 0.2.1

- Updated for WoW 12.1.5 — no longer shows as out of date.

## 0.2.0 — first public release

- Live pins for rares, world bosses, treasures and lore objects that are up right now, with rare health on hover.
- World bosses and zone events show zone-wide as soon as you open the map.
- Remembers every spot it has seen; ships with a starter map of 150+ spots captured in game.
- Spots shared between players on your realm: new finds go to everyone, and entering a zone asks others for what they know there. Shared spots show fainter until a second player confirms them.
- Rare sightings shared between players (`/vsw sync` on/off, `/vsw net` to check).
- Rares and world bosses now stay on the map after you've killed them (dimmed until they're back up); looted treasures still disappear.
- Fixed: treasures disappearing when you flew past them.
- Fixed: category markers in the map menu showed as empty boxes.
- Fixed: the map button's gold ring sat off-center.
- Fixed: the `/vsw` help line was garbled.
