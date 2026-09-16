# Project Hellian — from prototype to game

**Status:** proposal for review. Companion to
[DECISIONS-TO-MAKE.md](DECISIONS-TO-MAKE.md) (which gates it) and
[MAP_EDITOR.md](MAP_EDITOR.md) (the first piece of the content pipeline,
already built).

What exists is a *combat prototype*: one map, seven classes, a real tactics
core, battle vignettes with a Legend of Dragoon timing layer, an AI that
plays both sides, and a map editor. What it isn't yet is a *game*: nothing
persists, nobody has a story, and there is no reason to play map two. This
document is the plan for closing that gap, in an order that keeps something
playable at every step.

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
   growths, story hooks), and a Classic/Casual choice from day one.

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

4. **The weapon triangle and durability create texture.** Sword > Axe >
   Lance > Sword (+15 hit / +1 dmg), bows effective vs fliers, tomes vs
   armor; weapons break. Every fight is a small read, and the convoy is a
   resource game.
   → Items and inventory; we need an axe class (there is none).

5. **Full information, fair consequences.** Battle forecasts, visible
   enemy ranges, danger zones. FE is never about hidden information (fog
   maps are the deliberate exception); it's about *planning* with what
   you can see, and then living with the enemy phase.
   → We have forecasts and ranges. Add danger-zone overlay and a limited
   rewind (Divine Pulse) — modern FE's answer to "one misclick ends 40
   minutes."

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
   → Difficulty as data: enemy stat scaling, QTE window scaling, rewinds.

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
   voiced through dialogue, mournable.
2. **Your hands matter.** The Legend of Dragoon layer is our
   differentiator: tactics decide *whether* you fight, execution decides
   *how well*. Additions should grow with the character (LoD's own
   mechanic — additions level up through use, unlocking longer chains
   and higher multipliers), making mastery a progression axis FE doesn't
   have.
3. **Full information, fair consequences.** Forecasts, ranges, danger
   zones, and a rewind budget. Punish plans, never surprise them.
4. **Readable one-handed on a phone.** Portrait, thumb-zone input, no
   information that needs a mouse hover. (Assumes DECISIONS §1 resolves
   toward mobile-portrait, which the prototype work has been steering to.)

## Part 3 — Systems inventory

| System | Have | Need | Milestone |
|---|---|---|---|
| Grid, terrain, movement, ranges | ✅ | villages/thrones/chests/doors as terrain | M3 |
| Combat math (hit/crit/double/counter) | ✅ | weapon triangle, effectiveness, weapon stats | M5 |
| Classes | 7 | Fighter (axe), Brigand, Thief, promoted tiers | M2/M5 |
| Characters (identity, growths, story) | ❌ | `Character` resource | M1 |
| AI | ✅ solid | boss behaviour (hold position), objective-aware AI | M3 |
| Battle vignette + QTE/parry | ✅ | addition leveling, effect polish | M6 |
| Map editor + validation + playtest | ✅ | event authoring, new terrain | M3 |
| Objectives | rout only | seize, survive, defend, boss, escape | M3 |
| Map events (reinforcements, talk, visit) | ❌ | trigger system | M3 |
| Persistent roster, EXP, levels, promotion | ❌ | progression core | M2 |
| Items, inventory, durability, convoy, shop | ❌ | items core + prep screen | M5 |
| Dialogue (portraits, text, choices, flags) | ❌ | script format + UI | M4 |
| Supports | ❌ | adjacency tracking + ranks | M4 |
| Campaign flow (title → chapter → results) | ❌ | `CampaignController` | M1 |
| Save/load | ❌ | JSON to `user://` | M1 |
| Rewind | ❌ | state snapshots (cheap — core is pure) | M6 |
| Difficulty modes, Classic/Casual | ❌ | data-driven modifiers | M6 |
| Audio | ❌ | music + SFX pass | M6 |
| Art (sprites, portraits, tiles) | procedural | asset pipeline; portraits are the big need | M6→M8 |
| Menus, settings, accessibility | ❌ | title, options, colorblind QTE cues | M9 |
| Headless testing | battle-level | campaign-level sim + balance report | M2 |

