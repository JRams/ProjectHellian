# Project Hellian — from prototype to game

**Status:** proposal for review. Companion to
[DECISIONS-TO-MAKE.md](DECISIONS-TO-MAKE.md) (which gates it),
[DESIGN_GAPS.md](DESIGN_GAPS.md) (the design holes being reviewed one by
one; their calls feed the milestones below), and
[MAP_EDITOR.md](MAP_EDITOR.md) (the first piece of the content pipeline,
already built).

What exists is a *combat prototype*: one map, seven classes, a real tactics
core, battle vignettes with a Legend of Dragoon timing layer, an AI that
plays both sides, and a map editor. What it isn't yet is a *game*: nothing
persists, nobody has a story, and there is no reason to play map two. This
document is the plan for closing that gap, in an order that keeps something
playable at every step.

> **Not a Fire Emblem clone.** FE is the skeleton for chapters, permadeath,
> growth, and presentation. Combat itself diverges: there is **no weapon
> triangle**. Effectiveness comes from an **attunement chart** (a small
> elemental table driving damage and hit), and classes define a *kit*
> (addition pattern, weapon, range, physical/magical/support attribute)
> rather than a triangle slot. See DESIGN_GAPS Gap 0 and milestone M1.

---

## Part 1 — What Fire Emblem gets right (and what each means for us)

FE's design is often summarized as "chess with permadeath," but the actual
pinnacles are the places where two systems reinforce each other. Each one
below ends with the concrete implication for this codebase.

1. **Units are people, and losing them is permanent.** Names, faces,
   personalities, and support conversations turn stat blocks into
   characters; permadeath turns tactics into care. Neither works alone —
   permadeath without attachment is just a harder puzzle, attachment
   without stakes is a visual novel.
   → We need a `Character` layer above `UnitClass` (identity, portrait,
   growths, attunement, story hooks), and a Classic/Casual choice from
   day one.

2. **The chapter is the unit of design.** Story beat → preparations →
   a *handcrafted* map with a specific objective and scripted events →
   aftermath. Maps are authored, not generated; the objective (seize the
   throne, survive 10 turns, rescue the villagers) is what makes a map
   memorable, not its terrain.
   → `ChapterData` bundling map + objective + events + script + rewards.
   The map editor already produces the map half.

3. **Growth is legible and slightly random.** Level-ups roll each stat
   against a per-character growth rate; promotion at level 10+ changes
   class. You feel a unit "turn out well" and you plan around it.
   → EXP/level/growth/promotion, with growths on the Character, not the
   class.

4. **Every fight is a small read.** In FE the read is the weapon triangle
   (Sword > Axe > Lance, +15 hit / +1 dmg), bows vs fliers, tomes vs
   armour, and weapons that break. The lesson is the *read*, not the
   triangle.
   → **We replace the triangle with the attunement chart** (Gap 0): the
   read is "what are they attuned to, what am I", shown in the forecast
   as Effective / Neutral / Resisted. Classes become kits, so we choose
   new classes for kit variety, not to complete a triangle. Items and
   durability stay (M6); weapon *type* carries no rock-paper-scissors.

5. **Full information, fair consequences.** Battle forecasts, visible
   enemy ranges, danger zones. FE is never about hidden information (fog
   maps are the deliberate exception); it's about *planning* with what
   you can see, and then living with the enemy phase.
   → We have forecasts and ranges. Add danger-zone overlay and a limited
   rewind (Divine Pulse) — modern FE's answer to "one misclick ends 40
   minutes." The QTE layer must respect this too (Gap 1: the forecast is
   a floor, execution only adds).

6. **Recruitment mid-battle.** Talk to that green unit, that enemy who
   hesitates. The roster grows through play, and each recruit is a story.
   → Event triggers + a `talk` action + recruit conditions on Characters.

7. **Supports.** Pairs who fight side by side unlock conversations and
   combat bonuses. It is the cheapest narrative system per line of text
   ever devised — and it makes positioning emotionally loaded.
   → Adjacency tracking, support ranks, paired dialogue files.

