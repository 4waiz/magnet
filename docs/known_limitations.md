# Known Limitations

Honest status as of 2026-08-05. This lists what is **not** done as plainly as
what is, so nothing here is mistaken for finished work.

## Completed and verified on an Android build

* Renderer selected, and the choice validated by a running app rather than by
  reasoning — see `docs/renderer_decision.md`.
* `lib/dev/smoke_test.dart`: Kanban Core, 100 collectible objects, hold-to-attract,
  controlled swarm orbit, release-to-repel, one breakable wall, frame-time
  instrumentation. Debug **and** release APKs build and run.
* Measured on device: 94 objects collected, 81 in simultaneous controlled orbit,
  5 wall blocks destroyed by a release.
* Blender pipeline: 54 GLB assets generated headlessly, 0 budget violations,
  and `kanban_core.glb` confirmed loading and rendering on device.
* A shipping-critical Impeller GLES crash root-caused and fixed
  (`third_party/README.md`).

## Not yet built

The brief describes a full commercial title. The following are **not started**;
the foundations above exist to support them, but no part of them should be
assumed working.

* **Game proper.** `lib/` currently contains the smoke-test harness and the
  default `main.dart`. The feature-based architecture in section 26 is not laid
  down yet.
* **Vertical slice (section 25).** The smoke test covers roughly half its
  checklist. Missing: armour, bridge formation, magnetic key, locked finish
  portal, audio, haptics, particles, scoring/combo, success/fail flow.
* **Content.** 0 of 50 levels; 0 of 5 worlds; 0 enemies; 0 of 5 bosses.
* **Asset library.** 54 of the ~120 assets in the brief. Missing: most obstacles,
  all enemies, all bosses, most of the platform kit's moving pieces.
* **Meta systems.** Upgrades, shop/cosmetics, missions, daily challenge, endless
  mode, settings, persistence — none implemented.
* **Monetization.** Not implemented (section 21).
* **Tests.** No unit or integration tests yet (section 27). `flutter analyze`
  passes on the smoke test.
* **Play Store prep.** Adaptive icon, splash, signing config, versioning and
  store documentation not done. Package name, portrait lock and app label *are*
  configured.
* **AAB.** Not yet produced. Release **APK** builds successfully.

## Caveats on what *is* done

* **Performance numbers are emulator-only.** No physical Android device was
  attached to this machine. The emulator's GLES path is software-rasterised and
  is a pessimistic bound, not a phone measurement:

  | Build | Backend | avg | p95 | max |
  |---|---|---|---|---|
  | Debug | Vulkan | 10.88 ms | 16.35 ms | 26.53 ms |
  | Release | GLES 3.0 | 23.52 ms | 37.48 ms | 68.75 ms |

  The 60 FPS target in section 28 is **not yet demonstrated on real hardware.**
  This is the single most important open verification item.

* **`flutter_scene` is pinned to 0.16.0 and vendored.** It is two months behind
  upstream because newer releases require the Flutter master channel. The patch
  and its rationale are documented in `third_party/README.md`. This is a
  deliberate trade — stable channel over newest engine — and it carries a real
  cost: no upstream fixes without re-vendoring.

* **Camera framing is rough.** Tuned enough to read on a phone, not art-directed.

* **Visual fidelity vs the reference images is partial.** Geometry, palette and
  the faceted style are in place. Not yet present: environment fog and depth
  fading, bloom/glow tuning, orange hazard accents in situ, layered background
  structures, and particles. The smoke test looks like the references' *subject*
  but not yet their *finish*.

* **OneDrive.** The repo lives under `OneDrive\Desktop`, and its sync
  intermittently triggers `File modified during build. Build must be rerun.`
  Builds succeed on retry, but moving the project outside OneDrive is advisable.

* **No Blender MCP server** was connected; Blender is driven headlessly via its
  Python API instead. See `docs/blender_pipeline.md`.
