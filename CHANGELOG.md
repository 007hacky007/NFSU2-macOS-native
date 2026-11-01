# Changelog

What each version of NFSU2 Builder brings. The newest version is first.

## 1.0.1 - 2026-11-02

### Added
- Settings checks your online player name on the server and lets you claim it with your cloud saves keyphrase, so nobody else can play under it there. If another player claimed the name, the launcher offers one with four digits added, or you can play under it anyway.
- The free-roam world map shows up to 2048 players of your room, and their markers move while the map is open.
- Online statistics: a small panel in a corner of the game shows your connection, the round trip to the server, how many play on the server, in free roam, in the Online lobby, in your room and in your crews, and how many cars are shown near you. A switch in Settings, Online; off as in the original game.
- Friends: add players by name in the launcher, or by touching front bumpers for three seconds in free roam. Friends show in their own colour, you get a notice when one starts free roam, and Join takes you to their room. Needs a claimed name.
- Invite links: copy a link to your free-roam room or crew and paste one in the launcher to join it. Game Tools can change the room while you play.
- The game's own outrun challengers drive in free roam with other players around, greyed on the minimap and the world map. Both have a switch in Settings.
- The world map's legend can hide other players and their races.
- Photo mode: a farther camera, and names over the cars (your own too) with N. Tab and N switch back.
- Show hidden races: the career map shows the races the game hides, as the Show Hidden Races mod does. Off as in the original game.
- Exposure and White Level in the Display options, for a picture that tires the eyes less. The original game's values by default.
- Your first profile's name starts with your player name.

### Changed
- Free roam works with the community server's new free-roam version (core version 9).
- Room and crew names match even when friends type them a little differently: capitals (Greek and Cyrillic too), spaces and invisible characters do not count. The launcher's player counts for your room and crews follow the same rule.
- Drift mode in free roam uses the drift races' handling and your car's Drift tuning, and keeps your nitrous.
- Less input lag: the controller is read after the wait for the next frame.
- Replays above 60 fps run in step with the race.
- The game sends the server less: it asks only for changes to the list of players, and only for the LAN broadcasts it listens for.

### Fixed
- Online play no longer reconnects every second on a busy server, which kept the Online menu at Connecting to lobby.
- The game no longer crashes when your car touches another player's car in free roam.
- Free roam's Loading screens no longer drag on, or never end, with many players around: the city's sections load before other players' cars.
- In Online races, the other players' cars come straight from each player and their corrections are smoothed, so they jump less.
- Your car keeps its spoiler and exhaust tips after a shop in free roam with other players.
- A failed magazine or DVD cover save no longer garbles your profile's name.
- LAN play's network clock can no longer step backwards.
- A key held while you switch to another app and back works again on its next repeat.

## 1.0.0 - 2026-11-01

### Added
- NFSU2 Builder makes NFSU2.app on your Mac from your own game: your installed folder or the two PC disc images, European or North American v1.2. A checklist fixes each missing item with one button, and no Terminal is needed.
- The game runs as native Apple Silicon code with Metal graphics and CoreAudio sound. No Wine, CrossOver or emulator. The app holds the game inside it, so you can move it anywhere, and saves and settings stay outside.
- LAN play between Macs and Windows PCs, and the game's Online mode through a community server.
- Free roam with friends: see other players' cars live in career free roam, challenge them to outruns or open a race lobby at a race marker, with rooms, crews, quick chat and horns.
- A launcher where every optional feature has a switch that names the original game's value. Restore Original Game turns them all back.
- Graphics options: 30 to 240 FPS with speed and physics kept as at 60, resolution scale, sharper reflections, picture options without the yellow-green tint, other cars' headlights and 60 FPS cutscenes.
- One-click mods: the Upscaled HUD, community texture packs, data mods, 4x upscaled textures built from your own files, and language packs. 16 languages in all.
- Better controls: typing on every Mac keyboard layout, key rebinding that is kept, and game controllers with dead zones and rumble.
- Career extras: a 10-car garage with Trade Car, power in bhp or kW, both regions' cars, photo mode, drift mode in free roam, your own music through EA Trax and encrypted cloud saves.
- Fixes for the original game: the car lot opens on damaged profiles, the Performance Shop no longer locks up after Nitrous, the music keeps playing after shops, and Cmd-Q quits safely.