8. **Difficulty is a menu, not a compromise.** Normal/Hard/Lunatic,
   Classic/Casual, rewind counts. The same content serves a first-timer
   and a veteran.
   → Difficulty as data, on two axes: Tactics (enemy scaling, rewinds)
   and Timing (QTE window scale, or Auto). See Gap 1.

9. **Between-map management matters but stays light.** Prep screen
   (deploy who, equip what), shop, convoy. Later entries added hub bases;
   the GBA games prove you don't need one.
   → Preparations screen; no hub in v1.

10. **Presentation carries weight cheaply.** Portrait + expression +
    name plate + text box is 90% of the storytelling. Map/battle themes
    and a per-character theme do the rest.
    → A portrait-driven dialogue layer and a small music pass.

## Part 2 — Design pillars for Hellian

Where FE is the skeleton, these four are the identity. Every feature
below should serve at least one; anything that serves none is cut.

1. **Every unit is a person.** (FE pillar, kept whole.) Named, drawn,
   voiced through dialogue, mournable. Attunement is a fact about the
   *person*, not the class, so it is part of who they are.
2. **Your hands matter.** The Legend of Dragoon layer is our
   differentiator: tactics decide *whether* you fight, execution decides
   *how well*. Additions should grow with the character (LoD's own
   mechanic — additions level up through use, unlocking longer chains
   and higher multipliers), making mastery a progression axis FE doesn't
   have.
3. **Full information, fair consequences.** Forecasts, ranges, danger
   zones, and a rewind budget. Punish plans, never surprise them. The
   attunement chart is small enough to hold in your head; the forecast
   is a floor that execution can only raise.
4. **Readable one-handed on a phone.** Portrait, thumb-zone input, no
   information that needs a mouse hover. (Assumes DECISIONS §1 resolves
   toward mobile-portrait, which the prototype work has been steering to.)

## Part 3 — Systems inventory

| System | Have | Need | Milestone |
|---|---|---|---|
| Combat rules (formula, effectiveness) | hit/crit/double/counter | **attunement chart, class kits, resolution order, COMBAT_RULES.md** | **M1** |
| QTE rules (floors, prompts, difficulty axes) | offense + parry, always-on | Gap 1 rules encoded; tuning later | M1 / M7 |
| Grid, terrain, movement, ranges | ✅ | villages/thrones/chests/doors as terrain | M4 |
| Classes | 7 | kits formalized (M1); new classes for kit holes; promoted tiers | M1 / M3 |
| Characters (identity, growths, attunement, story) | ❌ | `Character` resource | M2 |
| AI | ✅ solid | per-unit profiles (hold/guard/chase), objective-aware | M4 |
| Battle vignette + QTE/parry | ✅ | addition leveling, heal addition, effect polish | M7 |
| Map editor + validation + playtest | ✅ v1 schema | schema v2 tokens, event authoring, new terrain | M1 / M2 / M4 |
| Objectives | rout only | seize, survive, defend, boss, escape; attrition out of play | M4 |
| Map events (reinforcements, talk, visit) | ❌ | trigger system | M4 |
| Persistent roster, EXP, levels, promotion | ❌ | progression core | M3 |
| Items, inventory, durability, convoy, shop | ❌ | items core + prep screen + weapon attunement override | M6 |
| Dialogue (portraits, text, choices, flags) | ❌ | script format + UI | M5 |
| Supports | ❌ | adjacency tracking + ranks | M5 |
| Campaign flow (title → chapter → results) | ❌ | `CampaignController` | M2 |
| Save/load, suspend/resume | ❌ | `Game.to_dict()`, JSON to `user://` | M2 |
| Rewind | ❌ | state snapshots (cheap — core is pure) | M7 |
| Difficulty modes, Classic/Casual | ❌ | data-driven modifiers, two axes | M7 |
| Audio | ❌ | timing cues (M8), music + SFX pass | M7 / M8 |
| Art (sprites, portraits, tiles) | procedural | asset pipeline; portraits are the big need | M7→M9 |
| Menus, settings, accessibility | ❌ | title, options, shape-coded QTE cues | M10 |
| Headless testing | battle-level | matchup matrix (M1), campaign-level sim + balance report (M3) | M1 / M3 |

## Part 4 — Architecture: the campaign layer

