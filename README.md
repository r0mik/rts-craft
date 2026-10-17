# MINI CRAFT

**English** · [Русский](README.ru.md)

![Mini Craft — Humans vs The Fog](docs/logo.jpg)

A real-time strategy game in the spirit of StarCraft, set in a Silent Hill–like fog.
A human field army fights the creatures of the Fog: build a base, mine minerals, raise an army and destroy the enemy.

- **Two factions** — Humans (soldiers, APCs, rocket artillery, jets, a heavy tank) and the Fog (twisted creatures,
  rusted bloody buildings, the Executioner; everything of the Fog regenerates).
- **Squads** — commanders lead up to 6 soldiers or 4 vehicles / aircraft and make them stronger.
- **Ages** — like Age of Empires: tougher buildings, energy shields, stronger units.
- **Missiles** — tactical, cluster, napalm and heavy, fired from a silo.
- **Fog of war**, armor and target classes, save / load, two difficulty levels, English and Russian.

## Run

1. Install [Godot 4.3+](https://godotengine.org/download) (standard version, not .NET).
2. `git clone https://github.com/r0mik/rts-craft.git`
3. Open `project.godot` in Godot and press **F5**.

Standalone builds for Windows / Linux: [HOW_TO_RUN.md](HOW_TO_RUN.md).

## Controls

| | |
|---|---|
| Select / order | LMB, box select / RMB |
| Camera | `WASD`, mouse wheel, `Space` — to base |
| Attack-move / stop / hold | `G` / `X` / `H` |
| Groups | `Ctrl+1..9`, `1..9` |
| Squad (commander + units) | `Z` add, `U` disband |
| Next age | HQ → `E` |
| Quick save / load | `F5` / `F9` |
| Pause, settings | `Esc` |

All commands are also on the buttons at the bottom right, with tooltips. Balance lives in `scripts/defs.gd`.
