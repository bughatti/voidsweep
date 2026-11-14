# VoidSweep Changelog

## 0.2.33 — 2026-11-14

- **WoW Forever layers:** the layer network VoidSweep shares with VoidLayer got VoidLayer 0.2.0's update: layer names are the same for everyone ("Layer 98"), and your layer is read again right after the game's world refresh moves you (it kept showing the old one for up to 3 minutes).

## 0.2.32 — 2026-11-12

- **Fixed: a side of a box could be missing**, e.g. the right line of the recipes box and its buttons when the game window is an odd number of pixels wide. Every Void box now always shows all four border lines.

## 0.2.31 — 2026-11-12

- **Fixed: any chair counted as a Camp Chair** (an inn chair, the chairs in Scarlet Monastery). A chair counts only at a campfire now; a real Camp Chair is still always recognized.
- **Fixed: the campfire box popped up inside a dungeon** (a group member's campfire). It stays out of dungeons and raids now; hovering a camp item there still shows its verdict in the tooltip.
- **Rares in dungeons and raids:** a rare or rare elite you see on a nameplate, your target or your mouseover now plays a sound and says "<name> is here!", once per rare per run (no map pin, nothing shared: every group has its own copy). With VoidGPS's rare alerts on, VoidGPS speaks instead, so it's never twice.
- **WoW Forever:** the addon list no longer calls VoidSweep a Midnight radar; it works on WoW Forever too.
- **The players-here box:** its tooltip no longer covers the box while you drag it, and it opens above or below the box depending on where the box sits on screen.
- **Void hub button:** left-click opens one panel with all your Void addons by name, grouped, each with its own on/off switches (it replaces the ring of icons), with a background slider. The hub's info window now stays where you put it.

## 0.2.30

- **WoW Forever: sharing per faction** (the network VoidSweep shares with VoidGather and VoidLayer). Messages to the other faction never arrived and the players box counted them; Horde and Alliance now each have their own channel. `/vsw net` shows bounced whispers. Older versions stay on the old channel: please update.

## 0.2.29

- **WoW Forever, layer hops** (the engine VoidSweep shares with VoidLayer): when the Void players on another layer can't bring anyone over right now, the hop message now says so instead of "no Void player", and the player who brought you over is listed on the layer you landed on.

## 0.2.28

- **WoW Forever, layer hops** (the engine VoidSweep shares with VoidLayer): a hop now finishes as soon as you've moved to the other player's layer, and you're always taken out of the hop group afterwards. Before, a hop could wait for a stale layer number and leave you grouped.

## 0.2.27

- **WoW Forever:** pins to another continent take the zeppelin (and VoidGPS's learned boats when installed).

## 0.2.26

- **Nothing about other players is saved any more:** the short list of players who had just logged off (it kept the online count right after a reload) now lasts only for your session, and the old saved list is deleted.
- "Hop to any layer" with nobody to bring you over now says "on another layer", not "on that layer".

## 0.2.25

- **Layer hops that work:** a hop needs a Void player on the other layer to send you an invite, and with hosting off by default there was almost never one. Helping others change layer is now **on by default**, so every VoidSweep player can bring others over. A helping player only invites while solo, alive, out of combat and outside instances, at most once every 2 minutes and 8 times an hour, and the group ends on its own. A one-time chat line says so; the Void hub's quick switches (or `/vsw host`) turn it off, and anyone who turned it off before keeps it off.
- **One layer network with the new VoidLayer addon:** layers, hops and rares now go over their own hidden channel (daily password) shared by VoidSweep and VoidLayer players, so there are more players to hop with. With both installed, only one of them does the work.
- **Rares on other layers:** a rare a Void player sees on another layer of your zone asks "Hop there?", and the player who saw it brings you over.
- **No more "try again in a few seconds":** when nobody is known on that layer yet, a hop asks around and carries on by itself.
- Layers have short names now ("Layer A", "Layer B").
- **The campfire box closes when you leave:** right away when you ride, fly or take a flight path out of the fire's range, and 20 seconds after you walk off (it could stay about 40).
- **The Layers window moved to VoidLayer:** with both installed there were two windows showing the same thing. **Layers...** in the map button menu (and `/vsw layers`) opens VoidLayer's window, or lists the layers in chat without it.

## 0.2.24

- **Sit button on the campfire box:** one click and you sit down by the fire; rest a minute and the camp's buffs land. It hides while the rest timer counts down.
- **Close button (x) on the campfire box:** done with a fire? Close the box; it comes back at the next campfire you walk up to.
- **Fixed: box borders missing a side.** A box's left, right or bottom line could vanish, depending on where it sat on screen (the campfire box and its Sit button, the Layers window, the Players online box). Borders are now exactly one screen pixel and drawn so they can't round away.

## 0.2.23

- **Fixed: the campfire box now knows which buffs you already have.** On WoW Forever all camp buffs come as one buff, "Camp Benefits", that lists what you got ("Lodestone: Melee Attack Power increased by 32."). The box now reads that list, so after resting those items show **have** (with minutes left) instead of still saying NEW, and "Worth sitting" only counts what you'd really gain at the next camp.

## 0.2.22

- **WoW Forever: is this campfire worth sitting at?** Walk up to a player's campfire and a small box judges it for you: "Worth sitting: 3 new buffs" or "Nothing new for you here". One line per camp item: **NEW** with what you'd gain at your level, **have** (minutes left), **covered** (your class buff of that kind already gives it; they don't stack), **no use** (Intellect on a rogue, the other faction's banner) or **wait** (the tent's rested XP is on cooldown, or you're already rested). While you rest it counts down to your buffs, and the lines turn to "have" when they land. Items show up as you walk up to them or hover them, and hovering adds the same verdict to the item's tooltip. The box opens at the fire and goes away 20 seconds after you leave; drag it anywhere, `/vsw camp` turns it off. Camp item data from Campfire Tooltips: Forever by GideonWhitlock (GPL-3.0-or-later).
- **Layers window stays up:** Esc no longer closes it (only its X does), and it comes back after a reload or login if you left it open.

## 0.2.21

- **WoW Forever: layer hop.** `/vsw hop` moves you to another layer in your zone, `/vsw hop 6833-21` to that one. A VoidSweep player on that layer sends you a group invite, VoidSweep accepts it (only that one invite), checks that your layer really changed, and leaves the group again. No host answers, or you didn't move? It tries the next one. One hop every 5 minutes.
- **A rare up on another layer with a Void host there** now pops up "Hop?"; one click and you're on your way.
- **Hosting is opt-in:** `/vsw host`, or **Sweep: Host layer hops** in the Void hub's quick switches. Hosts only invite while solo, out of combat and outside instances, at most once every 2 minutes, and leave the group on their own after 3 minutes.
- If leaving the group ever sends you back to your old layer, VoidSweep notices and keeps you grouped on later hops (`/vsw hopstay` to change).
- **Layers window:** `/vsw layers`, or **Layers...** in the VoidSweep world-map button menu. It shows your layer, every layer other VoidSweep players reported in your zone (how many Void players, and a **Hop** button where one of them hosts), **Hop to any layer**, **Refresh**, what a hop is doing right now, the 5-minute hop timer, and the two options (host hops for others, stay grouped after a hop). Drag it anywhere; Esc closes it. `/vsw layers text` still prints the list in chat.

## 0.2.20

- **WoW Forever: which layers other VoidSweep players are on.** `/vsw layers` asks the VoidSweep players in your zone and shows each layer with how many Void players are on it, for example "6833-20 (you + 1 Void player) · 6833-21: 2 Void players". The map button's tooltip shows the same. When a rare is reported up on another layer, VoidSweep asks quietly, so it already knows whether a Void player is over there (that's what the coming layer hop needs).
- Only players in that zone answer, everyone else stays silent; a zone is asked about at most every 5 minutes, and only VoidSweep players in the sharing channel get an answer. Names are never shown or saved.

## 0.2.19

- **WoW Forever: rares know their layer.** Forever splits each zone into layers, and a rare that's up on someone else's layer isn't there for you. VoidSweep now works out your layer from the NPCs around you, and every rare sighting carries the layer it was seen on. Shared sightings say **your layer** or **another layer, not up for you**, in chat and on the map pin, so you stop riding to rares you can't see. A kill on another layer no longer marks the rare dead on yours.
- **Your layer** shows on the VoidSweep map button's tooltip and with `/vsw layer`.
- Players on 0.2.18 don't see sightings from players who know their layer until they update.

## 0.2.18

- **WoW Forever: sharing moved to a new password-protected channel, a fresh one every day.** The old channel was open: anyone could join it by hand, become its owner and ban players, which silently stops their sharing (it happened to VoidQuest's channel). Now every VoidSweep player joins that day's channel with its password, and at 00:00 UTC everyone moves to the next one together, so even if someone gets in, it only lasts until the next day. Players on older versions aren't counted until they update. Retail is unchanged.
- **"blocked" in the players box** when the game won't let you into the sharing channel, and `/vsw net` says why.

## 0.2.17

- **See what sharing is doing.** `/vsw net` now starts with the sharing traffic since the counter started: what was sent to and received from other VoidSweep players, and how often nothing went out because nobody else was online.

## 0.2.16

- **WoW Forever: rare pins light up.** The Classic world has no rare markers, so VoidSweep now sees a rare the way you do: its nameplate shows up, you target it or point at it. Its pin gets the white "up" ring for 5 minutes ("UP · seen 1 min ago"), and a kill is remembered for 2 hours ("Killed 12 min ago"), so you can tell when it might be back.
- **Shared with other VoidSweep players:** when someone sees a rare up, you get "Rathorian is up (seen by ...)" in chat and the pin lights up on your map too. Only rares VoidSweep knows, near their spot, are accepted.

## 0.2.15

- **WoW Forever: every Classic rare on your map.** Over 300 rares (Humar the Pridelord, Rocklance, Takk the Leaper and the rest) now have a pin where they spawn, one per rare, with directions on click. The Classic world shows no live markers for rares, so these pins show where to look; they don't light up when the rare is up. Data from NorgannonDB, see Credits.
- **The starter map is refreshed** with more Midnight rares, treasures, world bosses and lore spots. From now on it can also take in spots two or more players have shared (never single reports).
- **Starter-map pins say so.** Hover one you haven't seen yourself and it reads "Known spawn spot" instead of "Seen here before".
- **WoW Forever: the players box is right after a /reload.** Players who logged off stay on the sharing channel's list; VoidSweep already left them out once a message to them bounced, but forgot that on every reload, so the count jumped up for a minute. It now remembers.
- **Licence: VoidSweep is now GPL-3.0** (was MIT), because it includes NorgannonDB's data. See Credits in the README.

## 0.2.14

- **WoW Forever: the players box shows the right count.** VoidGather, VoidQuest and VoidSweep each read their own sharing channel's member list, but the game hands out only one list at a time, so they took it from each other. A count could stick, and VoidSweep could lose its list of players to send rare alerts to. They now take turns.
- **Offline players stay off the count.** A player who logged off stays at 0 until a message to them goes through again. Before, they came back as "online" every 30 minutes.

## 0.2.13

- **Fixed: sharing errors during encounters.** While the game's chat lockdown is on (boss fights), system messages are hidden from addons; VoidSweep read one and errored. It now skips them.
- **Fixed: "VoidSweep tried to call a protected function".** It joined its sharing channel again even when already in it, which the game blocks in combat. It now joins only when it isn't in the channel, and waits until combat or the lockdown is over.

## 0.2.12

- **WoW Forever: offline players no longer counted or messaged.** Forever's sharing channel still lists players who have logged off. When one of them can't be reached, VoidSweep now leaves them out for 30 minutes, so the players box shows who's really online and rare alerts go to players who can get them.
- **The players box says "Players online" on WoW Forever** (it counts players online, not per zone, there), and it has room for VoidQuest's line too.

## 0.2.11

- **Sharing works again on WoW Forever.** Forever's live servers stopped carrying addon messages on the hidden sharing channel, so rare alerts and shared spots silently stopped arriving there. On Forever, VoidSweep now sends them by hidden addon whisper to a few other VoidSweep players online instead (they never show in chat). Retail is unchanged.
- **On Forever the players box counts VoidSweep players online** (Forever can't count them by zone any more). `/vsw here` says the same.

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
