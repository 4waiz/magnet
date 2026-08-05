# Renderer & Physics Decision

**Status:** decided, validated on an Android device build.
**Date:** 2026-08-05

## Summary

| | Choice |
|---|---|
| App shell, UI, HUD, meta | Flutter (stable 3.44.8, Dart 3.12.2) |
| Gameplay 3D renderer | `flutter_scene` **0.16.0**, vendored + patched, on Flutter GPU / Impeller |
| Graphics backend | Impeller **Vulkan** preferred, Impeller **GLES 3.0** supported |
| Swarm rendering | One merged, GPU-resident dynamic mesh rebuilt in place per frame |
| Physics | Custom deterministic kinematics. **No rigid-body engine.** |

## How this was decided

The brief required a technical smoke test before committing. That harness lives
at `lib/dev/smoke_test.dart` and is a real, runnable Android app.

### Candidates considered

| Option | Verdict |
|---|---|
| `flutter_scene` + Flutter GPU | **Chosen.** Only maintained Flutter-native 3D engine with instancing, PBR/unlit materials, glTF import, particles, bloom and post-processing. |
| Raw `flutter_gpu` custom renderer | Viable — stable ships a complete low-level API (`RenderPass`, `RenderPipeline`, `DeviceBuffer`, `ShaderLibrary`). Rejected as a first choice: weeks of work to re-derive what `flutter_scene` already provides. Remains the fallback. |
| `three_js` (Dart port) | Rejected. CPU-bound scene graph; will not hold hundreds of moving objects at 60 FPS. |
| `flame_3d` | Rejected. Early-stage, thinner feature set than `flutter_scene`. |
| Embedded Unity/Godot view | Rejected. Enormous binary-size and build-complexity cost for a one-finger game whose art style is flat-shaded low-poly. |

### Why 0.16.0 and not 0.20.0

`flutter_scene` officially targets the Flutter **master** channel. Magnet Rush
ships to Google Play, so it builds on **stable**. Stable's bundled `flutter_gpu`
(`bin/cache/pkg/flutter_gpu`) predates APIs the newer releases need. Measured by
compiling each version against stable 3.44.8:

| Version | Result |
|---|---|
| 0.20.0 | ✗ `TextureCompressionFamily`, `supportsTextureCompression`, `ShaderLibrary.reinitialize` undefined |
| 0.19.0 | ✗ `gpu.VertexFormat` undefined |
| 0.18.1 | ✗ `gpu.VertexLayout` undefined |
| 0.17.0 | ✗ `gpu.TextureCompressionFamily` undefined |
| **0.16.0** | ✓ compiles, runs, renders |

Moving the whole project to the master channel was rejected: an unpinned,
daily-moving SDK is the wrong foundation for a store release.

### The GLES crash, and why it mattered

With stock 0.16.0 the release build **hard-crashed on launch**:

```
[FATAL:flutter/impeller/renderer/backend/gles/render_pass_gles.cc(726)]
Check failed: result. Must be able to encode GL commands without error.
```

Root cause: `flutter_gpu_shaders` 0.4.5 never passes `--gles-language-version`,
so impellerc compiles the engine shader bundle at **GLSL ES 1.00**. The lighting
shaders sample radiance with `textureLod`, which is core in `300 es` but under
the 1.00 profile requires `GL_EXT_shader_texture_lod`. Impeller's GLES backend
rejects it at compile time and aborts the raster thread.

This is **not** merely an emulator artefact. Impeller selects its GLES backend on
any device without a usable Vulkan driver, so shipping unpatched would crash on
launch across that entire slice of the Android install base.

**Fix:** `flutter_scene` is vendored at `third_party/flutter_scene` (MIT) with two
marked changes — `hook/build.dart` passes `glesLanguageVersion: 300`, and
`pubspec.yaml` raises `flutter_gpu_shaders` to `^0.5.1`, the first release
accepting that argument. Upstream shipped the same fix in 0.20.0, so the patch
retires once Flutter GPU reaches stable. Details: `third_party/README.md`.

Android also needs both opt-in manifest keys, which are now set:
`io.flutter.embedding.android.EnableFlutterGPU` and `...EnableImpeller`
(plus `...ImpellerBackend=vulkan` to prefer Vulkan where available).

## Swarm architecture

Section 5 of the brief forbids simulating every orbiting object as a rigid body.
`InstancedMesh` in 0.16.0 does not solve this either — its own documentation
states *"the naive backend still issues one draw call per instance."*

So the swarm is **not** a scene graph of nodes. It is one `MeshGeometry` created
with `GeometryStorage.updatable`. Each frame:

