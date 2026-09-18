# Design gaps — review log

**Status:** under review, one gap at a time. Companion to
[GAME_PLAN.md](GAME_PLAN.md) (the milestone plan these gaps feed) and
[DECISIONS-TO-MAKE.md](DECISIONS-TO-MAKE.md) (engineering/tuning decisions
and carry-forward notes).

This file exists because the plan, the prototype, and the decisions doc
each assumed things the others never wrote down. Each gap below is
structured the same way so it can be reviewed and closed in one sitting:

- **What's missing** — the hole, stated against what is actually built.
- **Why it matters now** — which milestone breaks if it stays open.
- **Proposal** — a concrete default to argue with, not a menu.
- **Decisions to make** — the calls the review has to produce.
- **Calls made** — filled in during review. Empty until then.
- **Milestone** — where the implementation lands in GAME_PLAN.md.

Status legend: `OPEN` (not reviewed) · `DECIDED` (calls recorded, ready to
plan an implementation session) · `DONE` (shipped, kept for history).

Review order is the numbering below. Gap 0 comes first because its calls
change the data model everything else carries (Character, Item, MapData
all gain an attunement field).

---

## Gap 0 — Combat rule foundations: the attunement system

**Status:** DECIDED — mechanism confirmed, a few concrete numbers still
OPEN (see Round 3 below) · **Milestone:** M1 (new, dedicated)

> **Three rounds, read in order, each superseding parts of the last.**
> Round 1 settled a symmetric attacker-attunement-vs-defender-attunement
> cycle. Round 2 kept an asymmetric offense/defense split but defaulted
> the defending side onto the **class**, and made the attacking side
> conditional. Round 3 keeps Round 2's offense rule and its two-pronged
> chart (§3a), but rejects the class default entirely: **attunement
> lives only on the individual character, never the class, on either
> side of a fight.** Rounds 1 and 2 are kept below for history; Round 3,
> further down, is what M1 implements.

### Direction (given, not up for review)

Hellian does **not** use Fire Emblem's weapon triangle. Effectiveness
comes from an **attunement chart**: a small elemental table, in the
spirit of Pokémon's type chart but much smaller, and *weakness, hit
chance, and damage all derive from the charted effectiveness*. Because
the chart, not the weapon type, carries the rock-paper-scissors read,
unit **classes** are freed to define the *kit*: the addition pattern
(QTE rhythm), the weapon (flavour, animation, stats), whether the class
attacks at range, and whether it does so with **physical or magical**
attributes. Combat will not be one-for-one with FE.

> Confirmed: "physical or medical attributes" meant physical or
> **magical**. A third attribute, **support** (healers and, later,
> buffers), is confirmed so that every class has exactly one attribute.

### What's missing

- `combat.gd` has no effectiveness axis at all: damage is
  `power − guard`, hit is `hit + skl×2 − avoid`. The only asymmetry is
  `is_magic` choosing Res over Def.
- GAME_PLAN.md (before this revision) assumed the FE triangle in Part 1,
  Part 4.4, the systems inventory, and M5, and called for an axe class
  purely to complete the triangle.
- `UnitClass` mixes kit facts (`weapon`, `attack_range`, `is_magic`,
  `heal_range`, `qte`) with stat blocks; nothing states what a "kit" is,
  so there is no way to audit whether the seven classes cover the kit
  space or just duplicate each other.
- Nothing carries an attunement: not the class, not the map unit lines,
  not the (not yet existing) Character.

### Why it matters now

Every later schema carries the answer: `Character` (M2) needs an
attunement field, enemy map lines (Gap 2) need a token for it, `Item`
(M6) needs to know whether weapons can override it, the forecast UI and
the AI's expected-damage math read it, and the campaign balance sim (M3)
is meaningless if the effectiveness rules change under it. Settle the
rules first, then build the layers that store them.

### Round 1 proposal — element-vs-element cycle (superseded, kept for history)

**1. The chart — settled.** Five elements in a single cycle, no Null:

**Earth → Lightning → Fire → Wind → Water → Earth** (each beats the
next, the loop closes).

Data, not code: a table in `core/` mapping
`(attacker_attunement, defender_attunement) → tier`. Five elements give
ten ordered pairs of *distinct* elements. The cycle covers all ten with
no extra rules needed:

- **Effective**: attacker's element is the one the defender's element
  falls to in the cycle (Earth attacking Lightning, Lightning attacking
  Fire, Fire attacking Wind, Wind attacking Water, Water attacking
  Earth). 5 ordered pairs.
- **Resisted**: the reverse of any Effective pair (Lightning attacking
  Earth, Fire attacking Lightning, Wind attacking Fire, Water attacking
  Wind, Earth attacking Water). 5 ordered pairs.
- **Neutral**: everything else — same element on both sides, and the
  two "non-adjacent" pairs each element has (e.g. Earth vs Fire, Earth
  vs Wind are both Neutral; Earth only has a read against Lightning and
  Water). 10 ordered pairs (5 same-element + 5 non-adjacent).