## Part 4 — Architecture: the campaign layer

The rule that made every feature so far cheap — **nothing in `core/`
touches a node** — holds. The campaign layer is more pure data and one
new orchestrator. Everything here is `Resource`s (Inspector-editable for
free, like `MapData`) or human-readable text (like the map rows).

### 4.1 Data model

```
Character (Resource)      who they are
  id, display_name, portrait, class_id, join_level
  bases{hp,str,mag,skl,spd,def,res}, growths{…} (0–100 %)
  addition_id, affinity, death_quote, recruit{condition}
  supports[{with: id, ranks: [C,B,A] -> dialogue files}]

UnitClass (exists)        what they can do
  + weapon_types[], promotes_to, promotion_bonuses{}, level_cap

Item (Resource)           what they carry
  kind (sword/lance/axe/bow/tome/staff/consumable)
  might, hit, crit, weight, uses, rank, effective_vs[], price

MapData (exists)          where they fight
  + player spawns become deploy SLOTS (the roster fills them at prep)
  + enemy lines gain level + item:  "Brigand 15 2 Raider L4 IronAxe"
  + boss flag, "generic" vs named

ChapterData (Resource)    one chapter
  id, title, map: MapData
  objective{type, params}         # rout | seize@(x,y) | survive N |
                                  # defend@(x,y) N | boss id | escape zone
  events[]                        # see 4.3
  intro_script, outro_script      # dialogue files
  deploy_count, forced_deploys[], rewards{gold, items}, next_chapter

Campaign (Resource)       the whole game
  chapters[], starting_roster[], starting_convoy[], starting_gold

SaveData (JSON, user://)  the player's run
  campaign_id, chapter_index, difficulty, mode (classic|casual)
  roster[{char_id, level, exp, stats{}, inventory[], alive, addition_lvl}]
  convoy[], gold, flags{}, supports{pair: points}, rewinds_left
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
turn 3        : reinforce enemy "Brigand 15 2 Raider L4 IronAxe" ×3 at east
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

### 4.4 Progression math (v1, GBA-flavoured, all tunable)

- EXP per action: 10 for a hit, +20 for a kill, scaled by
  `clamp(1 + (enemy_level − my_level) × 0.1, 0.3, 2.0)`; 100 EXP = level.
- Level-up: each stat gains +1 with probability `growth%`. Caps per class.
- Promotion: level ≥ 10 + a promotion item → promoted class, +bonuses,
  level resets to 1. (Skip branching promotions in v1.)
- Weapon triangle: +15 hit / +1 dmg with advantage, mirrored at
  disadvantage. Bows ×3 might vs fliers. Durability: `uses` per weapon,
  breaks at 0.
- **Additions** (our twist): each character has one addition; it has a
  level (1–5). Each *completed* chain (no misses) earns addition EXP;
  levels add steps to the rhythm and raise the MAX multiplier
  (1.5 → 1.6 → … → 2.0). Losing a step never loses progress. This makes
  execution a visible, per-character growth track.
- Difficulty: enemy level offset (+0/+3/+6), enemy growth boost, QTE
  window scale (1.25×/1.0×/0.8×), rewinds per chapter (∞/5/2), Casual
  revives dead units after the chapter.

## Part 5 — Milestones

Each milestone ends with something playable and a stated exit test. Order
is chosen so the *content pipeline* is complete (M1–M5) before *content
production* (M8) — writing ten chapters against a moving engine is how
projects die.

### M0 — Foundations (1 week)
- Resolve DECISIONS §1: platform & canonical version. Recommendation:
  **mobile-portrait canonical**, desktop as a secondary export of the same
  build; retire the web version to a test harness or archive it.
- Merge order: `map-editor` → `mobile-swipe-prototype` (mirroring the
  rename in DECISIONS §1b).
- First real Godot run; fix first-run nits; commit `uid://` updates.
- Wire CI: `gdparse`/`gdlint` + `sim_test.gd` on every push.
- **Exit:** one branch, green CI, F5 plays Grimwater in portrait.

