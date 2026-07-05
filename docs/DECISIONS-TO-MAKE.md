# Decisions to make & carry-forward notes

One consolidated list of every open question, tuning knob, caveat, and
recommendation accumulated across the project — pulled from
[GODOT_PORT.md](GODOT_PORT.md), [MOBILE_SWIPE.md](MOBILE_SWIPE.md), and
working notes that previously lived only in session discussion. When a
decision gets made, record it here (or delete the entry) so this file
stays the single source of truth.

---

## 1. The big one: which version is the game?

Three implementations exist and have diverged:

| | `js/` (web) | `godot/` on main branch | `godot/` on `claude/mobile-swipe-prototype` |
|---|---|---|---|
| Layout | landscape | landscape | **portrait** |
| Offense QTE | timed taps | timed taps | **directional swipes** |
| Defense QTE | hold-release parry | hold-release parry | hold parry + **positional deflect** |
| Haptics | — | — | on parries |
| Art | placeholder | placeholder | **procedural art pass** (`art.gd`) |
| Purpose | fast prototyping/testing | learning-guide reference | mobile direction |

- [ ] **Decide the canonical shape.** If mobile-portrait is the game,
  merge the prototype branch and accept that the landscape layout is
  gone from Godot. The learning value of the main-branch Godot version
  is preserved by git history and GODOT_PORT.md either way.
- [ ] **Decide the web version's future.** Options: (a) keep it as the
  fast test harness only, letting features drift (it already lacks
  swipes/art); (b) retire it once the Godot headless tests cover
  everything you care about; (c) keep it in lockstep (real ongoing
  cost — every feature lands twice).
- Note: if the prototype merges, the art pass exists **only in Godot**.
  The web version keeps placeholder art unless deliberately back-ported
  (the canvas source for the art already exists — it was designed in
  canvas first — but wiring it into `js/render.js`/`js/battle.js` is
  its own task).

## 2. Combat & QTE design decisions

- [ ] **Deflect trigger rule** — currently *magic attackers only*
  (readable: see a mage coming, know the motion). Alternatives: heavy
  chargers (Knight/Cavalier) also deflect; or a per-strike random mix.
  One line to change: `_start_qte()` in `battle_vignette.gd`.
- [ ] **Parry strength tuning** — flagged during playtest planning:
  50% off a perfect parry may make enemy phases too safe. All knobs in
  one place each version:
  - multipliers: `defense_result()` (Parried 0.5 / Blocked 0.75 /
    Guarded 0.9 / Exposed 1.0)
  - timing: `DEFENSE_QTE` in `game_data.gd` / `data.js`
    (`windup 0.5s, travel 0.9s, perfect ±0.07s, good ±0.16s`)
