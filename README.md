# MINI CRAFT

**English** · [Русский](README.ru.md)

**A real-time strategy game in the spirit of StarCraft — with Age of Empires–style ages, squads led by commanders and missile silos.**
Build a base, raise an army of infantry, tanks and aircraft, form squads under commanders, lead your base through four ages
and wipe out the enemy with tactical, cluster and napalm missiles. Fully 3D, free and open source.

![Battle: marines with a medic and tanks against red infantry](docs/screenshots/en/battle.jpg)

<p align="center">
  <b>Godot 4</b> · Windows · Linux · macOS · English and Russian · save games · free and open source
</p>

---

## Two factions

Pick your side in the main menu (**Faction**); the enemy plays the other one.

- **Humans** — soldiers in helmets and uniforms, workers in hard hats, medics and officers, backed by tanks, AA
  vehicles, APCs, rocket artillery, jets and a heavy tank; their base is a field camp of concrete, sandbags,
  Quonset huts, containers and hangars.
- **The Fog** — a Silent Hill–like faction living in a rotting town of its own: a chapel-like Altar with a bell
  tower, a boarded-up Asylum, a Slaughterhouse with smoking chimneys, a Crypt, a Cage, a Nest of girders and bones,
  a Well, an air-raid Siren — all rusted, blood-stained and hung with chains — and twisted creatures — Gatherers, straitjacketed Cocoons spitting acid, faceless Sisters,
  eyeless Beasts, Flyers and the Executioner with his great rusted helmet and cleaver. Everything of the Fog slowly
  regenerates (1.5 HP/s).

![The Fog faction: buildings and creatures](docs/screenshots/fog_faction.jpg)

The whole world is wrapped in thick white fog with falling ash, flat grey light, washed-out colours and film grain.

## Why play

- ⚔️ **Classic RTS you know from the first minute.** Workers mine minerals, you build barracks, a factory and a starport,
  drag-select your army and right-click it into battle. A StarCraft-style interface: minimap, live 3D portrait,
  command card with hotkeys.
- 🎖️ **Squads and commanders.** Train an Officer at the Barracks, a Command APC at the Factory or a Command Aircraft
  at the Airfield and give it up to 6 soldiers or up to 4 vehicles or aircraft. The commander never fires a shot, but it
  sees far like a scout, the squad follows it, and near it the troops hit harder, take less damage and (infantry) heal.
- 🏛️ **Ages, like in Age of Empires.** Lead your base from the Colony Age to the Stellar Age: buildings get twice as tough,
  gain regenerating energy shields, and your army gets a power boost.
- 🚀 **Missile silos.** Four kinds of missiles: tactical, cluster, napalm and heavy. The missile flies on an arc, the impact
  zone is marked in advance, and the blast hits everyone — enemies and your own units alike.