The rule that made every feature so far cheap — **nothing in `core/`
touches a node** — holds. The campaign layer is more pure data and one
new orchestrator. Everything here is `Resource`s (Inspector-editable for
free, like `MapData`) or human-readable text (like the map rows).

### 4.1 Data model

```
Attunement chart (core data)   the read
  elements[] (e.g. ember, gale, stone, tide, null)
  chart[(atk, def)] -> tier      effective | neutral | resisted
  tiers{tier -> dmg_mult, hit_delta, crit_delta}

Character (Resource)      who they are
  id, display_name, portrait, class_id, join_level, is_lord
  attunement
  bases{hp,str,mag,skl,spd,def,res}, growths{…} (0–100 %)
  addition_override (optional), addition_level, death_quote, recruit{condition}
  supports[{with: id, ranks: [C,B,A] -> dialogue files}]

UnitClass (exists)        what they can do — the KIT
  attribute (physical | magical | support), attack_range[], weapon,
  addition (default QTE pattern), movement (foot|mounted|flier, armoured)
  + promotes_to, promotion_bonuses{}, level_cap

Item (Resource)           what they carry
  kind (sword/lance/axe/bow/tome/staff/consumable — flavour + animation)
  might, hit, crit, weight, uses, price
  attunement (optional; overrides the wielder's on offense only)

MapData (exists, schema v2 in Gap 2)   where they fight
  + player lines become deploy SLOTS (the roster fills them at prep)
  + enemy lines gain tokens:  "Brigand 15 2 Raider L4 tide ai=hold boss"
  + npc_units, features (village/throne/escape), schema_version

ChapterData (Resource)    one chapter
  id, title, map: MapData
  objective{type, params}         # rout | seize@(x,y) | survive N |
                                  # defend@(x,y) N | boss id | escape zone
  events[]                        # see 4.3
  intro_script, outro_script      # dialogue files
  deploy_count, forced_deploys[], rewards{gold, items}, next_chapter, par_turns

Campaign (Resource)       the whole game
  chapters[], starting_roster[], starting_convoy[], starting_gold

SaveData (JSON, user://)  the player's run
  campaign_id, chapter_index, difficulty{tactics, timing}, mode (classic|casual)
  roster[{char_id, level, exp, stats{}, inventory[], alive, addition_lvl}]
  convoy[], gold, flags{}, supports{pair: points}, rewinds_left
  suspended_battle (Game.to_dict(), optional)
```

`Unit` (the live battle object) is then *constructed from* a Character +
its SaveData entry at chapter start, and its results (EXP, HP, items,
death) are written back at chapter end. Battle code keeps seeing plain
`Unit`s; it never learns what a campaign is.

### 4.2 Flow

One autoload singleton — `CampaignController` — owns the state machine.
(Autoloads are the one Godot concept the port guide hasn't covered yet;
this is its natural introduction.)

```
Title ─► New/Continue ─► ChapterIntro (dialogue)
       ─► Preparations (deploy, equip, shop) ─► Battle (main.tscn)
       ─► ChapterOutro (dialogue) ─► Results (EXP summary, deaths, rewards)
       ─► autosave ─► next chapter … ─► Ending
```

Each box is a scene; the controller swaps them with `change_scene_to_file`
and carries `SaveData` between them. `main.tscn` gains one input (the
`ChapterData` to run) and one output (a results dictionary), and is
otherwise untouched.

### 4.3 Text formats (keep the "fixable in vim" ethos)

**Events**, inside a ChapterData, one trigger per line:
```
turn 3        : reinforce enemy "Brigand 15 2 Raider L4 tide" ×3 at east
turn 6        : dialogue ch01_boss_taunt
reach 7,3 by player   : dialogue ch01_bridge ; flag bridge_taken
talk Silke -> Vask    : recruit Vask ; dialogue ch01_vask_joins
visit 2,9             : item Vulnerary ; dialogue ch01_village
dies Kaia             : dialogue ch01_kaia_falls
```
Trigger vocabulary: `turn N`, `reach x,y by <side|name>`, `talk A -> B`,
`visit x,y`, `dies <name>`, `start`, `end`. Action vocabulary:
`reinforce`, `dialogue`, `flag`, `recruit`, `item`, `gold`, `end_chapter`,
`spawn_npc`. A ~150-line parser plus a dispatcher that `Game` calls at
the right moments (`turn_started`, `unit_moved`, `unit_died`, …) — and
those are just signals `Game` doesn't emit yet.

