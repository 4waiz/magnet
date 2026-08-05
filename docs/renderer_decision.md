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

## Measured results

Android emulator (`emu64xa`, Android 16, x86_64), portrait 1080×2400,
100 collectible objects + 28-block breakable wall, 128 batched objects total
(1,536 triangles) in **one draw call**.

| Build | Backend | avg | p95 | max |
|---|---|---|---|---|
| Debug | Vulkan | 10.88 ms | 16.35 ms | 26.53 ms |
| Release | GLES 3.0 | 23.52 ms | 37.48 ms | 68.75 ms |

Verified interactively on device: hold-to-attract captured 94 objects, 81 held
in simultaneous controlled orbit, release launched the swarm, and 5 wall blocks
were destroyed by the launched projectiles.

**Caveat, stated plainly:** these are emulator numbers. The emulator's GLES path
is software-rasterised and is the pessimistic bound, not a phone measurement.
The Vulkan figure is the more representative one, and real hardware should beat
both. No physical Android device was attached to this machine, so a
hardware-measured figure is still outstanding — see `docs/known_limitations.md`.

## Consequences

* Gameplay renders through `Scene.render(camera, canvas)` from a `CustomPainter`
  driven by a `Ticker`; the game owns its frame loop rather than the widget tree.
* `vector_math` (32-bit) is the gameplay math library. Flutter's own `Matrix4` is
  `vector_math_64` and must be hidden at import to avoid ambiguity.
* Minimum practical target is OpenGL ES 3.0.
* Every gameplay object must be expressible as a low-poly template plus a
  transform, so it can enter the batch.
