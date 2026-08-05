# Level Design — World 1, Level 1

**Status:** playable vertical slice. Data at `assets/levels/level_01.json`,
parsed by `lib/game/levels/level_data.dart`, checked by
`lib/game/levels/level_validator.dart`.

## Why levels are data

Nothing about Level 1's layout lives in Dart. The parser and the validator are
code; the level is a JSON document. That buys two things:

* a level can be changed, and a new one authored, without touching the engine;
* **the validator can refuse a broken level before it ever reaches a device.**

The validator is not decoration. Every rule maps to a way a level can look fine
and still strand the player — see the list below.

## The Level 1 route

Forward axis is `+Z`. The Core auto-advances; the player only holds and
releases.

| Z | Beat |
|---|---|
| 0 | Core enters on a wide research deck. Scripted intro: nearby metal twitches toward the Core before the player touches anything. |
| 9 | `intro_scrap` — 16 light pieces (cubes, bolts, nuts, triangular scrap). Reaches swarm stage 1. |
| 13 | `ledge_cache` on a raised side ledge, off the main lane. |
| 21 | Raised laboratory section to the **left** of the lane, carrying `lab_machinery` — 16 medium pieces (gears, plates). Stage 2. |
| 24.5 | `heavy_stock` — 12 heavy pieces (rods, pipe, block scrap). Stage 3. |
| 27.5 | **Cracked wall.** 7×4 blocks. Blocks the route until destroyed by a release. |
| 33 | **Armour** — 8 plates and spikes, revealed once the wall is down. |
| 34.5 | Hazard telegraph begins. |
| 40.5 | **Hazard discharge.** Armour absorbs it and visibly sheds plates; with no armour, the run fails. |
| 39 | `post_wall_debris` — replenishes the swarm after the wall. |
| 45 | **Bridge pieces** — 8 beams, 6 required. |
| 47.4 / 56.6 | Magnetic bridge anchors flanking the gap. |
| 48–56 | **The gap.** Impassable until the bridge forms. |
| 62.4 | **Magnetic key**, behind bars at 61.6. Must be attracted between the bars. |
| 71 | **Finish portal.** Locked until the key is in orbit. |

## Composition rules used

* **Three depth layers.** Playable lane (lit decks, cyan circuits), midground
  (side ledges, towers, cable supports, machinery sockets), and background
  (`prop_backdrop_*` silhouettes at y −9 to −12, darkest and lowest contrast).
* **Never a straight runway.** The route weaves ±1.4 m and the decks are offset
  to match, so the corridor bends.
* **Cyan means safe, orange means hazard.** The only orange in Level 1 is the
  hazard emitter's lens and the destruction debris tint.
* **Nothing decorative sits on the lane.** Learned the hard way: the laboratory
  section was first placed at x −1.4, directly over the route, and the Core
  flew underneath it completely hidden from the camera. It now sits at x −6.4.

## Camera zones

Six zones cover z −10 → 90. `fovDegrees` is authored as the **horizontal**
field of view; `GameCamera.verticalFovFor` converts it using the live viewport
aspect. This matters: `PerspectiveCamera` derives horizontal FOV as
`tan(fovY/2) * aspect`, and at a phone's 0.45 aspect a 45° *vertical* FOV gives
barely 21° horizontally — the first playable build framed a 4 m lane as if it
were two metres across.

| Zone | Purpose |
|---|---|
| −10 → 20 | Opening. Widest lookahead so the first metal is visible early. |
| 20 → 30.5 | Tightens for the wall encounter. |
| 30.5 → 44 | Opens again for armour and the telegraphed hazard. |
| 44 → 57.5 | Widest and highest — the gap and bridge need to be read whole. |
| 57.5 → 67 | Pulls in and looks ahead 3 m to reveal the key before arrival. |
| 67 → 90 | Portal approach. |

## Validator rules

`LevelValidator` reports errors (block the level) and warnings (allow it).
Covered by 20 tests in `test/level_test.dart`.

| Code | Catches |
|---|---|
| `missing_asset` | A referenced GLB that does not exist on disk. |
| `unknown_object_type` | An asset outside every known model category. |
| `invalid_route` | Route with <2 points, non-advancing Z, or ending before `finishZ`. |
| `invalid_platform_reference` | No platforms, all-decorative platforms, non-positive scale. |
| `missing_finish_portal` | Portal at or behind the Core spawn. |
| `missing_key_for_locked_portal` | Portal requires a key the level never spawns. |
| `invalid_bars` | Bar gap non-positive, or too narrow for the key to pass. |
| `invalid_key_placement` | Key unreachable — at or past the portal. |
| `insufficient_bridge_pieces` | Fewer beams spawn than the bridge requires, or a gap with no bridge at all. |
| `insufficient_bridge_anchors` | Fewer than two anchors. |
| `invalid_bridge_placement` | Beams spawn past the gap they must cross. |
| `invalid_gap` | Inverted or zero-length gap. |
| `hazard_overlaps_spawn` | Hazard within 6 m of spawn — no time to react. |
| `hazard_trigger_too_late` | Telegraph starts at or after the hazard itself. |
| `hazard_telegraph_too_short` | Under 0.4 s of warning. |
| `invalid_camera_zone` | Inverted zone, non-positive distance/height, FOV out of range, first zone starting after spawn, or zones ending before `finishZ`. |
| `camera_zone_gap` (warning) | Uncovered stretch of route. |
| `impossible_swarm_requirement` | Stage thresholds that do not increase, exceed the metal the level spawns, exceed swarm capacity, or a wall whose first stage cannot be reached from the metal available before it. |
| `invalid_wall` | Wall with no blocks. |
| `invalid_objective` (warning) | Non-positive objective target. |

## Authoring a new level

1. Copy `assets/levels/level_01.json`.
2. Reference only assets that exist under `assets/models/`.
3. Add it to a test that runs `LevelValidator(knownAssets: …).validate(level)`
   and asserts `isValid`. Level 1 is covered this way already, so a level that
   breaks a rule fails CI rather than shipping.

## Not yet built

Levels 2–50, worlds 2–5, all bosses, moving platforms and enemies. World 1
Level 1 is the only level in the game.