- 🤖 **Unusual units.** A heavy tank (or the Fog's Executioner) boss with a random name and stats, a bomber that only hits buildings, kamikaze drones,
  a scout with sensor beacons, medics and mechanics that heal and repair your army mid-battle.
- 🛡️ **Fair combat mechanics.** Armor and target classes: infantry barely scratches tanks, tanks crush vehicles and buildings,
  and only AA, turrets and fighters can shoot down aircraft. A blob of marines alone won't take a base.
- 🌫️ **Fog of war and scouting.** You only see what your troops see. The scout and its beacons reveal the map.
- 🎨 **A living 3D world.** Shadows, glow, explosions, smoke, missiles with smoke trails, palms swaying in the wind, animated
  lakes, buildings that rise as holograms with welding sparks, marching infantry and tank turrets tracking their targets.
- 💾 **Comfortable.** A main menu with a live battle in the background, two difficulty levels, English and Russian, pause,
  three save slots plus quick save (`F5` / `F9`), and settings for graphics, camera and game speed.

## Screenshots

| | |
|---|---|
| ![Main menu](docs/screenshots/en/menu.jpg) | ![Ages and building shields](docs/screenshots/en/age.jpg) |
| **Main menu** — a live AI battle plays in the background | **Energy Age** — buildings under shields |
| ![Aiming a missile](docs/screenshots/en/aim.jpg) | ![A squad with its officer](docs/screenshots/en/squad.jpg) |
| **Missile launch** — silo range circle and blast radius | **Squad** — an officer, his soldiers and the bonus markers |
| ![Fog faction](docs/screenshots/fog_faction.jpg) | |
| **The Fog** — its own buildings and creatures | |

## How to start

**With Godot (easiest):**

1. Install [Godot 4.3+](https://godotengine.org/download) (the standard version, not .NET).
2. Get the game: `git clone https://github.com/r0mik/rts-craft.git`
   (or as an [archive](https://github.com/r0mik/rts-craft/archive/refs/heads/main.zip)).
3. In Godot, click *Import*, pick `project.godot` and press **F5**.

**A standalone build without Godot** (a Windows `.exe` or a Linux binary) takes a single command —
see [HOW_TO_RUN.md](HOW_TO_RUN.md) (in Russian).

The game starts in English or Russian depending on your system language; switch it in **Settings → Language / Язык**.

## Your first five minutes

1. In the main menu, pick a difficulty: **Easy** — the enemy only defends, so you can learn in peace;
   **Normal** — a full AI that grows its army and attacks in waves.
2. Workers mine minerals on their own. Select a worker and build a **Supply Depot** (`V`) and **Barracks** (`B`).
3. Select the barracks and train marines (`Q`) and medics (`E`). Train an Officer (`C`), select it together with the soldiers and press `Z` — now they are a squad.
4. Build a **Factory** (`F`) for tanks, AA and mechanics, then a **Airfield** (`P`) for aircraft.
5. Press `E` at the Headquarters to advance to a new age and harden your base.
6. Scout the map with a Recon Drone (`R` at the Headquarters) and destroy every red building.

Stuck? The main menu has a "How to play" page, and every button at the bottom of the screen shows a tooltip.

## Controls

| Action | How |
|---|---|
| Select | LMB or drag a box, `Shift` — add to selection |
| Order: move, attack, mine | RMB |
| Attack-move / stop / hold position | `G` + click / `X` / `H` |
| Groups | `Ctrl+1..9` — assign, `1..9` — select, double press — jump to group |
| Camera | `WASD` or arrows, screen edge, mouse wheel — zoom, `Space` — to base, click the minimap |
| Squads | select a commander with units and press `Z` to add them, `U` — disband |
| Next age | Headquarters → `E` |
| Missiles | silo → `M` / `J` / `N` / `K` to build, `L` + click to launch |
| Quick save / load | `F5` / `F9` |
| Pause, save, settings, back to menu | `Esc` |

Every command is also on the command card buttons at the bottom right.

---

## Everything about the game

<details>
<summary><b>Buildings</b></summary>

Built by a worker: select it and press the key.

| Key | Building | Cost | Requires | HP / armor | Provides |
|---|---|---|---|---|---|
| `C` | Headquarters | 400 | — | 1500 / 3 | workers, Recon Drone, Heavy Tank, ages, mineral drop-off, +10 supply |
| `V` | Supply Depot | 100 | — | 400 / 1 | +8 supply (max 200) |
| `B` | Barracks | 150 | — | 1000 / 2 | marines, medics |
| `U` | Bunker | 100 | Barracks | 550 / 4 | gun emplacement (7 damage, range 150); `R` — repair for minerals |
| `E` | Workshop | 125 | — | 850 / 1 | weapons (`G`) and armor (`R`) upgrades, up to 3 levels |
| `T` | AA Turret | 100 | Workshop | 300 / 2 | air defense: ×2 damage against air, range 230 |
| `F` | Factory | 200 | Barracks | 1250 / 2 | APCs, AA, engineers, MLRS |
| `P` | Airfield | 200 | Factory | 1300 / 2 | fighters, missile bombers, bombers, drones |
| `M` | Missile Silo | 200 | Workshop | 600 / 3 | four kinds of missiles |
</details>

<details>
<summary><b>Units</b></summary>

| Unit | Where / key | Cost | HP / armor | Class | Damage / range | Notes |
|---|---|---|---|---|---|---|
| Worker | CC `Q` | 50 | 45 / 0 | infantry | 5 / melee | mines minerals, builds |
| Recon Drone | CC `R` | 60 | 55 / 0 | infantry | — | unarmed, very fast, sight 460; `F` — a beacon that sees everything around for 90 s |
| Soldier | Barracks `Q` | 50 | 45 / 0 | infantry | 6 / 130 | the backbone of the army, can't hit air |
| Medic | Barracks `E` | 75 | 60 / 0 | infantry | — | heals infantry for 14 HP/s, walks up to the wounded |
| APC | Factory `T` | 150 | 160 / 4 | vehicle | 30 / 240, splash | eight-wheeled carrier with an autocannon; crushes vehicles and buildings, weak against infantry |
| MLRS | Factory `V` | 225 | 130 / 1 | vehicle | 40 / 420, splash, every 6 s | rocket artillery: a ripple of six rockets, outranges everything; can't hit air |
| AA Vehicle | Factory `Y` | 125 | 140 / 3 | vehicle | 20 / 280 | hits air only |
| Engineer | Factory `R` | 100 | 120 / 2 | vehicle | — | repairs vehicles, aircraft and buildings for 18 HP/s |
| Fighter | Airfield `V` | 150 | 120 / 1 | air | 10 / 150 | flies high; infantry and tanks can't reach it |
| Attack Jet | Airfield `B` | 300 | 280 / 2 | air | 32 / 240, splash | missile salvos against ground and air |
| Bomber | Airfield `N` | 400 | 280 / 3 | air | 120 / 200 | attacks buildings only |
| Kamikaze Drone | Airfield `K` | 100 | 40 / 0 | air | 250 | dives into a building and explodes |
| Officer, Command APC, Command Aircraft | Barracks / Factory / Airfield `C` | 100 / 175 / 200 | 130 / 320 / 260 | by class | — | unarmed squad leaders, see Squads |
| Heavy Tank (boss) | CC `Y` | 500 | ~1400 / 6 | vehicle | ~40 / 220, splash | one per side; random name and stats |
</details>

<details>
<summary><b>Squads and commanders</b></summary>

A commander takes units of its class into its squad: select it together with the units and press `Z` (`U` disbands).
Ordering the commander orders the whole squad; idle members that fall behind walk back to it. A commander never shoots,
but it sees far like a scout. Members within 380 of their commander get the bonuses; if the commander dies, the squad breaks up.

| Commander | Where / key | Cost | HP / armor | Squad | Bonus near the commander |
|---|---|---|---|---|---|
| Officer | Barracks `C` | 100 | 130 / 1 | up to 6 infantry | damage +25%, armor +2, healing 1.5 HP/s |
| Command APC | Factory `C` | 175 | 320 / 4 | up to 4 vehicles | damage +20%, armor +2 |
| Command Aircraft | Airfield `C` | 200 | 260 / 2 | up to 4 aircraft | damage +20%, armor +1 |
</details>

<details>
<summary><b>Combat</b></summary>

- **Armor** is subtracted from every hit (at least 1 damage): a marine does only 2 per shot to a tank.
- **Target classes** — infantry, vehicles, air, buildings. Weapons are more or less effective against each:

  | Attacker | infantry | vehicles | air | buildings |
  |---|---|---|---|---|
  | tank | ×0.5 | ×1.5 | — | ×2 |
  | Heavy Tank | ×0.8 | ×1.3 | ×1 | ×1.5 |
  | marine | ×1 | ×1 | — | ×0.8 |
  | fighter | ×1 | ×0.8 | ×1.4 | ×0.5 |
  | missile bomber | ×1.2 | ×1 | ×1 | ×0.7 |
  | bunker | ×1.3 | ×0.6 | — | — |
  | missile turret | ×0.5 | ×0.5 | ×1 (plus ×2 bonus against air) | — |

- **Upgrades** at the Workshop, 3 levels (100 / 175 / 250): +10% damage or armor per level, but at least +1.
</details>

<details>
<summary><b>Ages</b></summary>

| Age | Cost / time | Requires | Bonus |
|---|---|---|---|
| I Colony | — | — | starting age |
| II Industrial | 300 / 45 s | Barracks | building durability ×2 |
| III Energy | 500 / 60 s | Factory | durability ×2 and building energy shields (30% of durability) |
| IV Stellar | 800 / 80 s | Airfield | durability ×2, shields 60%, units +25% HP and damage |

Shields absorb damage first and recharge after 4 s without hits — shown as a blue dome.
</details>

<details>
<summary><b>Missiles</b></summary>

| Key | Missile | Cost | Effect | Range |
|---|---|---|---|---|
| `M` | tactical | 100 | 220 damage, radius 120 | 1500 |
| `J` | cluster | 175 | 7 bomblets of 110 damage over radius 220 | 1500 |
| `N` | napalm | 150 | burning ground in radius 160 for 8 s, 35 damage/s | 1500 |
| `K` | heavy | 300 | 600 damage, radius 210 | 1100 |

Launch with `L` + click inside the silo's yellow range circle. The blast hits everyone, including your own units.
</details>

<details>
<summary><b>Enemy, fog of war, saves and settings</b></summary>

- **Enemy.** On Easy, red only defends its base (but still advances through the ages, forms squads and fires missiles
  at anything that comes close). On Normal it plays the full AI: vehicles, aircraft, the Heavy Tank and attack waves.
- **Fog of war.** Explored ground is darkened, unexplored ground is almost black; enemy units in the fog are hidden,
  while buildings you've seen stay on the map. The fog can be turned off in the settings.
- **Saves.** Three slots plus quick save (`F5` / `F9`); load from the pause menu or the main menu. The whole match is saved:
  resources, ages, upgrades, units, construction, queues, loaded missiles and the explored map.
- **Settings** (main menu or pause): language, display mode (window, fullscreen or borderless full screen), window
  resolution (1280×720 to 3840×2160), v-sync, graphics quality (low / medium / high), FPS counter,
  camera speed, edge scrolling, game speed (×0.75–×1.5), fog of war and health bars over every unit.
</details>

---

## For developers

The game is written in GDScript; the logic (AI, combat, economy) is 2D, and a 3D layer (`scripts/view3d.gd`) renders it.
All models are built from primitives in code, so there are almost no assets. Balance lives in one file — `scripts/defs.gd`.
Texts are written in Russian and translated by `scripts/i18n.gd`.

| File | Purpose |
|---|---|
| `menu.tscn`, `scripts/menu.gd` | main menu (start scene) with an AI battle in the background |
| `main.tscn`, `scripts/main.gd` | a match: map, input, orders, combat, missiles, ages, squads, fog, saves |
| `scripts/defs.gd` | stats of units, buildings, upgrades, missiles, ages, squads, armor and damage multipliers |
| `scripts/unit.gd`, `scripts/building.gd` | a unit (state machine) and a building (construction, queues, shields, defense) |
| `scripts/ai.gd` | the computer opponent |
| `scripts/view3d.gd`, `scripts/models.gd` | 3D view, animations, effects and models built from primitives |
| `scripts/hud.gd`, `scripts/overlay.gd`, `scripts/minimap.gd` | interface, pause, saves, settings, minimap |
| `scripts/settings.gd`, `scripts/i18n.gd` | player settings (`user://settings.cfg`) and the English translation |
| `scripts/terrain.gd`, `scripts/doodads.gd`, `scripts/*.gdshader` | terrain, vegetation, ground / water / fog shaders |
| `tools/export.sh` | builds standalone Windows and Linux versions |

**Autotest:** `godot --headless --path . --fixed-fps 30 --quit-after 20000 -- --autotest` runs an AI-vs-AI match
and prints stats every 30 seconds.

**Ideas for the future:** navmesh pathfinding, ramps onto plateaus, gas, AI expansions, more maps, sound and music.
Suggestions and pull requests are welcome!
