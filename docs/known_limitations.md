# Known Limitations

Honest status as of 2026-08-05. This lists what is **not** done as plainly as
what is, so nothing here is mistaken for finished work.

## What exists and was verified on a running Android build

* **A playable Level 1 vertical slice**, reached through the normal app flow
  (home → PLAY), not through a developer harness.
* **The Kanban Core as a hero asset** — 11 separable Blender-authored parts,
  animated at runtime: split shell caps, a chamber glowing through a tilted
  energy seam, emissive cracks, three gyroscopic rings and orbiting fragments.
* **The swarm** — Blender-authored metal silhouettes (cubes, bolts, nuts, rods,
  plates, rings, gears, scrap, armour, bridge beams, the key) stamped into
  **one** merged dynamic mesh in three orbit layers.
* **Environment** — 20 modular platform and obstacle assets composing a floating
  facility with foreground lane, midground ledges and towers, and background
  silhouettes.
* Attraction, charge, venting, release, wall destruction, swarm stages, combo,
  perfect-release window, pooled mesh particles, trails, shockwaves, camera
  impulses, synthesized audio, rate-limited haptics, the UI design system,
  quality presets, reduced motion, settings persistence.
* `flutter analyze` clean; **91 tests passing**; debug APK, release APK and
  release AAB all build and launch.

Screenshots from the running Android build: `docs/shots/`.

## Verified on device vs. verified only by test

This distinction matters and is easy to blur, so it is stated plainly.

**Seen working on the device, in screenshots:** intro, attraction with curved
capture, swarm growth through stages 1–2, combo chains, charge and the vent
warning, release with shockwave and trailed metal, wall damage and destruction,
debris, hazard emitter present and telegraphing, HUD, home screen, settings,
pause.

**Now also verified on device** (`tool/verify_level.ps1`, `docs/shots/09_*`):
the wall clearing, armour entering orbit, bridge assembly, key collection,
portal unlock, level completion and the results screen. A full run reaches
`phase=complete` with `wallAlive=0/15 bridge=true key=true portal=true`.

Getting there required two changes to how the game is driven:

* **Do not screenshot while playing.** Pulling a frame every cycle drops the
  emulator to ~2 FPS (400-500 ms frames), so a hold delivers only a handful of
  simulation frames and the run stalls. `verify_level.ps1` drives with input
  only, reads progress from a `[state]` log line, and captures a single frame
  when a milestone is reached.
* **Use the release build.** It runs roughly three times faster than debug on
  this emulator, which is the difference between reaching the portal and not.

**Still not photographed:** the failure screen and instant retry. A scripted
run has not yet failed on purpose.

## Performance — read `docs/performance_report.md`

* **All numbers are emulator-only.** No physical Android device was attached.
* Release (Impeller GLES, software-rasterised emulator): **19–24 ms average**,
  25–40 ms p95 at swarm sizes up to ~27.
* **60 FPS is not demonstrated on real hardware.**
* **100- and 150-object swarms were never measured.** The architecture is built
  and unit-tested for them; the frame cost at those counts is unknown.
* Peak and post-retry memory were not captured — the measurement script's
  readings were lost to a scripting mistake, and guesses are not reported.
* Release APK is 44.4 MB. That is engine plus four ABIs, not art (all 80 GLBs
  total 886 kB). `--split-per-abi` is untried.

## Not built

* **Content.** 1 of 50 levels. 1 of 5 worlds. 0 enemies. 0 of 5 bosses.
* **Meta systems.** Upgrades, shop, skins, missions, daily challenge and endless
  mode are visible on the home screen as explicitly **LOCKED** tiles. None are
  implemented. Progress (stars, coins, level unlocks) is **not persisted** —
  only settings are.
* **Monetization.** Not implemented, not stubbed.
* **Play Store prep.** No signing config, no adaptive icon, no splash, no store
  listing. The release build is unsigned beyond the debug keystore.
* **Moving platforms, the full obstacle library, the full enemy library.**

## Caveats on what *is* done

* **No headless integration test of the Level 1 chain.** `GameWorld` owns a
  `flutter_scene` `Scene` and needs a GPU surface, so it cannot be built inside
  `flutter test`. The encounter sequencing is therefore verified by hand, not by
  CI. Extracting that state machine from rendering is the highest-value next
  testing task.

