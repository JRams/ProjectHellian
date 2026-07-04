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

## Open questions for your review

1. **Orientation** — the prototype keeps landscape (matches the wide
   battle vignette). Portrait would mean redesigning the sidebar into a
   bottom sheet. Preference?
2. **Swipe patterns per class** — directions above are flavor guesses;
   happy to tune (should Mage be a circle gesture? Godot can match those
   too, it's just more detection code).
3. **Scope** — confirm Option A, or go straight to B (pan/zoom camera)?
4. **Haptics** — `Input.vibrate_handheld()` on Perfect/Parried is a
   one-liner and feels great on phones. Add it?
5. **Keep keyboard fallbacks** in the mobile build, or strip them?
