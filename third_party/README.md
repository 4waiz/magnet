# third_party

## flutter_scene 0.16.0 (vendored, patched)

Upstream: <https://pub.dev/packages/flutter_scene> — MIT, © 2023 Brandon DeRosier.
The unmodified licence ships at `third_party/flutter_scene/LICENSE`.

### Why it is vendored rather than pulled from pub

**Version pin.** `flutter_scene` targets the Flutter **master** channel. Magnet
Rush ships to Google Play and therefore builds on **stable** (3.44.8). Stable's
bundled `flutter_gpu` (`bin/cache/pkg/flutter_gpu`) predates the APIs that
0.17.0+ require, so those versions fail to compile:

| flutter_scene | Result on stable 3.44.8 |
|---|---|
| 0.20.0 | `TextureCompressionFamily`, `supportsTextureCompression`, `ShaderLibrary.reinitialize` undefined |
| 0.19.0 | `gpu.VertexFormat` undefined |
| 0.18.1 | `gpu.VertexLayout` undefined |
| 0.17.0 | `gpu.TextureCompressionFamily` undefined |
| **0.16.0** | **compiles and runs** |

0.16.0 is the newest release that builds against stable, so it is the version
we ship. See `docs/renderer_decision.md`.

### The patch

Two files differ from upstream 0.16.0. Both are marked in-source with
`MAGNET RUSH LOCAL PATCH`:

1. `hook/build.dart` — pass `glesLanguageVersion: 300` to
   `buildShaderBundleJson`.
2. `pubspec.yaml` — raise `flutter_gpu_shaders` to `^0.5.1`, the first release
   whose `buildShaderBundleJson` accepts that argument.

**What it fixes.** Upstream 0.16.0 compiles the engine shader bundle at
impellerc's default GLSL ES 1.00. The lighting shaders sample radiance with
`textureLod`, which is core in `300 es` but under the 1.00 profile needs
`GL_EXT_shader_texture_lod`. Impeller's GLES backend rejects it at compile time
and aborts the raster thread:

```
[FATAL:flutter/impeller/renderer/backend/gles/render_pass_gles.cc(726)]
Check failed: result. Must be able to encode GL commands without error.
```

Impeller selects its GLES backend on the Android emulator and on devices with
no usable Vulkan driver, so without this patch the game hard-crashes on launch
for that entire slice of devices. Pinning 300 sets the native GLES floor at
OpenGL ES 3.0, which every device in our target range supports.

Upstream shipped the identical fix in 0.20.0, so this patch disappears whenever
Flutter GPU reaches stable and we can move to current `flutter_scene`.

### Updating

Re-vendoring means copying the new release over `flutter_scene/` and reapplying
both patches — search for `MAGNET RUSH LOCAL PATCH`.
