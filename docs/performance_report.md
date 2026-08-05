# Performance Report

**Date:** 2026-08-05

## The one thing to read first

**No physical Android device was attached to this machine.** Every number below
comes from the Android emulator `emu64xa` (Android 16, x86_64, 1080×2400
portrait). The emulator's GLES path is software-rasterised and is a *pessimistic
bound*, not a phone measurement.

**The 60 FPS target is not demonstrated on real hardware.** That remains the
single most important open verification item.

## How it is measured

Frame times come from Flutter's own `SchedulerBinding.addTimingsCallback`
(`lib/core/performance/frame_stats.dart`), reading `FrameTiming.totalSpan` —
build plus raster, which is the figure that decides whether a frame was
delivered on time. The first 60 samples are discarded: shader warm-up and
first-frame buffer uploads are not steady state.

The overlay is compiled in with `--dart-define=MR_STATS=true` and driven by
`tool/measure.ps1` / `tool/playthrough.ps1`, which use `adb input` to hold and
release. Screenshots of every measurement are in `docs/shots/perf/`.

## Emulator results

### Release build — Impeller **GLES 3.0**

The emulator has no usable Vulkan driver for the release path, so release falls
back to GLES. That makes these the pessimistic numbers, and it also exercises
the vendored GLES shader fix (`third_party/README.md`) — the app launches
without the `render_pass_gles.cc` abort that stock `flutter_scene` 0.16.0 hits.

| Scene state | Swarm | Batched tris | avg | p95 | max |
|---|---:|---:|---:|---:|---:|
| Level loaded, idle | 0 | ~1,200 | 19.4 ms | 24.4 ms | 113.7 ms |
| Light attraction | ~18 | 1,928 | 21.8 ms | 26.5 ms | 87.5 ms |
| Mid attraction | ~27 | 2,704 | 22.0 ms | 25.8 ms | 120.8 ms |
| Post-release, debris settling | 0 | 2,956 | 24.2 ms | 39.9 ms | 87.5 ms |

### Debug build — Impeller **Vulkan**

Debug carries assertion and observatory overhead; included only to show the
relative cost of the swarm.

| Scene state | Swarm | Batched tris | avg | p95 | max |
|---|---:|---:|---:|---:|---:|
| Level loaded, idle | 0 | 3,504 | 24.6 ms | 31.1 ms | 43.4 ms |
| Attraction, stage 2 | 28 | 3,708 | 27.6 ms | 46.9 ms | 363.7 ms |
| Attraction, stage 2 | 41 | 4,176 | 44.6 ms | 83.9 ms | 105.3 ms |
| Release frame, full destruction | 0 (just launched) | 8,660 | 46.9 ms | 85.5 ms | 114.9 ms |

The 363.7 ms maximum is a one-off: it coincides with the first swarm-stage
transition, which allocates nothing but does first-touch several particle pool
entries and triggers the first audio playback of the session.

### Swarm counts actually reached

| Target | Reached | Notes |
|---|---|---|
| 25 objects | ✅ 27–28 | comfortably |
| 50 objects | ✅ 41–46 observed; cap is 110 on medium | reached in interactive play |
| 100 objects | ⚠️ **not reached in a measured run** | the scripted harness releases every few seconds and never accumulates that many |
| 150 objects | ⚠️ **not measured** | high preset caps at 160; untested |

This is an honest gap: the swarm architecture is designed and unit-tested for
these counts (capacity, slot assignment and orbit expansion are covered in
`test/gameplay_test.dart`), but 100- and 150-object frame times have **not**
been measured on any device.

## A caution about the scripted-capture numbers

`tool/playthrough.ps1` pulls a screenshot every few seconds while the game
renders. Under that load the emulator collapses to **~400 ms average frame time**
(~2.5 FPS). Those figures appear in `docs/shots/play/` and are **not** a
measurement of the game — they measure an emulator being thrashed by concurrent
`screencap`/`adb pull` while software-rasterising. The clean numbers in the
tables above were captured without concurrent pulls and are the ones to read.

## Memory

Emulator, release build, `dumpsys meminfo` TOTAL PSS:

| Point | PSS |
|---|---|
| Home screen, before Level 1 | 73.6 MB |

Peak-during-swarm and after-five-retries figures were attempted by
`tool/measure.ps1` but the script's memory readings were swallowed by a
PowerShell pipeline mistake and are **not** reported here rather than guessed.

## Draw calls

Not read from a GPU profiler — counted from the scene graph:

| Source | Draws |
|---|---:|
| Environment (one node per placement, sharing cached meshes) | ~26 |
| Kanban Core (one node per animated part) | 11 |
| Entire swarm + wall + debris | **1** |
| Every particle, trail and shockwave | **1** |

So N orbiting objects cost one draw call and one buffer upload, which is the
architecture `docs/renderer_decision.md` commits to. The environment is the
larger share and is the obvious next optimisation: baking the static decks into
a second pair of batches would take the whole scene under 15 draws.

## Load and retry

| Operation | Observed |
|---|---|
| Level 1 cold load (renderer init + 11 Core GLBs + 26 environment placements + 18 metal templates + audio bank synthesis) | ~6–8 s on the emulator, dominated by `Scene.initializeStaticResources` and shader warm-up |
| Retry (`resetLevel`) | Immediate — no asset reload; the level rebuilds from a fixed seed |

Retry determinism is asserted in `test/gameplay_test.dart`: the same seed
reproduces the same swarm trajectory to 1e-12.

## Artefact sizes

| Artefact | Size |
|---|---|
| `app-release.apk` | 44.4 MB |
| `app-release.aab` | 44.7 MB |
| `app-debug.apk` | 178 MB |
| All 80 GLB assets combined | 886 kB |

The release APK is large for a game whose art is 886 kB. It is not the art: it
is the Flutter engine plus the four ABIs in a fat APK. A split-per-ABI release
(`--split-per-abi`) or the AAB's per-device delivery will cut this
substantially. **Not yet measured.**

## What would change these numbers

1. **A physical device.** The emulator's software GLES rasteriser is the
   dominant cost here. Real hardware should beat every figure above.
2. **Batching the static environment**, taking ~26 draws to ~2.
3. **Reducing the release APK** with `--split-per-abi`.