* **The 3D scene renders upside down on Impeller GLES.** Confirmed, root-caused
  and worked around — but the workaround's *detection* is a heuristic.

  Impeller's GLES backend composites the offscreen scene texture with the
  opposite vertical orientation from Vulkan. Identical game state, identical
  code, only the backend differs: `docs/shots/cmp_debug_vulkan.png` (correct)
  versus `docs/shots/cmp_release_gles.png` (flipped). This is what I earlier
  and wrongly recorded as "intermittent camera skew" — it was never
  intermittent, it tracked the build's backend exactly.

  `GameWorld` compensates by flipping the canvas before compositing. The
  problem is knowing *when*: **nothing in the Flutter GPU Dart API reports the
  active backend.** The only capability that differed on the test device was
  the minimum uniform alignment (Vulkan 64, GLES 256), so that is what the
  `auto` mode keys off. That is a driver property, not a backend contract — a
  Vulkan device reporting 256 would be flipped wrongly. Overrides exist:

  ```
  flutter run --dart-define=MR_FLIP_Y=on     # force the flip
  flutter run --dart-define=MR_FLIP_Y=off    # never flip
  ```

  The proper fix belongs below flutter_scene, in Impeller's texture handling.
  Until then this is the single most important thing to re-test on any new
  device.

  A second, real bug was found and fixed along the way: camera shake was being
  accumulated into the smoothed target, so every impact permanently biased the
  aim. That one has a regression test (`test/camera_test.dart`).

* **Wall balance is tuned from a scripted harness, not from play.** The wall
  went through three revisions during device testing:

  1. 7x4 blocks at 48% of their grid spacing — a sparse lattice of floating
     cubes that neither read as a wall nor reliably stopped projectiles;
  2. blocks filling their cells, 7x3, hit radius widened — cleared 11 of 21
     blocks over 14 releases, still too slow;
  3. **5x3 blocks of 0.92 m** — fewer, larger, and crucially *taller* (top at
     2.18 m rather than 1.66 m). The orbit spreads roughly two metres above the
     Core, so most launched metal was flying straight over the earlier walls.

  The final configuration **is** clear-able, verified on device: the wall goes
  from 15/15 to 0/15 within one or two releases (`tool/verify_level.ps1`,
  `docs/shots/09_wall_cleared.png`). If anything it is now too *easy* — a
  five-second hold builds enough swarm to level it in a single shot. It has
  still not been balanced against real play.

* **The environment costs ~26 draw calls.** The swarm and all effects cost 2.
  Batching the static decks is the obvious next optimisation and is not done.

* **Audio is synthesized, not composed.** Every cue is generated as PCM in Dart
  (`lib/core/audio/synth.dart`). This is deliberate — nothing to license,
  nothing shipped — but it is placeholder-grade sound design, not final audio.
  There is no music track; `startAmbience` reuses the attraction hum.

* **Haptics are pattern-based, not amplitude-based.** Flutter exposes only canned
  patterns, so "strength" is expressed by choosing between them and by pulse
  cadence. Devices without a vibrator disable the service after one probe.

* **The Core's `defer`-status assets.** Six older Core GLBs (charge ring, field
  line, overcharge shell, repulse wave, shield, trail) are retained for features
  not yet built. They are unused by Level 1 and were **not** visually reviewed.
  Five superseded Core assets were deleted outright.

* **`flutter_scene` is pinned to 0.16.0 and vendored.** It is behind upstream
  because newer releases require the Flutter master channel. The patch and its
  rationale are in `third_party/README.md`. This is a deliberate trade — stable
  channel over newest engine — and it carries a real cost: no upstream fixes
  without re-vendoring.

* **Two-material limit on the Core shell.** The bright/deep split is done by face
  normal at export, giving two glTF primitives. It reads well but is coarser
  than a gradient.

* **OneDrive.** The repo lives under `OneDrive\Desktop`, and its sync
  intermittently triggers `File modified during build. Build must be rerun.`
  Builds succeed on retry, but moving the project outside OneDrive is advisable.

## Blender

Blender MCP **was** connected and used interactively for this pass — the Core
and the whole environment kit were authored, rendered from the gameplay camera,
judged, revised and exported through it. Editable sources are at
`art/blender/src/*.blend`.

One caveat worth recording: the interactive session had an unrelated project
open in another scene. All work was done in an isolated `MR_Build` scene and
that project was left untouched, but the glTF exporter's `use_selection` mode
picked up its selection and welded a stray prop into every early export. Assets
are now exported through a throwaway single-object scene, which cannot be
contaminated that way.
