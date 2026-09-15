# The map editor — building scenarios inside Godot

Maps used to be source code: a `const MAP_LAYOUT` string array wired into
`game_data.gd`, with the rosters beside it. This adds a proper authoring
path — paint terrain and place units in the Godot editor, validate the
result, and balance-test it against the AI before you ever play it.

Written like the rest of `GODOT_PORT.md`: each piece names the engine
concept it uses and why it was chosen over the alternatives.

---

## Quick start

1. Open the project in **Godot 4.5**, then open `tools/map_workbench.tscn`.
2. Select the root **MapWorkbench** node. The Inspector shows the map plus
   a set of action checkboxes (tick one, it runs and unticks itself).
3. Tick **Load From Map** → the tile layers fill in with the current map.
4. Select the **Terrain** or **Units** layer in the scene tree, open the
   *TileMap* panel at the bottom, and paint. This is Godot's own tile
   painter — brush, line, rect, bucket fill, and pick all work.
   - Atlas **row 0** is terrain; **row 1** is player units; **row 2** is
     enemy units. Paint units onto the *Units* layer, terrain onto *Terrain*.
5. Tick **Save To Map** → the layers are written back into the MapData.
6. Tick **Validate**, then **Playtest**. Read the Output panel.
7. `Ctrl+S` to write the `.tres` to disk.

To start a new scenario: set `Grid Width`/`Grid Height`, tick
**New Blank Map**, paint, **Save To Map**, then save the resource under
`maps/` via the Inspector's resource menu.

To play a map, select the **Main** node in `scenes/main.tscn` and drop a
different MapData into its `Map` property.

## Why it's built this way

**The workbench does not implement painting.** That is the central design
decision. Godot already ships a good tile editor, and a hand-rolled one
would have been several hundred lines of untested UI that behaves worse.
So the tool only supplies what the engine can't know about:

| Godot provides | The workbench provides |
|---|---|
| Brushes, fill, rect, pick, undo | MapData ⇄ TileMapLayer conversion |
| Tile palette, layer switching | Validation against the game's own rules |
| Inspector editing of resources | AI playtesting / balance reports |
| Save/load of `.tres` files | Blank-map scaffolding, JSON export |

It is also why there's **no `EditorPlugin`**. A plugin dock would be nicer
chrome, but a `@tool` scene reaches the same capability with a fraction of
the engine-API surface — and API surface I can't execute here is exactly
where bugs hide. Adding the dock later is a contained change; see
`DECISIONS-TO-MAKE.md`.

## The engine concepts in play

**`Resource` + `@export` = a free editor.** `MapData` extends `Resource`,
so every `@export`ed field is Inspector-editable with no UI code, `.tres`
is a diffable text format, and `load()` handles file IO. This is the same
"data as assets" idea listed as a next step in the port guide, applied to
maps first because maps are the thing you'll create most of.

**`@tool` runs a script inside the editor.** Normally scripts only run in
the game; `@tool` at the top of `map_workbench.gd` makes the editor
execute it too, which is how ticking a checkbox can flood-fill a tile
layer while you're authoring.

**Inspector buttons via setter side effects.** Godot 4.4+ has
`@export_tool_button`, but the portable idiom across all of 4.x is a bool
`@export` whose setter fires the action and immediately resets the value:

```gdscript
@export var validate := false:
    set(v):
        validate = false
        if v:
            _validate()
```

**`TileMapLayer` + `TileSet`.** Two layers share one TileSet: terrain and
units. Reading painted cells back out is `get_used_cells()` plus
`get_cell_atlas_coords()`, which is how **Save To Map** reconstructs the
ASCII rows and the rosters.

## The scenario format

`maps/*.tres`, deliberately human-readable:

```
map_name     = "Grimwater Crossing"
objective    = "rout"
turn_limit   = 60
terrain_rows = ["....f..~~...m...", "..f....~~..mm..f", ...]
player_units = ["Knight 1 4 Doran", "Mercenary 2 3 Silke", ...]
enemy_units  = ["Knight 14 5 Gorm", ...]
```

