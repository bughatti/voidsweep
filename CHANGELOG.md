# VoidSweep Changelog

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