### M1 — Campaign skeleton (2 weeks)
- `Character`, `ChapterData`, `Campaign`, `SaveData` resources/JSON.
- `CampaignController` autoload; Title → Chapter → Battle → Results loop
  with two stub chapters reusing Grimwater.
- Roster persists across chapters (HP resets, deaths stick in Classic).
- Save/load to `user://saves/slot_N.json`; autosave after each chapter.
- **Exit:** play chapter 1 → 2 → 1 again from a save; a unit killed in
  chapter 1 is absent in chapter 2 on Classic, present on Casual.

### M2 — Progression (2 weeks)
- EXP, level-ups with growths, level caps, promotion items.
- Class additions: Fighter (axe), Brigand (enemy axe), Thief.
- `campaign_test.gd`: headless AI playthrough of the whole campaign
  (neutral QTE multipliers), reporting per-chapter win rate, average
  level at each chapter, death rate per character. **This is the balance
  instrument for everything after.**
- **Exit:** headless campaign sim runs green; level curves look sane.

### M3 — Objectives & events (2–3 weeks)
- Objective strategies in `Game`: rout / seize / survive / defend /
  boss / escape. AI awareness: bosses hold, guards defend the objective.
- New terrain: village (visitable, destroyable), throne, gate, chest,
  door. Map editor legend + atlas extended; validator learns objective
  rules (seize target must exist, escape zone reachable…).
- Event trigger system (4.3) + `Game` signals; reinforcements, talk/
  recruit, visit, flags.
- **Exit:** one chapter per objective type, each validating and passing
  the headless sim.

### M4 — Dialogue, story, supports (2–3 weeks)
- Dialogue parser + scene UI (portrait, expression, name plate, text box,
  choices, auto/skip/log). Portrait placeholders: coloured silhouettes
  with class glyphs until art arrives.
- Intro/outro scripts per chapter; event-triggered mid-battle dialogue;
  death quotes; boss banter.
- Supports: adjacency points per turn, C/B/A thresholds, conversations
  unlocked from the prep screen, +hit/+avoid when adjacent.
- **Exit:** three chapters fully scripted; a choice in chapter 1 changes
  a line in chapter 3.

### M5 — Items & economy (2 weeks)
- `Item` resources; inventory (5 slots), equip, durability, convoy.
- Weapon triangle + effectiveness in `combat.gd`; forecast shows it.
- Preparations screen: deploy slots, equip, trade, shop (gold from
  chapter rewards/villages).
- **Exit:** a weapon breaks mid-chapter and the unit falls back to the
  next; the sim's balance report includes gold/item flow.

### M6 — Feel (2–3 weeks)
- Rewind: snapshot `Game` state per player action; N per chapter by
  difficulty. (Cheap: the core is plain data.) Decide whether RNG is
  re-rolled on rewind — FE says yes-ish; recommend **no re-roll** so
  rewind fixes plans, not dice.
- Difficulty modes + Classic/Casual + accessibility: auto-resolve
  battles toggle, QTE window scale, **shape-coded QTE cues** so the
  blue/green/red scheme isn't the only signal (colourblind users).
- Addition leveling (4.4). Enemy-phase QTE fatigue rule (DECISIONS §2).
- Audio: map theme, battle theme, victory/defeat stings, hit/parry/
  MAX! SFX via `AudioStreamPlayer`.
- Art pipeline decision: commission sprites/portraits, or commit to a
  polished procedural style. Portraits are the long pole either way.
- **Exit:** a new player finishes chapter 1 on Normal without reading
  docs; a veteran finds Hard/Classic threatening.

### M7 — Vertical slice (2 weeks)
- Chapter 1 to shipping quality: final map, script, music, art (or final
  procedural style), tutorialization woven into events (first parry,
  first addition, first village).
- External playtest with 5–10 people; instrument: chapter time, deaths,
  QTE grade distribution, rewind usage.
- **Exit:** playtesters finish chapter 1 and ask for chapter 2.

### M8 — Content production (6–10 weeks, the long pole)
- Chapters 2–10 through the pipeline: map → events → script → sim →
  playtest → tune. Target cadence: one chapter/week once the pipeline is
  warm.