1. Reset a preallocated `Float32List` batch (positions, normals, colors) — no
   per-frame allocation.
2. For every live object, stamp its low-poly template through its 4×4 transform
   directly into the batch with scalar float math.
3. Upload once via `MeshGeometry.rebuild()`, which reuses the existing GPU
   buffers when the data fits their spare capacity.

Result: **N objects → 1 draw call, 1 buffer upload, 0 rigid bodies.** Orbit
motion is closed-form (radius, angle, tilt, height per slot), so it is
deterministic, resettable, and costs a few trig ops per object.

Physics is likewise custom and minimal: attraction is a clamped inverse-range
impulse, projectiles are ballistic, and collisions are radius tests. Nothing
needs a general solver, and avoiding one keeps resets exact.

## Getting Blender geometry into the batch

The batcher needs triangles **on the CPU**. `flutter_scene` imports GLB straight
onto the GPU, which is right for static scenery and useless for a mesh that is
rebuilt every frame. Without a CPU path the swarm could only stamp shapes
hand-coded in Dart — which is exactly how the first pass ended up as a hundred
identical cubes.

`lib/game/renderer/glb_template_loader.dart` parses GLB in Dart into
`MeshTemplate` (positions, per-face normals, indices, and per-vertex colours
baked from each primitive's `baseColorFactor`). Scope is deliberately narrow —
triangle primitives, float POSITION, non-sparse accessors, no Draco — i.e. what
`art/blender/*.py` actually exports. Anything else throws with a clear message
rather than producing silently wrong geometry.

Consequence: the swarm stamps **real Blender-authored silhouettes** — bolts,
nuts, gears, rods, plates, rings, scrap, armour, bridge beams, the key — and
still costs one draw call. Multi-material meshes survive the merge because each
primitive's colour is baked per vertex. Covered by
`test/glb_template_loader_test.dart`.

## Two batches, not one

* **Metal batch** — `PhysicallyBasedMaterial`, lit, opaque. Swarm, wall blocks,
  heavy debris.
* **Glow batch** — a `GlowMaterial` subclass of `UnlitMaterial` that overrides
  `isOpaque()` to return `false`. Trails, shockwave rings and sparks.

That override matters: stock `UnlitMaterial` does not override `isOpaque`, so
unlit geometry always lands in the opaque pass and its alpha is ignored.
Overriding moves those draws into the depth-sorted translucent pass, which is
what makes effects read as light rather than as solid plastic.

## Camera field of view on a portrait phone

`PerspectiveCamera` takes a **vertical** FOV and derives horizontal as
`tan(fovY/2) * aspect`. On a 1080×2400 phone the aspect is 0.45, so an
apparently reasonable 45° vertical FOV gives barely 21° horizontally — the first
playable build framed a 4 m lane as if it were two metres across, and the
platforms filled the entire screen width.

Level data therefore authors the **horizontal** angle, and
`GameCamera.verticalFovFor` solves for vertical against the live viewport
aspect, clamped to 35–78° (past ~78° the edge distortion becomes obvious).
Covered by `test/camera_test.dart`.

## Measured results

See `docs/performance_report.md` for the full table. Summary, on the Android
emulator only:

| Build | Backend | Swarm | avg | p95 |
|---|---|---:|---:|---:|
| Release | Impeller GLES 3.0 | 0–27 | 19.4–22.0 ms | 24.4–26.5 ms |
| Debug | Impeller Vulkan | 28–41 | 27.6–44.6 ms | 46.9–83.9 ms |

Draw calls, counted from the scene graph: ~26 for the environment (one node per
placement, sharing cached meshes), 11 for the Core's animated parts, **1** for
the entire swarm and **1** for every particle, trail and shockwave.

**Caveat, stated plainly:** these are emulator numbers. The emulator's GLES path
is software-rasterised and is the pessimistic bound, not a phone measurement. No
physical Android device was attached to this machine, so a hardware-measured
figure is still outstanding, and **60 FPS is not demonstrated on real hardware.**
Swarms of 100 and 150 objects were never measured at all.

## Consequences

* Gameplay renders through `Scene.render(camera, canvas)` from a `CustomPainter`
  driven by a `Ticker`; the game owns its frame loop rather than the widget tree.
* `vector_math` (32-bit) is the gameplay math library. Flutter's own `Matrix4` is
  `vector_math_64` and must be hidden at import to avoid ambiguity.
* Minimum practical target is OpenGL ES 3.0.
* Every gameplay object must be expressible as a low-poly template plus a
  transform, so it can enter the batch.
* Batched geometry is indexed with 16-bit indices, so a single template cannot
  exceed 21,845 triangles. The loader rejects anything larger rather than
  overflowing.