**Dialogue**, one file per scene:
```
@scene forest dusk
Doran|worried: We can't hold the bridge much longer.
Silke|smirk: Then we don't hold it. We cross it.
? What do we do?
  > Cross now          => set bold
  > Wait for Averil    => set cautious
@if cautious
Averil: Took you long enough.
@end
```
Speaker`|`expression`:` text; `?` choices with `=>` effects; `@if/@end` on
flags; `@scene` sets the backdrop (reusing the terrain-keyed backdrop
system). ~200 lines to parse and drive. **Checkpoint:** if branching
outgrows this (nested conditions, variables, timelines), graduate to the
*Dialogue Manager* addon rather than growing a custom language — its
`.dialogue` files are close enough that porting is mechanical.

### 4.4 Combat and progression math (v1, all tunable)

Combat (settled in M1, written up in `docs/COMBAT_RULES.md`):

- Attribute picks the defence: physical → Def, magical → Res, support
  heals. Base = `power − guard` as today.
- **Attunement tier** from the chart: Effective ×1.5 dmg / +15 hit,
  Neutral ×1.0 / +0, Resisted ×0.67 / −15 (Gap 0 proposal; numbers live
  in one table).
- Resolution order per strike:
  `(power − guard) × tier × (3 if crit) × offense_QTE × defense_QTE`,
  rounded once. Hit = `hit + skl×2 − avoid + tier_hit`, clamped 5–100.
- No triangle, no bow-vs-flier bonus, no weapon ranks (Gaps 0 and 9).
- QTE: offense floor 1.0× (forecast is a guarantee), inaction on defence
  = Guarded 0.9×, enemies never roll a QTE (Gap 1 proposal).

Progression (M3, GBA-flavoured):

- EXP per action: 10 for a hit, +20 for a kill, scaled by
  `clamp(1 + (enemy_level − my_level) × 0.1, 0.3, 2.0)`; 100 EXP = level.
- Level-up: each stat gains +1 with probability `growth%`. Caps per class.
- Promotion: level ≥ 10 + a promotion item → promoted class, +bonuses,
  level resets to 1, the addition gains a finisher step. (Skip branching
  promotions in v1.)
- Durability: `uses` per weapon, breaks at 0. Weapons may carry an
  attunement that overrides the wielder's on offense (M6).
- **Additions** (our twist): the class kit defines the pattern; each
  character carries an addition level (1–5). Each *completed* chain (no
  misses) earns addition EXP; levels add steps to the rhythm and raise
  the MAX multiplier (1.5 → 1.6 → … → 2.0). Losing a step never loses
  progress. This makes execution a visible, per-character growth track.
- Difficulty, two axes: **Tactics** = enemy level offset (+0/+3/+6),
  enemy growth boost, rewinds per chapter (∞/5/2), Casual revives dead
  units after the chapter; **Timing** = QTE window scale
  (1.25×/1.0×/0.8×) or Auto (every battle at neutral).

## Part 5 — Milestones

Each milestone ends with something playable and a stated exit test. Order
is chosen so the *rules* are settled (M1) before the schemas that carry
them (M2–M4), and the whole *content pipeline* is complete (M1–M6) before
*content production* (M9) — writing ten chapters against a moving engine
is how projects die.

### M0 — Foundations (1 week)
- Resolve DECISIONS §1: platform & canonical version. Recommendation:
  **mobile-portrait canonical**, desktop as a secondary export of the same
  build; retire the web version to a test harness or archive it.
- Merge order: `map-editor` → `mobile-swipe-prototype` (mirroring the
  rename in DECISIONS §1b).
- First real Godot run; fix first-run nits; commit `uid://` updates.
- Wire CI: `gdparse`/`gdlint` + `sim_test.gd` on every push.
- **Exit:** one branch, green CI, F5 plays Grimwater in portrait.

