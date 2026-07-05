# Going mobile with swipes — process, options, and a prototype

**Status: PROTOTYPE FOR REVIEW.** Everything described here lives on the
`claude/mobile-swipe-prototype` branch only. The main branch is untouched.
Read this, try the prototype, pick the options you want, and we fold the
chosen shape back in.

## Short answer

Yes — this is squarely in Godot's wheelhouse. One codebase exports to
Android, iOS, desktop, and web from the editor's Export dialog, and the
choices already made in the port happen to be the mobile-friendly ones
(the `gl_compatibility` renderer targets exactly the mobile GPU baseline;
the game is turn-based, so performance is a non-issue).

## What Godot gives you for touch

Three mechanisms matter, and knowing they exist changes how much work
this is:

1. **Touch events.** Fingers arrive as `InputEventScreenTouch`
   (press/release, with a finger `index` for multitouch) and
   `InputEventScreenDrag` (movement while held). These flow through the
   same input pipeline from Step 5 of the port doc — `_gui_input`,
   `_unhandled_input` — no separate "mobile input system."
2. **Two-way emulation.** `emulate_mouse_from_touch` (on by default)
   makes taps behave as mouse clicks — meaning **our existing board code
   already works on a phone**: tap a unit, tap a tile, tap an enemy.
   `emulate_touch_from_mouse` (a one-line project setting) does the
   reverse, so swipe gestures are testable on a desktop with a mouse
   drag. You develop the mobile game without owning a phone.
3. **Resolution independence.** `stretch/mode = canvas_items` +
   `stretch/aspect = keep` scales our fixed 1104×624 layout to any
   screen, adding letterbox bars rather than breaking the layout.

There is no built-in "swipe" event — a swipe is a pattern you read from
touch+drag (press, move ≥ some distance, judge the direction). That's
~30 lines, implemented in the prototype.

## What's already touch-native (no work needed)

- **Board play**: tap to select / move / attack — mouse emulation covers it.
- **The parry**: hold-and-release is *more* natural on a touchscreen than
  on a keyboard — press finger to guard, lift to parry. The defense QTE
  needed nothing but wiring touch press/release to the existing
  `_hold_start()` / `_hold_end()`.
- **Buttons, panels, log**: Godot Control nodes respond to touch as-is.

The only genuinely open design question is **what swipes should mean**.

## The options

| | Option A — swipe additions | Option B — A + map gestures | Option C — full gesture UI |
|---|---|---|---|
| Offense QTE | timed **directional swipes** (each class gets a swipe pattern) | same as A | same as A |
| Defense QTE | hold finger / release | same as A | same as A |
| Map: select & move | tap (existing) | tap, or **drag a path** from unit to tile | drag-a-path only |
| Map: camera | none (map fits screen) | **swipe to pan, pinch to zoom** (needed for bigger maps) | same as B |
| Menus | tap | tap | swipe between panels |
| Effort | small — vignette only | medium — adds Camera2D + gesture arbitration | large; arbitration gets hairy |
| Risk | low | drag-vs-tap ambiguity needs care | gesture conflicts multiply |