Terrain legend unchanged: `.` plain, `f` forest, `m` mountain, `~` water,
`=` bridge, `F` fort. Units are `<Class> <x> <y> <Name>`; names may contain
spaces. Both stay strings on purpose — if the tooling is ever in the way,
a map is still fixable in a text editor, and diffs stay one line per row.

**Tick `Export Json`** to write the same data as `maps/<name>.json`. That
keeps maps readable by the web prototype and any external tooling, so
choosing `.tres` here doesn't quietly settle the "which implementation is
canonical" question (DECISIONS-TO-MAKE §1).

Loading a map is one call — `MapData.apply()` — because everything that
reads the board goes through `GameData.map_layout` / `map_w` / `map_h` /
`player_army` / `enemy_army`. Those five were `const`s; they're now
`static var`s that `apply()` swaps. No other file changed.

## Validation: the mistakes an editor actually makes

`Validate` reports, using the game's own passability rules rather than a
second copy of them:

- rows of unequal length, unknown terrain characters
- empty rosters, malformed unit lines, unknown classes, off-map spawns
- two units stacked on one tile
- a unit starting somewhere its class can't stand (infantry in a river)
- **armies walled off from each other** — a flood-fill from every player
  unit checks whether any enemy is reachable or adjacent to reachable
  ground. It is movement-profile aware: a Pegasus crosses the river that
  strands the infantry, and cavalry is stopped by a mountain ridge that
  foot units walk over. A single stranded unit is a `WARN`; nobody able
  to engage at all is an `ERROR`.

## Playtesting: the AI as map QA

`Playtest` runs seeded AI-vs-AI battles on the map and reports:

```
[maps] playtest 'Grimwater Crossing' over 25 battles:
  player win rate : 72% (18/25)
  turns           : avg 9.4, min 7, max 14
  hit turn limit  : 0
```

It warns when a map looks lopsided (≥80% or ≤20% win rate) or stalls
often. The same thing works headlessly, which makes it CI-able:

```bash
godot --headless -s tests/sim_test.gd -- --map res://maps/grimwater.tres
```

That flag validates the map, refuses to run if it has errors, and prints a
balance summary alongside the usual assertions. This is the part worth
more than the editor itself: "is this map fair?" becomes a number, and it
cost almost nothing because the simulator already existed.

## The placeholder art

`maps/tiles/hellian_atlas.png` is a generated 308×132 atlas (44px tiles):
six terrain tiles, then a row of player unit tokens and a row of enemy
tokens. It was produced from the same procedural drawing code the game
renders with, so the editor looks like the game.

It is **placeholder**, and swapping it is the whole upgrade path: replace
the PNG with real tile art at the same grid size and nothing else changes.
If you add terrain types, extend `GameData.TERRAIN_CHARS`, add the tile to
the atlas and to `TERRAIN_TILE` in `map_workbench.gd`.

Note the board in-game still draws terrain procedurally in `board.gd` —
the TileMapLayer is the *editing* surface only. Converting the game's
renderer to a TileMapLayer as well is the natural follow-up, and this
atlas is the asset that unblocks it.

## First-run notes and known gaps

- On first open Godot will import the PNG and generate
  `hellian_atlas.png.import` next to it — that's expected; commit it.
  If the TileSet looks empty, reload the project once after the import.
- **None of this has been executed.** The engine could not be run in the
  environment this was written in, so every script is parser- and
  lint-verified (`gdparse`/`gdlint`) and the validator's *algorithm* was
  separately mirrored and unit-tested outside Godot — but the first real
  run happens on your machine. The riskiest files are the hand-written
  `.tres`/`.tscn` resources; if one fails to parse, the error names the
  file and line.
- `objective` accepts `rout`/`seize`/`survive`, but only **rout** is
  implemented. Validation emits a WARN for the others rather than
  pretending they work.
- `turn_limit` is now per-map (it drives the attrition valve that used to
  be `Game.TURN_LIMIT`).