### M1 — Combat rule foundations (2 weeks)
The rules of engagement, settled and written down before anything stores
them. Inputs: the calls from DESIGN_GAPS Gap 0, Gap 1, Gap 5, Gap 9.
- **Attunement chart as data** in `core/`: elements, `(atk, def) → tier`,
  `tier → (dmg_mult, hit_delta, crit_delta)`. Two tables, one file.
- `attunement` on `Unit`. Interim source: a per-class default so
  Grimwater plays with the system live before `Character` exists (M2).
  Enemy map lines accept an optional attunement token (first piece of
  schema v2, Gap 2); the validator and workbench learn it.
- **Class = kit.** `UnitClass` gains `attribute` (physical | magical |
  support) replacing `is_magic`/`heal_*`; the seven classes are audited
  against the kit table in Gap 0 and the holes recorded for M3.
- **`combat.gd` rewrite**: `strike_stats` returns the tier and applies
  it to damage and hit; `resolve_strike` uses the fixed resolution
  order; QTE floor rules from Gap 1 (offense floor, inaction = Guarded).
  Enemies stay at neutral.
- **Forecast** shows tier (word + shape), post-tier hit and damage, and
  the damage band with the kill threshold by grade.
- **Sim**: matchup matrix (kit × kit × tier pairs) in `sim_test.gd`;
  regression that Null vs Null reproduces today's numbers exactly;
  Grimwater still lands in the 60–75% player-win band with attunements
  assigned.
- **`docs/COMBAT_RULES.md`**: single source of truth for the formula,
  the chart, tiers, QTE multipliers, and resolution order.
- **Exit:** Grimwater plays with attunements visible in the forecast and
  on units; the sim's matchup matrix shows Effective pairs winning
  measurably more; COMBAT_RULES.md matches the code line for line.

### M2 — Campaign skeleton (2 weeks)
- `Character` (with `attunement`, `is_lord`), `ChapterData`, `Campaign`,
  `SaveData` resources/JSON.
- `Game.to_dict()`/`from_dict()` including RNG state; suspend/resume
  between actions (Gap 7).
- `CampaignController` autoload; Title → Chapter → Battle → Results loop
  with two stub chapters reusing Grimwater.
- Map schema v2 deploy slots + forced deploys (Gap 2); action menu shell
  with Attack/Staff/Wait and free undo-move (Gap 6).
- Roster persists across chapters (HP resets, deaths stick in Classic).
- Save/load to `user://saves/slot_N.json`; autosave after each chapter.
- **Exit:** play chapter 1 → 2 → 1 again from a save; a unit killed in
  chapter 1 is absent in chapter 2 on Classic, present on Casual; a
  battle suspended mid-way resumes identically.

### M3 — Progression (2 weeks)
- EXP, level-ups with growths, level caps, promotion items; addition
  level stored per character (Gap 5).
- New classes chosen to fill the kit holes from M1's audit (a melee
  magical kit, a 1–2 physical kit, an enemy support kit; Brigand and
  Thief for enemy variety), not to complete a triangle.
- `campaign_test.gd`: headless AI playthrough of the whole campaign
  (neutral QTE multipliers), reporting per-chapter win rate, average
  level at each chapter, death rate per character, matchup matrix per
  chapter. **This is the balance instrument for everything after.**
- **Exit:** headless campaign sim runs green; level curves look sane.

### M4 — Objectives, events, AI profiles (2–3 weeks)
- Objective strategies in `Game`: rout / seize / survive / defend /
  boss / escape. Attrition and `turn_limit` leave play and become QA-only
  (Gap 3); par turns on the results screen.
- Per-unit AI profiles (`aggressive`/`hold`/`guard`/`chase`/`support`)
  from map tokens; caution timers relative to spawn turn (Gap 8).
- New terrain: village (visitable, destroyable), throne, gate, chest,
  door. Map editor legend + atlas extended; validator learns objective
  rules (seize target must exist, escape zone reachable…) and all
  schema-v2 tokens.
- Event trigger system (4.3) + `Game` signals; reinforcements, talk/
  recruit, visit, flags. Menu verbs Talk/Visit/Seize (Gap 6).
- **Exit:** one chapter per objective type, each validating and passing
  the headless sim.

