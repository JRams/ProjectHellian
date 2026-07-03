# Project Hellian

A turn-based strategy game in the spirit of Fire Emblem. This repo currently
contains a playable browser demo: **Grimwater Crossing**, a 16×12 skirmish map
where two armies of seven fight across a river.

## Running the demo

No build step, no dependencies — it's plain HTML/JS/Canvas:

```
# Option 1: just open it
open index.html          # or double-click it in a file browser

# Option 2: serve it (avoids any file:// quirks)
npx serve .              # then visit the printed URL
```

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
- **Playable + auto-simulation** — control the blue army yourself against
  the enemy AI, or press **Simulate Battle** and watch the AI play both
  sides to a conclusion. The AI scores every reachable (tile, target) pair,
  avoids bad trades, advances with threat-range awareness and army cohesion,
  and healers triage the most wounded ally.

## Architecture

The game core is deliberately engine-agnostic — plain data and functions
with no DOM or rendering dependencies — so it can be ported into a real
engine later without rewriting the rules:

| File | Role |
|---|---|
| `js/data.js` | Terrain table, class definitions, rosters, map layout |
| `js/grid.js` | Cardinal-direction pathfinding, ranges, targeting |
| `js/combat.js` | Battle forecast and resolution (hit/crit/double/counter) |
| `js/ai.js` | Action planning for AI-controlled units |
| `js/game.js` | Game state, turn flow, win conditions |
| `js/render.js` | Canvas presentation layer |
| `js/main.js` | Input handling, UI panels, simulation loop |

## Engine choice

**For prototyping (this demo):** plain web tech. Instant iteration, runs
anywhere, trivially shareable, and forces the game rules to live in clean
engine-independent code.

**For the real game: Godot over Unity.** Unity absolutely *can* build this,
but a 2D grid tactics game uses almost none of what Unity is heavy for
(3D pipeline, physics, its asset/licensing ecosystem). Godot is free and
open source, dramatically lighter, and its 2D tooling (TileMapLayer, grid
coordinates, animation) maps one-to-one onto this genre. GDScript is close
enough to the JavaScript here that `grid.js`, `combat.js`, and `ai.js` port
almost mechanically. Unity is the better pick only if C# is a hard
requirement or console porting support matters early.
