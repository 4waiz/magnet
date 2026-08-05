# Testing Report

**Date:** 2026-08-05
**Commands run:** `dart format .`, `flutter analyze`, `flutter test`,
`flutter build apk --debug`, `flutter build apk --release`,
`flutter build appbundle --release`

## Results

| Check | Result |
|---|---|
| `dart format .` | 192 files formatted, clean |
| `flutter analyze` | **No issues found** |
| `flutter test` | **91 tests, all passing** |
| `flutter build apk --debug` | ✅ built |
| `flutter build apk --release` | ✅ built, 44.4 MB |
| `flutter build appbundle --release` | ✅ built, 44.7 MB |
| Release APK launches on device | ✅ Impeller GLES, no crash |
| Debug APK launches on device | ✅ Impeller Vulkan, no crash |

## Test inventory

### `test/glb_template_loader_test.dart` — 6 tests
Proves Blender-authored GLBs load into CPU-side templates that the swarm
batcher can stamp.

* parses a single-material Blender export
* merges multi-material meshes and bakes per-primitive colour
  (the Core shell exports as two primitives; both colours must survive)
* normals are unit length and per-face (flat shading)
* `normalizedTo` rescales to a requested bounding radius
* rejects non-GLB bytes with a clear message
* every metal asset loads and stays inside the 16-bit index budget

### `test/level_test.dart` — 25 tests
6 parser tests and 19 validator tests. Every validator rule has a test that
deliberately breaks the level and asserts the right error code:

missing asset · unknown object type · locked portal with no key · portal behind
spawn · insufficient bridge pieces · gap with no bridge · too few anchors ·
non-advancing route · route ending before the finish · all-decorative platforms
· hazard on the spawn · hazard telegraph too short · invalid camera zone ·
camera zones ending before the finish · impossible swarm stage · non-increasing
swarm stages · bars too narrow for the key · wall unreachable with available
metal.

Also asserts **Level 1 itself validates against the real on-disk asset set**,
so a level referencing a deleted GLB fails the suite.

### `test/gameplay_test.dart` — 43 tests

| Group | Covers |
|---|---|
| MagnetField — range | out-of-range inert, in-range attracted, charge extends range, falloff shape |
| MagnetField — response | movement within one frame of touch-down, distant pieces accelerating, settling home on release |
| MagnetField — mass | light before medium before heavy, heavy resisting for a beat, mass constants ordered |
| Swarm — capacity/orbit | capacity refusal, armour→middle and key→inner layer, distinct slots, **curved** capture path, settling onto the analytic slot, orbit radius expanding with swarm size |
| Swarm — stages | monotonic stage transitions across thresholds |
| Swarm — release | all orbiting launched, charge and perfect increase speed, heavy launches slower, >90% forward-biased, target assist steers the burst, spin and trails, layer bookkeeping reset |
| ChargeState | rise/decay, window opens near full, venting closes it, vent pressure, **window open ≥ 0.33 s** (fairness), reset |
| RunScore | combo build and expiry, multiplier applied to destruction, star thresholds, coins, reset |
| Determinism | identical seed → identical swarm trajectory to 1e-12; identical magnet resolution |
| Quality presets | presets scale presentation only; every preset self-consistent |
| Settings persistence | map round-trip, malformed values fall back, volumes clamped, listener notified once |

### `test/camera_test.dart` — 7 tests
* horizontal FOV preserved across aspect ratios
* vertical FOV clamped against edge distortion
* camera sits behind and above the Core and looks ahead
* **repeated shake impulses do not drift the aim** (regression — see below)
* reduced motion shrinks shake without moving framing
* camera widens as the swarm grows
* zone changes ease the rig rather than cutting it
* reset returns the rig to a clean state

### `test/swarm_recovery_test.dart` — 4 tests
* metal landing over solid deck becomes collectable again (regression)
* metal falling over the void is destroyed
* with no landing predicate supplied, nothing lands
* a piece only lands while descending

### `test/widget_test.dart` — 6 tests
* home renders the Magnet Rush shell and **is not a MaterialApp**
* settings toggles write through to the store; quality presets change the cap
* settings open from home
* button fires once per tap
* cyan and orange stay far apart in hue (gameplay colour language)

## Bugs found by testing or on-device verification, and fixed

| Bug | How it was found | Fix |
|---|---|---|
| Every exported GLB contained a stray 480-triangle prop from an unrelated Blender project (75% of each file) | Parsing the exported GLB rather than trusting the exporter log | Export through a throwaway single-object scene instead of `use_selection` |
| Circuits, greeble and understructure overhung every deck by 2× | Composed environment review render | `deck`/`greeble`/`understructure` now take half-extents and double internally |
| A 4 m lane filled the whole screen on a phone | First playable build on device | Author horizontal FOV, solve for vertical using live aspect (`verticalFovFor`) |
| Decks rendered as bright metallic grey instead of dark navy | On-device screenshot | Structural materials dropped from 0.45–0.80 metallic to 0.05–0.25 |
| The Core was nearly invisible — dark, and dwarfed by the lane | On-device screenshot + a load-time diagnostic proving all 11 parts were present | Core emission tuned against the device, not the Blender preview; runtime rig scale 1.38 |
| The laboratory platform sat on the route; the Core flew underneath it, fully occluded | On-device screenshot | Moved to x −6.4, beside the lane |
| Camera aim drifted permanently with every impact | Reasoning about the shake code after seeing skewed framing | Shake applied to the outgoing camera only, never folded into smoothed state. Regression test added. |
| Launched metal that missed was destroyed forever, so a player could run out at the wall with no way to continue | Scripted playthrough getting stuck | Metal landing over solid deck becomes collectable again; plus a soft-lock guard that fails the run with a clear reason. Regression tests added. |
| Wall blocks rendered at 48% of their grid spacing — a sparse lattice, not a wall | On-device diagnostic (`wallAlive=16/28`) | Blocks fill their cell; hit radius widened against tunnelling |

## What is *not* covered by automated tests

The full Level 1 encounter chain — wall → armour → hazard → bridge → key →
portal → results — is **not** driven by an automated integration test. `GameWorld`
owns a `flutter_scene` `Scene` and needs a live GPU surface, so it cannot be
constructed in `flutter test`. Its constituent systems (magnet, swarm, charge,
scoring, camera, level parsing and validation) are unit-tested; the sequencing
between them is verified by hand and by scripted device playthroughs
(`tool/playthrough.ps1`), not by CI.

Extracting the encounter state machine from rendering so it *can* be tested
headlessly is the single most valuable next testing task.
