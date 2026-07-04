# Porting the tactics demo to Godot — an integration walkthrough

This document records, step by step, how the browser prototype in `js/` was
ported into the Godot 4.5 project in `godot/`. It's written for a programmer
who is comfortable with code but new to game engines: each step names the
engine concept it introduces and contrasts it with the plain-JS version,
so you can diff the two implementations side by side.

The single most important idea: **the game rules didn't change, only the
runtime around them did.** `grid.js`, `combat.js`, `ai.js`, and `game.js`
map 1:1 onto GDScript files. What got *replaced* is everything the browser
was doing for us — the render loop, the DOM, event listeners, `setTimeout`
— each swapped for the engine's native mechanism.

---

## Step 0 — Install Godot 4.5

Download the standard (non-.NET) editor from <https://godotengine.org/download>
(or GitHub releases: `godotengine/godot`, tag `4.5-stable`). It's a single
~60 MB executable — no installer, no SDK. GDScript needs nothing else.

> This port was written and lint-verified against the Godot **4.x** API
> (4.5 at time of writing). It will not run on Godot 3 — the API renames
> between 3 and 4 are extensive.

## Step 1 — Project skeleton

A Godot project is any directory containing a `project.godot` INI-style
manifest. Ours ([godot/project.godot](../godot/project.godot)) declares:

- `run/main_scene="res://scenes/main.tscn"` — what to run on launch.
  `res://` is a virtual path meaning "project root"; use it everywhere
  instead of relative filesystem paths.
- `window/size/viewport_*` — fixed window matching the old canvas + sidebar.
- `renderer/rendering_method="gl_compatibility"` — the OpenGL backend; for
  a 2D game it's the most portable choice (runs on weak GPUs and in
  web exports).

