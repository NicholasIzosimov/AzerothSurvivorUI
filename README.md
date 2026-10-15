# Azeroth Survivor UI

A lightweight interface addon for **Azeroth Survivors**: flat, dark unit frames, a compact action bar and a set of run panels (damage meter, build, tally, timer, Lexicon) in place of the stock 1.12 look. Everything can be moved, resized and switched off.

## Install

1. Download the latest zip from [Releases](https://github.com/NicholasIzosimov/AzerothSurvivorUI/releases) (or **Code → Download ZIP**).
2. Open the zip and copy the **`SurvivorUI`** folder into your game's `AddOns` folder.
   The result must be `AddOns/SurvivorUI/SurvivorUI.toc`. The folder has to be named `SurvivorUI`, or the game will not load it.
3. Start the game (or `/reload`) and type `/sui opt` for the options.

## Features

- **Unit frames**: flat player and target frames with size, width and height sliders, short health numbers (1.2k) and a band showing your absorb shield on the health bar. Switch off for the game's own frames.
- **Action bar**: one compact row with cooldown numbers (size, color, rounding) and a configurable number of abilities per row.
- **Buffs**: a centered buff row above the player frame with an optional clock sweep.
- **Damage meter**: muted bars, spell icons and a hover card per line with the average cast and the targets hit.
- **Build**: your spells colored by the rarity their upgrades add up to, your jewelry, and hover cards with upgrades and gear stats.
- **Lexicon**: a book of every amulet, ring and trinket you have worn, across runs.
- **Tally**: kills, gold, gold per second and gold needed; **Tracker**: run timer with per-class best boss times, speedrun style; **XP bar** with a next-level estimate; **Boss bars**; **Loot log**.
- **Caches**: a reminder and an arrow to the nearest cache, plus cache pins on the minimap.

## Commands

| Command | What it does |
| --- | --- |
| `/sui opt` | Options window (also the **UI** button on the minimap) |
| `/sui reload` | Reload the interface |
| `/sui frames` | Addon unit frames on/off |
| `/sui build` | Build panel on/off |
| `/sui lexicon` | Open the Lexicon |
| `/sui meter` | Damage meter on/off |
| `/sui tally` | Tally on/off |
| `/sui timer` | Run timer on/off (`/sui timer compact` for the small one) |
| `/sui xp` | Level bar on/off |
| `/sui caches` | Cache reminder and minimap pins |
| `/sui events` | The game's event banners on/off |
| `/sui sweep` | Buff sweep on/off |
| `/sui nodamage` | Hide all damage numbers (the game's and the addon's) |

Hold **Alt** and drag to move any panel; positions snap to a grid.

## Settings

Everything is saved per account in `SurvivorUIDB` (the game's saved variables). Delete that file to start from the defaults.

## License

[MIT](LICENSE)