Every unit must be assigned one of the five — **there is no Null /
unattuned tier**, including generic enemies (decision #9).

**2. Tiers and numbers (v1, locked as a starting point — all tunable in
one table).**

| Tier | Damage | Hit | Crit |
|---|---|---|---|
| Effective | ×1.5 | +15 | +0 (tentative — flag if you want Effective to also raise crit) |
| Neutral | ×1.0 | +0 | +0 |
| Resisted | ×0.67 | −15 | +0 |

Damage multiplier applies **after** the `power − guard` subtraction, the
same place the crit ×3 applies, so the forecast number times the tier is
what the player sees happen. Order in `resolve_strike`:
`(power − guard) × tier × (3 if crit) × offense_QTE × defense_QTE`, rounded
once at the end. An Effective hit that would round to 0 deals a minimum
of 1 (confirmed).

**3. Where attunement lives.** On the **unit**, sourced from the
*person*, not the class (confirmed):

- Player and named characters: a field on `Character` (M2). Until
  `Character` exists, M1 gives each of the seven prototype classes a
  default attunement so Grimwater plays with the system live.
- Enemies: a **required** token on the map unit line
  (`Mercenary 15 2 Raider water`; Gap 2 formalizes the token grammar).
  The validator errors on a missing token — there is no default to fall
  back to.
- Weapons: the `Item` resource (M6) gets an *optional* `attunement` that
  overrides the wielder's on **offense only** — e.g. a Water-attuned
  blade lets an Earth-attuned wielder strike as Water; their defence
  (what they resist/are weak to when hit) stays their own attunement
  regardless of what they're holding. This is the hook that gives the
  item economy texture without a triangle. Tentative default recorded
  in decision #7 below — flag it if the offense-only framing isn't what
  you meant.

**4. Class = kit.** Formalize `UnitClass` as:

```
kit:
  attribute     physical | magical | support   # which stat pair, or heals
  attack_range  [1] | [2] | [1,2] | []          # [] for pure support
  weapon        flavour + animation + base might/hit/crit (stats move to Item in M6)
  addition      the QTE pattern (rhythm, tolerances, colour follows attribute)
  movement      foot | mounted | flier (+ armoured flag for weight/anim)
stats: bases as today; growths move to Character in M2
```

`is_magic`, `heal_range`, `heal_power` collapse into `attribute` +
`attack_range` + a support power stat. Audit of today's seven classes as
kits:

| Class | Attribute | Range | Movement | Kit note |
|---|---|---|---|---|
| Knight | physical | 1 | foot, armoured | tank |
| Mercenary | physical | 1 | foot | baseline |
| Cavalier | physical | 1 | mounted | reach |
| Archer | physical | 2 | foot | uncounterable at 2 |
| Mage | magical | 1–2 | foot | only magical kit |
| Healer | support | — (heal 1) | foot | only support kit |
| Pegasus Knight | physical | 1 | flier | mobility |

Holes the audit exposes (for M3's new classes): no **melee magical**
kit, no **1–2 physical** kit (javelin/hand-axe role), no **ranged
support**, no second magical or support kit for enemies to field.
New classes are chosen to fill kit holes, not triangle slots.

**5. Class-based effectiveness (bow vs flier, armour-slayers).** Recommend
**none in v1**: the chart is the *only* effectiveness axis, so the
forecast has one thing to explain. Archer identity stays "range 2, cannot
be countered there". Revisit at M6 if fliers prove unpunishable.

**6. Forecast and readability.** The forecast shows the tier as a word
plus a shape (▲ Effective / ● Neutral / ▼ Resisted) so colour is never
the only cue, and shows hit and damage *after* the tier. Attunement is
visible on the map (unit glyph corner) and in the unit panel.

**7. AI and sim.** The AI already plans from `strike_stats`, so it prefers
effective matchups the moment `strike_stats` includes the tier: no AI
work. The headless sim gains a **matchup matrix** (kit × kit at each of
the five attunements, each tier) and a regression check: any
same-element matchup (Neutral tier, e.g. Earth vs Earth) must reproduce
today's pre-attunement numbers exactly.

**8. Deliverable doc.** `docs/COMBAT_RULES.md`: the single source of truth
for the formula, the chart, the tier table, the QTE multipliers, and the
resolution order. Written in M1, kept current after.

### Round 1 decisions (superseded, kept for history)

_(all recorded below — kept for history.)_

1. Confirm "medical" → magical, and accept **support** as the third
   attribute.
2. Chart shape: 3-cycle, 4-cycle + Null, or a bigger chart.
3. Element names and whether Null exists.
4. Tier numbers: ×1.5 / ×0.67 and ±15 hit as the starting point? Does
   Effective also add crit?
5. Minimum 1 damage on an Effective hit: yes/no.
6. Attunement lives on the person (Character / map line), never the
   class: confirm.
7. Weapon attunement override on offense: include the field now,
   implement at M6: confirm.
8. Class-based effectiveness (bow vs flier): dropped in v1: confirm.
9. Generic enemies default to Null, or must every enemy be attuned?
10. Does the web prototype mirror any of this?

### Round 1 calls (superseded except where Round 2 says otherwise, kept for history)

1. **Confirmed.** Magical + support are the three attributes.
2. **5-cycle**, no Null (rejects the recommended 4-cycle + Null shape).
3. **Earth → Lightning → Fire → Wind → Water → Earth** (each beats the
   next). Names are final, not placeholders, unless revisited later.
4. **Locked as the starting point:** ×1.5 Effective / ×1.0 Neutral /
   ×0.67 Resisted, ±15 hit. Crit bonus on Effective: **not explicitly
   answered** — recorded as +0 (no crit change) pending confirmation;
   flag if Effective should also raise crit.
5. **Yes** — an Effective hit rounds up to a minimum of 1 damage.
6. **Confirmed, refined by Round 2** — a caster's own inherent element
   still lives on the person, never the class. Round 2 adds a second,
   separate thing that *does* live on the class: the defending **type
   tag**. The two aren't the same field.
7. **Resolved by Round 2** — the weapon override turned out to be the
   central mechanism, not a nice-to-have: it's now the *only* way a
   physical or support unit ever attacks with an element. See Round 2
   below.
8. **Confirmed at the time — reversed by Round 2**, which makes the
   defender's class-derived type tag the entire basis of the elemental
   chart. Kept for history only; Round 2 is what M1 implements.
9. **Reversed by Round 2** — attunement (offense) is now conditional,
   not mandatory; a generic enemy with a mundane weapon simply attacks
   with no element. Every enemy still has a type tag, but that comes
   free from its class, not from being individually attuned.
10. **Deferred** — decide whether the web prototype mirrors this after
    all design gaps have been reviewed, not now.

### Round 2 — elemental attunement vs unit type (partially superseded by Round 3 — see the strikethroughs below; the offense rule, the tier numbers, and the QTE window scaling all still stand)

The Round 1 cycle made every attack elemental, attacker element vs
defender element, symmetrically. On reflection that only actually reads
as an *elemental* choice for casters — a Knight swinging a sword being
"Earth-attuned" was the weapon triangle wearing new names, exactly the
thing Gap 0 exists to avoid. Round 2 changes what the chart's defending
side is, and who gets to touch the attacking side at all.

**1. Two different questions, not one.** *Does this attack carry an
element?* (offense, conditional) and *what is this unit vulnerable to?*
(defense — ~~universal, free from class~~ **per-character, see Round
3**) are separate questions, still.

**2. Whether an attack carries an element (offense) — stands as-is:**
- A **magical**-attribute unit has an inherent element — their own
  attunement, a `Character` field (M2) / ~~per-class default~~ **a
  per-unit field (M1 interim, Round 3)**. This is the "only casters are
  inherently elemental" framing from your answer.
- **Any** unit — physical, magical, or support — carries an element
  instead if they're wielding an **attuned weapon**. The weapon's
  element **overrides** the wielder's own inherent element for that
  attack (tentative default; flag if it should need to match or stack
  instead). This is what lets a Mercenary's fire-forged blade strike as
  Fire despite the Mercenary having no elemental nature of their own.
- Otherwise (physical/support unit, mundane weapon) the attack carries
  **no element**. The chart contributes nothing: damage, hit, and QTE
  windows are exactly what they'd be with no attunement system at all.
  This is the same "Neutral vs no-type" regression floor as Round 1's,
  just reached a different way.
- Priority when both could apply (a magical unit wielding an attuned
  weapon): **the weapon wins.** A Water-attuned tome lets a
  Lightning-attuned mage strike as Water for that fight.

**3. What a unit is vulnerable to (defense) — SUPERSEDED by Round 3
below.** ~~Every class carries a **type tag**, assigned once on the
class, inherited for free by every unit of that class — no
per-character or per-map-line authoring needed.~~ Round 3 rejects
per-class defaults outright: vulnerability, like the offense-side
element, is bound to the character, never the class. Kept below for
history; skip to Round 3 for what M1 implements. Vocabulary (still
current): the five element names, reused for this axis too
(Earth/Lightning/Fire/Wind/Water) — confirmed, not a separate monster
vocabulary.

**3a. The matchup table — confirmed, two-pronged, no neutral among the
five.** Each element is Effective against **two** of the other four (and
therefore Resisted by the other two) — not the single-adjacency read
Round 2 first proposed. This is a complete regular tournament: every
element beats exactly two, loses to exactly two, and there are no
neutral pairs left among the five real elements (Neutral now only
happens against the "none" tag, or when the attack has no element at
all).

| Attacker ↓ / Defender → | Earth | Lightning | Fire | Wind | Water |
|---|---|---|---|---|---|
| **Earth** | — | Effective | Resisted | Effective | Resisted |
| **Lightning** | Resisted | — | Resisted | Effective | Effective |
| **Fire** | Effective | Effective | — | Resisted | Resisted |
| **Wind** | Resisted | Resisted | Effective | — | Effective |
| **Water** | Effective | Resisted | Effective | Resisted | — |

In words: Earth is effective against Wind and Lightning; Water is
effective against Fire and Earth; Lightning is effective against Water
and Wind; Wind is effective against Fire and Water; Fire is effective
against Earth and Lightning. The diagonal (an element attacking its own
type) is **Neutral** — not part of the ten stated relations, filled in
as the obvious default.

Every cell reads as "this row's element, attacking this column's type."
The reverse relationship is never assumed — it's whatever the table says
for that pair, and every pair in this table happens to have a single
consistent direction (it's a complete tournament: each element wins
exactly two matchups and loses exactly two, with none left over).
Read as a defensive profile instead (which attackers hurt a given type
most), each type is vulnerable to exactly two elements and resists
exactly two:

- **Earth-type** defenders: vulnerable to Fire and Water; resist
  Lightning and Wind.
- **Lightning-type** defenders: vulnerable to Earth and Fire; resist
  Wind and Water.
- **Fire-type** defenders: vulnerable to Water and Wind; resist Earth
  and Lightning.
- **Wind-type** defenders: vulnerable to Earth and Lightning; resist
  Fire and Water.
- **Water-type** defenders: vulnerable to Lightning and Wind; resist
  Earth and Fire.

~~Proposed tag assignment for the seven existing classes:~~ **dropped
along with per-class typing.** No class carries a default. (This also
makes the Archer/Pegasus Knight Wind collision that this table would
have created moot — see Round 3.)

**4. Tiers and numbers — unchanged from Round 1, just reapplied.**
Effective ×1.5 dmg / +15 hit, Neutral ×1.0 / +0, Resisted ×0.67 / −15
hit, minimum 1 damage on an Effective hit. These numbers already stood
on their own merits; only the axis they're read against has changed.

**5. New: tier scales the QTE, not just damage and hit.** Both sides'
timing windows widen or narrow with the tier of the strike as that side
experiences it:

| Tier | Window scale | Effect |
|---|---|---|
| Effective | ×1.15 (proposed) | more forgiving — easier to chain a perfect addition, easier to land a perfect parry |
| Neutral / no element | ×1.0 | today's windows, unchanged |
| Resisted | ×0.85 (proposed) | tighter — a mismatched element punishes execution, not just damage |

This multiplies whatever the Tactics/Timing difficulty scale already
applies (Gap 1: 1.25×/1.0×/0.8×/Auto), so the two systems compose rather
than compete. Applies to the attacker's addition rhythm *and* the
defender's hold-and-release parry — an Effective strike is both harder
to fully mitigate (bigger number) and easier to attempt mitigating well
(looser window), which reads as "a big hit you at least got a fair shot
at," matching pillar 3 (full information, fair consequences).

**6. Ripple effects — see Round 3** for the corrected version; the
points below assumed the now-superseded per-class typing.
- ~~Gap 2 (map schema): the required-attunement-token rule is dropped.
  Type comes free from class; enemy lines need nothing new for v1.~~
- ~~`Character` (M2): `attunement` is only meaningful for
  magical-attribute characters.~~
- ~~Sim/regression (M1): the matchup matrix becomes **element × type**
  instead of element × element.~~
- Forecast: still shows the tier word/shape and the QTE window hint —
  unaffected by Round 3, just reads a per-character value now instead
  of a class-derived one.

### Decisions to make (Round 2, open)

1. ~~The seven-class tag table above: confirm or adjust~~ — moot, see
   Round 3.
2. Weapon overrides the wielder's own inherent element when both are
   present (proposed) vs. requiring a match, vs. stacking somehow.
3. QTE window scale numbers: ×1.15 / ×1.0 / ×0.85 as a starting point.
4. Can a monster/beast ever be innately elemental without being
   magical-attribute (a fire drake's claws just *are* fire)? Flagged as
   a future nuance — not needed for the current seven-class roster, can
   wait until M3's new-class pass or M9 content.

### Calls made (Round 2)

1. **Conditional, not universal.** Inherent attunement only for
   magical-attribute units; a physical or support unit only carries an
   element if their weapon is attuned; otherwise no element at all.
2. **New type tags per class — reversed by Round 3.** Vocabulary (the
   five element names for this axis too) stands; *where the tag lives*
   does not.
3. **QTE timing windows scale with tier**, on both the offense addition
   and the defense parry.
4. **Two-pronged matchup table, no neutral among the five real
   elements** — each element is Effective against two others and
   Resisted by the other two (§3a's table). This replaces Round 2's
   first-draft single-adjacency reuse of the cycle order. Unaffected by
   Round 3 — this is the table, just looked up against a differently
   sourced value now.

### Round 3 — attunement is character-bound, full stop (current)

> "The unit types themselves shouldn't have default attunement at all.
> The attunement is character bound, not class."

Round 2 split the system into two questions — *does this attack carry an
element* (offense) and *what is this unit vulnerable to* (defense) — and
answered the second one by defaulting it onto the class. That default is
withdrawn. There is no class-level elemental default of any kind,
offense or defense. **Attunement lives on the individual — the
`Character`, or for M1's prototype roster before `Character` exists, the
unit itself — and nowhere else.**

**1. One field, two uses, always optional.** A character's `attunement`
(one of the five elements, or unset) is the single source for both
sides of a fight:
- **Offense**, unchanged from Round 2's conditional rule: it applies
  automatically if the character is magical-attribute; a weapon's own
  attunement overrides it (or supplies one, for a physical/support
  character with no attunement of their own) when equipped; otherwise
  the strike carries no element.
- **Defense**: the chart looks up `(attacker's element, this
  character's own attunement)`. No attunement set = the "none" case,
  Neutral no matter what hits them — same floor as an unelemented
  attack, just from the other side.

**2. Classes carry no attunement, no default, nothing.** `UnitClass`
loses the `type_tag` field Round 2 proposed. A Knight isn't Earth-typed
by being a Knight; *a specific Knight* might be, if that's who they are.
This also means the Archer/Pegasus Knight Wind collision Round 2 flagged
can't happen — collisions would now require two *characters* to
deliberately share an element, which is a writing choice, not a data
accident.

**3. Most units have none, and that's the point.** Elemental play
becomes a **texture, not a universal axis**. A generic soldier has no
attunement — fighting them is exactly today's math, no chart involved at
all. Attunement is something a character *has*: the lord, the recurring
antagonist, mages (usually), a themed elite enemy, an heirloom weapon's
wielder. This reads better against pillar 1 (every unit is a person) —
being elementally attuned becomes a fact about *who somebody is*, not a
side effect of their job.

**4. Ripple effects, corrected.**
- `Character` (M2): `attunement` is a plain optional field, no attribute
  gating on whether it's "meaningful" — any character, physical,
  magical, or support, may have one or not.
- M1 interim (before `Character` exists): the prototype roster lines
  (`[class, x, y, name]`) need an optional fifth slot for a specific
  unit's attunement, defaulting to none when absent. Only a handful of
  Grimwater's named units (say, the Mage and one or two named enemies)
  would carry one for M1's exit test — most of the roster stays
  unattuned, which is realistic to how the finished game will look too.
- Gap 2 (map schema): the attunement token **returns, but now genuinely
  optional** (not Round 1's mandatory-on-every-line rule). Present only
  on the units it's narratively true for; the validator accepts absence
  as "no attunement," not an error.
- Sim/regression (M1): the matchup matrix is **element × (a defending
  character's attunement, or none)**. The regression floor — no element
  on either side reproduces today's pre-attunement numbers exactly — is
  even easier to hold now, since it's the *common* case, not an edge
  case.
- Forecast: shows a character's attunement only when they have one; a
  fight between two unattuned units shows no elemental line at all,
  which itself communicates something (this one's just a fight).

### Decisions to make (Round 3, open)

1. M1 interim: which of Grimwater's named units get an attunement, and
   which element — a content call for the person, not a mechanism call
   (propose: the Mage gets one, since testing a caster's inherent-element
   path is the point; one named enemy gets one to test the Resisted
   side).
2. Should a magical-attribute character *without* an attunement set
   still be a valid build (an "unattuned" caster whose spells carry no
   elemental bonus or penalty), or should every magical character be
   required to pick one? Proposed: valid and unremarkable — "no
   attunement" is a legitimate character, not a placeholder state.
3. Items not yet touched by Round 2/3: weapon-match-or-override question
   (Round 2 #2 above) and the QTE window-scale numbers (Round 2 #3)
   still stand as open.

### Calls made (Round 3)

1. **Confirmed — no class-level attunement or type, offense or
   defense, in any form.** Reverses Round 2's item 2 (new type tags per
   class) and its class-tag table.
2. **Attunement is a single per-character field**, used conditionally
   on offense (Round 2's rule, unchanged) and directly on defense
   (looked up against the attacker's element, or Neutral if unset).
3. **Most units carry no attunement.** It's an individual trait, not a
   mechanic every unit is expected to participate in.

---

## Gap 1 — The QTE layer vs the Fire Emblem loop

**Status:** OPEN · **Milestone:** M1 (rules), M7 (tuning and feel)

### What's missing

The plan calls the Legend of Dragoon layer the differentiator and also
adopts FE's pillar of *full information, fair consequences*. The two are
unreconciled:

- A forecast that says "12" is false when the strike can land anywhere
  from 9 (0.75× worst offense) to 18 (MAX!).
- Every enemy attack demands a parry. Seven-a-side is fine; a ten-hour
  campaign with 20-unit enemy phases is a thumb-endurance test
  (DECISIONS §2 already flags fatigue).
- Difficulty conflates tactics and reflexes: a strong tactician with
  slow thumbs, or the reverse, has no setting that fits.
- Healers have no addition at all, so the support kit has no execution
  layer.

### Why it matters now

The QTE multipliers are part of the combat formula (Gap 0's resolution
order), so the *rules* must be fixed in M1 even if the *tuning* waits
for real hands at M8. The forecast UI and the difficulty data model both
depend on the answers.

### Proposal

1. **Offense is pure upside.** Floor becomes 1.0× (today 0.75×). The
   forecast number is a guarantee; the addition adds up to +50% on top.
   Tactics decide the floor, hands decide the ceiling.
2. **Inaction is never punished.** Not touching the screen during an
   enemy strike resolves as Guarded (0.9×). The forecast shows *that*
   number. Only a wrong action (early release, wrong deflect spot) drops
   to Exposed (1.0×); a good release parries to 0.75×/0.5×.
3. **Meaningful-moment prompts.** Enemy-phase QTEs trigger only when the
   strike could kill the defender, the attacker is a boss, or the target
   is the lord (Gap 4). Everything else auto-resolves at Guarded. An
   "Always prompt" option exists for players who want the full layer.
4. **Forecast shows the band.** `9–13  KILL at Good+` on offense;
   `takes 6 (parry → 3)` on defence. Kill thresholds by grade are the
   single most useful number a timing game can show.
5. **Two difficulty axes.** *Tactics* (enemy levels/growths, rewinds,
   Classic/Casual) × *Timing* (QTE window scale 1.25/1.0/0.8, or **Auto**
   which resolves every battle at neutral). Chosen independently at new
   game, changeable in options.
6. **Heal addition.** Healers get a green support QTE: staff heal amount
   scales with grade (floor = forecast). Same rules as offense.
7. **Cues are input, not polish.** The windup sound and the haptic tick
   *are* the timing signal on a phone. They ship with the vertical slice
   (M8), not the audio pass.
8. **Enemies never roll a QTE.** AI strikes resolve at neutral; the layer
   is the player's edge, and the sim stays a tactics-only instrument.

### Decisions to make

1. Offense floor 1.0× (recommended) or keep 0.75× with a shown band.
2. Inaction = Guarded: confirm. Does Exposed stay at 1.0× or go above?
3. Prompt policy: meaningful-moments default with "Always" opt-in, or
   always-on with a cap.
4. Two independent difficulty axes: confirm, and confirm an Auto timing
   setting exists.
5. Heal QTE: yes/no in v1.
6. Do enemies ever get a virtual grade (e.g. bosses "crit" via MAX!)?
   Recommend no.

### Calls made

_(pending review)_

---

## Gap 2 — Map schema v2

**Status:** OPEN · **Milestone:** M1 (attunement token), M2 (deploy slots), M4 (AI flags, waves)

### What's missing

`MapData` v1 is a *skirmish* format: a fixed roster of
`<Class> <x> <y> <Name>` lines per side. The campaign needs:

- **Deploy slots** on the player side, filled from the persistent roster
  at preparations, with optional forced deploys (the lord, a recruit).
- **Enemy attributes**: level, attunement (Gap 0 Round 3 — optional,
  per-character, no default of any kind; present only on named/notable
  units), equipped item (M6), AI profile (Gap 8), boss flag, drop item.
- **Reinforcement waves** and **NPC/green units** (recruitables,
  villagers) with their own lines and triggers.
- **Terrain with parameters**: village contents, throne/seize target,
  escape zone, chest contents, locked doors.
- A **schema version** so old `.tres`/JSON maps load or fail loudly.

### Why it matters now

The map editor is built and working on v1. Every chapter authored before
v2 lands is rework; every field added piecemeal is a validator and
editor change. Decide the grammar once.

### Proposal

Keep lines human-readable; extend with tokens after the name, order-free,
`key` or `key=value`. Every token, including attunement (one of the five
elements, Gap 0 Round 3), is **optional** — most enemy/npc lines carry
no attunement token at all, which is the normal case, not a gap:

```
# player side: deploy slots (roster fills them), or a fixed named unit
slot 1 4
slot 2 5 forced=lord
Knight 1 6 Doran                       # fixed unit, chapter-1 style

# enemy side: name, then whatever optional attributes apply
Mercenary 15 2 Raider L4 ai=hold       # no attunement — the common case
Knight 14 3 Gorm L8 earth boss ai=guard:14,3:1 drop=Vulnerary
Archer 12 7 Bowman L3                  # default AI, no attunement

# npc side (new list)
Healer 6 9 Averil lightning recruit=talk:Silke
```

Waves and terrain features stay in `ChapterData` events (GAME_PLAN 4.3),
so `MapData` remains "terrain + who starts where". `MapData` gains
`schema_version := 2`, `npc_units`, and `features` (a line list:
`village 2 9 item=Vulnerary`, `throne 14 3`, `escape 0 11 w=2 h=1`).

Editor: the Units layer paints positions (slot, player, enemy, npc rows in
the atlas); attributes are edited in the text lines, which the workbench
preserves by position on save (it already does this for names).
Validator learns each token, and every rule from Gap 0/4/8 that touches a
line (unknown attunement, `forced=lord` without a lord, `ai=guard` off
the map).

### Decisions to make

1. Tokens in the text line (recommended) vs per-unit sub-Resources.
2. Player deploy: slots + roster (FE norm) from M2, with fixed lines only
   for chapter 1 and scripted joins: confirm.
3. Which tokens are v2 scope: `L`, attunement, `ai=`, `boss`, `drop=`,
   `forced=`, `recruit=`. Items (`item=`) wait for M6.
4. Features in `MapData` or in `ChapterData` events.
5. JSON export mirrors v2 (yes, it is the portability path).

### Calls made

_(pending review)_

---

## Gap 3 — Objectives vs turn limit vs attrition

**Status:** OPEN · **Milestone:** M4

### What's missing

Today a battle ends by rout or by hitting `turn_limit`, at which point
`decide_by_attrition` picks a winner by remaining strength. That is a
**simulation stalemate valve** that leaked into the game rules: FE has
no turn limit except on survive/defend maps, and losing is *the lord
dies*, never "the clock ran out". `MapData.turn_limit` and `objective`
exist but only rout is implemented.

### Why it matters now

Objectives are M4's core; the AI (Gap 8) and the validator both need to
know what "win" means per map; the sim's win rate is meaningless if the
attrition rule can decide it.

### Proposal

- `turn_limit` becomes a **QA-only knob**: used by the validator and the
  sim to detect stalemates, invisible in play. In-game, a map with no
  time-based objective runs until won or lost.
- **Win** is the chapter objective: `rout`, `seize (x,y)` by the lord,
  `survive N`, `defend (x,y) N`, `boss <name>`, `escape zone`.
- **Loss** is: the lord dies (both modes), all deployed units dead, the
  defend point taken, or the escape map's last turn passing with units
  left (per map). No attrition in play.
- Optional **par turns** per chapter for a results-screen rank and bonus
  EXP; exceeding par costs nothing. Keeps the "efficiency" FE players
  enjoy without punishing careful play.
- The sim keeps attrition for *reporting* (a chapter that hits the QA
  limit is flagged as a stalemate, which is a design bug).

### Decisions to make

1. Attrition removed from play: confirm.
2. Par turns: yes (rank + bonus) / no.
3. Loss conditions list: confirm, especially "all deployed dead" when the
   lord is not deployed (recommend: the lord is always deployed, Gap 4).
4. Seize by the lord only (FE), or by any unit?

### Calls made

_(pending review)_

---

## Gap 4 — Protagonist: lord, avatar, or neither

**Status:** OPEN · **Milestone:** M2 (`is_lord` flag), M5 (story)

### What's missing

The story shape (a border garrison of seven, cut off when the crossing
falls) names no protagonist. FE ties defeat, seizing, and the player's
emotional anchor to the lord; modern FE adds a customizable avatar. The
plan's `Character` resource has no notion of either.

### Why it matters now

Loss conditions (Gap 3), meaningful-moment prompts (Gap 1), forced
deploys (Gap 2), and the intro script (M5) all reference the lord. The
avatar decision changes portrait and text budgets.

### Proposal

- **One fixed lord, no avatar in v1.** An avatar costs portrait
  variants, name-templated dialogue, and pronoun handling for every
  line; none of it serves the four pillars.
- The lord is one of the current seven, with a **unique kit variant**:
  a Mercenary-kit body with a unique addition and a signature weapon
  (M6). Recommendation: promote **Doran** or **Silke** (both already
  speak in the dialogue example) and decide from the intro script's
  voice.
- Lord death = game over in Classic *and* Casual (FE norm). Lord is a
  forced deploy on every chapter.
- The lord's attunement is a story choice (Gap 0), and the recurring
  antagonist is personally attuned to one of the two elements that
  resist it (Gap 0 §3a) — a character trait chosen for them, not
  inherited from their class — so the final fight opens as a Resisted
  matchup.

### Decisions to make

1. Fixed lord, no avatar in v1: confirm.
2. Who: Doran / Silke / a new character.
3. Lord kit: unique addition + Mercenary body, or a new class.
4. Lord death rule in Casual: game over (recommended) or retreat.

### Calls made

_(pending review)_

---

## Gap 5 — Additions: per class or per character

**Status:** OPEN · **Milestone:** M1 (data shape), M3 (leveling data), M7 (leveling feel)

### What's missing

The QTE pattern lives on `UnitClass`. GAME_PLAN 4.4 says "each character
has one addition" with a level 1–5. Promotion changes class. Three
statements, no reconciliation: does a promoted unit lose its addition?
Do two Mercenaries share one? Gap 0's direction says classes dictate
addition patterns.

### Proposal

- **Class dictates the pattern** (per direction). The kit's addition is
  the default every unit of that class performs; generic enemies use it
  unchanged.
- **Character carries the progress and may carry an override.**
  Addition *level* (1–5) is per Character; named characters (lord,
  bosses) may specify a unique pattern in their `Character` resource.
- **Promotion keeps the addition** and unlocks one extra step at the end
  of the chain (the promoted "finisher"), so mastery is never reset by
  growth.
- One addition per character in v1. Multiple selectable additions (LoD
  proper) are a stretch item after M9.

### Decisions to make

1. Class default + per-Character override: confirm.
2. Promotion adds a step rather than swapping the addition: confirm.
3. One addition per character in v1: confirm.

### Calls made

_(pending review)_

---

## Gap 6 — The action menu and its verbs

**Status:** OPEN · **Milestone:** M2 (shell: attack/heal/wait, undo move), M4 (talk/visit/seize), M6 (item/trade)

### What's missing

The prototype has no action menu: move, then tap a target to attack or
heal, or tap the unit to wait. A campaign needs **Attack, Staff, Item,
Trade, Talk, Visit, Seize, Wait**, plus **cancel move** before
committing. FE also has Rescue/Shove/Pair-up variants. Nothing in the
core exposes "what can this unit do here".

### Proposal

- Core: `Game.available_actions(unit) -> Array[{verb, targets}]`, pure
  data, computed after a move. The UI renders it as a thumb-zone list
  (portrait layout, DECISIONS §4). Wait is always present.
- **Undo move** before any action is free and exact (no RNG has been
  consumed).
- v1 verbs: Attack, Staff, Item (use consumable), Trade (adjacent ally),
  Talk, Visit, Seize, Wait. **No Rescue, Shove, or Pair-up in v1.**
- After Attack/Staff the unit auto-waits (FE norm); after Item/Trade/
  Talk/Visit the unit may still act only if the design says so
  (recommend: Trade does not end the turn; everything else does).

### Decisions to make

1. Verb list for v1: confirm; Rescue out.
2. Trade does not end the turn: confirm.
3. Menu placement/interaction in portrait: list vs radial (defer to M2
   mock-up).

### Calls made

_(pending review)_

---

## Gap 7 — Suspend/resume, rewind, and the RNG

**Status:** OPEN · **Milestone:** M2 (battle serialization + suspend), M7 (rewind)

### What's missing

Mobile play is interrupted constantly; a 20-minute battle must survive a
phone call. Rewind (Divine Pulse) needs state snapshots. Both need the
battle to be **fully serializable including the RNG state**. Today
`Game` holds live `Unit` objects and an injected
`RandomNumberGenerator`; nothing writes them out.

### Proposal

- `Game.to_dict()` / `Game.from_dict()`: units, positions, HP, turn,
  phase, acted flags, event/flag state, log, and `rng.state`. The core is
  plain data, so this is cheap and testable headlessly (round-trip test
  in `sim_test.gd`).
- **Suspend** = write `to_dict()` to `user://suspend.json` on
  `NOTIFICATION_APPLICATION_PAUSED` and after every completed action;
  resume offers it at title. Granularity: between actions only (a
  vignette mid-QTE is not saved; it restarts).
- **Rewind** = a stack of `to_dict()` snapshots, one per player action;
  N per chapter by difficulty (∞/5/2).
- **RNG on rewind: no re-roll.** The restored state replays the same
  dice for the same action, so rewind fixes *plans*, not luck. The QTE
  is replayed live, so hands can still improve the outcome.

### Decisions to make

1. No re-roll on rewind: confirm (FE: Three Houses re-rolls; the
   recommendation is deliberately stricter).
2. Suspend granularity between actions: confirm.
3. Rewind counts per difficulty.

### Calls made

_(pending review)_

---

## Gap 8 — AI on asymmetric, multi-wave, objective maps

**Status:** OPEN · **Milestone:** M4

### What's missing

The AI is tuned for a symmetric 7v7 rout: caution fades by turn 7,
cohesion until turn 8, and every unit advances eventually. That breaks
on campaign maps: bosses should hold thrones, guards should defend a
point, reinforcements spawning on turn 9 should not start "fearless",
escape maps need pursuers, and healers should not wander into range.

### Proposal

- **Per-unit AI profile** from the map line (Gap 2 `ai=` token):
  - `aggressive` (today's behaviour, the default)
  - `hold` (never moves; attacks anything in range)
  - `guard:x,y:r` (stays within `r` of a point; returns after attacking)
  - `chase` (advances from turn 1, ignores caution)
  - `support` (healers/buffers: stay behind the nearest ally line)
- Caution timers count from **the unit's spawn turn**, not the chapter
  turn, so waves behave like turn-1 units.
- Objective awareness: `defend` maps make enemies `chase`; `escape`
  maps spawn `chase` waves behind the player; `seize` maps give the
  throne guard `hold`.
- The sim runs objective-aware wins (seize by turn N) and reports per
  profile whether units ever engage.

### Decisions to make

1. Profile vocabulary: confirm the five.
2. Does the AI prioritize the lord (FE AI does target kills, not lords)?
   Recommend: no special lord weighting; the kill bonus already does it.
3. Difficulty affects AI profile (e.g. Hard turns `hold` bosses into
   `guard`)? Recommend: no, difficulty is stats and counts only.

### Calls made

_(pending review)_

---

## Gap 9 — Weapon ranks

**Status:** OPEN (proposed resolution: drop) · **Milestone:** M6

### What's missing

FE gates weapons by E–S ranks that grow through use. The plan never
mentions them. With Gap 0 removing the weapon triangle, the main reason
ranks exist (making weapon *type* a progression choice) is gone.

### Proposal

**Drop weapon ranks.** A class kit has one weapon type; items of that type
are usable by anyone with the kit. Rare items may carry a **unit level**
requirement, nothing else. The mastery axis that ranks provided is
already covered by **addition levels** (Gap 5), and the texture ranks
provided by **weapon attunement overrides** (Gap 0, M6).

### Decisions to make

1. Drop ranks entirely: confirm.
2. Item gating: none, or unit level for legendaries only.

### Calls made

_(pending review)_
