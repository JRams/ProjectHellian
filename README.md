# Project Hellian

A turn-based strategy game in the spirit of Fire Emblem. The playable
scenario is **Grimwater Crossing**, a 16×12 skirmish map where two armies
of seven fight across a river — available in two implementations:

- **`index.html` + `js/`** — the original zero-dependency browser prototype.
- **`godot/`** — the Godot 4.5 port. See
  [docs/GODOT_PORT.md](docs/GODOT_PORT.md) for a step-by-step walkthrough
  of how the prototype was integrated into the engine (written as a
  learning guide for programmers new to game engines).

## Running the demo

**Browser version** — no build step, no dependencies:

```
# Option 1: just open it
open index.html          # or double-click it in a file browser

# Option 2: serve it (avoids any file:// quirks)
npx serve .              # then visit the printed URL
```

**Godot version** — install [Godot 4.5](https://godotengine.org/download),
then Import → `godot/project.godot` → F5. Headless battle-simulation test:
`cd godot && godot --headless -s tests/sim_test.gd`.

## What's in the demo

- **Unit classes** — Knight, Mercenary, Cavalier, Archer, Mage, Healer, and
  Pegasus Knight, each with FE-style stats (HP/Str/Mag/Skl/Spd/Def/Res/Mov),
  a weapon, and attack ranges. Archers can't be countered at range 2, mages
  target Res instead of Def, healers can't attack at all.
- **Cardinal grid movement** — units move north/south/east/west only
  (Dijkstra flood-fill, no diagonals) with terrain movement costs: forests
  cost 2, mountains cost 3 and block cavalry, rivers are impassable except at
  bridges, and fliers ignore terrain entirely. Enemies block passage; allies
  can be passed through but not stopped on.
- **Combat simulation** — damage/hit/crit formulas, terrain defense and
  avoid bonuses, counterattacks when the defender's range allows, and
  follow-up attacks when one side is 4+ Spd faster. Hovering a target shows
  a battle forecast before you commit.
- **Battle vignettes** — Fire Emblem style combat cut-ins overlaid on the
  battlefield: fighters lunge, damage numbers pop, HP bars drain, crits
  flash, misses dodge, deaths fade. Turn animations off entirely with the
  "Battle anims" toggle.
- **Quick Time Events** — Legend of Dragoon style additions in every
  battle the player fights. Attacking: tap Space/click against a shrinking
  ring, one tap per step of your class's unique rhythm — perfect chains
  deal **MAX! (1.5×)** damage. Defending: **hold to guard** while the
  enemy charges you, then **release as the blow lands** — a perfect
  release parries for 50% damage, holding through still guards (90%),
  dropping your guard early leaves you exposed. Colors code the combat
  type: blue physical, green magic, red defense. AI-vs-AI simulation
  stays fully automatic.
- **Playable + auto-simulation** — control the blue army yourself against
  the enemy AI, or press **Simulate Battle** and watch the AI play both
  sides to a conclusion. The AI scores every reachable (tile, target) pair,
  avoids bad trades, advances with threat-range awareness and army cohesion,
  and healers triage the most wounded ally.

## Architecture

The game core is deliberately engine-agnostic — plain data and functions
with no DOM or rendering dependencies. The Godot port kept that boundary:
each core file maps 1:1 to a script in `godot/scripts/core/`.

| Browser prototype | Godot port | Role |
|---|---|---|
| `js/data.js` | `core/game_data.gd` (+ `terrain_type.gd`, `unit_class.gd`) | Terrain table, class definitions, rosters, map layout |
| `js/grid.js` | `core/grid.gd` | Cardinal-direction pathfinding, ranges, targeting |
| `js/combat.js` | `core/combat.gd` | Battle forecast and resolution (hit/crit/double/counter) |
| `js/ai.js` | `core/ai.gd` | Action planning for AI-controlled units |
| `js/game.js` | `core/game.gd` (+ `unit.gd`) | Game state, turn flow, win conditions |
| `js/render.js` | `scripts/board.gd`, `scripts/unit_node.gd` | Presentation layer |
| `js/battle.js` | `scripts/battle_vignette.gd` | Animated battle vignette overlay |
| `js/main.js` | `scripts/main.gd`, `scripts/ui.gd` | Input handling, UI panels, simulation loop |

## Engine choice

**For prototyping:** plain web tech. Instant iteration, runs anywhere,
trivially shareable, and forces the game rules to live in clean
engine-independent code.

**For the real game: Godot over Unity.** Unity absolutely *can* build this,
but a 2D grid tactics game uses almost none of what Unity is heavy for
(3D pipeline, physics, its asset/licensing ecosystem). Godot is free and
open source, dramatically lighter, and its 2D tooling (TileMapLayer, grid
coordinates, animation) maps one-to-one onto this genre. GDScript is close
enough to the JavaScript here that the core files ported almost
mechanically — [docs/GODOT_PORT.md](docs/GODOT_PORT.md) documents exactly
how. Unity is the better pick only if C# is a hard requirement or console
porting support matters early.