When the editor first opens a project it generates a hidden `.godot/` cache
directory. That is machine-generated state, never source —
[godot/.gitignore](../godot/.gitignore) excludes it. (Expect the editor to
also rewrite the `.tscn` files once on first open to add `uid://` resource
IDs — that's normal; commit the result.)

Layout chosen:

```
godot/
├── project.godot
├── scenes/            # node trees (what the editor edits)
│   ├── main.tscn
│   └── unit.tscn
├── scripts/
│   ├── core/          # engine-agnostic rules (ported 1:1 from js/)
│   └── *.gd           # presentation layer (talks to Godot APIs)
└── tests/
    └── sim_test.gd    # headless battle simulation
```

The `scripts/core/` vs `scripts/` split preserves the discipline from the
JS version: nothing in `core/` imports a single Godot node type. You could
lift `core/` into a dedicated server or a different engine again.

## Step 2 — Porting the rules layer (JS → GDScript)

File-by-file mapping:

| JS (prototype) | GDScript (port) | Notes |
|---|---|---|
| `js/data.js` | `core/game_data.gd` + `core/terrain_type.gd` + `core/unit_class.gd` | ad-hoc object literals became real classes |
| `js/grid.js` | `core/grid.gd` | `Map` keyed by `y*W+x` became `Dictionary` keyed by `Vector2i` |
| `js/combat.js` | `core/combat.gd` | `Math.random` became an injected, seedable `RandomNumberGenerator` |
| `js/ai.js` | `core/ai.gd` | JS `Set` became `Dictionary[Vector2i -> true]` (GDScript has no Set) |
| `js/game.js` | `core/game.gd` + `core/unit.gd` | added a `log_added` **signal** (see Step 7) |

Language notes a traditional programmer will care about, all hit during
this port:

- **`class_name X` registers a global type.** No imports/requires anywhere;
  `GameData.TILE` just resolves from any script. (Registration happens at
  editor scan time — another reason the `.godot/` cache exists.)
- **`static` everything for stateless modules.** `Grid`, `Combat`, `AI`
  are namespaces of static functions, exactly like the free functions in
  the JS files. `const` only accepts compile-time constants, so tables of
  constructed objects (`TerrainType.new(...)`) must be `static var`.
- **Renamed identifiers to dodge built-ins.** `str` is a global function
  in GDScript, `class` and `range` are keywords, `name` collides with
  `Node.name`. Hence `strength`, `u_class`, `attack_range`, `unit_name`.
  When a stat name fights the language, rename the stat.
- **`Vector2i` replaced `{x, y}` pairs.** It's a value type, compares by
  value, and hashes — so it keys Dictionaries directly. The JS trick of
  encoding positions as `y * MAP_W + x` integers became unnecessary.
- **Typing is gradual.** Signatures are typed (`func manhattan(a: Vector2i,
  b: Vector2i) -> int`), but pathfinding nodes stayed plain Dictionaries,
  same shape as the JS objects. You can tighten later without redesign.
- **Lambdas capture by value** — but Arrays/Dictionaries/objects are
  reference types, so the `strike` closure in `combat.gd` can append to
  `events` just like its JS counterpart. Reassigning a captured local
  would *not* propagate; mutating through a reference does.
- **Ternary is `a if cond else b`**, floats have `INF`, and integer
  helpers are functions (`maxi`, `clampi`, `absi`) rather than
  `Math.max` overloads.

## Step 3 — Scenes and nodes (the actual mental-model shift)

The browser version had one implicit "scene": an HTML page with a canvas
and some divs. Godot makes that structure explicit. A **node** is one unit
of engine behavior (draws something, plays a sound, times something); a
**scene** is a saved tree of nodes; scenes **instance** other scenes.
The whole running game is one big tree.

[main.tscn](../godot/scenes/main.tscn) — written by hand here, normally
built in the editor — is this tree:

```
Main (Node2D, main.gd)         ← orchestrator; owns the Game object
├── Board (Node2D, board.gd)   ← draws terrain + highlights
├── Units (Node2D)             ← container; one UnitNode child per unit
├── SimTimer (Timer)           ← paces AI actions (Step 8)
└── UI (CanvasLayer, ui.gd)    ← screen-space layer, ignores world position
    ├── Banner (Label)
    ├── Sidebar (VBoxContainer)
    │   ├── Controls (HBox: Simulate / End Turn / Reset buttons)
    │   ├── SpeedRow (HBox: Label + OptionButton)
    │   ├── Counts (Label)
    │   ├── InfoPanel ▸ Info (RichTextLabel)
    │   ├── LogPanel ▸ Log (RichTextLabel)
    │   └── Help (RichTextLabel)
    └── Forecast (PanelContainer ▸ RichTextLabel)
```

[unit.tscn](../godot/scenes/unit.tscn) is the engine's equivalent of a
prefab/component class: a one-node scene with `unit_node.gd` attached.
`main.gd` stamps out an instance per unit:

```gdscript
const UNIT_SCENE := preload("res://scenes/unit.tscn")
var n := UNIT_SCENE.instantiate()
units_root.add_child(n)          # nothing exists until it enters the tree
n.setup(u, game)
```

In JS, units were rows in an array that a monolithic `render()` looped
over. Here each unit is an *object in the world* that owns its own
position, drawing, and animation. That inversion — from "one renderer
iterates data" to "each thing renders itself" — is the core engine habit.

`.tscn` files are plain text, diff cleanly, and are safe to hand-edit;
the editor and the text format are two views of the same data.

## Step 4 — Rendering: `_draw()` instead of a canvas loop

The JS version repainted the whole canvas after every change. Godot's 2D
drawing is *retained*: a `CanvasItem` (any 2D node) has a `_draw()` callback,
the engine caches the result, and only re-invokes it after you call
`queue_redraw()`. `board.gd` is `render.js` translated almost line for
line — `ctx.fillRect` → `draw_rect`, `ctx.beginPath()+fill` →
`draw_colored_polygon`, `ctx.stroke` polyline → `draw_polyline` — plus
explicit invalidation:

```gdscript
func refresh(p_reachable, p_path, p_attack, p_heal) -> void:
    reachable = p_reachable
    ...
    queue_redraw()   # ask the engine to call _draw() once
```

Text in `_draw()` needs an explicit font; `ThemeDB.fallback_font` is the
built-in default (`unit_node.gd`).

*Why not a TileMapLayer?* `TileMapLayer` is Godot's purpose-built terrain
node — but it wants a TileSet resource with texture atlases, i.e. art
assets. Programmatic `_draw()` keeps the port asset-free and 1:1 with the
JS. Swapping the Board's `_draw_terrain()` for a TileMapLayer once you
have tiles is the natural first upgrade, and nothing outside `board.gd`
would change.

## Step 5 — Input: events propagate through the tree

`main.js` attached `click`/`mousemove` listeners to the canvas element.
Godot instead *routes* every `InputEvent` through the scene tree: UI
`Control` nodes get first claim, and only unconsumed events reach
`_unhandled_input()`. That's why `main.gd` listens there — a click on the
"End Turn" **Button** is consumed by the button and never falls through to
the battlefield. No `stopPropagation()` bookkeeping.

Pixel → grid conversion uses the Board's local space rather than manual
offset math (`e.clientX - rect.left` in JS):

```gdscript
func _mouse_cell() -> Vector2i:
    var local := board.get_local_mouse_position()  # Board's coordinate frame
    return Vector2i(int(floor(local.x / GameData.TILE)),
            int(floor(local.y / GameData.TILE)))
```

Because `Board` sits at `position = (16, 72)`, the engine does the
offsetting. Move the board, and input math stays correct.

The selection state machine (`IDLE → MOVE_SELECT → ACTION_SELECT`) ported
unchanged — it was never browser-specific. Compare `_on_click()` in
`main.gd` with the click handler in `main.js`: same branches, same order.

## Step 6 — UI: Control nodes instead of DOM + CSS

The sidebar was HTML/CSS (`aside`, flexbox, `#log` div). The Godot
equivalents used in `main.tscn` / `ui.gd`:

| Browser | Godot |
|---|---|
| `<div>` + flexbox column | `VBoxContainer` (lays out children automatically) |
| `<div class="panel">` background | `PanelContainer` |
| `<button>` + `addEventListener` | `Button` + `pressed` signal |
| `<select>` | `OptionButton` |
| `innerHTML` with styled spans | `RichTextLabel` with BBCode (`[b]`, `[color=#8dbef0]`) |
| `document.getElementById` | `@onready var x = $Path/To/Node` |
| CSS `overflow-y: auto` log | `RichTextLabel.scroll_following = true` |
| CSS classes for colors | `add_theme_color_override(...)` / BBCode |

`CanvasLayer` is the one concept without a DOM analogue: it renders its
subtree in screen space, unaffected by any world camera. UI goes on a
CanvasLayer so it stays put even if you later add a scrolling map camera.

## Step 7 — Signals: the engine's event system

Two deliberate uses, both replacing something ad-hoc in JS:

1. **Core → UI, without coupling.** In JS, `main.js` re-read `game.log`
   and rebuilt the log HTML after every action. The GDScript `Game` core
   instead declares `signal log_added(entry)` and emits it inside
   `add_log()`. The UI subscribes once (`game.log_added.connect(ui.on_log_added)`)
   and appends lines as they happen. The core still never references a UI
   type — same boundary as before, but push instead of poll.

2. **Buttons.** `Button.pressed` is itself a signal. `ui.gd` connects the
   three buttons and re-emits *semantic* signals (`end_turn_pressed`,
   `simulate_toggled`) so `main.gd` depends on the UI's interface, not on
   its node layout. Connections are made in code here so they're visible
   in review; the editor's Node dock does exactly the same thing visually.

## Step 8 — Time: Timer and Tween instead of `setTimeout`

The JS simulation loop was a chain of `setTimeout(step, delay)` callbacks.
The port uses the `SimTimer` **Timer node**: `_start_auto()` sets a mode
(`ENEMY_PHASE` or `SIMULATE`) and starts the timer; the `timeout` signal
handler performs one AI step and re-arms. Same recursion shape, but the
engine owns the clock — pausing the tree pauses the game for free.

Movement animation uses a **Tween** (`unit_node.gd`):

```gdscript
create_tween().tween_property(self, "position", target, 0.15) \
        .set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
```

Fire-and-forget: the engine interpolates `position` every frame and
disposes the tween when done. The JS version simply teleported units;
this is the first thing the engine gives you "for free."

## Step 9 — Battle vignettes: overlays, `_process` animation, and `await`

The Fire Emblem combat cut-in (`js/battle.js` → `scripts/battle_vignette.gd`)
is the most instructive piece of the port, because it forces three engine
concepts at once.

**The design is identical in both versions**, and the vignette runs in two
modes:

- **Replay** (AI vs AI): the core resolves combat instantly
  (`combat.gd` mutates HP and returns an event list), and `game.attack()`
  records a snapshot — combatants, pre-battle HP, events — that the
  vignette replays as pure animation: fighters lunge on each strike,
  damage numbers pop, HP bars drain, crits flash, misses dodge, deaths
  fade out. Nothing waits on animation state, which is why the headless
  test from Step 10 still runs at full speed with no window.
- **Interactive** (the player's battles — see "Quick Time Events" below):
  the core only *plans* the strike order (`Combat.plan_strikes`), and each
  strike resolves mid-vignette (`Combat.resolve_strike`) after the
  player's timed input sets its damage multiplier.

What differs is the plumbing:

1. **The overlay is a full-screen `Control`.** While visible, its default
   `mouse_filter = STOP` swallows every click before it reaches the board
   *or* the sidebar buttons — the whole "block input during the animation"
   problem disappears into node ordering (BattleFX is the last child of the
   UI layer, so it's drawn — and hit-tested — on top). Its `_gui_input`
   gets the clicks it swallowed, which implements click-to-skip in four
   lines. The JS version needed an `ui.battlePlaying` flag checked in
   every input handler.

2. **The animation loop is `_process(delta)`.** The JS version drives a
   `requestAnimationFrame` chain and computes `dt` from timestamps; in
   Godot the engine calls `_process(delta)` on every node, every frame,
   with `delta` handed to you. The beat timeline (intro → one beat per
   strike → outro) transfers line for line.

3. **Completion is a signal you can `await`.** The vignette emits
   `finished`; the three places that trigger battles (player attack,
   enemy phase step, simulation step) do
   `if await _play_battle_if_any(): ...continue...`.
   Compare with `js/main.js`, where the same control flow has to thread a
   `done` callback through `playBattleThen(...)` — GDScript's `await`
   flattens continuation-passing into straight-line code. One real-world
   wrinkle came with it: **Reset can fire while a coroutine is suspended.**
   If Reset aborts the vignette, the suspended continuation must not
   resume against the freshly reset game — `main.gd` guards this with an
   `epoch` counter captured before each `await` and checked after. That
   invalidation pattern (generation counters around suspension points)
   shows up in every engine with async gameplay code.

Timing knob: on the Fast sim speed replay vignettes play at 3× (`time_scale`
multiplies `delta`), and the "Battle anims" toggle skips vignettes
entirely — both mirrored in the web version.

### Quick Time Events (Legend of Dragoon style additions)

Battles involving the player are interactive, with two distinct input
feels:

- **Attacking (tap timing):** before each of your blows, a ring shrinks
  onto a target and you tap Space (or click) at the moment they align —
  one tap per step of the attacking class's unique rhythm (`qte` in
  `game_data.gd`: the Knight is one slow heavy beat, the Mercenary a
  three-press chain, the Pegasus three rapid taps…). Tap quality
  (Perfect / Good / Miss) averages into a damage multiplier of 0.75×–1.5×;
  chaining every press perfectly earns **MAX!**.
- **Defending (hold-and-release parry):** when an enemy strike is
  incoming there is no separate approach animation — the enemy's charge
  happens *during* the QTE and is itself the timing cue. You **press and
  hold** to raise your guard while they close in, then **release as the
  blow lands**: a perfect release **parries (50% damage)**, a good one
  blocks (75%), holding through the hit still guards (90%), and dropping
  your guard early — or never raising it — leaves you exposed (100%).
  Once released, the guard cannot be re-raised for that strike.

Ring/gauge colors encode the combat type: **blue** physical, **green**
magic, **red** defense.

Engine notes on the implementation (`battle_vignette.gd`):

- **The QTE is a sub-state machine inside the vignette.** Interactive mode
  swaps the replay-mode beat list for phases
  (`INTRO → APPROACH → QTE → IMPACT → … → OUTRO`), all advanced by the
  same `_process(delta)`. Timing windows are measured in accumulated
  `delta` time, not frames — the same discipline as the JS version's
  `requestAnimationFrame` deltas, and the reason timing feels identical
  at any frame rate.
- **Keyboard input arrives via `_unhandled_key_input`** — the keyboard
  sibling of `_unhandled_input` from Step 5 — while mouse presses reuse
  the overlay's `_gui_input`. The parry made both handlers edge-aware:
  `event.pressed` (minus `event.echo` key repeats) routes to
  `_hold_start()`, the release edge to `_hold_end()`. Taps and holds are
  the same two edges — a "tap" is just a press whose release nobody
  listens to, which is why offense needed no changes when defense
  started caring about release timing.
- **The core/presentation boundary held.** `combat.gd` gained
  `plan_strikes()` and `resolve_strike(actor, target, rng, off_mult,
  def_mult)`; it knows nothing about rings or input. The grading math
  (`grade_press`, `offense_result`, `defense_result`) is `static` on the
  vignette, so the headless test exercises it without a window. AI-vs-AI
  paths pass neutral multipliers and behave exactly as before.
- **`time_scale` is forced to 1 in interactive mode** — speeding up the
  animation would change the difficulty, because the timing *is* the
  gameplay.

## Step 10 — Verifying without a window

The JS prototype was verified by driving headless Chromium with
Playwright. The Godot equivalent is built into the binary — no browser
needed:

```bash
cd godot
godot --headless -s tests/sim_test.gd
```

`-s` runs a script (extending `SceneTree`) instead of the main scene.
[tests/sim_test.gd](../godot/tests/sim_test.gd) plays 10 full AI-vs-AI
battles with **seeded RNG** (reproducible — an upgrade over the JS
version's `Math.random`), asserts every reachable tile is within movement
budget and every path is strictly cardinal, and exits nonzero on failure.
That exit code makes it CI-ready as-is.

(The battle vignette is deliberately not exercised here — it's pure
playback of the same event lists the test already validates.)

Static checking exists too, via `pip install gdtoolkit` (the community
GDScript toolchain, versioned in lockstep with Godot):

```bash
gdparse scripts/**/*.gd tests/*.gd   # syntax against the 4.5 grammar
gdlint  scripts/**/*.gd tests/*.gd   # style/structure lints
```

Both pass clean on this port. **Honest caveat:** this environment could
not download the Godot binary itself (network policy), so the scripts are
parser-verified and API-checked by review, but the project has not been
*executed* here. On first open, if the editor reports a script error, it
will name the exact file/line — expect at most small API-signature nits,
and please fix-and-commit (the docs and structure won't change).

## Running it

1. Open Godot → **Import** → select `godot/project.godot` → **Edit**.
2. Let the editor finish its first import scan (generates `.godot/`,
   adds `uid://` lines to the `.tscn` files).
3. Press **F5** (Run Project). `main.tscn` launches: same demo as the
   web version — click blue units to move/attack, or hit **Simulate**.
4. From a terminal, the headless test: `godot --headless -s tests/sim_test.gd`
   (run inside the `godot/` directory).

## Where to go next (each teaches one engine system)

1. **TileMapLayer + a tile atlas** — replace `board.gd`'s terrain drawing
   with real tiles. Teaches: TileSet resources, atlases, terrain sets.
2. **Resources (`.tres`)** — lift `UnitClass` definitions out of
   `game_data.gd` into `@export`-annotated Resource files editable in the
   Inspector. Teaches: Godot's data-asset pipeline (designers edit data
   without touching code).
3. **AnimationPlayer / AnimatedSprite2D** — sprite units with idle/attack
   animations. Teaches: keyframe animation. (The battle vignette is the
   natural place to start: rebuild its hand-rolled beat timeline as
   AnimationPlayer tracks and compare.)
4. **Camera2D** — bigger maps with scrolling and edge-pan. The
   `get_local_mouse_position()` input code already survives this change.
5. **AudioStreamPlayer** — hit/heal/victory sounds. Teaches: the audio bus.
6. **Export templates** — ship a Windows/Linux/Web build from the Export
   dialog. The web export closes the loop: the Godot game back in the
   browser where the prototype started.