- [ ] **Offense QTE tuning** — multiplier curve in `offense_result()`
  (0.75×–1.5×, all-perfect = MAX!); per-class rhythms and tolerances in
  the `qte` blocks of `game_data.gd` (Archer's ±0.04s perfect window is
  the strictest — verify it's hittable on a real touchscreen).
- [ ] **Swipe patterns per class** (prototype) — current directions are
  flavor guesses (Knight ↓, Mercenary →←→, Cavalier →→, Archer ↑,
  Mage ↑↓, Pegasus ↑→↓). Tune in `game_data.gd`. A circle gesture for
  the Mage is possible but needs more detection code.
- [ ] **Deflect spot reach** — the three anchor positions
  (`DEFLECT_ANCHORS` x = 100/220/340) stretch one-handed play at the
  edges. Narrow the spread if one-thumb play matters.
- [ ] **Unskippable interactive battles** — deliberate (timing = the
  gameplay), but consider an accessibility/pace option later: e.g. an
  "auto-resolve my battles" toggle that runs them at neutral
  multipliers, like the anims-off path already does.
- [ ] **Enemy-phase QTE fatigue** — every enemy attack demands a parry.
  Fine at 7v7; on bigger maps consider limiting prompts (e.g. only when
  the defender could die, or a stamina-style cap).

## 3. Balance & AI knobs (all data, no redesign needed)

Symmetric-army AI sims currently land ~70–75% player wins (player moves
first; the AI plays both sides identically). Knobs, in `ai.js` /
`core/ai.gd` unless noted:

- attack commit threshold: score `> -5` in `plan_action`
- kill bonus `+50`, likely-death penalty `-40`, counter-damage weight `0.6`
- threat-range caution: fades to zero by **turn 7** (`advance_toward`)
- army cohesion: anchors to fighting allies until **turn 8**, penalty
  `(dist-3) × 1.5`
- stalemate valve: attrition decision at **turn 60**
  (`Game.TURN_LIMIT` / `decideByAttrition`)
- combat math: crit = ×3, hit clamped 5–100, doubling at Spd+4
  (`combat.js` / `core/combat.gd`)

## 4. Mobile UX decisions (prototype branch)

- [ ] **Scope: Option A vs B** — A (swipe QTEs only) is implemented.
  B adds map gestures: Camera2D pan/zoom, drag-a-path movement. Only
  needed when maps outgrow one screen; pairs with the "bigger maps"
  roadmap item. (Option C — all-gesture UI — was assessed and rejected:
  gesture-conflict cost, no benefit in a turn-based game.)
- [ ] **Map touch targets** — tiles land at 33px after the 0.75 board
  scale, under the ~44px comfortable-touch guideline. Options: tap-radius
  forgiveness, bigger tiles + camera (Option B), or accept for prototype.
- [ ] **Help panel → onboarding** — the how-to text is heavy for a
  phone. Candidates: collapsible sheet, or a first-run tutorial overlay
  that walks one battle.
- [ ] **Info/log panels** — flagged for a real mobile pass: collapsible
  bottom sheets instead of fixed panels.
- Decided ✓: portrait orientation (sensor), enemy-top/player-bottom
  staging, dedicated swipe pad with pad-gated input, haptics on parries
  (70ms Parried / 35ms Blocked), keyboard fallbacks stay for now.

## 5. Art & presentation

- [ ] **Sprites eventually?** The procedural art (`godot/scripts/art.gd`,
  prototype branch) is the entire visual layer — one file to swap when
  real sprite/tile assets arrive. The backdrop contract to preserve:
  `draw_backdrop(ci, rect, terrain_key)` keyed off the defender's tile.
- [ ] **Known art gaps** (cheap wins if staying procedural):
  - death fade "pops" the figure out instead of alpha-fading (per-shape
    alpha wasn't worth plumbing through ~40 shapes; trivial with sprites)
  - no idle animation (a breathing bob is ~3 lines in `_process`)
  - no attack effects (arrow projectile, spell bolt, slash arc)
  - single time-of-day palette (dusk); per-battle palettes and weather
    (forest rain) are natural variants of the same layered backdrop
- Note: art was designed canvas-first (scratchpad mock), then ported.
  Detail placement uses a deterministic LCG with identical constants in
  both, so the mock renders match the engine pixel-for-pixel — keep that
  parity if you iterate on either side.

## 6. Engineering carry-forward notes (not decisions — must-knows)

1. **The Godot project has never been executed.** The dev environment
   could not download the engine (network policy), so all GDScript is
   parser/lint-verified (`gdparse`/`gdlint`, gdtoolkit 4.5) and
   API-checked by review, but the first real F5 happens on your machine.
   First-run checklist: open `godot/project.godot` in **Godot 4.5**
   (4.x required; will not run on 3.x) → let the import scan finish →
   the editor adds `uid://` lines to the `.tscn` files (normal — commit
   them) → F5 → if any script error appears, it names file/line; fix
   and commit.
2. **Headless test**: `cd godot && godot --headless -s tests/sim_test.gd`
   — seeded AI battles + pathfinding + QTE-math assertions, exits
   nonzero on failure. CI-ready; wiring a GitHub Action for it (plus
   `gdparse`/`gdlint` via `pip install gdtoolkit`) is an easy win.
3. **The web test harness is not in the repo.** The Playwright suites
   that verified every web feature (QTE grading, parry outcomes, full
   sims, vignette lifecycle) lived in the session scratchpad and are
   gone with it. If the web version stays load-bearing, recreate a
   `tests/web/` harness (Playwright + the patterns documented in
   GODOT_PORT.md Step 9/10) — otherwise the Godot headless test is the
   only committed automation.
4. **Async-invalidation pattern**: Reset during a vignette resumes
   suspended coroutines — `main.gd` guards with an `epoch` counter
   captured before each `await`. Any new async flow (new overlays,
   network later) needs the same guard.
5. **Core/presentation boundary is the load-bearing wall.** Nothing in
   `scripts/core/` (or the JS equivalents) touches a node, the DOM, or
   input. Every big feature so far (vignettes, QTEs, swipes, art) cost
   zero core changes beyond data + the strike-plan API. Keep it that way.
6. **AI-vs-AI paths must stay instant**: simulation and anims-off play
   resolve through the same `resolve_strike` at neutral multipliers.
   If a change makes the sim depend on animation state, the headless
   test will hang — that's the canary.

## 7. Roadmap (consolidated, roughly ordered)

1. Run the Godot project for the first time; fix any first-run nits
   (item 6.1) and commit the uid updates.
2. Playtest & tune: QTE windows, parry multipliers, AI knobs (§2–3).
3. Decide §1 (canonical version) — gates everything below.
4. Option B mobile: Camera2D pan/zoom + bigger maps + touch-target pass.
5. Ship-to-device: Android export first (SDK + keystore + one-click
   deploy; see MOBILE_SWIPE.md), iOS later (needs a Mac + $99/yr);
   web export as a zero-store playtest channel.
6. Engine-learning items still unexplored from GODOT_PORT.md:
   TileMapLayer with a real atlas, Resources (`.tres`) for unit classes,
   AnimationPlayer (rebuild the vignette timeline as tracks),
   AudioStreamPlayer (hit/parry/victory sounds).
7. Game-design backlog from the original demo: weapon triangle,
   multiple maps/objectives (not just rout), inventories & weapon
   durability, campaign structure.