- Roster to ~14 characters (1–2 recruits per chapter), 2–3 bosses with
  distinct behaviour, one late-game twist map (fog or escape).
- Balance from the campaign sim after every chapter lands.
- **Exit:** full campaign completes headlessly and by hand on Normal.

### M9 — Ship (2–3 weeks)
- Title/options/credits; settings persistence; localization hooks
  (all strings through `tr()`, dialogue files per locale).
- Exports: Android (primary), desktop; iOS when a Mac is available; web
  build as the free demo/playtest channel.
- Store assets, versioning, crash reporting, a "send feedback" path.
- **Exit:** a build a stranger can install and finish.

Rough total: **6–8 months** of focused solo work, or ~4 with a second
person on content/art. The honest variance is all in M8 (content) and
the art decision in M6.

## Part 6 — Content plan & scope tiers

Scope is the only real risk lever, so define it in tiers you can stop at:

| Tier | Chapters | Characters | Objectives used | Playtime |
|---|---|---|---|---|
| Vertical slice (M7) | 1 | 6 | rout | 20 min |
| Demo | 3 | 8 | rout, seize, survive | 1.5 h |
| **v1 (target)** | 10 (prologue + 8 + finale) | 14 | all six | 8–10 h |
| Stretch | 15 + paralogues | 20 | + fog, escape gauntlet | 15 h |

Story shape for v1 (three acts, deliberately simple so chapters can be
written independently): a border garrison (our seven) is cut off when the
river crossing falls; Act 1 is holding and escaping (ch. 1–3), Act 2 is
gathering allies across the realm (ch. 4–7, most recruits here), Act 3 is
taking the crossing back (ch. 8–10). The named enemies from Grimwater
(Gorm, Vask, Hessa…) are the recurring antagonists; at least one becomes
recruitable.

## Part 7 — Testing & balance strategy

This project's unusual asset is that the AI can play the whole game
without a screen. Lean on it:

- `sim_test.gd` (exists): per-map balance.
- `campaign_test.gd` (M2): plays the campaign end-to-end on each
  difficulty, 20 seeds. Reports win rate per chapter, average roster
  level per chapter, per-character death rate, gold curve, turn counts.
  Fails CI if any chapter is < 40% or > 95% winnable on Normal.
- Validator (exists) extended per objective (M3).
- Human playtests at M7 and each M8 chapter; instrument the build
  (local JSON logs are enough) for QTE grade distributions — the timing
  windows can only be tuned against real thumbs.

## Part 8 — Decisions that gate the start

All tracked in DECISIONS-TO-MAKE.md; these are the ones the plan cannot
begin without:

1. **Platform / canonical version** (§1). Recommendation: mobile-portrait.
2. **Permadeath default**: Classic default with Casual offered (FE norm),
   or Casual default? Recommendation: Classic default, ask at new game.
3. **Dialogue tech**: custom-lite format (learning value, fits the text
   ethos) vs Dialogue Manager addon (speed). Recommendation: custom-lite
   with the stated graduation checkpoint.
4. **Art strategy**: commission vs. polished procedural. Portraits are
   the deciding case — procedural faces are hard; silhouettes are fine
   for M1–M5 but not for shipping. Recommendation: budget for portraits
   + a tile set; keep procedural battle backdrops.
5. **Content tier** (Part 6). Recommendation: build the pipeline for v1,
   ship the demo tier first as a public playtest.

## Part 9 — Risks

- **Content is the long pole**, not engineering. Every milestone before
  M8 exists to make M8 cheap. Resist adding systems during M8.
- **QTE fatigue** across a 10-hour campaign is unknown until M7's
  playtest. Mitigations are already designed (auto-resolve, prompt
  limits, addition progression making chains satisfying) — but the
  playtest decides.
- **Art** is the biggest budget/time unknown; decouple it from
  engineering by keeping the placeholder pipeline working to the end.
- **Mobile QTE timing** on real devices (touch latency, refresh rates)
  may need per-device calibration — measure at M7.
- **Solo-dev scope**: v1 is ambitious for one person. The tier table is
  the pressure valve; the demo tier is a complete, shippable game.