### M5 — Dialogue, story, supports (2–3 weeks)
- Dialogue parser + scene UI (portrait, expression, name plate, text box,
  choices, auto/skip/log). Portrait placeholders: coloured silhouettes
  with class glyphs until art arrives.
- Intro/outro scripts per chapter; event-triggered mid-battle dialogue;
  death quotes; boss banter. The lord's identity and voice (Gap 4).
- Supports: adjacency points per turn, C/B/A thresholds, conversations
  unlocked from the prep screen, +hit/+avoid when adjacent.
- **Exit:** three chapters fully scripted; a choice in chapter 1 changes
  a line in chapter 3.

### M6 — Items & economy (2 weeks)
- `Item` resources; inventory (5 slots), equip, durability, convoy.
  Weapon stats (might/hit/crit/weight) move from the class to the item.
- **Weapon attunement override** on offense in `combat.gd`; forecast
  shows the effective attunement. No weapon ranks (Gap 9).
- Preparations screen: deploy slots, equip, trade, shop (gold from
  chapter rewards/villages). Menu verbs Item/Trade (Gap 6).
- **Exit:** a weapon breaks mid-chapter and the unit falls back to the
  next; a Tide tome flips a Resisted matchup to Effective in the
  forecast; the sim's balance report includes gold/item flow.

### M7 — Feel (2–3 weeks)
- Rewind: snapshot `Game` state per player action; N per chapter by
  difficulty. No RNG re-roll on rewind (Gap 7), so rewind fixes plans,
  not dice.
- Difficulty on two axes (Tactics × Timing, incl. Auto) + Classic/Casual
  + accessibility: **shape-coded QTE cues** so the blue/green/red scheme
  isn't the only signal (colourblind users).
- Addition leveling (4.4); heal addition for support kits; meaningful-
  moment enemy-phase prompts with an "Always prompt" option (Gap 1).
- Audio: map theme, battle theme, victory/defeat stings, hit/parry/
  MAX! SFX via `AudioStreamPlayer`.
- Art pipeline decision: commission sprites/portraits, or commit to a
  polished procedural style. Portraits are the long pole either way.
- **Exit:** a new player finishes chapter 1 on Normal without reading
  docs; a veteran finds Hard/Classic threatening.

### M8 — Vertical slice (2 weeks)
- Chapter 1 to shipping quality: final map, script, music, art (or final
  procedural style), tutorialization woven into events (first parry,
  first addition, first Effective hit, first village).
- QTE timing cues (windup sound, haptic tick) treated as input and
  shipped here, not in the audio pass.
- External playtest with 5–10 people; instrument: chapter time, deaths,
  QTE grade distribution, rewind usage, how often players check the
  attunement of a target before attacking.
- **Exit:** playtesters finish chapter 1 and ask for chapter 2.

### M9 — Content production (6–10 weeks, the long pole)
- Chapters 2–10 through the pipeline: map → events → script → sim →
  playtest → tune. Target cadence: one chapter/week once the pipeline is
  warm.
- Roster to ~14 characters (1–2 recruits per chapter) covering every
  attunement and kit, 2–3 bosses with distinct AI profiles, one
  late-game twist map (fog or escape).
- Balance from the campaign sim after every chapter lands.
- **Exit:** full campaign completes headlessly and by hand on Normal.

### M10 — Ship (2–3 weeks)
- Title/options/credits; settings persistence; localization hooks
  (all strings through `tr()`, dialogue files per locale).
- Exports: Android (primary), desktop; iOS when a Mac is available; web
  build as the free demo/playtest channel.
- Store assets, versioning, crash reporting, a "send feedback" path.
- **Exit:** a build a stranger can install and finish.

Rough total: **7–9 months** of focused solo work, or ~4–5 with a second
person on content/art. The honest variance is all in M9 (content) and
the art decision in M7; M1 is the cheapest place to be slow, because
every later schema depends on its answers.

## Part 6 — Content plan & scope tiers

Scope is the only real risk lever, so define it in tiers you can stop at:

| Tier | Chapters | Characters | Objectives used | Playtime |
|---|---|---|---|---|
| Vertical slice (M8) | 1 | 6 | rout | 20 min |
| Demo | 3 | 8 | rout, seize, survive | 1.5 h |
| **v1 (target)** | 10 (prologue + 8 + finale) | 14 | all six | 8–10 h |
| Stretch | 15 + paralogues | 20 | + fog, escape gauntlet | 15 h |

Story shape for v1 (three acts, deliberately simple so chapters can be
written independently): a border garrison (our seven) is cut off when the
river crossing falls; Act 1 is holding and escaping (ch. 1–3), Act 2 is
gathering allies across the realm (ch. 4–7, most recruits here), Act 3 is
taking the crossing back (ch. 8–10). The named enemies from Grimwater
(Gorm, Vask, Hessa…) are the recurring antagonists; at least one becomes
recruitable. The recurring antagonist's attunement is the lord's
opposite, so the final fight is a neutral read decided by play.

## Part 7 — Testing & balance strategy

This project's unusual asset is that the AI can play the whole game
without a screen. Lean on it:

- `sim_test.gd` (exists): per-map balance. M1 adds the matchup matrix
  and the Null-vs-Null regression.
- `campaign_test.gd` (M3): plays the campaign end-to-end on each
  difficulty, 20 seeds. Reports win rate per chapter, average roster
  level per chapter, per-character death rate, gold curve, turn counts.
  Fails CI if any chapter is < 40% or > 95% winnable on Normal.
- Validator (exists) extended per schema-v2 token (M1–M4) and per
  objective (M4).
- Human playtests at M8 and each M9 chapter; instrument the build
  (local JSON logs are enough) for QTE grade distributions — the timing
  windows can only be tuned against real thumbs.

## Part 8 — Decisions that gate the start

All tracked in DECISIONS-TO-MAKE.md and DESIGN_GAPS.md; these are the
ones the plan cannot begin without:

1. **Platform / canonical version** (DECISIONS §1). Recommendation:
   mobile-portrait.
2. **Attunement chart shape and semantics** (DESIGN_GAPS Gap 0): chart
   size, tier numbers, attunement on the person not the class, no
   class-based effectiveness. Recommendation: 4-cycle + Null, ×1.5/×0.67,
   ±15 hit. Gates M1.
3. **QTE floor rules** (Gap 1): offense floor 1.0×, inaction = Guarded,
   two difficulty axes. Gates M1.
4. **Permadeath default**: Classic default with Casual offered (FE norm),
   or Casual default? Recommendation: Classic default, ask at new game.
5. **Dialogue tech**: custom-lite format (learning value, fits the text
   ethos) vs Dialogue Manager addon (speed). Recommendation: custom-lite
   with the stated graduation checkpoint.
6. **Art strategy**: commission vs. polished procedural. Portraits are
   the deciding case — procedural faces are hard; silhouettes are fine
   for M2–M6 but not for shipping. Recommendation: budget for portraits
   + a tile set; keep procedural battle backdrops.
7. **Content tier** (Part 6). Recommendation: build the pipeline for v1,
   ship the demo tier first as a public playtest.

## Part 9 — Risks

- **Content is the long pole**, not engineering. Every milestone before
  M9 exists to make M9 cheap. Resist adding systems during M9.
- **Rules drift.** If the attunement chart or QTE floors change after
  M2, every schema and every authored chapter carries the old answer.
  M1 exists to make that change once; COMBAT_RULES.md is the contract.
- **QTE fatigue** across a 10-hour campaign is unknown until M8's
  playtest. Mitigations are already designed (Auto timing, meaningful-
  moment prompts, addition progression making chains satisfying) — but
  the playtest decides.
- **A four-element chart can feel arbitrary** if the fiction doesn't
  carry it. The element names, the lord/antagonist opposition, and
  per-attunement visual identity are story and art work, not just data.
- **Art** is the biggest budget/time unknown; decouple it from
  engineering by keeping the placeholder pipeline working to the end.
- **Mobile QTE timing** on real devices (touch latency, refresh rates)
  may need per-device calibration — measure at M8.
- **Solo-dev scope**: v1 is ambitious for one person. The tier table is
  the pressure valve; the demo tier is a complete, shippable game.