**Recommendation: Option A now** (it's what the prototype implements),
and treat B's camera work as its own step later if maps outgrow the
screen — it's the natural companion to the "bigger maps + Camera2D" item
already on the roadmap. C sacrifices discoverability for no real gain in
a turn-based game.

## What the prototype on this branch implements (Option A)

- **Directional swipe additions.** Each class's QTE steps now carry a
  swipe direction, themed to the attack (`game_data.gd`):
  - Knight: **↓** — one heavy overhead chop
  - Mercenary: **→ ← →** — a slashing combo
  - Cavalier: **→ →** — charging thrusts
  - Archer: **↑** — draw and loose
  - Mage: **↑ ↓** — gather, then unleash
  - Pegasus: **↑ → ↓** — a diving arc
  An arrow inside the timing ring shows the required direction. The
  timing rules are unchanged (ring shrinks onto the target; the moment
  your swipe crosses the minimum distance is what's graded) — but a swipe
  in the **wrong direction is a Miss**, so the class rhythm is now felt
  in the wrist, not just the clock.
- **Parry via touch**: finger down = guard up, finger up = release.
  Identical grading to the keyboard version.
- **Desktop testing**: `emulate_touch_from_mouse = true` is set, so mouse
  drags are swipes. Arrow keys also work as instant "swipes" (desktop
  fallback), Space still drives the parry.
- **Mobile display settings**: landscape orientation, `canvas_items`
  stretch with `keep` aspect.

Deliberately *not* changed: the web prototype (`js/`) stays button-based;
the AI simulation, combat math, and all core scripts are untouched — the
swipe is purely an input-layer change, which is itself the point: the
core/presentation boundary from the original port meant going mobile
touched two files.

## The ship-to-device process (when you're ready)

**Android** (very reasonable from Linux/Windows/macOS):
1. Editor → Export → Add preset → Android.
2. Install export templates (editor prompts, one download).
3. Install Android SDK + a debug keystore; point editor settings at them
   (Editor Settings → Export → Android). Godot docs walk through it.
4. Enable "One-Click Deploy": plug in a phone with USB debugging, press
   the Android icon in the editor toolbar, the game installs and runs.
5. For the Play Store: switch to a release keystore and export an `.aab`.

**iOS** (more ceremony, Apple's rules):
1. Requires a Mac with Xcode and an Apple Developer account ($99/yr).
2. Editor → Export → iOS produces an Xcode project; you sign and submit
   from Xcode. Testing on your own device works with a free account.

**Escape hatch**: the web export (Step 6 of the roadmap) runs in a mobile
browser with touch working — worth knowing as a zero-store distribution
path for playtesting.

## Round 2 — review decisions applied

Feedback from the first review, now implemented on this branch:

1. **Portrait orientation** (was open question 1). The viewport is now
   540×960 with `sensor_portrait`. The map screen stacks vertically —
   banner, board (the Board/Units nodes are simply `scale = 0.75`, and
   because input conversion uses `get_local_mouse_position()`, tap
   detection survived the rescale with zero code changes — that was the
   point of doing coordinate math in local space), then controls, info,
   and log below.
2. **Vertical battle vignette.** The enemy fights from the TOP of the
   panel, your unit from the BOTTOM; lunges travel vertically, dodges and
   hit-shakes sideways. HP plates sit above (enemy) and below (player)
   the scene. Placement is by *team*, not by who initiated — so the
   camera language is consistent: down = incoming, up = outgoing.
3. **Dedicated swipe pad.** A bordered zone at the bottom of the vignette
   is the controller; the scene above is just the view. All QTE prompts
   (offense ring + arrow, defense gauge, deflect spot) render inside the
   pad, and only touches that **start inside the pad** count during a
   QTE — resting a thumb on the scene does nothing. The pad's border
   takes the QTE color (blue/green/red) as a peripheral-vision cue.
4. **Haptics on parries.** `Input.vibrate_handheld(70)` on **Parried!**,
   `(35)` on **Blocked** — a strong buzz for the perfect window, a tick
   for the good one. No-op on desktop, works on Android/iOS exports.
5. **Keyboard fallbacks kept**: arrow keys swipe, Space is the hold
   finger (and always "arms" a deflect — the position requirement is a
   touch-only mechanic).
6. **NEW — the deflect parry** (positional). Physical attackers are
   parried with the existing hold-and-release. **Magic attackers demand a
   deflect**: a spot lights up somewhere in the pad (one of three
   anchors, randomized) with a direction arrow — put your finger ON the
   spot to arm, hold while the spell charges, then **swipe the shown
   direction as it lands** to fling it aside. Grading mirrors the hold
   parry (Parried! 50% / Blocked 75%), with two new failure shapes:
   wrong spot = your guard is up but can't deflect (Guarded 90% at
   best); wrong swipe direction = guard broken (Exposed 100%). The
   attack-type → parry-type rule is deliberate: the player can read
   "mage incoming" on the map and know which motion is coming.

## Round 3 — procedural art pass

The placeholder look (flat tiles, lettered circles) is replaced by a
procedural art module, `godot/scripts/art.gd` (`BattleArt`) — still zero
image assets; everything is `draw_*` calls, iterated pixel-first in a
canvas mock and then ported:

- **Terrain-aware battle backdrops.** The vignette reads the *defender's
  map tile* and stages the duel there, Fire Emblem style: plains with
  wildflowers, a pine forest with a treeline and framing trees, rocky
  crags with snowcaps, a river with a plank bridge deck the fighters
  stand on, or a fort wall with a banner. All variants share a layered
  composition: gradient dusk sky, sun with glow, clouds, birds, two
  ridgelines, gradient ground, grass tufts, and an edge vignette.
- **Class figures instead of lettered circles.** Pokémon-style staging:
  the enemy is drawn in ¾ front view at the top, your unit from behind
  at the bottom. Each class is a distinct flat-shaded vector figure —
  armored Knight with tower shield and plume, bandana'd Mercenary with
  raised sword, mounted Cavalier, hooded Archer with bow, Mage with
  pointed hat and floating tome, robed Healer with glowing staff,
  winged Pegasus rider.
- **Textured map tiles** (`BattleArt.draw_map_tile`, used by `board.gd`):
  grass speckle, canopy trees with shadows, faceted snow-capped peaks,
  gradient water with waves, plank bridges, stone forts with gates.
  Map unit tokens got contact shadows and a faked radial highlight.
- **UI chrome**: bronze-trimmed panel and plates (StyleBoxFlat), team
  ribbons on the HP plates, HP bars with a sheen, corner ticks on the
  swipe pad, drop shadows under popup text.
- Detail placement uses a deterministic LCG (same constants in the JS
  mock and GDScript), so scenes are stable frame to frame and identical
  across the prototype and the engine.

The natural end-state is still real sprite/tile assets — when that day
comes, `BattleArt` is the single file to swap, and the backdrop's
terrain-key contract (`draw_backdrop(ci, rect, terrain)`) is exactly the
interface a texture-based version would keep.

## Still open for review

1. **Deflect trigger rule** — currently magic attacks only. Alternatives:
   heavy chargers (Knight/Cavalier) too, or a random mix per strike.
2. **Swipe patterns per class** — directions are flavor guesses; happy to
   tune (a circle gesture for the Mage is possible, just more detection
   code).
3. **Scope** — Option B (pan/zoom camera for bigger maps) remains the
   natural next step after this shape is approved.
4. **Portrait map screen polish** — the board currently scales to fit;
   a real mobile pass would enlarge touch targets and rethink the
   info/log panels as collapsible sheets.
